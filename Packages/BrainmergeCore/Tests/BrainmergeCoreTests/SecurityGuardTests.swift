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

    @Test func noTelemetryOrAnalytics() throws {
        let hits = try offenders(["Analytics", "Telemetry", "Sentry", "Crashlytics", "Firebase", "Mixpanel"])
        #expect(hits.isEmpty, "\(hits)")
    }
}
