import AppKit
import SwiftUI
import BrainmergeCore

/// Everything about an account in one place: name, color or photo, note, memory, and its app in the Dock (for the primary,
/// which is Claude itself, an optional app of its own that opens Claude), with the apps the person made that also open it.
public struct EditAccountSheet: View {
    @Bindable var model: AppModel
    @Binding var isPresented: Bool
    let account: Account
    @State private var edit: AccountEdit
    @State private var problem: String?
    /// Apps the person made that also open this account, read before the sheet opens (never run, never touched): the
    /// sheet opens at its full size, nothing moves under the pointer.
    @State private var otherApps: [ExistingApp]
    /// The swap waiting for its confirmation, and why the last one could not be done.
    @State private var pendingSwap: CodeAccountNote?
    @State private var swapProblem: UserMessage?

    public init(model: AppModel, isPresented: Binding<Bool>, account: Account, otherApps: [ExistingApp] = []) {
        self.model = model; _isPresented = isPresented; self.account = account
        _otherApps = State(initialValue: otherApps)
        let memory = (try? model.store.load())?.brain(for: account.identity)?.id ?? AppState.defaultBrainID
        _edit = State(initialValue: AccountEdit(account: account, memory: memory))
    }

    /// The tallest the sheet gets, its buttons included (a 1440 by 900 screen keeps it whole): beyond it, its sections scroll.
    nonisolated static let maxHeight: CGFloat = 680
    /// What the sections may take of it: the header, the buttons, a line of problem and the margins take the rest.
    nonisolated static let maxSectionsHeight: CGFloat = 500

