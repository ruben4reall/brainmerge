import ArgumentParser
import Foundation
import BrainmergeCore

struct IdentityCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "identity", abstract: "Claude identities on this Mac.",
                                                    subcommands: [List.self, Add.self, Edit.self, Remove.self, Launch.self, Quit.self, Rebuild.self])

    struct List: ParsableCommand {
        @Flag var json = false
        func run() throws {
            let context = Context()
            let state = try context.store.load()
            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                print(String(decoding: try encoder.encode(state.identities), as: UTF8.self))
                return
            }
            if state.identities.isEmpty { print("No identities yet. Run: brainmerge adopt-primary") }
            for identity in state.identities {
                let running = (try? context.manager.isRunning(identity)) ?? false
                let kind = identity.isPrimary ? "primary" : identity.iconMode.rawValue
                let login = identity.surfaces.desktop ? (DesktopSession.hasSession(dataDir: identity.desktopData(in: context.paths)) ? "logged in" : "not logged in") : "cli only"
                print("\(identity.slug)\t\(identity.name)\t\(kind)\t\(running ? "running" : "stopped")\t\(login)\tbuilt for \(identity.builtForClaudeVersion ?? "-")")
            }
        }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Add an identity: CLI profile, Desktop data folder, launcher app. You log in yourself in the window that opens.")
        @Option var name: String
        @Option var tint: Tint = .blue
        @Option(help: "PNG or other image used as the icon instead of a tint.") var logo: String?
        @Flag(name: .customLong("no-desktop"), help: "CLI only, no Desktop instance.") var noDesktop = false
        @Flag(name: .customLong("tinted-icon"), help: "Distinct Dock icon via a local tinted copy of Claude.app (rebuilt after each Claude update).") var tintedIcon = false
        @Flag(name: .customLong("shared-history"), help: "Share the session history with the primary identity.") var sharedHistory = false
        @Option(name: .customLong("adopt-cli"), help: "Existing CLAUDE_CONFIG_DIR to reuse.") var adoptCLI: String?
        @Option(name: .customLong("adopt-desktop"), help: "Existing Claude Desktop data folder to reuse.") var adoptDesktop: String?
        @Option(help: "A short line shown under the name: Personal, Work, a client.") var note: String?
        @Option(help: "The memory this account writes to (its id, see brain list). Default: the shared one.") var brain: String?
        @Flag(name: .customLong("own-brain"), help: "Give this account a memory of its own, in ~/Brain-<slug>.") var ownBrain = false

        func run() throws {
            let context = Context()
            try context.ensureCLILink()
            var request = IdentityManager.AddRequest(name: name)
            request.note = note
            request.brain = brain
            request.ownBrain = ownBrain
            request.tint = tint
            request.logo = logo.map { URL(fileURLWithPath: $0) }
            request.surfaces = Surfaces(desktop: !noDesktop, cli: true)
            request.iconMode = tintedIcon ? .tintedClone : .launcher
            request.sharedHistory = sharedHistory
            request.adoptCLIProfile = adoptCLI.map { URL(fileURLWithPath: $0, isDirectory: true) }
            request.adoptDesktopData = adoptDesktop.map { URL(fileURLWithPath: $0, isDirectory: true) }
            let identity = try context.manager.add(request)
            print("Added \(identity.name) (\(identity.slug)).")
            if !noDesktop {
                print("Launch it with: brainmerge identity launch \(identity.slug)")
                print("Then log in with this identity's account. macOS may ask once to allow \"Claude Safe Storage\": choose Always Allow.")
            }
        }
    }

    struct Edit: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Rename an identity, change its tint, logo, note, memory or app. The slug never changes. The primary can be edited while Claude runs, except its memory.")
        @Argument var slug: String
        @Option var name: String?
        @Option var tint: Tint?
        @Option var logo: String?
        @Option var note: String?
        @Option(help: "Attach the identity to this memory (its id, see brain list). Its notes stay where they were written.") var brain: String?
        @Option(help: "The Dock icon: distinct (a local tinted copy of Claude, its own icon and name in the Dock) or launcher.") var icon: String?
        @Option(name: .customLong("own-app"), help: "The primary account only: on adds an app with its color or photo in ~/Applications/Brainmerge that opens Claude, off removes it. Claude itself is never changed.") var ownApp: String?
        func run() throws {
            let context = Context()
            let iconMode: IconMode? = try icon.map {
                switch $0 { case "distinct": return .tintedClone; case "launcher": return .launcher; default: throw ValidationError("--icon must be distinct or launcher") }
            }
            let ownAppOn: Bool? = try ownApp.map {
                switch $0 { case "on": return true; case "off": return false; default: throw ValidationError("--own-app must be on or off") }
            }
            if ownAppOn != nil, try context.store.load().identity(slug: slug)?.isPrimary == false {
                throw ValidationError("--own-app is for the primary account only: the other accounts open through an app of their own already.")
            }
            if let brain { try context.manager.setBrain(of: slug, to: brain) }
            if name != nil || tint != nil || logo != nil || note != nil || iconMode != nil || ownAppOn != nil {
                let identity = try context.manager.update(slug: slug, name: name, tint: tint, logo: logo.map { URL(fileURLWithPath: $0) }, note: note,
                                                          iconMode: iconMode, ownApp: ownAppOn)
                print("Updated \(identity.name) (\(identity.slug)).")
            } else if let brain {
                print("\(slug) now writes to the memory \(brain).")
            } else {
                print("Nothing to change.")
            }
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Remove an identity: its launcher and brain hooks go; its folders stay unless --delete-data.")
        @Argument var slug: String
        @Flag(name: .customLong("delete-data"), help: "Also delete the profile and data folders Brainmerge created. Folders adopted from an existing setup are never deleted.") var deleteData = false
        func run() throws {
            try Context().manager.remove(slug: slug, deleteData: deleteData)
            if deleteData {
                print("Removed \(slug) and the folders Brainmerge had created. The brain keeps everything this identity wrote.")
            } else {
                print("Removed \(slug). Its folders are kept (add --delete-data to remove them). The brain keeps everything this identity wrote.")
            }
        }
    }

    struct Launch: ParsableCommand {
        @Argument var slug: String
        func run() throws { try Context().manager.launch(slug: slug) }
    }

    struct Quit: ParsableCommand {
        @Argument var slug: String
        func run() throws {
            let context = Context()
            guard let identity = try context.store.load().identity(slug: slug) else { throw BrainmergeError.identityNotFound(slug) }
            try context.manager.quit(identity)
        }
    }

    struct Rebuild: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Rebuild the launcher or tinted copy for the installed Claude version, or the primary's own app.")
        @Argument var slug: String
        func run() throws {
            try Context().manager.rebuild(slug: slug)
            print("Rebuilt \(slug).")
        }
    }
}
