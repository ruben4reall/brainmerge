import AppKit
import SwiftUI
import BrainmergeCore

/// Everything about an account in one place: name, color or photo, note, memory, and its app in the Dock.
public struct EditAccountSheet: View {
    @Bindable var model: AppModel
    @Binding var isPresented: Bool
    let account: Account
    @State private var edit: AccountEdit
    @State private var problem: String?

    public init(model: AppModel, isPresented: Binding<Bool>, account: Account) {
        self.model = model; _isPresented = isPresented; self.account = account
        let memory = (try? model.store.load())?.brain(for: account.identity)?.id ?? AppState.defaultBrainID
        _edit = State(initialValue: AccountEdit(account: account, memory: memory))
    }

    var appLabel: String? {
        guard let url = model.appURL(of: account.id) else { return nil }
        let home = model.paths.home.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                OrbView(name: edit.name, tint: edit.tint, logo: edit.logo.flatMap { NSImage(contentsOf: $0) }, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Edit \(account.identity.name)").font(Theme.Fonts.sheetTitle)
                    Text(account.isRunning ? "Quit this account first: its app is rebuilt when you save." : "Changes apply when you save.")
                        .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted)
                }
            }
            labeled("Name") {
                TextField("Name", text: $edit.name).textFieldStyle(.plain).font(Theme.Fonts.body)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Theme.Colors.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            labeled("Color") {
                HStack(spacing: 8) {
                    ForEach(Theme.pickableTints, id: \.self) { t in
                        Button { edit.tint = t; edit.logo = nil } label: {
                            Circle().fill(Theme.color(for: t)).frame(width: 24, height: 24)
                                .overlay(Circle().strokeBorder(Theme.Colors.text, lineWidth: edit.tint == t && edit.logo == nil ? 2.5 : 0))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(t.rawValue.capitalized)
                    }
                    Spacer()
                    Button(edit.logo == nil ? "Use a photo…" : "Change the photo…") { choosePhoto() }.buttonStyle(.glass).controlSize(.small)
                }
            }
            labeled("Note") {
                TextField("Optional: Personal, Work, a client…", text: $edit.note).textFieldStyle(.plain).font(Theme.Fonts.body)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Theme.Colors.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            labeled("Memory") {
                Picker("Memory", selection: $edit.memory) {
                    ForEach(model.brains) { folder in Text(folder.name).tag(folder.id) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
                Text("What this account wrote so far stays where it is; it goes on in the memory you pick.")
                    .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint)
            }
            if !account.identity.isPrimary {
                labeled("In the Dock") {
                    Toggle("Own icon in the Dock", isOn: $edit.distinctIcon).toggleStyle(.switch).tint(Theme.Colors.accent)
                    Text("Recommended when several accounts stay open: the Dock shows this account's icon and name while it runs. It is a local copy of Claude, rebuilt after each Claude update.")
                        .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint)
                    if let appLabel {
                        HStack(spacing: 10) {
                            Text(appLabel).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button("Show in Finder") { model.revealApp(account.id) }.buttonStyle(.glass).controlSize(.small)
                        }
                        Text("Drag it to your Dock to open this account from there, like any app.")
                            .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint)
                    }
                }
            }
            if let problem { Text(problem).foregroundStyle(Theme.Colors.accentLight).font(Theme.Fonts.secondary) }
            HStack(spacing: 10) {
                if let working = model.working { Text(working).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted) }
                Spacer()
                Button("Cancel") { isPresented = false }.buttonStyle(.glass).keyboardShortcut(.cancelAction)
                Button("Save") { save() }.buttonStyle(.glassProminent).tint(Theme.Colors.button)
                    .keyboardShortcut(.defaultAction).disabled(model.working != nil)
            }
        }
        .padding(22)
        .frame(width: 480)
        .background(WarmBackground(accents: [edit.tint]))
    }

    func labeled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(Theme.Fonts.sectionLabel).foregroundStyle(Theme.Colors.textFaint)
            content()
        }
    }

    func save() {
        problem = nil
        Task {
            await model.apply(edit, to: account.id)
            if let message = model.message { problem = message.detail; model.message = nil } else { isPresented = false }
        }
    }

    func choosePhoto() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK { edit.logo = panel.url }
    }
}
