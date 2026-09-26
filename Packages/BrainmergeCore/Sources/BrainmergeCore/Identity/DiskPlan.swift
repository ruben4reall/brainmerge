import Foundation

/// The disk space one account takes: its Claude data folder, its Claude Code profile, its app.
public struct AccountDisk: Equatable, Sendable {
    public enum Part: String, CaseIterable, Sendable { case claude, claudeCode, app }
    /// Folders of a Claude Code profile that can be links to the first account's.
    public enum Folder: String, CaseIterable, Sendable { case history, skills }
    public enum PartSize: Equatable, Sendable {
        case measured(DiskSize)
        /// The folder is, or lies inside, another account's folder: counted once, there (the account's slug).
        case countedWith(String)
        /// In a place macOS guards with a consent prompt (Documents, iCloud Drive…): never walked.
        case notMeasured
    }

    public var slug: String
    /// A part missing from the dictionary does not exist on disk.
    public var parts: [Part: PartSize]
    /// Profile folders that are links into another account's profile, counted there (history, skills).
    public var sharedWith: [Folder: String]

    public init(slug: String, parts: [Part: PartSize], sharedWith: [Folder: String] = [:]) {
        self.slug = slug; self.parts = parts; self.sharedWith = sharedWith
    }

    public func size(_ part: Part) -> DiskSize? {
        if case .measured(let size) = parts[part] { return size }
        return nil
    }
    public func bytes(_ part: Part) -> Int64? { size(part)?.bytes }

    /// The measured parts added up; complete only when every one of them was.
    public var total: DiskSize {
        let sizes = Part.allCases.compactMap(size)
        return DiskSize(bytes: sizes.reduce(0) { $0 + $1.bytes }, complete: sizes.allSatisfy(\.complete))
    }
    /// At least one part was walked.
    public var isMeasured: Bool { Part.allCases.contains { size($0) != nil } }
}

/// Which folders to walk for which account, so that each byte is counted once. Planning only looks at paths and at
/// link texts (readlink): it never lists a folder and never steps into a place that asks macOS for consent.
public enum DiskPlan {
    public struct Root: Equatable, Sendable {
        public let slug: String
        public let part: AccountDisk.Part
        /// Where the folder really is, links resolved.
        public let url: URL
        /// A tinted copy: its allocated size is mostly Claude's own blocks, shared by the clone.
        public let privateOnly: Bool
        /// Other planned folders inside this one, left to their own account.
        public let skipping: [URL]
    }

    public struct Plan: Equatable, Sendable {
        /// The accounts, in the order given (the sidebar's).
        public var slugs: [String]
        public var roots: [Root]
        public var countedWith: [String: [AccountDisk.Part: String]]
        public var protected: [String: Set<AccountDisk.Part>]
        public var sharedWith: [String: [AccountDisk.Folder: String]]
    }

    /// The first account first, so a folder two accounts reach is counted with it: shared history, shared skills,
    /// an adopted folder that is another account's.
    public static func plan(for identities: [Identity], paths: Paths) -> Plan {
        let home = paths.home
        let ordered = identities.filter(\.isPrimary) + identities.filter { !$0.isPrimary }
        var planned: [Root] = []
        var countedWith: [String: [AccountDisk.Part: String]] = [:]
        var protected: [String: Set<AccountDisk.Part>] = [:]
        for identity in ordered {
            var candidates: [(AccountDisk.Part, URL, Bool)] = [(.claude, identity.desktopData(in: paths), false),
                                                               (.claudeCode, identity.cliProfile(in: paths), false)]
            if let app = identity.appURL(in: paths) {
                candidates.append((.app, app, !identity.isPrimary && identity.iconMode == .tintedClone))
            }
            for (part, url, privateOnly) in candidates {
                guard let real = resolve(url, home: home) else { protected[identity.slug, default: []].insert(part); continue }
                if let owner = planned.first(where: { contains($0.url, real) }) {
                    if owner.slug != identity.slug { countedWith[identity.slug, default: [:]][part] = owner.slug }
                    continue
                }
                planned.append(Root(slug: identity.slug, part: part, url: real, privateOnly: privateOnly, skipping: []))
            }
        }
        let roots = planned.map { root in
            Root(slug: root.slug, part: root.part, url: root.url, privateOnly: root.privateOnly,
                 skipping: planned.filter { $0 != root && contains(root.url, $0.url) }.map(\.url))
        }
        var sharedWith: [String: [AccountDisk.Folder: String]] = [:]
        for root in roots where root.part == .claudeCode {
            for (folder, name) in [(AccountDisk.Folder.history, "projects"), (.skills, "skills")] {
                let lexical = root.url.appending(path: name)
                guard let real = resolve(lexical, home: home), real.path != lexical.path,
                      let owner = roots.first(where: { $0.part == .claudeCode && $0.slug != root.slug && contains($0.url, real) })
                else { continue }
                sharedWith[root.slug, default: [:]][folder] = owner.slug
            }
        }
        return Plan(slugs: identities.map(\.slug), roots: roots, countedWith: countedWith, protected: protected, sharedWith: sharedWith)
    }

