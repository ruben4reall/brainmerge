import Foundation

/// An app the person made themselves that opens one of their Claude accounts, such as a copy of Claude whose
/// executable was replaced by a launch script with its own folders. Found by reading the bundle; never run,
/// adopted, re-signed, moved or trashed by Brainmerge.
public struct ExistingApp: Equatable, Sendable {
    /// The name shown in Finder (the bundle's file name without ".app").
    public let name: String
    public let url: URL
    /// A copy of Claude itself: Claude's bundle id and its frameworks inside.
    public let isClaudeCopy: Bool
    /// The version of Claude the copy runs; nil when the app is not a copy of Claude.
    public let claudeVersion: String?
    /// The Claude data folder its script passes (`--user-data-dir=`).
    public let dataDir: URL?
    /// The Claude Code folder its script sets (`CLAUDE_CONFIG_DIR=`).
    public let configDir: URL?

    public init(name: String, url: URL, isClaudeCopy: Bool, claudeVersion: String?, dataDir: URL?, configDir: URL?) {
        self.name = name; self.url = url; self.isClaudeCopy = isClaudeCopy; self.claudeVersion = claudeVersion
        self.dataDir = dataDir; self.configDir = configDir
    }

    /// It uses one of this account's folders: whole paths compared, so "Claude-Second" is not "Claude-Second-2".
    public func opens(_ identity: Identity, in paths: Paths) -> Bool {
        dataDir.map { ExistingApps.sameFolder($0, identity.desktopData(in: paths)) } == true
            || configDir.map { ExistingApps.sameFolder($0, identity.cliProfile(in: paths)) } == true
    }

    /// A copy of Claude older than the one installed: opening the account's data with it can damage that data.
    public func runsOlderClaude(than installed: String) -> Bool {
        guard isClaudeCopy, let claudeVersion else { return false }
        return claudeVersion.compare(installed, options: .numeric) == .orderedAscending
    }
}

/// Finds the apps of `ExistingApp`: the top level of ~/Applications (and /Applications for the real home), without
/// Brainmerge's own apps and without Claude itself. Per bundle, only its Info.plist (under 1 MB) and, when it is a short
/// script (it starts with "#!", under 64 KB), the script's text; no link inside a bundle is followed. Nothing is executed
/// and nothing inside a Claude data folder is read.
public struct ExistingApps: Sendable {
    public let paths: Paths
    public let claudeAppURL: URL
    public let folders: [URL]

    /// A launch line is short: anything larger is not read.
    static let maxScriptBytes = 64 * 1024
    /// An Info.plist is a few kilobytes: anything larger is not read.
    static let maxInfoPlistBytes = 1024 * 1024

    public init(paths: Paths, claudeAppURL: URL, folders: [URL]? = nil) {
        self.paths = paths; self.claudeAppURL = claudeAppURL; self.folders = folders ?? Self.folders(for: paths)
    }

    /// ~/Applications, plus /Applications when `paths` is the real home. A test or demo home never sees the Mac's
    /// apps: "$HOME" in their scripts means the real home, not that one.
    public static func folders(for paths: Paths, realHome: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        let own = paths.home.appending(path: "Applications", directoryHint: .isDirectory)
        let isReal = sameFolder(paths.home.resolvingSymlinksInPath(), realHome.resolvingSymlinksInPath())
        return isReal ? [own, URL(fileURLWithPath: "/Applications", isDirectory: true)] : [own]
    }

    /// Every app found that passes a folder to Claude, in folder order then by name.
    public func scan() -> [ExistingApp] {
        let fm = FileManager.default
        let skipped = [claudeAppURL, paths.launchersDir]
        var found: [ExistingApp] = []
        for folder in folders {
            guard let entries = try? fm.contentsOfDirectory(atPath: folder.path) else { continue }
            let bundles = entries.filter { ($0 as NSString).pathExtension.lowercased() == "app" }
                .map { ($0 as NSString).deletingPathExtension }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            for name in bundles {
                let bundle = folder.appending(path: "\(name).app", directoryHint: .isDirectory)
                guard !skipped.contains(where: { Self.sameFolder($0, bundle) }), let app = read(bundle, name: name) else { continue }
                found.append(app)
            }
        }
        return found
    }

    /// The apps that open this account.
    public func apps(opening identity: Identity) -> [ExistingApp] {
        scan().filter { $0.opens(identity, in: paths) }
    }

