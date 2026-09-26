import AppKit
import SwiftUI

/// A row of tiles to choose what opens the memory: the folder, an installed notes app (with its real icon),
/// any other app, and, when nothing is installed, free apps to get. The apps and their icons come looked up already
/// (`found`, the guide looks them up as it opens), or are looked up off the main thread as the picker appears: drawing it
/// never asks macOS for anything.
public struct NotesAppPicker: View {
    @Binding var selection: String?
    let given: NotesApps.Found?
    @State private var looked: NotesApps.Found?
    @State private var customIcon: NSImage?
    @State private var customIconPath: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init(selection: Binding<String?>, found: NotesApps.Found? = nil) {
        _selection = selection; self.given = found
    }

    var found: NotesApps.Found? { given ?? looked }
    var installed: [NotesApp] { found?.apps ?? [] }

    var custom: URL? {
        guard let selection, selection.hasPrefix("path:") else { return nil }
        return URL(fileURLWithPath: String(selection.dropFirst(5)))
    }

    public var body: some View {
        tiles.task { if given == nil, looked == nil { looked = await NotesApps.found() } }
    }

    var tiles: some View {
        HStack(alignment: .top, spacing: 10) {
            tile(.folder, title: "Folder", subtitle: "Finder", selected: selection == nil) { selection = nil }
            ForEach(installed) { app in
                tile(.app(app), title: app.name, subtitle: nil, selected: selection == app.bundleIdentifier) { selection = app.bundleIdentifier }
            }
            if let custom {
                tile(.custom(custom), title: custom.deletingPathExtension().lastPathComponent, subtitle: nil, selected: true) {}
                    .task(id: custom.path) {
                        let path = custom.path
                        let box = await Task.detached(priority: .userInitiated) { NotesApps.Found(apps: [], icons: ["": NotesApps.icon(for: .custom(URL(fileURLWithPath: path)))]) }.value
                        customIcon = box.icons[""]
                        customIconPath = path
                    }
            }
            Button {
                if let url = NotesApps.chooseApp() { selection = "path:" + url.path }
            } label: {
                tileLabel(image: Image(systemName: "ellipsis.circle"), title: "Other app", subtitle: nil, selected: false)
            }
            .buttonStyle(.plain)
            if found != nil, installed.isEmpty {
                ForEach(NotesApps.suggestions) { app in
                    Button { NSWorkspace.shared.open(app.website) } label: {
                        tileLabel(image: Image(systemName: "arrow.down.circle"), title: app.name, subtitle: "Get, free", selected: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    func tile(_ target: NotesTarget, title: String, subtitle: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            tileLabel(image: icon(for: target), title: title, subtitle: subtitle, selected: selected)
        }
        .buttonStyle(.plain)
    }

    /// The icon looked up with the apps; a custom app picked in "Other app" is looked up once, when picked.
    func icon(for target: NotesTarget) -> Image {
        if let image = found?.icon(for: target) { return Image(nsImage: image) }
        if case .custom(let url) = target, let image = customIcon, customIconPath == url.path { return Image(nsImage: image) }
        return Image(systemName: target == .folder ? "folder" : "app")
    }

    func tileLabel(image: Image, title: String, subtitle: String?, selected: Bool) -> some View {
        // The subtitle slot is always there, so every title sits on the same line.
        VStack(spacing: 5) {
            image.resizable().scaledToFit().frame(width: 36, height: 36).foregroundStyle(Theme.Colors.textMuted)
            Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1)
            Text(subtitle ?? " ").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textFaint)
        }
        .padding(.horizontal, 6)
        .frame(width: 88, height: 88)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .choiceStroke(selected: selected, reduceMotion: reduceMotion)
    }
}
