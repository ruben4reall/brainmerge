import AppKit
import SwiftUI
import BrainmergeCore

public struct MemoryView: View {
    @Bindable var model: AppModel
    public init(model: AppModel) { self.model = model }

    public enum Mode: String, CaseIterable, Identifiable { case graph = "Graph", timeline = "Timeline"; public var id: String { rawValue } }
    /// BRAINMERGE_MEMORY=timeline opens on the timeline (screenshots); the graph otherwise.
    @State private var mode: Mode = ProcessInfo.processInfo.environment["BRAINMERGE_MEMORY"] == "timeline" ? .timeline : .graph

    var installedApps: [NotesApp] { NotesApps.installed() }
    var target: NotesTarget { NotesApps.target(for: model.notesApp, installed: installedApps) }
    var brainLabel: String {
        guard let root = model.selectedBrain?.root.path else { return "~/Brain" }
        let home = model.paths.home.path
        return root.hasPrefix(home) ? "~" + root.dropFirst(home.count) : root
    }
    /// "What your accounts remember" for the shared memory, the accounts' names for a memory of their own.
    var subtitle: String {
        guard model.brains.count > 1, let folder = model.selectedFolder else {
            return "What your accounts remember about your projects. One folder, \(brainLabel)."
        }
        let users = model.accounts(using: folder.id).map(\.identity.name)
        let who = users.isEmpty ? "No account writes here yet" : "What \(users.joined(separator: ", ")) remember\(users.count == 1 ? "s" : "") about your projects"
        return "\(who). \(brainLabel)."
    }
    var sortedCounts: [(slug: String, count: Int)] {
        model.memoryCounts.map { (slug: $0.key, count: $0.value) }.sorted { $0.count == $1.count ? $0.slug < $1.slug : $0.count > $1.count }
    }
    /// Row text starts after the padding, the avatar and the gap: the divider starts there too.
    static let rowInset: CGFloat = 14 + 30 + 14

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader("Memory", subtitle: subtitle) {
                HStack(spacing: 10) {
                    if model.brains.count > 1 {
                        Picker("Memory", selection: Binding(get: { model.selectedBrainID ?? model.brains.first?.id ?? "" }, set: { model.selectBrain($0) })) {
                            ForEach(model.brains) { folder in Text(folder.name).tag(folder.id) }
                        }
                        .labelsHidden().pickerStyle(.menu).fixedSize()
                    }
                    Button(target.label) { open(with: target) }.buttonStyle(.glassProminent).tint(Theme.Colors.button)
                    openWithMenu
                }
            }
            HStack(spacing: 12) {
                Picker("View", selection: $mode) { ForEach(Mode.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                // The graph carries its own legend; the timeline keeps the counts of saves.
                if mode == .timeline { chips }
            }
            switch mode {
            case .graph:
                MemoryGraphView(graph: model.memoryGraph, app: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .timeline:
                ScrollView { timeline.padding(.bottom, 8) }
            }
        }
        .padding(Theme.Layout.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { model.refreshMemory() }
    }

    var timeline: some View {
        VStack(alignment: .leading, spacing: 16) {
            GlassCard {
                VStack(alignment: .leading, spacing: 0) {
                    if model.memoryEvents.isEmpty {
                        Text("Nothing remembered yet. Open an account and work on a project: what it learns shows up here.")
                            .foregroundStyle(Theme.Colors.textMuted).padding(22)
                    }
                    ForEach(Array(model.memoryEvents.enumerated()), id: \.element.id) { index, event in
                        row(event)
                        if index < model.memoryEvents.count - 1 { Divider().overlay(Theme.Colors.surfaceLine).padding(.leading, Self.rowInset) }
                    }
                }
            }
            .frame(maxWidth: Theme.Layout.readingWidth, alignment: .leading)
            if installedApps.isEmpty, target == .folder {
                HStack(spacing: 8) {
                    Text("These are plain Markdown files: any notes app that reads files can show them.").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint)
                    ForEach(NotesApps.suggestions) { app in
                        Button("Get \(app.name)") { NSWorkspace.shared.open(app.website) }.buttonStyle(.plain).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.accent)
                    }
                }
            }
        }
    }

    /// The other ways to open the folder: Finder, the other notes apps found, any app.
    var openWithMenu: some View {
        Menu("Open with") {
            if target != .folder { Button("Finder") { open(with: .folder) } }
            ForEach(installedApps.filter { .app($0) != target }) { app in Button(app.name) { open(with: .app(app)) } }
            Divider()
            Button("Other app…") {
                if let url = NotesApps.chooseApp(), let root = model.selectedBrain?.root {
                    model.setNotesApp("path:" + url.path)
                    NotesApps.open(root, with: .custom(url))
                }
            }
        }
        .menuStyle(.button).buttonStyle(.glass).fixedSize()
    }

    func open(with target: NotesTarget) {
        guard let root = model.selectedBrain?.root else { return }
        NotesApps.open(root, with: target)
    }

    var chips: some View {
        HStack(spacing: 8) {
            ForEach(sortedCounts, id: \.slug) { item in
                let account = model.accounts.first { $0.id == item.slug }
                chip(color: account.map { Theme.color(for: $0.identity.tint) } ?? Theme.color(for: .gray),
                     text: "\(account?.identity.name ?? "Someone") · \(item.count)")
            }
            chip(color: Theme.Colors.sage, text: model.projectCount == 1 ? "1 project" : "\(model.projectCount) projects")
        }
    }

    func chip(color: Color, text: String) -> some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(Theme.Fonts.secondary)
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .glassEffect(.regular, in: Capsule())
    }

    func row(_ event: MemoryEvent) -> some View {
        HStack(alignment: .center, spacing: 14) {
            OrbView(name: event.name, tint: event.tint, size: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(Text(event.name).fontWeight(.semibold)) \(event.sentence)")
                    .font(Theme.Fonts.body)
                Text(event.detail).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted)
            }
            Spacer()
            Text(Self.relative(event.date)).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    static func relative(_ date: Date) -> String {
        if Date().timeIntervalSince(date) < 60 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