    /// Only the bundle's own files are read: the bundle, Contents and MacOS must be real folders, and Info.plist and the
    /// executable regular files, none of them a link. So a bundle can never point the reader into a Claude data folder.
    func read(_ bundle: URL, name: String) -> ExistingApp? {
        let contents = bundle.appending(path: "Contents", directoryHint: .isDirectory)
        let macos = contents.appending(path: "MacOS", directoryHint: .isDirectory)
        guard Self.isRealFolder(bundle), Self.isRealFolder(contents), Self.isRealFolder(macos),
              let plist = Self.readFile(at: contents.appending(path: "Info.plist"), maxBytes: Self.maxInfoPlistBytes),
              let info = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any],
              let executable = info["CFBundleExecutable"] as? String,
              !executable.isEmpty, !executable.contains("/"), executable != "..", executable != ".",
              let script = Self.script(at: macos.appending(path: executable))
        else { return nil }
        let folders = Self.launchFolders(script: script, home: paths.home)
        guard folders.dataDir != nil || folders.configDir != nil else { return nil }
        let copy = info["CFBundleIdentifier"] as? String == ClaudeApp.bundleIdentifier
            && Self.isRealFolder(contents.appending(path: "Frameworks", directoryHint: .isDirectory))
        return ExistingApp(name: name, url: bundle, isClaudeCopy: copy,
                           claudeVersion: copy ? info["CFBundleShortVersionString"] as? String : nil,
                           dataDir: folders.dataDir, configDir: folders.configDir)
    }

    /// The text of a short script (a regular file starting with "#!", under 64 KB), read and never run; nil for anything
    /// else. Only its first two bytes are read unless they are "#!".
    static func script(at url: URL) -> String? {
        readFile(at: url, maxBytes: maxScriptBytes - 1, startingWith: [0x23, 0x21]).map { String(decoding: $0, as: UTF8.self) }
    }

    /// A folder that is not a link.
    static func isRealFolder(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
    }

    /// The bytes of a regular file of at most `maxBytes`. Opened without following a link and without waiting (a pipe put
    /// in its place is never waited on), then checked on the open file itself, so nothing can be swapped in between.
    /// With `startingWith`, those bytes are read first and nothing more unless they match.
    static func readFile(at url: URL, maxBytes: Int, startingWith prefix: [UInt8] = []) -> Data? {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_size <= maxBytes else { return nil }
        let size = Int(info.st_size)
        guard size >= prefix.count else { return nil }
        let head = readBytes(descriptor, count: prefix.count)
        guard head == prefix else { return nil }
        return Data(head + readBytes(descriptor, count: size - prefix.count))
    }

    static func readBytes(_ descriptor: Int32, count: Int) -> [UInt8] {
        guard count > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: count)
        var total = 0
        while total < count {
            let n = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress! + total, count - total) }
            if n < 0, errno == EINTR { continue }
            if n <= 0 { break }
            total += n
        }
        return Array(buffer.prefix(total))
    }

    /// Two folders are the same when their standardized paths match whole, ignoring case and Unicode form (APFS).
    static func sameFolder(_ a: URL, _ b: URL) -> Bool { folderKey(a) == folderKey(b) }

    static func folderKey(_ url: URL) -> String {
        var path = url.standardizedFileURL.path
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path.precomposedStringWithCanonicalMapping.lowercased()
    }

    // MARK: Reading a launch script

    /// The folders a launch script gives Claude: the value of `--user-data-dir=` and of a `CLAUDE_CONFIG_DIR=` assignment,
    /// quoted or not, with `$HOME`, `${HOME}` and a leading `~` expanded against `home`. A value built from anything else
    /// (another variable, a command, a relative path) is unknown, so nil. The last one wins, as when the script runs.
    static func launchFolders(script: String, home: URL) -> (dataDir: URL?, configDir: URL?) {
        let homePath = home.standardizedFileURL.path
        var dataDir: URL?, configDir: URL?
        for command in ScriptWords.commands(in: script) {
            var index = 0
            while index < command.count, ScriptWords.keywords.contains(command[index].text) { index += 1 }
            // Assignments before the command: NAME=value, the name unquoted.
            while index < command.count, let name = command[index].assignedName {
                if name == configKey { configDir = command[index].value(after: configKey.count + 1, home: homePath) }
                index += 1
            }
            // export, env and their kind take NAME=value arguments.
            if index < command.count, ScriptWords.assigningCommands.contains(command[index].text) {
                for word in command[(index + 1)...] where word.text.hasPrefix(configKey + "=") {
                    configDir = word.value(after: configKey.count + 1, home: homePath)
                }
            }
            for word in command where word.text.hasPrefix(dataFlag) {
                dataDir = word.value(after: dataFlag.count, home: homePath)
            }
        }
        return (dataDir, configDir)
    }

    static let configKey = "CLAUDE_CONFIG_DIR"
    static let dataFlag = "--user-data-dir="
}

/// Just enough of the shell's word rules to read a launch line: quotes, backslashes, comments, command separators and
/// substitutions (kept opaque). Every character remembers how it was quoted, which decides what expands.
struct ScriptWords {
    enum Quoting: Equatable { case none, single, double, escaped, substitution }

    struct Word {
        var characters: [(Character, Quoting)] = []
        /// The word once its quotes are removed (a substitution shows as a placeholder that never matches a key).
        var text: String { String(characters.map(\.0)) }