    /// The account as loaded now: its name changes after a swap, its Claude Code account on a refresh.
    var current: Account { model.accounts.first { $0.id == account.id } ?? account }

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
                    Text("Edit \(current.identity.name)").font(Theme.Fonts.sheetTitle)
                    Text(Self.header(for: current))
                        .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted)
                }
            }
            // Past its limit the sections scroll, so Save and Cancel always stay on screen.
            ScrollView {
                sections.frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: Self.maxSectionsHeight)
            .fixedSize(horizontal: false, vertical: true)
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
        .confirmationDialog(pendingSwap?.swapQuestion(thisName: current.identity.name) ?? "",
                            isPresented: Binding(get: { pendingSwap != nil }, set: { if !$0 { pendingSwap = nil } }), presenting: pendingSwap) { note in
            Button("Swap names") { if let other = note.swapWith { swapNames(with: other) } }
            Button("Cancel", role: .cancel) {}
        } message: { note in
            Text(note.swapExplanation)
        }
    }

    @ViewBuilder var sections: some View {
        VStack(alignment: .leading, spacing: 14) {
            labeled("Name") {
                TextField("Name", text: $edit.name).textFieldStyle(.plain).font(Theme.Fonts.body)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Theme.Colors.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                if let note = CodeAccountNote.make(for: current, typedName: edit.name, among: model.accounts) { codeAccountLines(note) }
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
                .disabled(Self.memoryLocked(for: current))
                Text(Self.memoryHint(for: current))
                    .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint)
            }
            if account.identity.isPrimary {
                if account.identity.surfaces.desktop {
                    labeled("App") {
                        Toggle("Own app with this color", isOn: $edit.ownApp).toggleStyle(.switch).tint(Theme.Colors.accent)
                        Text(Self.ownAppText(name: current.identity.name))
                            .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint)
                            .fixedSize(horizontal: false, vertical: true)
                        appLocation
                    }
                }
            } else {
                labeled("In the Dock") {
                    Toggle("Own icon in the Dock", isOn: $edit.distinctIcon).toggleStyle(.switch).tint(Theme.Colors.accent)
                    Text("Recommended when several accounts stay open: the Dock shows this account's icon and name while it runs. It is a local copy of Claude, rebuilt after each Claude update.")
                        .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint)
                    appLocation
                    if appLabel != nil {
                        Text("Drag it to your Dock to open this account from there, like any app.")
                            .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint)
                    }
                }
            }
            labeled("Connections") { ConnectionsSection(model: model, account: current, choice: $edit.browser) }
            if let note = otherAppNote {
                labeled("Apps you made") { otherAppLines(note) }
            }
        }
    }

    /// The apps the person made that also open this account, found before the sheet opened: each once with its own
    /// "Show in Finder", then the risk and the advice, once. A copy made by hand keeps Claude's icon, so the Dock switch
    /// above still matters.
    var otherAppNote: OtherAppNote? {
        OtherAppNote.make(apps: otherApps, account: current.identity, installedClaude: model.claude?.version, home: model.paths.home, ownIconOn: edit.distinctIcon)
    }

    @ViewBuilder func otherAppLines(_ note: OtherAppNote) -> some View {
        if let intro = note.intro {
            Text(intro).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.text)
        }
        ForEach(note.rows) { row in
            HStack(spacing: 10) {
                Text(row.text).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.text)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Show in Finder") { model.revealInFinder(row.app.url) }.buttonStyle(.glass).controlSize(.small)
                    .accessibilityLabel("Show \(row.app.name) in Finder")
            }
        }
        if let warning = note.warning {
            Text(warning).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.accentLight)
                .fixedSize(horizontal: false, vertical: true)
        }
        Text(note.advice).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Which email Claude Code uses for this account, and the renames it suggests. Nothing is renamed without a click,
    /// and the swap, which renames both accounts at once, is asked first.
    @ViewBuilder func codeAccountLines(_ note: CodeAccountNote) -> some View {
        HStack(spacing: 10) {
            Text(note.line).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let label = note.useLabel, let name = note.suggestedName {
                Button(label) { edit.name = name }.buttonStyle(.glass).controlSize(.small)
            }
        }
        if let line = note.swapLine, let label = note.swapLabel {
            HStack(spacing: 10) {
                Text(line).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(label) { swapProblem = nil; pendingSwap = note }.buttonStyle(.glass).controlSize(.small).disabled(model.working != nil)
            }
        }
        // A swap that could not be done says why right here, with the way out when there is one (quitting a secondary).
        if let swapProblem {
            HStack(spacing: 10) {
                Text(swapProblem.detail).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.accentLight)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if case .quit(let slug) = swapProblem.action, let label = swapProblem.actionLabel,
                   model.accounts.first(where: { $0.id == slug })?.identity.isPrimary == false {
                    Button(label) { model.quit(slug); self.swapProblem = nil }.buttonStyle(.glass).controlSize(.small)
                }
            }
        }
        Text(CodeAccountNote.privacy).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Both accounts are renamed at once; the field then shows this account's new name, so Save keeps it. Only the swap's
    /// own problem is shown here: another message set meanwhile stays for the window's alert.
    func swapNames(with other: CodeAccountNote.Other) {
        swapProblem = nil
        Task {
            if let failure = await model.swapNames(account.id, with: other.slug) { swapProblem = failure; model.dismiss(failure) }
            else { edit.name = current.identity.name }
        }
    }

    /// Where the account's app is, with a way to find it, once it exists on disk.
    @ViewBuilder var appLocation: some View {
        if let appLabel {
            HStack(spacing: 10) {
                Text(appLabel).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Show in Finder") { model.revealApp(account.id) }.buttonStyle(.glass).controlSize(.small)
            }
        }
    }

    /// Only a secondary's app is rebuilt on save, so only a secondary has to be closed first. The primary is Claude itself:
    /// saving never touches it (its memory waits for Claude to quit, which the memory picker says while it runs).
    nonisolated static func header(for account: Account) -> String {
        guard account.isRunning else { return "Changes apply when you save." }
        return account.identity.isPrimary ? "Changes apply when you save. Claude stays open." : "Quit this account first: its app is rebuilt when you save."
    }

    /// Moving the memory links needs the account closed: the primary may stay open for everything else, so while it runs
    /// its memory picker is off and says why, rather than a save that asks to quit Claude after the header said it stays open.
    nonisolated static func memoryLocked(for account: Account) -> Bool { account.identity.isPrimary && account.isRunning }

    nonisolated static func memoryHint(for account: Account) -> String {
        memoryLocked(for: account) ? "Quit Claude to change \(account.identity.name)'s memory."
            : "What this account wrote so far stays where it is; it goes on in the memory you pick."
    }

    /// Why the primary has no icon of its own in the Dock, and what the switch adds instead.
    nonisolated static func ownAppText(name: String) -> String {
        "\(name) is the Claude app itself. Brainmerge never changes Claude, so while it runs the Dock shows Claude's icon. With this switch, Brainmerge adds an app with this color or photo that opens \(name): keep it in the Dock in place of Claude."
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
            if let failure = await model.apply(edit, to: account.id) { problem = failure.detail; model.dismiss(failure) }
            else { isPresented = false }
        }
    }

    func choosePhoto() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK { edit.logo = panel.url }
    }
}
