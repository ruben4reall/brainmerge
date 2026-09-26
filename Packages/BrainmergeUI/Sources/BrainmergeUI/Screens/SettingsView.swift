import AppKit
import SwiftUI
import UniformTypeIdentifiers
import BrainmergeCore

public struct SettingsView: View {
    @Bindable var model: AppModel
    public init(model: AppModel) { self.model = model }

    @State private var showNewMemory = false
    @State private var showUninstall = false
    @State private var claudeNote: String?

    func label(_ path: String) -> String {
        let home = model.paths.home.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    /// One memory: its name, its folder, the accounts that write to it, and what can be done with it.
    func memoryRow(_ folder: MemoryFolder, isDefault: Bool) -> some View {
        let users = model.accounts(using: folder.id).map(\.identity.name)
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(folder.name).font(Theme.Fonts.cardName)
                    if isDefault { Text("default").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textFaint) }
                }
                Text(label(folder.path)).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted)
                Text(users.isEmpty ? "No account writes here" : "Written by \(users.joined(separator: ", "))").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint)
            }
            Spacer()
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder.url]) }.buttonStyle(.glass).controlSize(.small)
            Button("Rename…") { rename(folder) }.buttonStyle(.glass).controlSize(.small)
            if !isDefault, users.isEmpty {
                Button("Forget") { Task { await model.forgetBrain(folder.id) } }.buttonStyle(.glass).controlSize(.small)
                    .help("Removes it from the list. The folder stays on your disk.")
            }
        }
        .padding(.vertical, 4)
    }

    func rename(_ folder: MemoryFolder) {
        let alert = NSAlert(); alert.messageText = "Rename \(folder.name)"; alert.informativeText = "The folder does not move."
        alert.addButton(withTitle: "Rename"); alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24)); field.stringValue = folder.name; alert.accessoryView = field
        if alert.runModal() == .alertFirstButtonReturn { let name = field.stringValue; Task { await model.renameBrain(folder.id, to: name) } }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader("Settings")
                GlassCard {
                    VStack(alignment: .leading, spacing: 0) {
                        section("Where Claude is") {
                            if let claude = model.claude {
                                Text("\(claude.url.path) · version \(claude.version)").foregroundStyle(Theme.Colors.textMuted)
                                Button("Choose…") { chooseClaude() }.buttonStyle(.glass)
                                if let claudeNote { Text(claudeNote).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted) }
                            } else {
                                Text("Not found. Brainmerge needs the Claude app to open accounts.").foregroundStyle(Theme.Colors.textMuted)
                                Button("Get Claude") { if let url = URL(string: "https://claude.ai/download") { NSWorkspace.shared.open(url) } }.buttonStyle(.glassProminent).tint(Theme.Colors.button)
                                Button("Choose…") { chooseClaude() }.buttonStyle(.glass)
                                if let claudeNote { Text(claudeNote).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted) }
                            }
                        }
                        section("Menu bar") {
                            Toggle(MenuBarMenu.settingTitle, isOn: Binding(get: { model.menuBarIcon }, set: { model.setMenuBarIcon($0) })).toggleStyle(.switch).tint(Theme.Colors.accent)
                            Text(MenuBarMenu.settingFootnote)
                                .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint)
                        }
                        section("Distinct icons") {
                            Toggle("Rebuild tinted copies after each Claude update", isOn: Binding(get: { model.autoRebuild }, set: { model.setAutoRebuild($0) })).toggleStyle(.switch).tint(Theme.Colors.accent)
                            Text("Only accounts that chose a distinct Dock icon are affected. Accounts that are open are rebuilt the next time they are closed.")
                                .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint)
                        }
                        section(model.brains.count > 1 ? "Memories" : "Memory") {
                            ForEach(Array(model.brains.enumerated()), id: \.element.id) { index, folder in memoryRow(folder, isDefault: index == 0) }
                            HStack(spacing: 8) {
                                Button("Add a memory…") { showNewMemory = true }.buttonStyle(.glass)
                                Button("Repair links") { model.repair() }.buttonStyle(.glass)
                            }
                            Text("Every account writes to one memory. Give an account its own from its card's menu: what it learns then stays there.")
                                .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint)
                        }
                        section("Notes app") {
                            NotesAppPicker(selection: Binding(get: { model.notesApp }, set: { model.setNotesApp($0) }))
                            Text("What opens the memory folder from the Memory screen. The notes are plain Markdown files, any app that reads files works.")
                                .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint)
                        }
                        section("Notes language") {
                            Picker("Notes language", selection: Binding(get: { model.language }, set: { model.setLanguage($0) })) {
                                Text("English").tag(BrainLanguage.en)
                                Text("French").tag(BrainLanguage.fr)
                            }
                            .pickerStyle(.segmented).labelsHidden().frame(width: 220).tint(Theme.Colors.accent)
                            Text("Applies to the instructions written in a new memory folder. Notes already written stay as they are.")
                                .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint)
                        }
                        section("Command line") {
                            HStack(spacing: 10) {
                                Circle().fill(model.commandLineInstalled ? Theme.Colors.sage : Theme.Colors.textFaint).frame(width: 8, height: 8)
                                Text(model.commandLineInstalled ? "Installed at ~/.local/bin/brainmerge" : "Not installed").foregroundStyle(Theme.Colors.textMuted)
                                Button("Install command line") { model.installCommandLine() }.buttonStyle(.glass)
                            }
                            if let hooks = model.hooks, let sentence = hooks.sentence {
                                HStack(spacing: 10) {
                                    Circle().fill(hooks.allCurrent ? Theme.Colors.sage : Theme.Colors.textFaint).frame(width: 8, height: 8)
                                    Text(sentence).foregroundStyle(Theme.Colors.textMuted)
                                    Button("Repair hooks") { Task { await model.repairHooks() } }.buttonStyle(.glass)
                                }
                            }
                            Text("Optional. Everything here can be done from a terminal with the brainmerge command.")
                                .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint)
                        }
                        section("About", last: true) {
                            Text("Brainmerge \(BrainmergeUIInfo.version) · Works with Claude. Not made by Anthropic.").foregroundStyle(Theme.Colors.textMuted)
                            HStack(spacing: 14) {
                                // Opens the page in the browser, nothing more: no count fetched, never asked for on its own.
                                Link(MenuBarMenu.starTitle, destination: BrainmergeLinks.repository)
                                Text("MIT license").foregroundStyle(Theme.Colors.textFaint)
                            }
                            .font(Theme.Fonts.secondary)
                            HStack(spacing: 8) {
                                Button("Check for updates") { if let url = URL(string: "https://github.com/ruben4reall/brainmerge/releases") { NSWorkspace.shared.open(url) } }.buttonStyle(.glass)
                                Text("Opens the releases page in your browser. Brainmerge never connects on its own.").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint)
                            }
                            HStack(spacing: 8) {
                                Button("Remove Brainmerge…") { showUninstall = true }.buttonStyle(.glass)
                                Text("Your memories and your logins stay.").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint)
                            }
                        }
                    }
                }
            }
            .padding(Theme.Layout.padding)
            .frame(maxWidth: Theme.Layout.formWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await model.refreshHooks() }
        .sheet(isPresented: $showNewMemory) { NewMemorySheet(model: model, isPresented: $showNewMemory) }
        .sheet(isPresented: $showUninstall) { UninstallSheet(model: model, isPresented: $showUninstall) }
    }

    /// Picks another Claude app: refused unless Anthropic signed it, used by Brainmerge from its next launch.
    func chooseClaude() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            if let refusal = await model.chooseClaude(url) {
                claudeNote = refusal.detail
            } else {
                // An account's app keeps the path of the Claude it was built with: only a rebuild moves it.
                claudeNote = "Brainmerge uses this Claude from its next launch. Apps already made for your accounts keep the Claude they were built with until you rebuild them."
            }
        }
    }

    func section<Content: View>(_ title: String, last: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(Theme.Fonts.sectionLabel).foregroundStyle(Theme.Colors.textFaint)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.vertical, 16)
        .overlay(alignment: .bottom) { if !last { Divider().overlay(Theme.Colors.surfaceLine).padding(.horizontal, 20) } }
    }
}
