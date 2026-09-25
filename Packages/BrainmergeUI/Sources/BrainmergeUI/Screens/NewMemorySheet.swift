import AppKit
import SwiftUI
import BrainmergeCore

/// Creates a memory: a name and a folder (`~/Brain-<id>` unless another one is chosen). With `attach`, the
/// account is moved to it right after; what it wrote so far stays in its previous memory.
public struct NewMemorySheet: View {
    @Bindable var model: AppModel
    @Binding var isPresented: Bool
    let attach: Account?
    @State private var name: String
    @State private var folder: URL?
    @State private var problem: String?

    public init(model: AppModel, isPresented: Binding<Bool>, attach: Account? = nil) {
        self.model = model; _isPresented = isPresented; self.attach = attach
        _name = State(initialValue: attach?.identity.name ?? "")
    }

    var suggestedFolder: URL {
        let id = IdentitySlug.make(from: name.trimmingCharacters(in: .whitespaces), taken: Set(model.brains.map(\.id)))
        return model.paths.home.appending(path: "Brain-\(id)", directoryHint: .isDirectory)
    }
    var folderLabel: String {
        let path = (folder ?? suggestedFolder).path
        let home = model.paths.home.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("New memory").font(Theme.Fonts.sheetTitle)
                Text(attach.map { "\($0.identity.name) will write to it. What it wrote so far stays where it is." }
                     ?? "A folder of plain notes that accounts can be attached to.")
                    .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("NAME").font(Theme.Fonts.sectionLabel).foregroundStyle(Theme.Colors.textFaint)
                TextField("Work, a client…", text: $name).textFieldStyle(.plain).font(Theme.Fonts.body)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Theme.Colors.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("FOLDER").font(Theme.Fonts.sectionLabel).foregroundStyle(Theme.Colors.textFaint)
                HStack(spacing: 10) {
                    Text(folderLabel).font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textMuted).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Choose…") { pickFolder() }.buttonStyle(.glass).controlSize(.small)
                }
                Text("Created if missing. A folder you already have is used as is: nothing in it is renamed.")
                    .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint)
            }
            if let problem { Text(problem).foregroundStyle(Theme.Colors.accentLight).font(Theme.Fonts.secondary) }
            HStack(spacing: 10) {
                if let working = model.working { Text(working).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted) }
                Spacer()
                Button("Cancel") { isPresented = false }.buttonStyle(.glass).keyboardShortcut(.cancelAction)
                Button("Create") { create() }.buttonStyle(.glassProminent).tint(Theme.Colors.button)
                    .keyboardShortcut(.defaultAction).disabled(model.working != nil || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 440)
        .background(WarmBackground(accents: [.purple]))
    }

    func create() {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { problem = "Give this memory a name."; return }
        // An open account cannot move: say so before creating anything.
        if let attach, attach.isRunning { problem = "Quit \(attach.identity.name) first, then try again."; return }
        Task {
            guard let created = await model.addBrain(name: clean, path: folder) else { problem = model.message?.detail; model.message = nil; return }
            if let attach {
                if let failure = await model.setBrain(of: attach.id, to: created.id) { problem = failure.detail; model.dismiss(failure); return }
            }
            isPresented = false
        }
    }

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = "Use this folder"
        if panel.runModal() == .OK { folder = panel.url }
    }
}
