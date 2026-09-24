import Foundation

/// What an account has consumed: an assistant message from Claude Code, or a one-day aggregate (same project, same model).
public struct UsageSample: Codable, Equatable, Sendable {
    public var date: Date
    /// The project's name: its real folder's name when the transcript says where it is, else Claude Code's sessions folder (a slug).
    public var project: String
    public var model: String
    public var input: Int
    public var cacheCreation: Int
    public var cacheRead: Int
    public var output: Int
    public init(date: Date, project: String, model: String, input: Int, cacheCreation: Int, cacheRead: Int, output: Int) {
        self.date = date; self.project = project; self.model = model
        self.input = input; self.cacheCreation = cacheCreation; self.cacheRead = cacheRead; self.output = output
    }
    public var total: Int { input + cacheCreation + cacheRead + output }
}

/// Reads a profile's Claude Code JSONL transcripts, locally, with no network calls or tokens.
///
/// Incremental and lightweight: a per-file cache (offset, size, date) means later passes only read what
/// was added; a file modified before the requested period is never opened; files are read in chunks;
/// the cache keeps one aggregate per day, project, and model (not one sample per message), trimmed to the period, and is
/// only rewritten if something changed. Streaming writes several lines per message with a provisional output
/// count: we keep the maximum, meaning the last line.
public struct UsageReader: Sendable {
    public let cacheFile: URL
    public let chunkSize: Int
    public init(cacheFile: URL, chunkSize: Int = 4 * 1024 * 1024) { self.cacheFile = cacheFile; self.chunkSize = chunkSize }

    /// A local day, a project, a model.
    public struct DayBucket: Codable, Equatable, Sendable {
        public var day: Date
        public var project: String
        public var model: String
        public var input: Int, cacheCreation: Int, cacheRead: Int, output: Int
        public var messages: Int
        var key: String { "\(day.timeIntervalSinceReferenceDate)|\(project)|\(model)" }
        mutating func add(_ s: UsageSample) { input += s.input; cacheCreation += s.cacheCreation; cacheRead += s.cacheRead; output += s.output; messages += 1 }
        var sample: UsageSample { UsageSample(date: day, project: project, model: model, input: input, cacheCreation: cacheCreation, cacheRead: cacheRead, output: output) }
    }

    /// The last message seen in a file: its lines may still arrive on the next pass.
    public struct OpenMessage: Codable, Equatable, Sendable {
        public var id: String
        public var sample: UsageSample
    }

    public struct FileState: Codable, Equatable, Sendable {
        public var offset: Int64
        public var size: Int64
        public var modified: TimeInterval
        public var buckets: [DayBucket]
        public var open: OpenMessage?
        /// Lines parsed on the last pass (observability: zero when nothing changed).
        public var parsedLines: Int
        /// The project's real folder name, from the `cwd` the transcript carries; nil when no line had one.
        public var projectName: String?
    }

