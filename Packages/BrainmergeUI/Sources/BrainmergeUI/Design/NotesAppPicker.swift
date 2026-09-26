import AppKit
import SwiftUI

/// A row of tiles to choose what opens the memory: the folder, an installed notes app (with its real icon),
/// any other app, and, when nothing is installed, free apps to get.
public struct NotesAppPicker: View {
    @Binding var selection: String?
    let installed: [NotesApp]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init(selection: Binding<String?>, installed: [NotesApp] = NotesApps.installed()) {
        _selection = selection; self.installed = installed
    }

    var custom: URL? {
        guard let selection, selection.hasPrefix("path:") else { return nil }
        return URL(fileURLWithPath: String(selection.dropFirst(5)))
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            tile(.folder, title: "Folder", subtitle: "Finder", selected: selection == nil) { selection = nil }
            ForEach(installed) { app in
                tile(.app(app), title: app.name, subtitle: nil, selected: selection == app.bundleIdentifier) { selection = app.bundleIdentifier }
            }
            if let custom {
                tile(.custom(custom), title: custom.deletingPathExtension().lastPathComponent, subtitle: nil, selected: true) {}
            }
            Button {
                if let url = NotesApps.chooseApp() { selection = "path:" + url.path }
            } label: {
                tileLabel(image: Image(systemName: "ellipsis.circle"), title: "Other app", subtitle: nil, selected: false)
            }
            .buttonStyle(.plain)
            if installed.isEmpty {
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
            tileLabel(image: Image(nsImage: NotesApps.icon(for: target)), title: title, subtitle: subtitle, selected: selected)
        }
        .buttonStyle(.plain)
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
