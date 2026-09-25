import Foundation
import Testing
@testable import BrainmergeCore

/// The promises of the README, enforced on the source tree: no network, no shell interpreter, no reading of
/// Claude's credential stores, one place that runs processes. A failure here is a broken promise, not a style nit.
@Suite struct SecurityGuardTests {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    /// The shipped code: the core, the command line, the launcher and its guard, the app. Test fakes (BrainmergeTestSupport) are not shipped.
    static let roots = ["Packages/BrainmergeCore/Sources/BrainmergeCore", "Packages/BrainmergeCore/Sources/brainmerge",
                        "Packages/BrainmergeCore/Sources/launcher", "Packages/BrainmergeCore/Sources/LauncherGuard", "Packages/BrainmergeUI/Sources", "App"].map { repo.appending(path: $0) }

    static func sources() throws -> [(URL, String)] {
        var files: [(URL, String)] = []
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                files.append((url, try String(contentsOf: url, encoding: .utf8)))
            }
        }
        #expect(files.count > 40, "the scan must see the whole tree")
        return files
    }

    func offenders(_ patterns: [String], except allowed: Set<String> = []) throws -> [String] {
        var found: [String] = []
        for (url, text) in try Self.sources() where !allowed.contains(url.lastPathComponent) {
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where patterns.contains(where: { line.contains($0) }) && !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                found.append("\(url.lastPathComponent):\(number + 1): \(line.trimmingCharacters(in: .whitespaces).prefix(80))")
            }
        }
        return found
    }

    @Test func noNetworkCode() throws {
        let hits = try offenders(["URLSession", "NWConnection", "import Network", "CFNetwork", "NSURLConnection", "URLProtocol", "WebSocket"])
        #expect(hits.isEmpty, "\(hits)")
    }

    @Test func noShellInterpreterAndOneProcessRunner() throws {
        let shells = try offenders(["/bin/sh", "/bin/bash", "/bin/zsh", "NSAppleScript", "osascript", "system(\"", "popen("])
        #expect(shells.isEmpty, "\(shells)")
        let processes = try offenders(["Process()", "NSTask", "posix_spawn"], except: ["Shell.swift"])
        #expect(processes.isEmpty, "\(processes)")
    }

    @Test func credentialStoresAreNamedNeverRead() throws {
        // Only DesktopSession may mention Claude's storage files, and it may only test their presence.
        let mentions = try offenders(["\"Cookies\"", "Local Storage", "IndexedDB", "Session Storage", "SecItemCopyMatching", "SecKeychain", ".credentials.json", "sessionKey"], except: ["DesktopSession.swift"])
        #expect(mentions.isEmpty, "\(mentions)")
        let session = try #require(try Self.sources().first { $0.0.lastPathComponent == "DesktopSession.swift" }).1
        for forbidden in ["Data(contentsOf", "String(contentsOf", "FileHandle", "contents(atPath", "InputStream"] {
            #expect(!session.contains(forbidden), "DesktopSession must not read file contents: \(forbidden)")
        }
    }

    @Test func claudeCodeSecretsAreNeverNamed() throws {
        // Keys, tokens, the desktop app's token cache and account id, the keychain entry, plan and usage: no shipped file names them, not even to skip them.
        let hits = try offenders(["primaryApiKey", "customApiKeyResponses", "accessToken", "refreshToken", "oauth:tokenCache",
                                  "lastKnownAccountUuid", "buddy-tokens", "Claude Code-credentials", "cachedUsageUtilization", "RateLimitTier"])
        #expect(hits.isEmpty, "\(hits)")
    }

    /// Claude Code's account entry is read in one file, for three display fields only (SECURITY.md).
    @Test func accountEntryIsDisplayFieldsOnly() throws {
        let elsewhere = try offenders(["oauthAccount"], except: ["ClaudeCodeAccount.swift"])
        #expect(elsewhere.isEmpty, "only ClaudeCodeAccount.swift reads the account entry: \(elsewhere)")
        #expect(ClaudeCodeAccount.readFields == ["emailAddress", "displayName", "organizationName"])

        let file = try #require(try Self.sources().first { $0.0.lastPathComponent == "ClaudeCodeAccount.swift" })
        let code = file.1.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        // Typed decoding of declared keys only: nothing that loads the whole entry, nothing about identifiers, tokens, plan,
        // roles or limits, whatever the case of the word.
        let lowered = code.lowercased()
        for forbidden in ["jsonserialization", "[string: any]", "[string:any]", "uuid", "userid", "token", "secitem", "billing",
                          "ratelimit", "seattier", "usage", "subscription", "role", "createdat"] {
            #expect(!lowered.contains(forbidden), "ClaudeCodeAccount.swift must not mention \(forbidden)")
        }
        // Every key it can decode is a case of a CodingKey enum: together they are exactly the entry and its three fields.
        let enums = try Regex(#"enum\s+\w+\s*:[^{]*CodingKey[^{]*\{([^}]*)\}"#)
        let bodies = code.matches(of: enums).map { String($0.output[1].substring ?? "") }
        #expect(bodies.count >= 2, "the scan must see the entry's key and its fields")
        let caseLine = try Regex(#"case\s+([^\n;]+)"#)
        let keys = Set(bodies.flatMap { body in
            body.matches(of: caseLine).flatMap { String($0.output[1].substring ?? "").split(separator: ",") }
                .map { $0.split(separator: "=").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? "" }
        })
        #expect(keys == ["oauthAccount", "emailAddress", "displayName", "organizationName"], "decodable keys: \(keys)")
        // Its paths come from the profile it is given, never from the process: tests and demo captures never read the owner's real file.
        for forbidden in ["NSHomeDirectory", "homeDirectoryForCurrentUser", "ProcessInfo", "getenv", "environment", "CLAUDE_CONFIG_DIR"] {
            #expect(!code.contains(forbidden), "ClaudeCodeAccount.swift must not resolve paths itself: \(forbidden)")
        }
        let literals = try Regex(#""((?:[^"\\]|\\.)*)""#)
        let found = Set(code.matches(of: literals).map { String($0.output[1].substring ?? "") })
        let allowed: Set<String> = ["oauthAccount", "emailAddress", "displayName", "organizationName", ".claude.json", "'s Organization"]
        #expect(found.isSubset(of: allowed), "unexpected string literals: \(found.subtracting(allowed))")
    }

    /// Apps the person made are read, never run, changed or moved (SECURITY.md): no process, no opening, no writing, no
    /// trash, no link followed. What it may call on the file system is a short list; everything else is refused.
    @Test func existingAppsOnlyReadsBundles() throws {
        let file = try #require(try Self.sources().first { $0.0.lastPathComponent == "ExistingApps.swift" })
        let code = file.1.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        for forbidden in ["Shell", "Process", "execv", "execl", "posix_spawn", "fork(", "system(", "popen", "dlopen", "Bundle(", "NSAppleScript",
                          "NSWorkspace", "LSOpen", "bash", "codesign", "lsregister",
                          "FileHandle", "Data(contentsOf", "String(contentsOf", "InputStream", "Plist.read", "mmap",
                          "trashItem", "removeItem", "moveItem", "copyItem", "replaceItem", "linkItem", "createFile", "createDirectory",
                          "createSymbolicLink", "setAttributes", "setResourceValues", "write(", "unlink", "rename(", "truncate", "symlink(",
                          "link(", "mkdir", "rmdir", "chmod", "chown", "utimes", "setxattr", "removexattr",
                          "O_WRONLY", "O_RDWR", "O_CREAT", "O_TRUNC", "O_APPEND"] {
            #expect(!code.contains(forbidden), "ExistingApps.swift must only read: \(forbidden)")
        }
        // The file manager: listing a folder, nothing else.
        let members = try Regex(#"(?:FileManager\.default|\bfm)\s*\.\s*(\w+)"#)
        let used = Set(code.matches(of: members).map { String($0.output[1].substring ?? "") })
        #expect(used.isSubset(of: ["contentsOfDirectory", "homeDirectoryForCurrentUser"]), "file manager calls: \(used.subtracting(["contentsOfDirectory", "homeDirectoryForCurrentUser"]))")
        // Files are opened read only, never through a link, never waiting on a pipe.
        let opens = try Regex(#"\bopen\(([^)]*)\)"#)
        let flags = code.matches(of: opens).map { String($0.output[1].substring ?? "") }
        #expect(!flags.isEmpty)
        for call in flags { #expect(call.contains("O_RDONLY") && call.contains("O_NOFOLLOW") && call.contains("O_NONBLOCK"), "open(\(call))") }
    }

    /// Disk sizes come from the sizes the file system reports while listing a folder (SECURITY.md): the walker opens no
    /// file, reads no content or extended attribute, turns no name into text, follows no link, enters no other disk,
    /// writes nothing and starts nothing.
    @Test func diskSizesAreReadNeverContents() throws {
        let file = try #require(try Self.sources().first { $0.0.lastPathComponent == "DiskUsage.swift" })
        let code = file.1.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        #expect(code.contains("FTS_PHYSICAL") && code.contains("FTS_XDEV"), "the walk must not follow links nor cross disks")
        for forbidden in ["FTS_LOGICAL", "FTS_COMFOLLOW", "Data(contentsOf", "String(contentsOf", "FileHandle", "InputStream", "fopen",
                          "mmap", "getxattr", "listxattr", "String(cString", "String(validatingCString", "readlink",
                          "removeItem", "moveItem", "write(", "setAttributes", "unlink", "rename(", "contentsOfDirectory",
                          "Shell", "Process", "posix_spawn", "O_RDONLY", "O_RDWR", "O_WRONLY"] {
            #expect(!code.contains(forbidden), "DiskUsage.swift must only add up sizes: \(forbidden)")
        }
        // Plain word boundaries: fts_open and fts_read are the walk itself, open( and read( would be a file's contents.
        for call in [#"\bopen\("#, #"\bread\("#, #"\bpread\("#, #"\bopenat\("#] {
            #expect(code.firstMatch(of: try Regex(call)) == nil, "DiskUsage.swift must not open or read a file: \(call)")
        }
    }

    /// Planning which folders to walk only looks at paths and at link texts (SECURITY.md): DiskPlan.swift may resolve a
    /// link, never list a folder, read a file, write, or start anything. The one file manager call it may make reads a
    /// link's text.
    @Test func diskPlanOnlyResolvesLinks() throws {
        let file = try #require(try Self.sources().first { $0.0.lastPathComponent == "DiskPlan.swift" })
        let code = file.1.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        #expect(code.contains("destinationOfSymbolicLink"), "the guard must see the link resolution")
        for forbidden in ["contentsOfDirectory", "subpathsOfDirectory", "enumerator", "fts_open", "opendir", "readdir", "glob(",
                          "Data(contentsOf", "String(contentsOf", "FileHandle", "InputStream", "fopen", "mmap", "getxattr", "listxattr",
                          "fileExists", "attributesOfItem", "resourceValues", "realpath", "resolvingSymlinksInPath", "stat(",
                          "removeItem", "moveItem", "copyItem", "createFile", "createDirectory", "write(", "setAttributes",
                          "unlink", "rename(", "Shell", "Process", "posix_spawn", "NSWorkspace", "O_RDONLY", "O_RDWR", "O_WRONLY"] {
            #expect(!code.contains(forbidden), "DiskPlan.swift must only resolve links: \(forbidden)")
        }
        for call in [#"\bopen\("#, #"\bread\("#, #"\bopenat\("#] {
            #expect(code.firstMatch(of: try Regex(call)) == nil, "DiskPlan.swift must not open or read a file: \(call)")
        }
        let members = try Regex(#"(?:FileManager\.default|\bfm)\s*\.\s*(\w+)"#)
        let used = Set(code.matches(of: members).map { String($0.output[1].substring ?? "") })
        #expect(used == ["destinationOfSymbolicLink"], "file manager calls: \(used)")
    }

    /// The RAM of Claude's processes is asked of the kernel as one number per process. Nothing reads another process's
    /// arguments with their environment (KERN_PROCARGS2 returns both, and an environment can hold API keys), its memory,
    /// or its open files; `ps` is asked for pid, parent, size and arguments, never the environment.
    @Test func processesAreMeasuredNeverRead() throws {
        let reads = try offenders(["KERN_PROCARGS", "KERN_PROC_ARGS", "task_for_pid", "mach_vm_read", "vm_read(", "proc_pidfdinfo",
                                   "PROC_PIDLISTFDS", "PROC_PIDFDVNODEPATHINFO", "proc_pidinfo", "proc_listpids", "PROC_PIDREGIONPATHINFO"])
        #expect(reads.isEmpty, "\(reads)")
        let rusage = try offenders(["proc_pid_rusage"], except: ["ProcessMonitor.swift"])
        #expect(rusage.isEmpty, "only ProcessMonitor.swift asks for a footprint: \(rusage)")
        // One ps call, with exactly these arguments: -E or an "e" keyword would print every environment.
        let calls = try Self.sources().flatMap { url, text in text.matches(of: try Regex(#""/bin/ps",\s*\[([^\]]*)\]"#)).map { (url.lastPathComponent, String($0.output[1].substring ?? "")) } }
        #expect(calls.count == 1 && calls.first?.0 == "ProcessMonitor.swift", "\(calls)")
        #expect(calls.first?.1 == #""-axo", "pid=,ppid=,rss=,args=""#, "\(calls)")
        #expect(try offenders(["\"/bin/ps\""], except: ["ProcessMonitor.swift"]).isEmpty)
    }

    /// The repository is public: no real person's email address in it, not even in a test. Examples use example.com.
    @Test func noRealEmailAddressInTheRepository() throws {
        let skipped: Set<String> = [".git", ".build", ".swiftpm", "graphify-out", "DerivedData", "dist", "node_modules"]
        let text: Set<String> = ["swift", "md", "sh", "html", "css", "js", "json", "yml", "yaml", "txt", "plist", "entitlements", "pbxproj"]
        let address = try Regex(#"[A-Za-z0-9._%+-]+@((?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,})"#)
        let allowed: Set<String> = ["example.com", "example.org", "example.net", "brainmerge.local"]
        var found: [String] = []
        var scanned = 0
        let walk = try #require(FileManager.default.enumerator(at: Self.repo, includingPropertiesForKeys: [.isDirectoryKey]))
        for case let url as URL in walk {
            if skipped.contains(url.lastPathComponent) { walk.skipDescendants(); continue }
            guard text.contains(url.pathExtension.lowercased()), let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            scanned += 1
            for match in content.matches(of: address) {
                let domain = String(match.output[1].substring ?? "").lowercased()
                // Retina image names ("icon_16x16@2x.png") are not addresses.
                if allowed.contains(domain) || domain.range(of: #"^\d+x\."#, options: .regularExpression) != nil { continue }
                found.append("\(url.path.replacingOccurrences(of: Self.repo.path + "/", with: "")): \(match.output[0].substring ?? "")")
            }
        }
        #expect(scanned > 100, "the scan must see the tests and the docs too")
        #expect(found.isEmpty, "\(found)")
    }

    /// An Obsidian vault shown in the graph is only read (SECURITY.md): the code that lists vaults, reads their graph
    /// settings, evaluates their queries and builds their graph writes nothing, starts nothing, and never turns a vault
    /// into a Brainmerge memory. Obsidian's list of vaults is decoded for its folders' paths only.
    @Test func obsidianVaultsAreOnlyRead() throws {
        let names: Set<String> = ["ObsidianVaults.swift", "ObsidianGraphSettings.swift", "ObsidianQuery.swift", "ObsidianGraphFilter.swift", "MemoryGraph.swift"]
        let files = try Self.sources().filter { names.contains($0.0.lastPathComponent) }
        #expect(Set(files.map(\.0.lastPathComponent)) == names, "the guard must see every file of the vault graph")
        for (url, text) in files {
            let code = text.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
            for forbidden in ["write(", "createFile", "createDirectory", "removeItem", "moveItem", "copyItem", "replaceItem", "trashItem",
                              "setAttributes", "setResourceValues", "createSymbolicLink", "unlink", "rename(", "mkdir", "O_WRONLY", "O_RDWR",
                              "O_CREAT", "Brain.initialize", "BrainGit", "Shell", "Process", "NSWorkspace", "UserDefaults", "fopen"] {
                #expect(!code.contains(forbidden), "\(url.lastPathComponent) must only read: \(forbidden)")
            }
        }
        let list = try #require(files.first { $0.0.lastPathComponent == "ObsidianVaults.swift" }).1
        #expect(!list.contains("JSONSerialization") && !list.contains("[String: Any]"), "obsidian.json is decoded for paths only")
    }

    /// "Check limits" reads the text Claude Code prints and nothing else (SECURITY.md): the files that find Claude Code and
    /// ask it open no file, decode no JSON, look at no login or keychain, take nothing from Brainmerge's own environment,
    /// start nothing but through Shell, and ask exactly `--version` and `-p "/usage"`.
    @Test func limitsAreClaudeCodesPrintedText() throws {
        let names: Set<String> = ["ClaudeCodeLimits.swift", "ClaudeCodeBinary.swift"]
        let files = try Self.sources().filter { names.contains($0.0.lastPathComponent) }
        #expect(Set(files.map(\.0.lastPathComponent)) == names, "the guard must see both files")
        for (url, text) in files {
            let code = text.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
            for forbidden in ["Data(contentsOf", "String(contentsOf", "FileHandle", "InputStream", "fopen", "mmap", "contentsOfDirectory",
                              "JSONSerialization", "JSONDecoder", "Decodable", "PropertyListSerialization", "Plist.read", ".claude.json",
                              "oauthAccount", "credential", "eychain", "SecItem", "ProcessInfo", "getenv", "environ[", "--output-format",
                              "json", "Process(", "posix_spawn", "execv", "NSWorkspace", "UserDefaults", "write(", "createFile", "removeItem"] {
                #expect(!code.contains(forbidden), "\(url.lastPathComponent) must only read what Claude Code prints: \(forbidden)")
            }
        }
        let limits = try #require(files.first { $0.0.lastPathComponent == "ClaudeCodeLimits.swift" }).1
        // Only `runIsolated` starts Claude Code with nothing of Brainmerge's own environment: `run` and `check` merge it in.
        let limitsCode = limits.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        #expect(limitsCode.contains("runIsolated("), "Claude Code must be started by Shell.runIsolated")
        for merging in [".run(", ".check("] {
            #expect(!limitsCode.contains(merging), "ClaudeCodeLimits.swift must not start Claude Code with \(merging)")
        }
        let literals = Set(limits.matches(of: try Regex(#""((?:[^"\\]|\\.)*)""#)).map { String($0.output[1].substring ?? "") })
        #expect(Set(literals.filter { $0.hasPrefix("-") }) == ["--version", "-p"], "arguments: \(literals.filter { $0.hasPrefix("-") })")
        #expect(Set(literals.filter { $0.range(of: #"^/[a-z-]+$"#, options: .regularExpression) != nil }) == ["/usage"])
    }

    @Test func noTelemetryOrAnalytics() throws {
        let hits = try offenders(["Analytics", "Telemetry", "Sentry", "Crashlytics", "Firebase", "Mixpanel"])
        #expect(hits.isEmpty, "\(hits)")
    }
}
