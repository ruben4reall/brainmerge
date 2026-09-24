import Foundation
import Testing
@testable import BrainmergeCore

/// The promises of the README, enforced on the source tree: no network, no shell interpreter, no reading of
/// Claude's credential stores, one place that runs processes. A failure here is a broken promise, not a style nit.
@Suite struct SecurityGuardTests {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    /// The shipped code: the core, the command line, the launcher, the app. Test fakes (BrainmergeTestSupport) are not shipped.
    static let roots = ["Packages/BrainmergeCore/Sources/BrainmergeCore", "Packages/BrainmergeCore/Sources/brainmerge",
                        "Packages/BrainmergeCore/Sources/launcher", "Packages/BrainmergeUI/Sources", "App"].map { repo.appending(path: $0) }

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

    @Test func noTelemetryOrAnalytics() throws {
        let hits = try offenders(["Analytics", "Telemetry", "Sentry", "Crashlytics", "Firebase", "Mixpanel"])
        #expect(hits.isEmpty, "\(hits)")
    }
}