    /// Walks every planned folder with `measure` (nil: it does not exist) and puts each account together.
    public static func measure(_ plan: Plan, with measure: (Root) -> DiskSize?) -> [String: AccountDisk] {
        var parts: [String: [AccountDisk.Part: AccountDisk.PartSize]] = [:]
        for root in plan.roots { if let size = measure(root) { parts[root.slug, default: [:]][root.part] = .measured(size) } }
        for (slug, owners) in plan.countedWith { for (part, owner) in owners { parts[slug, default: [:]][part] = .countedWith(owner) } }
        for (slug, guarded) in plan.protected { for part in guarded { parts[slug, default: [:]][part] = .notMeasured } }
        return Dictionary(uniqueKeysWithValues: plan.slugs.map { slug in
            (slug, AccountDisk(slug: slug, parts: parts[slug] ?? [:], sharedWith: plan.sharedWith[slug] ?? [:]))
        })
    }

    /// Places macOS guards with a consent prompt: walking them from Brainmerge would ask the person, for a number.
    public static func isProtected(_ url: URL, home: URL) -> Bool {
        let path = "/" + components(of: url.path).joined(separator: "/")
        let base = "/" + components(of: home.path).joined(separator: "/")
        let guarded = ["Desktop", "Documents", "Downloads", "Library/Mobile Documents", "Library/CloudStorage"].map { base + "/" + $0 } + ["/Volumes"]
        return guarded.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    /// A path's components with "." and ".." applied, as text only. Foundation's standardizing is not used: it drops
    /// "/private" from "/private/var", which undoes the very link it resolves.
    static func components(of path: String) -> [String] {
        var result: [String] = []
        for part in path.split(separator: "/") where part != "." {
            if part == ".." { _ = result.popLast() } else { result.append(String(part)) }
        }
        return result
    }

    /// Where a path really is, links resolved, or nil when it reaches a protected place: links are followed one
    /// component at a time from their text alone, since realpath would already stat inside such a place.
    public static func resolve(_ url: URL, home: URL) -> URL? {
        // The home can itself sit behind a link (/var is /private/var): both spellings are guarded.
        let homes = [home, follow(home) { _ in false } ?? home]
        return follow(url) { candidate in homes.contains { isProtected(candidate, home: $0) } }
    }

    private static func follow(_ url: URL, refusing: (URL) -> Bool) -> URL? {
        var remaining = components(of: url.path)
        var done: [String] = []
        var hops = 0
        while !remaining.isEmpty {
            let next = remaining.removeFirst()
            let candidate = URL(fileURLWithPath: "/" + (done + [next]).joined(separator: "/"))
            if refusing(candidate) { return nil }
            if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: candidate.path) {
                hops += 1
                guard hops <= 32 else { return nil }   // a loop of links
                let base = target.hasPrefix("/") ? target : "/" + (done + [target]).joined(separator: "/")
                remaining = components(of: base) + remaining
                done = []
                continue
            }
            done.append(next)
        }
        return URL(fileURLWithPath: "/" + done.joined(separator: "/"))
    }

    /// `inner` is `outer` or lies inside it.
    static func contains(_ outer: URL, _ inner: URL) -> Bool {
        inner.path == outer.path || inner.path.hasPrefix(outer.path.hasSuffix("/") ? outer.path : outer.path + "/")
    }
}