    public struct Cache: Codable, Equatable, Sendable {
        /// Bumped when the parser changes what it stores: an older cache is simply rebuilt.
        public static let currentVersion = 2
        public var version = Cache.currentVersion
        public var files: [String: FileState] = [:]
        public init() {}
        public static func load(_ url: URL) throws -> Cache {
            guard let data = try? Data(contentsOf: url), let cache = try? JSONDecoder().decode(Cache.self, from: data),
                  cache.version == currentVersion else { return Cache() }
            return cache
        }
        func save(to url: URL) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(self).write(to: url, options: .atomic)
        }
    }

    /// The profile's samples since `since`: one per day, project, and model, plus the last message of each file.
    public func read(profile: CLIProfile, since: Date, now: Date = Date(), calendar: Calendar = .current) throws -> [UsageSample] {
        let fm = FileManager.default
        let root = profile.projectsDir
        let resolvedRoot = root.resolvingSymlinksInPath()
        let cache = try Cache.load(cacheFile)
        let sinceDay = calendar.startOfDay(for: since)
        var kept: [String: FileState] = [:]
        var dirty = false
        var result: [UsageSample] = []
        for (file, relative) in Self.transcripts(in: resolvedRoot) {
            // One file at a time, inside its own pool: what a big file allocates is released before the next one.
            autoreleasepool {
                let key = root.appending(path: relative).path
                let project = String(relative.split(separator: "/").first ?? "")
                guard let attrs = try? fm.attributesOfItem(atPath: file.path) else { return }
                let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
                let modified = (attrs[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
                // Nothing recent in a file that hasn't changed since the period: never opened, and forgotten if it was known.
                if modified < since.timeIntervalSinceReferenceDate { if cache.files[key] != nil { dirty = true }; return }
                var state = cache.files[key] ?? FileState(offset: 0, size: 0, modified: 0, buckets: [], open: nil, parsedLines: 0)
                if state.size == size, state.modified == modified {
                    state.parsedLines = 0
                } else {
                    if size < state.size { state = FileState(offset: 0, size: 0, modified: 0, buckets: [], open: nil, parsedLines: 0) }
                    var open = state.open
                    var projectName = state.projectName
                    let parsed = Self.parse(file: file, from: state.offset, chunkSize: chunkSize, project: project, open: &open, projectName: &projectName, calendar: calendar)
                    state.buckets = Self.merge(state.buckets, parsed.buckets)
                    state.open = open
                    state.projectName = projectName
                    state.offset += parsed.consumed
                    state.size = size
                    state.modified = modified
                    state.parsedLines = parsed.lines
                    dirty = true
                }
                let before = state.buckets.count
                state.buckets.removeAll { $0.day < sinceDay }
                if state.buckets.count != before { dirty = true }
                kept[key] = state
                // Samples carry the readable name when the transcript gave one, the sessions folder's slug otherwise.
                let name = state.projectName ?? project
                result += state.buckets.map { var s = $0.sample; s.project = name; return s }
                if let open = state.open { var s = open.sample; s.project = name; result.append(s) }
            }
        }
        if dirty || Set(kept.keys) != Set(cache.files.keys) {
            var updated = Cache(); updated.files = kept
            try? updated.save(to: cacheFile)
        }
        return result.filter { $0.date >= sinceDay }
    }

    static func merge(_ existing: [DayBucket], _ additions: [DayBucket]) -> [DayBucket] {
        var byKey: [String: DayBucket] = [:]
        var order: [String] = []
        for b in existing + additions {
            if var current = byKey[b.key] {
                current.input += b.input; current.cacheCreation += b.cacheCreation; current.cacheRead += b.cacheRead; current.output += b.output; current.messages += b.messages
                byKey[b.key] = current
            } else { byKey[b.key] = b; order.append(b.key) }
        }
        return order.compactMap { byKey[$0] }
    }

    /// All transcripts under `projects/` (resolved), including sub-agents, with their relative path;
    /// symbolic links (memory) are not followed.
    static func transcripts(in root: URL) -> [(URL, String)] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        let rootComponents = root.standardizedFileURL.pathComponents
        var files: [(URL, String)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let components = url.standardizedFileURL.pathComponents
            guard components.count > rootComponents.count else { continue }
            files.append((url, components[rootComponents.count...].joined(separator: "/")))
        }
        return files.sorted { $0.1 < $1.1 }
    }

    static let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    static let isoPlain = Date.ISO8601FormatStyle()
    static let usageMarker = Data("\"usage\"".utf8)
    static let cwdMarker = Data("\"cwd\"".utf8)

    /// Reads the file starting at `offset`, in chunks, one complete line at a time (the last one, with no line
    /// break, waits for the next pass). Lines belonging to the same message follow one another: the "open" message absorbs
    /// its following lines (maximum of each counter) and joins the day's aggregate when another message begins.
    /// The first `cwd` seen names the project; lines without usage are then not decoded at all.
    static func parse(file: URL, from offset: Int64, chunkSize: Int, project: String, open: inout OpenMessage?, projectName: inout String?, calendar: Calendar) -> (buckets: [DayBucket], consumed: Int64, lines: Int) {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return ([], 0, 0) }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: UInt64(max(0, offset)))) != nil else { return ([], 0, 0) }
        var buckets: [DayBucket] = []
        var consumed: Int64 = 0
        var lines = 0
        var buffer = Data()
        func flush(_ sample: UsageSample) {
            let day = calendar.startOfDay(for: sample.date)
            if let index = buckets.firstIndex(where: { $0.day == day && $0.project == sample.project && $0.model == sample.model }) {
                buckets[index].add(sample)
            } else {
                var bucket = DayBucket(day: day, project: sample.project, model: sample.model, input: 0, cacheCreation: 0, cacheRead: 0, output: 0, messages: 0)
                bucket.add(sample); buckets.append(bucket)
            }
        }
        func absorb(_ id: String?, _ sample: UsageSample) {
            if let id {
                if var current = open, current.id == id {
                    current.sample.input = max(current.sample.input, sample.input)
                    current.sample.cacheCreation = max(current.sample.cacheCreation, sample.cacheCreation)
                    current.sample.cacheRead = max(current.sample.cacheRead, sample.cacheRead)
                    current.sample.output = max(current.sample.output, sample.output)
                    open = current
                } else {
                    if let previous = open { flush(previous.sample) }
                    open = OpenMessage(id: id, sample: sample)
                }
            } else {
                flush(sample)
            }
        }
        // Each chunk in its own pool: the data the file handle hands out is released before the next read.
        // Lines are cut with memchr and screened with memmem; only the lines that matter are walked.
        while autoreleasepool(invoking: { () -> Bool in
            guard let chunk = try? handle.read(upToCount: max(1024, chunkSize)), !chunk.isEmpty else { return false }
            buffer.append(chunk)
            let wantsName = projectName == nil
            let done: Int = buffer.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int in
                guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
                let count = raw.count
                var start = 0
                while start < count, let found = memchr(base + start, 0x0A, count - start) {
                    let end = UnsafePointer<UInt8>(found.assumingMemoryBound(to: UInt8.self)) - base
                    let line = UnsafeBufferPointer(start: base + start, count: end - start)
                    consumed += Int64(end - start + 1)
                    lines += 1
                    start = end + 1
                    let hasUsage = memmem(line.baseAddress, line.count, "\"usage\"", 7) != nil
                    let wantsCwd = wantsName && projectName == nil && memmem(line.baseAddress, line.count, "\"cwd\"", 5) != nil
                    guard hasUsage || wantsCwd else { continue }
                    let fields = LineFields.parse(bytes: line)
                    if projectName == nil, let cwd = fields.cwd {
                        let last = URL(fileURLWithPath: cwd, isDirectory: true).lastPathComponent
                        if !last.isEmpty, last != "/" { projectName = last }
                    }
                    guard hasUsage, let (id, sample) = sample(from: fields, project: project) else { continue }
                    absorb(id, sample)
                }
                return start
            }
            if done > 0 { buffer.removeSubrange(0..<done) }
            return true
        }) {}
        return (buckets, consumed, lines)
    }

    /// An assistant message with usage becomes a sample; anything else is nothing.
    static func sample(from fields: LineFields, project: String) -> (String?, UsageSample)? {
        guard fields.type == "assistant", fields.hasUsage else { return nil }
        let stamp = fields.timestamp ?? ""
        let date = (try? Date(stamp, strategy: iso)) ?? (try? Date(stamp, strategy: isoPlain)) ?? Date()
        let sample = UsageSample(date: date, project: project, model: fields.model ?? "unknown",
                                 input: fields.input, cacheCreation: fields.cacheCreation, cacheRead: fields.cacheRead, output: fields.output)
        return (fields.messageID, sample)
    }

    /// Kept for the tests of the line format: the same result as the byte walker, from one line.
    static func parse(line: Data, project: String) -> (String?, UsageSample)? {
        sample(from: LineFields.parse(line), project: project)
    }
}

