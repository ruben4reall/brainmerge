import Foundation
import Testing
import BrainmergeTestSupport
@testable import BrainmergeCore

/// Apps the person made by hand that open one of their accounts: found by reading bundles, never by running them.
@Suite struct ExistingAppsTests {
    /// The owner's adopted second account: the folders his hand-made copies open.
    static func agency(_ home: TempHome) -> Identity {
        Identity(slug: "agency", name: "Agency", tint: .blue,
                 cliProfilePath: home.url.appending(path: ".claude-second").path,
                 desktopDataPath: home.url.appending(path: "Library/Application Support/Claude-Second").path)
    }

    func applications(_ home: TempHome) throws -> URL {
        let url = home.url.appending(path: "Applications", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func scanner(_ home: TempHome) -> ExistingApps {
        ExistingApps(paths: home.paths, claudeAppURL: home.url.appending(path: "Applications/Claude.app"),
                     folders: [home.url.appending(path: "Applications")])
    }

    // MARK: The owner's setup

    @Test func findsTheOwnersHandMadeCopies() throws {
        let home = try TempHome(); defer { home.remove() }
        let apps = try applications(home)
        let copy = try HandMadeApp.make("Claude Second", in: apps, script: HandMadeApp.ownersScript, version: "2.2553.13")
        let older = try HandMadeApp.make("Claude Second (ancienne 1.49585)", in: apps, script: HandMadeApp.ownersScript, version: "1.49585.0")

        let found = scanner(home).apps(opening: Self.agency(home))
        #expect(found.map(\.name) == ["Claude Second", "Claude Second (ancienne 1.49585)"])
        #expect(found.map(\.url.path) == [copy.path, older.path])
        #expect(found.allSatisfy { $0.isClaudeCopy })
        #expect(found.map(\.claudeVersion) == ["2.2553.13", "1.49585.0"])
        #expect(found.first?.dataDir?.path == home.url.appending(path: "Library/Application Support/Claude-Second").path)
        #expect(found.first?.configDir?.path == home.url.appending(path: ".claude-second").path)
        // They open Agency's folders, not the primary's.
        let primary = Identity(slug: "ruben", name: "Ruben", isPrimary: true)
        #expect(scanner(home).apps(opening: primary).isEmpty)
    }

    @Test func ignoresOurLaunchersClaudeAndOtherFolders() throws {
        let home = try TempHome(); defer { home.remove() }
        let apps = try applications(home)
        // Brainmerge's own apps live one level down, in ~/Applications/Brainmerge.
        try FileManager.default.createDirectory(at: home.paths.launchersDir, withIntermediateDirectories: true)
        try HandMadeApp.make("Agency", in: home.paths.launchersDir, script: HandMadeApp.ownersScript)
        // Claude itself is never "another app", whatever its executable says.
        try HandMadeApp.make("Claude", in: apps, script: HandMadeApp.ownersScript)
        // Another account's folders, a compiled executable, a script too large to be a launch line, a folder that is not an app.
        try HandMadeApp.make("Claude Work", in: apps, script: "#!/bin/zsh\nexec /Applications/Claude.app/Contents/MacOS/Claude --user-data-dir=\"$HOME/Library/Application Support/Claude-work\"\n")
        try HandMadeApp.make("Compiled", in: apps, executable: Data([0xCF, 0xFA, 0xED, 0xFE]) + Data(HandMadeApp.ownersScript.utf8))
        try HandMadeApp.make("Huge", in: apps, script: "#!/bin/sh\n" + String(repeating: "# padding\n", count: 7_000) + HandMadeApp.ownersScript)
        let plain = apps.appending(path: "Claude Second", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        try Data(HandMadeApp.ownersScript.utf8).write(to: plain.appending(path: "Claude"))

        #expect(scanner(home).apps(opening: Self.agency(home)).isEmpty)
        #expect(scanner(home).scan().map(\.name) == ["Claude Work"])
    }

    @Test func aSimilarFolderNameDoesNotMatch() throws {
        let home = try TempHome(); defer { home.remove() }
        let apps = try applications(home)
        try HandMadeApp.make("Claude Second 2", in: apps, script: """
        #!/bin/sh
        export CLAUDE_CONFIG_DIR="$HOME/.claude-second-2"
        exec "$(dirname "$0")/Claude-bin" --user-data-dir="$HOME/Library/Application Support/Claude-Second-2" "$@"
        """)
        #expect(scanner(home).apps(opening: Self.agency(home)).isEmpty)

        // The same folder written in another case, with a trailing slash, or through "..": the same folder on APFS.
        try HandMadeApp.make("Agency", in: apps, script: """
        #!/bin/sh
        exec "$(dirname "$0")/Claude-bin" --user-data-dir="$HOME/library/application support/claude-second/" "$@"
        """)
        try HandMadeApp.make("Agency Too", in: apps, script: """
        #!/bin/sh
        CLAUDE_CONFIG_DIR=$HOME/Library/../.claude-second exec "$(dirname "$0")/Claude-bin" "$@"
        """)
        #expect(scanner(home).apps(opening: Self.agency(home)).map(\.name) == ["Agency", "Agency Too"])
    }

    @Test func neverRunsTheScript() throws {
        let home = try TempHome(); defer { home.remove() }
        let apps = try applications(home)
        let marker = home.url.appending(path: "the-script-ran")
        let app = try HandMadeApp.make("Claude Second", in: apps, script: """
        #!/bin/sh
        touch "\(marker.path)"
        export CLAUDE_CONFIG_DIR="$HOME/.claude-second"
        exec "$(dirname "$0")/Claude-bin" --user-data-dir="$HOME/Library/Application Support/Claude-Second" "$@"
        """)
        let exe = app.appending(path: "Contents/MacOS/Claude")
        let past = Date(timeIntervalSince1970: 1_700_000_000)
        for url in [app, exe] { try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: url.path) }

        #expect(scanner(home).apps(opening: Self.agency(home)).map(\.name) == ["Claude Second"])
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        for url in [app, exe] {
            let modified = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
            #expect(modified == past, "\(url.lastPathComponent) was changed")
        }
    }

    @Test func reportsACopysClaudeVersion() throws {
        let home = try TempHome(); defer { home.remove() }
        let apps = try applications(home)
        try HandMadeApp.make("Copy", in: apps, script: HandMadeApp.ownersScript, version: "2.2553.13")
        // A script app of its own (not a copy of Claude): no Claude version to speak of.
        try HandMadeApp.make("Wrapper", in: apps, script: HandMadeApp.ownersScript, bundleID: "com.example.wrapper", version: "1.0", frameworks: false)
        try HandMadeApp.make("No Frameworks", in: apps, script: HandMadeApp.ownersScript, version: "2.2553.13", frameworks: false)
        let found = Dictionary(uniqueKeysWithValues: scanner(home).apps(opening: Self.agency(home)).map { ($0.name, $0) })
        #expect(found["Copy"]?.isClaudeCopy == true)
        #expect(found["Copy"]?.claudeVersion == "2.2553.13")
        #expect(found["Wrapper"]?.isClaudeCopy == false)
        #expect(found["Wrapper"]?.claudeVersion == nil)
        #expect(found["No Frameworks"]?.isClaudeCopy == false)

        let copy = try #require(found["Copy"])
        #expect(copy.runsOlderClaude(than: "2.9939.2"))
        #expect(copy.runsOlderClaude(than: "2.10000.0"))   // numbers, not text: 10000 comes after 2553
        #expect(!copy.runsOlderClaude(than: "2.2553.13"))
        #expect(!copy.runsOlderClaude(than: "2.999.0"))
        #expect(!(try #require(found["Wrapper"])).runsOlderClaude(than: "9.0"))
    }

    // MARK: Reading a launch script

    func folders(_ script: String, home: String = "/Users/alex") -> (data: String?, config: String?) {
        let found = ExistingApps.launchFolders(script: script, home: URL(fileURLWithPath: home, isDirectory: true))
        return (found.dataDir?.path, found.configDir?.path)
    }

    @Test func expandsHomeVariantsAndQuotedSpaces() {
        let data = "/Users/alex/Library/Application Support/Claude-X"
        for line in [#"exec bin --user-data-dir="$HOME/Library/Application Support/Claude-X""#,
                     #"exec bin --user-data-dir="${HOME}/Library/Application Support/Claude-X" "$@""#,
                     #"exec bin --user-data-dir=~/Library/Application\ Support/Claude-X"#,
                     #"exec bin --user-data-dir=$HOME/Library/'Application Support'/Claude-X"#,
                     #"exec bin "--user-data-dir=$HOME/Library/Application Support/Claude-X""#,
                     #"exec bin --user-data-dir='/Users/alex/Library/Application Support/Claude-X'"#] {
            #expect(folders("#!/bin/sh\n" + line).data == data, "\(line)")
        }
        let config = "/Users/alex/.claude-x"
        for line in [#"export CLAUDE_CONFIG_DIR="$HOME/.claude-x""#,
                     "export CLAUDE_CONFIG_DIR=~/.claude-x",
                     "CLAUDE_CONFIG_DIR=${HOME}/.claude-x exec bin",
                     #"env CLAUDE_CONFIG_DIR="$HOME/.claude-x" bin"#,
                     "A=1 CLAUDE_CONFIG_DIR='/Users/alex/.claude-x' bin"] {
            #expect(folders("#!/bin/sh\n" + line).config == config, "\(line)")
        }
        let owner = folders(HandMadeApp.ownersScript)
        #expect(owner.data == "/Users/alex/Library/Application Support/Claude-Second")
        #expect(owner.config == "/Users/alex/.claude-second")
    }

    @Test func onlyWhatTheScriptReallyPassesCounts() {
        // Comments, text printed by another command, single-quoted variables, unknown variables, relative paths: nothing.
        for script in ["#!/bin/sh\n# exec bin --user-data-dir=/Users/alex/Old\nexec bin",
                       "#!/bin/sh\nprintf 'CLAUDE_CONFIG_DIR=%s\\n' \"$CLAUDE_CONFIG_DIR\"",
                       "#!/bin/sh\necho CLAUDE_CONFIG_DIR=/Users/alex/.claude-x",
                       "#!/bin/sh\nexec bin --user-data-dir='$HOME/Library/X'",
                       "#!/bin/sh\nexec bin --user-data-dir=\"$DATA/X\"",
                       "#!/bin/sh\nexec bin --user-data-dir=\"$HOMEDIR/X\"",
                       "#!/bin/sh\nexport CLAUDE_CONFIG_DIR=~bob/.claude",
                       "#!/bin/sh\nexec bin --user-data-dir=Library/X"] {
            let found = folders(script)
            #expect(found.data == nil && found.config == nil, "\(script)")
        }
        // The last one wins, as in the shell.
        #expect(folders("#!/bin/sh\nexport CLAUDE_CONFIG_DIR=/a\nexport CLAUDE_CONFIG_DIR=/b\nexec bin --user-data-dir=/c --user-data-dir=/d").config == "/b")
        #expect(folders("#!/bin/sh\nexec bin --user-data-dir=/c --user-data-dir=/d").data == "/d")
    }

    // MARK: Only the bundle's own files are read

    /// The account's data folder, with a file named like an app's executable holding the owner's launch line: a bundle
    /// that points there through a link must never get it read.
    func dataFolderBait(_ home: TempHome) throws -> URL {
        let data = home.url.appending(path: "Library/Application Support/Claude-Second", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        try Data(HandMadeApp.ownersScript.utf8).write(to: data.appending(path: "Claude"))
        try Plist.write(["CFBundleIdentifier": ClaudeApp.bundleIdentifier, "CFBundleExecutable": "Claude", "CFBundleShortVersionString": "1.0.0"],
                        to: data.appending(path: "Info.plist"))
        return data
    }

    @Test func aLinkedMacOSFolderIsNotFollowed() throws {
        let home = try TempHome(); defer { home.remove() }
        let data = try dataFolderBait(home)
        let app = try HandMadeApp.make("Linked", in: try applications(home), script: "#!/bin/sh\n")
        let macos = app.appending(path: "Contents/MacOS")
        try FileManager.default.removeItem(at: macos)
        try FileManager.default.createSymbolicLink(at: macos, withDestinationURL: data)
        #expect(scanner(home).scan().isEmpty)
    }

    @Test func aLinkedExecutableIsNotFollowed() throws {
        let home = try TempHome(); defer { home.remove() }
        let data = try dataFolderBait(home)
        let app = try HandMadeApp.make("Linked", in: try applications(home), script: "#!/bin/sh\n")
        let exe = app.appending(path: "Contents/MacOS/Claude")
        try FileManager.default.removeItem(at: exe)
        try FileManager.default.createSymbolicLink(at: exe, withDestinationURL: data.appending(path: "Claude"))
        #expect(scanner(home).scan().isEmpty)
    }

    @Test func aLinkedInfoPlistOrContentsIsNotFollowed() throws {
        let home = try TempHome(); defer { home.remove() }
        let data = try dataFolderBait(home)
        let apps = try applications(home)
        let plistLink = try HandMadeApp.make("Plist", in: apps, script: HandMadeApp.ownersScript)
        let info = plistLink.appending(path: "Contents/Info.plist")
        try FileManager.default.removeItem(at: info)
        try FileManager.default.createSymbolicLink(at: info, withDestinationURL: data.appending(path: "Info.plist"))
        let contentsLink = apps.appending(path: "Contents.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contentsLink, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: contentsLink.appending(path: "Contents"), withDestinationURL: data)
        #expect(scanner(home).scan().isEmpty)
    }

    @Test func anExecutableNameThatClimbsOutIsRefused() throws {
        let home = try TempHome(); defer { home.remove() }
        _ = try dataFolderBait(home)
        let app = try HandMadeApp.make("Climb", in: try applications(home), script: "#!/bin/sh\n")
        for name in ["../../../../Library/Application Support/Claude-Second/Claude", "..", "."] {
            try Plist.write(["CFBundleIdentifier": ClaudeApp.bundleIdentifier, "CFBundleExecutable": name], to: app.appending(path: "Contents/Info.plist"))
            #expect(scanner(home).scan().isEmpty, "\(name)")
        }
    }

    /// An Info.plist is small: a large one is not loaded at all.
    @Test func aLargeInfoPlistIsNotRead() throws {
        let home = try TempHome(); defer { home.remove() }
        let app = try HandMadeApp.make("Large", in: try applications(home), script: HandMadeApp.ownersScript)
        try Plist.write(["CFBundleIdentifier": ClaudeApp.bundleIdentifier, "CFBundleExecutable": "Claude", "CFBundleShortVersionString": "1.0.0",
                         "Padding": Data(count: ExistingApps.maxInfoPlistBytes + 1)],
                        to: app.appending(path: "Contents/Info.plist"))
        #expect(scanner(home).scan().isEmpty)
    }

    /// A pipe in place of the executable: the read neither blocks nor reports anything.
    @Test func aPipeInPlaceOfTheExecutableIsSkipped() throws {
        let home = try TempHome(); defer { home.remove() }
        let app = try HandMadeApp.make("Pipe", in: try applications(home), script: HandMadeApp.ownersScript)
        let exe = app.appending(path: "Contents/MacOS/Claude")
        try FileManager.default.removeItem(at: exe)
        #expect(mkfifo(exe.path, 0o644) == 0)
        #expect(ExistingApps.script(at: exe) == nil)
        #expect(scanner(home).scan().isEmpty)
    }

    /// Only a file that starts with "#!" is read further: the first two bytes decide.
    @Test func onlyScriptsAreReadAndOnlyUpToTheCap() throws {
        let home = try TempHome(); defer { home.remove() }
        let file = home.url.appending(path: "exe")
        try Data("#!/bin/sh\necho hi\n".utf8).write(to: file)
        #expect(ExistingApps.script(at: file) == "#!/bin/sh\necho hi\n")
        try Data([0xCF, 0xFA, 0xED, 0xFE]).write(to: file)
        #expect(ExistingApps.script(at: file) == nil)
        try Data("#".utf8).write(to: file)
        #expect(ExistingApps.script(at: file) == nil)
    }

    @Test func theSystemFolderBelongsToTheRealHomeOnly() {
        let real = URL(fileURLWithPath: "/Users/alex", isDirectory: true)
        #expect(ExistingApps.folders(for: Paths(home: real), realHome: real).map(\.path) == ["/Users/alex/Applications", "/Applications"])
        // A test or demo home: "$HOME" in a system app's script means the real home, never this one.
        let demo = URL(fileURLWithPath: "/tmp/demo-home", isDirectory: true)
        #expect(ExistingApps.folders(for: Paths(home: demo), realHome: real).map(\.path) == ["/tmp/demo-home/Applications"])
    }
}
