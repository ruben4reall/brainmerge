import ArgumentParser
import Foundation
import BrainmergeCore

struct BrainCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "brain", abstract: "The memories: one shared by default, more if some accounts get their own.",
                                                    subcommands: [Init.self, List.self, Add.self, Forget.self, Rename.self, Status.self, Wire.self, Timeline.self])

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Every memory, the default one first, with the accounts attached to it.")
        func run() throws {
            let state = try Context().store.load()
            if state.brains.isEmpty { print("No memory yet. Run: brainmerge brain init") }
            for (index, folder) in state.brains.enumerated() {
                let users = state.identities(using: folder.id).map(\.name)
                print("\(folder.id)\t\(folder.name)\t\(folder.path)\t\(index == 0 ? "default" : "")\tused by: \(users.isEmpty ? "nobody" : users.joined(separator: ", "))")
            }
        }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a memory (default folder ~/Brain-<id>) that accounts can be attached to.")
        @Option var name: String
        @Argument(help: "Folder to use; created if missing, kept as is if it exists.") var path: String?
        func run() throws {
            let context = Context()
            let folder = try context.manager.addBrain(name: name, path: path.map { URL(fileURLWithPath: $0, isDirectory: true) },
                                                      language: try context.store.load().brainLanguage)
            print("Memory \(folder.name) (\(folder.id)) ready at \(folder.path). Attach an account with: brainmerge identity edit SLUG --brain \(folder.id)")
        }
    }

    struct Forget: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Forget a memory: its folder stays, no account may still use it.")
        @Argument var id: String
        func run() throws {
            let context = Context()
            guard let folder = try context.store.load().brain(id: id) else { throw BrainmergeError.brainUnknown(id) }
            try context.manager.forgetBrain(id: id)
            print("Forgot \(folder.name). Its folder stays at \(folder.path).")
        }
    }

    struct Rename: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Rename a memory (its folder does not move).")
        @Argument var id: String
        @Option var name: String
        func run() throws {
            try Context().manager.renameBrain(id: id, name: name)
            print("Renamed \(id) to \(name).")
        }
    }

    struct Init: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create the brain folder (default ~/Brain) and attach every identity to it.")
        @Argument(help: "Folder to use; created if missing, kept as is if it exists.") var path: String?
        @Option(help: "Language of the BRAIN.md template: en or fr. Default: the language saved in the app settings.") var lang: String?

        func run() throws {
            let context = Context()
            var state = try context.store.load()
            let language: BrainLanguage
            if let lang { guard let parsed = BrainLanguage(rawValue: lang) else { throw ValidationError("--lang must be en or fr") }; language = parsed }
            else { language = state.brainLanguage }
            let root = path.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? context.paths.defaultBrain
            let brain = try Brain.initialize(at: root, language: language)
            state.brainPath = brain.root.path
            state.brainLanguage = language
            try context.store.save(state)
            try context.ensureCLILink()
            for identity in state.identities { try context.manager.attachBrain(to: identity, state: state) }
            print("Brain ready at \(brain.root.path)")
        }
    }

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Where each memory is and which projects are linked.")
        func run() throws {
            let context = Context()
            let state = try context.store.load()
            if state.brains.isEmpty { throw BrainmergeError.brainNotConfigured }
            for folder in state.brains {
                let brain = Brain(root: folder.url)
                print("Memory \(folder.name): \(brain.root.path) (\(brain.isInitialized ? "ready" : "not initialized"))")
                if brain.isInitialized, let last = try BrainGit(brain: brain).log(limit: 1).first {
                    print("Last commit: \(last.date.formatted()) by \(last.authorName)")
                }
                for identity in state.identities(using: folder.id) {
                    let profile = CLIProfile(directory: identity.cliProfile(in: context.paths))
                    guard profile.exists, brain.isInitialized else { continue }
                    let statuses = try MemoryWiring(brain: brain, paths: context.paths, machineID: state.machineID).status(profile: profile)
                    print("\(identity.name):")
                    for s in statuses { print("  \(s.name)  \(describe(s.state))  \(s.path)") }
                }
            }
        }
        func describe(_ state: ProjectLinkState) -> String {
            switch state {
            case .linked: return "linked"
            case .missing: return "not linked"
            case .realDirectory: return "local only"
            case .external(let t): return "external -> \(t)"
            case .broken: return "BROKEN"
            }
        }
    }

    struct Wire: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Re-attach every identity: managed block, hook, memory links. Safe to repeat.")
        func run() throws {
            let context = Context()
            let state = try context.store.load()
            try context.ensureCLILink()
            for identity in state.identities {
                try context.manager.attachBrain(to: identity, state: state)
                print("Wired \(identity.name)")
            }
        }
    }

    struct Timeline: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Who wrote what, from a memory's git log (the default memory unless --brain names another).")
        @Option var limit: Int = 30
        @Option(help: "The memory to read (its id, see brain list).") var brain: String?
        func run() throws {
            let context = Context()
            let entries = try BrainGit(brain: try context.brain(id: brain)).log(limit: limit)
            if entries.isEmpty { print("No commits yet.") }
            for e in entries {
                print("\(e.date.formatted(date: .abbreviated, time: .shortened))  \(e.authorName)  \(e.message)  (\(e.files.count) files)")
            }
        }
    }
}

struct AdoptPrimary: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "adopt-primary",
                                                    abstract: "Register the existing Claude installation as the primary identity and attach it to the brain.")
    @Option var name: String = "Perso"
    func run() throws {
        let context = Context()
        try context.ensureCLILink()
        let identity = try context.manager.adoptPrimary(name: name)
        print("Primary identity: \(identity.name) (\(identity.slug))")
    }
}