/// What an account has consumed: today, seven days, thirty days, by project, by model, by day.
public struct UsageSummary: Equatable, Sendable {
    public struct Bucket: Equatable, Sendable, Identifiable {
        public var key: String
        public var tokens: Int
        public var output: Int
        public var id: String { key }
        public init(key: String, tokens: Int, output: Int) { self.key = key; self.tokens = tokens; self.output = output }
    }
    public var today = 0, todayOutput = 0
    public var week = 0, weekOutput = 0
    public var month = 0, monthOutput = 0
    public var byProject: [Bucket] = []
    public var byModel: [Bucket] = []
    /// Fourteen days, from oldest to today, key `yyyy-MM-dd`.
    public var byDay: [Bucket] = []
    public init() {}

    public static func make(_ samples: [UsageSample], now: Date, calendar: Calendar = .current) -> UsageSummary {
        var s = UsageSummary()
        let week = calendar.startOfDay(for: now.addingTimeInterval(-7 * 86_400)), month = calendar.startOfDay(for: now.addingTimeInterval(-30 * 86_400))
        var projects: [String: Bucket] = [:], models: [String: Bucket] = [:]
        let dayKey: (Date) -> String = { d in
            let c = calendar.dateComponents([.year, .month, .day], from: d)
            return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        }
        var days: [String: Bucket] = [:]
        for x in samples where x.date >= month {
            s.month += x.total; s.monthOutput += x.output
            if x.date >= week { s.week += x.total; s.weekOutput += x.output }
            if calendar.isDate(x.date, inSameDayAs: now) { s.today += x.total; s.todayOutput += x.output }
            projects[x.project, default: Bucket(key: x.project, tokens: 0, output: 0)].add(x)
            models[x.model, default: Bucket(key: x.model, tokens: 0, output: 0)].add(x)
            days[dayKey(x.date), default: Bucket(key: dayKey(x.date), tokens: 0, output: 0)].add(x)
        }
        s.byProject = projects.values.sorted { ($0.output, $0.tokens) > ($1.output, $1.tokens) }
        s.byModel = models.values.sorted { ($0.output, $0.tokens) > ($1.output, $1.tokens) }
        s.byDay = (0..<14).reversed().compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: now).map { day in days[dayKey(day)] ?? Bucket(key: dayKey(day), tokens: 0, output: 0) }
        }
        return s
    }
}

private extension UsageSummary.Bucket {
    mutating func add(_ x: UsageSample) { tokens += x.total; output += x.output }
}