        /// NAME when the word is an assignment NAME=value with its name and "=" unquoted.
        var assignedName: String? {
            guard let equals = characters.firstIndex(where: { $0.0 == "=" && $0.1 == .none }), equals > 0 else { return nil }
            let name = characters[..<equals]
            guard name.allSatisfy({ $0.1 == .none && ($0.0.isLetter || $0.0.isNumber || $0.0 == "_") && $0.0.isASCII }),
                  let first = name.first?.0, !first.isNumber else { return nil }
            return String(name.map(\.0))
        }

        /// The folder the characters after `offset` name, expanded; nil when it cannot be known without running anything.
        func value(after offset: Int, home: String) -> URL? {
            let value = Array(characters.dropFirst(offset))
            var path = ""
            var index = 0
            if let first = value.first, first == ("~", .none) {
                guard value.count == 1 || value[1].0 == "/" else { return nil }   // "~bob" is another person's home
                path = home; index = 1
            }
            while index < value.count {
                let (character, quoting) = value[index]
                if quoting == .substitution { return nil }
                if character == "$", quoting == .none || quoting == .double {
                    let rest = value[(index + 1)...].prefix { $0.1 == quoting }.map(\.0)
                    if rest.starts(with: Array("{HOME}")) { path += home; index += 7; continue }
                    if rest.starts(with: Array("HOME")), rest.count == 4 || !Self.isNameCharacter(rest[4]) {
                        path += home; index += 5; continue
                    }
                    if let next = rest.first, Self.isNameCharacter(next) || "{(@*#?$!-".contains(next) { return nil }
                }
                path.append(character)
                index += 1
            }
            guard path.hasPrefix("/") else { return nil }
            return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        }

        static func isNameCharacter(_ c: Character) -> Bool { c.isASCII && (c.isLetter || c.isNumber || c == "_") }
    }

    /// Words that open a command without being one.
    static let keywords: Set<String> = ["{", "}", "!", "then", "do", "else", "elif", "if", "while", "until", "time"]
    /// Commands whose NAME=value arguments set a variable.
    static let assigningCommands: Set<String> = ["export", "env", "declare", "typeset", "readonly", "local"]

    /// The script's simple commands, each as its words.
    static func commands(in script: String) -> [[Word]] {
        let characters = Array(script)
        var commands: [[Word]] = [], command: [Word] = []
        var word = Word(), inWord = false
        func endWord() { if inWord { command.append(word) }; word = Word(); inWord = false }
        func endCommand() { endWord(); if !command.isEmpty { commands.append(command) }; command = [] }
        var index = 0
        while index < characters.count {
            let character = characters[index]
            switch character {
            case "\\":
                if index + 1 < characters.count {
                    if !characters[index + 1].isNewline { word.characters.append((characters[index + 1], .escaped)); inWord = true }
                    index += 1
                }
            case "'":
                inWord = true
                index += 1
                while index < characters.count, characters[index] != "'" { word.characters.append((characters[index], .single)); index += 1 }
            case "\"":
                inWord = true
                index += 1
                while index < characters.count, characters[index] != "\"" {
                    if characters[index] == "\\", index + 1 < characters.count, "$`\"\\\n".contains(characters[index + 1]) {
                        if characters[index + 1] != "\n" { word.characters.append((characters[index + 1], .escaped)) }
                        index += 2; continue
                    }
                    if let end = substitutionEnd(characters, at: index) {
                        word.characters.append(("\u{FFFC}", .substitution)); index = end + 1; continue
                    }
                    word.characters.append((characters[index], .double)); index += 1
                }
            case "#" where !inWord:
                while index + 1 < characters.count, !characters[index + 1].isNewline { index += 1 }
            case " ", "\t", "<", ">":
                endWord()
            case "\n", "\r", "\r\n", ";", "&", "|", "(", ")":
                endCommand()
            default:
                if let end = substitutionEnd(characters, at: index) {
                    word.characters.append(("\u{FFFC}", .substitution)); inWord = true; index = end + 1; continue
                }
                word.characters.append((character, .none)); inWord = true
            }
            index += 1
        }
        endCommand()
        return commands
    }

    /// Where a `$(...)` or a backquoted command starting at `index` ends (its closing character), or nil if none starts there.
    static func substitutionEnd(_ characters: [Character], at index: Int) -> Int? {
        if characters[index] == "`" {
            var end = index + 1
            while end < characters.count, characters[end] != "`" { end += characters[end] == "\\" ? 2 : 1 }
            return min(end, characters.count - 1)
        }
        guard characters[index] == "$", index + 1 < characters.count, characters[index + 1] == "(" else { return nil }
        var depth = 0, end = index + 1
        var quote: Character?
        while end < characters.count {
            let c = characters[end]
            if let open = quote {
                if c == "\\", open == "\"" { end += 2; continue }
                if c == open { quote = nil }
            } else if c == "'" || c == "\"" {
                quote = c
            } else if c == "\\" {
                end += 2; continue
            } else if c == "(" {
                depth += 1
            } else if c == ")" {
                depth -= 1
                if depth == 0 { return end }
            }
            end += 1
        }
        return characters.count - 1
    }
}
