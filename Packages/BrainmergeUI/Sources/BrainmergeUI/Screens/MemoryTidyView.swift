import SwiftUI
import BrainmergeCore

/// The Memory screen's third tab: the notes Claude will not load, and what else wants a look, group by group, each row with
/// at most one button. Nothing changes without a click: File under shows what it will move first, Compare shows both
/// copies first. Glass buttons only: the screen's one purple button stays the notes app's.
struct MemoryTidyView: View {
    @Bindable var model: AppModel
    /// File under's preview, while it shows.
    @State private var filing: MemoryTidy.Plan?
    /// The two copies Compare shows, while it shows.
    @State private var comparing: MemoryHealth.Item?

    static let tidy = "Nothing to tidy. Every note is where the next session will find it."
    static let reading = "Reading the notes…"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let report = model.memoryTidy.report {
                    if report.groups.isEmpty {
                        GlassCard { Text(Self.tidy).foregroundStyle(Theme.Colors.textMuted).padding(22).frame(maxWidth: .infinity, alignment: .leading) }
                    }
                    ForEach(report.groups) { group in section(group, projects: report.projects) }
                } else {
                    Text(Self.reading).foregroundStyle(Theme.Colors.textMuted)
                }
            }
            .frame(maxWidth: Theme.Layout.readingWidth, alignment: .leading)
            .padding(.bottom, 8)
        }
        .alert(filing.map { "File under \($0.to)?" } ?? "", isPresented: Binding(get: { filing != nil }, set: { if !$0 { filing = nil } }),
               presenting: filing) { plan in
            Button("Move") { Task { await model.file(plan) } }
            Button("Cancel", role: .cancel) {}
        } message: { plan in
            Text(plan.preview)
        }
        .sheet(item: $comparing) { item in CompareCopiesSheet(model: model, item: item) }
    }

    func section(_ group: MemoryHealth.Group, projects: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.title.uppercased()).font(Theme.Fonts.sectionLabel).foregroundStyle(Theme.Colors.textFaint)
            GlassCard {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                        row(item, projects: projects)
                        if index < group.items.count - 1 { Divider().overlay(Theme.Colors.surfaceLine).padding(.leading, 14) }
                    }
                }
            }
        }
    }

    func row(_ item: MemoryHealth.Item, projects: [String]) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.sentence).font(Theme.Fonts.body).fixedSize(horizontal: false, vertical: true)
                if let detail = item.detail {
                    Text(detail).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            action(item, projects: projects)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    @ViewBuilder
    func action(_ item: MemoryHealth.Item, projects: [String]) -> some View {
        switch item.kind {
        case .oneOffNotes:
            fileMenu(item, projects: projects)
        case .emptyOneOffFolders:
            Button("Hide") { Task { await model.hideEmptyFolders(item) } }
                .buttonStyle(.glass).controlSize(.small).disabled(model.working != nil)
                .help("Hides them from this tab. The folders stay: accounts link to them.")
        case .conflictCopy:
            Button("Compare") { comparing = item }.buttonStyle(.glass).controlSize(.small)
        case .noIndex, .indexTooLong, .notInIndex, .danglingLines:
            Button("Open") { open(item) }.buttonStyle(.glass).controlSize(.small)
        case .unsaved:
            EmptyView()
        }
    }

    /// The projects the notes' names mention first, then every other project.
    func fileMenu(_ item: MemoryHealth.Item, projects: [String]) -> some View {
        let others = projects.filter { !item.suggested.contains($0) }
        return Menu("File under…") {
            if !item.suggested.isEmpty {
                Section("Suggested") { ForEach(item.suggested, id: \.self) { project in Button(project) { preview(item, under: project) } } }
            }
            if !others.isEmpty {
                Section(item.suggested.isEmpty ? "Projects" : "Other projects") {
                    ForEach(others, id: \.self) { project in Button(project) { preview(item, under: project) } }
                }
            }
        }
        .menuStyle(.button).buttonStyle(.glass).controlSize(.small).fixedSize()
        .disabled(projects.isEmpty || model.working != nil)
    }

    func preview(_ item: MemoryHealth.Item, under project: String) {
        guard let folder = item.project else { return }
        Task { if let plan = await model.planFiling(folder, under: project) { filing = plan } }
    }

    /// The project's index in the notes app, or its folder when it has none.
    func open(_ item: MemoryHealth.Item) {
        guard let root = model.selectedBrain?.root, let project = item.project else { return }
        let folder = root.appending(path: "memory/\(project)", directoryHint: .isDirectory)
        let url = item.kind == .noIndex ? folder : folder.appending(path: MemoryIndex.fileName)
        NotesApps.open(url, with: NotesApps.target(for: model.notesApp, installed: NotesApps.installed()))
    }
}

/// Compare: both copies side by side, read only, and Keep this one under each. The other copy goes to the project's
/// `_archive/` in a commit; nothing is deleted.
struct CompareCopiesSheet: View {
    @Bindable var model: AppModel
    let item: MemoryHealth.Item
    @Environment(\.dismiss) private var dismiss
    @State private var copies: [(name: String, text: String)]?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Compare the copies").font(Theme.Fonts.sheetTitle)
                Text("Keep one. The other goes to the project's _archive folder, saved in the history: nothing is deleted.")
                    .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted)
            }
            if let copies, copies.count == 2, item.files.count == 2 {
                HStack(alignment: .top, spacing: 12) {
                    column(copies[0], keep: item.files[0], over: item.files[1])
                    column(copies[1], keep: item.files[1], over: item.files[0])
                }
            } else {
                Text(copies == nil ? MemoryTidyView.reading : "One of the copies cannot be read.")
                    .foregroundStyle(Theme.Colors.textMuted).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            HStack(spacing: 10) {
                WorkingLine(text: model.working)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.glass).keyboardShortcut(.cancelAction)
            }
        }
        .padding(22)
        .frame(width: 720, height: 480)
        .background(WarmBackground())
        .task { copies = await model.readCopies(item) }
    }

    func column(_ copy: (name: String, text: String), keep kept: String, over other: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(copy.name).font(Theme.Fonts.cardName).lineLimit(1).truncationMode(.middle)
            ScrollView {
                Text(copy.text).font(Theme.Fonts.secondary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading).padding(10)
            }
            .background(Theme.Colors.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Button("Keep this one") { Task { await model.keep(kept, over: other); dismiss() } }
                .buttonStyle(.glass).disabled(model.working != nil)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
