import ArgumentParser
import Foundation
import BrainmergeCore

struct BrainCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "brain", abstract: "The memories: one shared by default, more if some accounts get their own.",
                                                    subcommands: [Init.self, List.self, Add.self, Forget.self, Rename.self, Status.self, Wire.self, Timeline.self,
                                                                  Health.self])

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
            let held = try context.store.lock()
            defer { held.release() }
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
            let wired = context.attachEachAccount(state: state)
            print("Brain ready at \(brain.root.path)")
            if !wired { throw ExitCode.failure }
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
            if !context.attachEachAccount(state: state, wired: { print("Wired \($0.name)") }) { throw ExitCode.failure }
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

extension BrainCommand {
    /// The Memory screen's Tidy tab, in the terminal: which notes Claude will not load, and what else wants a look. Only
    /// reads; the tab's buttons are the way to change anything.
    struct Health: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Notes Claude will not load, and what to tidy (the default memory unless --brain names another).")
        @Flag var json = false
        @Option(help: "The memory to read (its id, see brain list).") var brain: String?

        static let tidy = "Nothing to tidy. Every note is where the next session will find it."

        func run() throws {
            let context = Context()
            let state = try context.store.load()
            let folder: MemoryFolder
            if let brain {
                guard let named = state.brain(id: brain) else { throw BrainmergeError.brainUnknown(brain) }
                folder = named
            } else {
                guard let first = state.brains.first else { throw BrainmergeError.brainNotConfigured }
                folder = first
            }
            let memory = Brain(root: folder.url)
            guard memory.isInitialized else { throw BrainmergeError.brainNotFound(memory.root.path) }
            let held = Set(HeldStore(paths: context.paths, memoryID: folder.id).load().held.map(\.path))
            let report = MemoryHealth.analyze(MemoryHealth.read(brain: memory, git: BrainGit(brain: memory),
                                                                accountSlugs: Set(state.identities.map(\.slug)), held: held))
            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                print(String(decoding: try encoder.encode(report), as: UTF8.self))
                return
            }
            if report.groups.isEmpty { print(Self.tidy) }
            for (index, group) in report.groups.enumerated() {
                if index > 0 { print("") }
                print(group.title)
                for item in group.items {
                    print("  \(item.sentence)")
                    if let detail = item.detail { print("    \(detail)") }
                }
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
