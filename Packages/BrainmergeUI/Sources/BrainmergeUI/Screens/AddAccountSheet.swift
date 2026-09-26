import AppKit
import SwiftUI
import BrainmergeCore

public struct AddAccountSheet: View {
    @Bindable var model: AppModel
    @Binding var isPresented: Bool
    @State private var form = AddAccountForm()
    @State private var advanced = false
    @State private var problem = InlineProblem()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: AppModel, isPresented: Binding<Bool>) { self.model = model; _isPresented = isPresented }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                OrbView(name: form.name, tint: form.tint, logo: form.logo.flatMap { NSImage(contentsOf: $0) }, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Add an account").font(Theme.Fonts.sheetTitle)
                    Text("It opens in its own Claude window, where you log in as usual.").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted)
                }
            }
            labeled("Name") {
                TextField("Work, Studio, a client…", text: $form.name).textFieldStyle(.plain).font(Theme.Fonts.body)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Theme.Colors.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            labeled("Color") {
                HStack(spacing: 8) {
                    ForEach(Theme.pickableTints, id: \.self) { t in
                        TintSwatch(tint: t, selected: form.tint == t) { form.tint = t }
                    }
                    Spacer()
                    Button(form.logo == nil ? "Use a photo…" : "Change the photo…") { choosePhoto() }.buttonStyle(.glass).controlSize(.small)
                }
            }
            labeled("Note") {
                TextField("Optional: Personal, Work, a client…", text: $form.note).textFieldStyle(.plain).font(Theme.Fonts.body)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Theme.Colors.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            labeled("Memory") {
                Picker("Memory", selection: $form.memory) {
                    Text("Shared with your other accounts").tag(AddAccountForm.MemoryChoice.shared)
                    ForEach(model.brains.dropFirst()) { folder in Text(folder.name).tag(AddAccountForm.MemoryChoice.existing(folder.id)) }
                    Text("Its own memory").tag(AddAccountForm.MemoryChoice.own)
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
                Text(memoryHint).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint)
            }
            DisclosureGroup("Advanced", isExpanded: $advanced) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Share conversation history with your first account", isOn: $form.sharedHistory)
                    Toggle("Distinct icon in the Dock (a local tinted copy of Claude, rebuilt after each Claude update)", isOn: $form.distinctIcon)
                    HStack {
                        Text("Folders you already have for this account:").foregroundStyle(Theme.Colors.textMuted)
                        Button(form.adoptCLI.map { $0.lastPathComponent } ?? "Claude Code…") { if let u = pickFolder() { form.adoptCLI = u } }.buttonStyle(.glass).controlSize(.small)
                        Button(form.adoptDesktop.map { $0.lastPathComponent } ?? "Claude app data…") { if let u = pickFolder() { form.adoptDesktop = u } }.buttonStyle(.glass).controlSize(.small)
                    }
                }
                .font(Theme.Fonts.secondary).padding(.top, 8)
            }
            .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted)
            // Opening and closing ease the sheet to its new height.
            .animation(Theme.Motion.unlessReduced(Theme.Motion.out(0.2), reduceMotion), value: advanced)
            ProblemLine(problem: problem)
            Text("macOS may ask once to allow the keychain and your Documents folder for this account: click Allow.")
                .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint)
            HStack(spacing: 10) {
                WorkingLine(text: model.working)
                Spacer()
                Button("Cancel") { isPresented = false }.buttonStyle(.glass).keyboardShortcut(.cancelAction)
                Button("Add account") { submit() }.buttonStyle(.glassProminent).tint(Theme.Colors.button)
                    .keyboardShortcut(.defaultAction).disabled(model.working != nil)
            }
        }
        .padding(22)
        .frame(width: 460)
        .background(WarmBackground())
    }

    var memoryHint: String {
        switch form.memory {
        case .shared: return "What this account learns, every account on the shared memory knows."
        case .own: return "A new folder of notes, only for this account."
        case .existing(let id): return "What this account learns stays in \(model.brains.first { $0.id == id }?.name ?? "that memory")."
        }
    }

    func labeled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(Theme.Fonts.sectionLabel).foregroundStyle(Theme.Colors.textFaint)
            content()
        }
    }

    /// A problem said again (the same click twice) shakes the line rather than leaving it as it was.
    func submit() {
        problem.show(form.validate(existing: model.accounts.map(\.identity)))
        guard problem.text == nil else { return }
        Task {
            if await model.add(form) { isPresented = false }
            else { problem.show(model.message?.detail); model.message = nil }   // a single channel: the inline sentence, not the alert as well
        }
    }

    func choosePhoto() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK { form.logo = panel.url }
    }

    func pickFolder() -> URL? {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.showsHiddenFiles = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}
