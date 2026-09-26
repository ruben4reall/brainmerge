import AppKit
import SwiftUI
import BrainmergeCore

/// The quick opener's window: a panel that becomes key without activating Brainmerge, so the app below stays in front
/// until an action moves it, like Spotlight. It only hears keys typed into itself: never a global monitor.
final class QuickOpenerWindow: NSPanel {
    /// A key typed into the panel: true when the opener used it.
    var onKey: ((NSEvent) -> Bool)?
    var onResign: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        // A word still being composed (an input method) keeps Return and Esc for itself.
        let composing = (firstResponder as? NSTextView)?.hasMarkedText() == true
        if event.type == .keyDown, !composing, onKey?(event) == true { return }
        super.sendEvent(event)
    }

    /// A click elsewhere or another app in front: the panel goes, as Spotlight does.
    override func resignKey() {
        super.resignKey()
        onResign?()
    }
}

/// What the panel's search holds: the query, the picked row, and a count of showings that gives each one a fresh field.
@MainActor @Observable
final class QuickOpenerSearch {
    var query = "" { didSet { if query != oldValue { selection = 0 } } }
    var selection = 0
    var shows = 0
}

/// The quick opener: a small glass panel over the current app with a search field and the accounts. Return opens or
/// shows, Cmd-Return opens its memory in the notes app, Cmd-U shows its usage in Brainmerge, Esc closes. Owned by the
/// app delegate, so it works with the window closed.
@MainActor
public final class QuickOpenerPanelController {
    static let prompt = "Open an account"
    static let footer = "Return opens or shows · ⌘Return its memory · ⌘U its usage · Esc closes"
    static let noMatch = "No account matches."
    static let noAccounts = "No accounts yet."
    static let size = CGSize(width: 560, height: 420)

    let model: AppModel
    let search = QuickOpenerSearch()
    private var panel: QuickOpenerWindow?

    public init(model: AppModel) { self.model = model }

    public var isShown: Bool { panel?.isVisible == true }

    /// The shortcut was pressed.
    public func press() {
        switch QuickOpenerPress.response(setupDone: model.setupDone, panelShown: isShown) {
        case .showPanel: show()
        case .closePanel: close()
        case .showWindow: model.windowRequests += 1
        }
    }

    /// Centered on the screen, its top a fifth of the way down, never below the screen's bottom.
    static func frame(size: CGSize, in screen: CGRect) -> CGRect {
        let top = screen.maxY - screen.height / 5
        return CGRect(x: screen.midX - size.width / 2, y: max(screen.minY, top - size.height), width: size.width, height: size.height)
    }

    func show() {
        // With the window closed and no menu bar icon, no clock runs: the accounts are read again as the panel opens.
        if model.launchPhase == .ready { model.reload() }
        search.query = ""
        search.selection = 0
        search.shows += 1
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let visible = screen?.visibleFrame { panel.setFrame(Self.frame(size: Self.size, in: visible), display: false) }
        panel.animationBehavior = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .none : .utilityWindow
        panel.makeKeyAndOrderFront(nil)
    }

    func close() { panel?.orderOut(nil) }

    var results: [QuickOpenerRow] { QuickOpenerRanking.filter(model.quickOpenerRows, query: search.query) }

    /// A key, a click or a hover's pick: an action closes the panel first, then goes through the model.
    func perform(_ command: QuickOpenerCommand, on picked: QuickOpenerRow? = nil) {
        let rows = results
        switch command {
        case .close: close()
        case .next: search.selection = QuickOpenerRanking.moved(search.selection, by: 1, count: rows.count)
        case .previous: search.selection = QuickOpenerRanking.moved(search.selection, by: -1, count: rows.count)
        case .open, .memory, .usage:
            let index = QuickOpenerRanking.clamped(search.selection, count: rows.count)
            guard let row = picked ?? (rows.indices.contains(index) ? rows[index] : nil) else { return }
            // "Opening…" and "Updating…" do nothing on Return, as in the sidebar: the panel stays.
            if command == .open, !row.isEnabled { return }
            close()
            model.quickOpen(command, on: row.id)
        }
    }

    private func makePanel() -> QuickOpenerWindow {
        let panel = QuickOpenerWindow(contentRect: CGRect(origin: .zero, size: Self.size),
                                      styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .modalPanel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Cream text on glass: the panel keeps the app's dark look over a light app too.
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.onKey = { [weak self] event in
            guard let self, let command = QuickOpenerKeys.command(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers,
                                                                  modifiers: event.modifierFlags) else { return false }
            self.perform(command)
            return true
        }
        panel.onResign = { [weak self] in self?.close() }
        panel.contentView = NSHostingView(rootView: QuickOpenerView(controller: self, model: model, search: search))
        return panel
    }
}

/// The panel's content: the field, the rows, the keys. The glass is only as tall as its rows; the rest of the panel is
/// clear.
struct QuickOpenerView: View {
    let controller: QuickOpenerPanelController
    let model: AppModel
    @Bindable var search: QuickOpenerSearch
    @FocusState private var fieldFocused: Bool
    static let rowHeight: CGFloat = 44
    static let visibleRows = 6

    var body: some View {
        let rows = QuickOpenerRanking.filter(model.quickOpenerRows, query: search.query)
        let picked = QuickOpenerRanking.clamped(search.selection, count: rows.count)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.Colors.textMuted)
                TextField(QuickOpenerPanelController.prompt, text: $search.query)
                    .textFieldStyle(.plain).font(Theme.Fonts.search).foregroundStyle(Theme.Colors.text)
                    .focused($fieldFocused)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            Divider().overlay(Theme.Colors.surfaceLine)
            if rows.isEmpty {
                Text(model.accounts.isEmpty ? QuickOpenerPanelController.noAccounts : QuickOpenerPanelController.noMatch)
                    .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted)
                    .padding(.horizontal, 16).padding(.vertical, 14)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                rowView(row, picked: index == picked)
                                    .id(row.id)
                                    .onHover { inside in if inside { search.selection = index } }
                            }
                        }
                        .padding(6)
                    }
                    .frame(height: CGFloat(min(rows.count, Self.visibleRows)) * (Self.rowHeight + 2) + 12)
                    .onChange(of: picked) { if rows.indices.contains(picked) { proxy.scrollTo(rows[picked].id) } }
                }
            }
            Divider().overlay(Theme.Colors.surfaceLine)
            Text(QuickOpenerPanelController.footer)
                .font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textFaint)
                .padding(.horizontal, 16).padding(.vertical, 9)
        }
        .frame(width: QuickOpenerPanelController.size.width, alignment: .leading)
        .glassEffect(.regular.tint(Theme.Colors.background.opacity(0.55)), in: RoundedRectangle(cornerRadius: Theme.Layout.panelRadius, style: .continuous))
        .frame(maxHeight: .infinity, alignment: .top)
        // Each showing starts fresh, with the field ready for typing.
        .id(search.shows)
        .defaultFocus($fieldFocused, true)
        .onAppear { fieldFocused = true }
    }

    func rowView(_ row: QuickOpenerRow, picked: Bool) -> some View {
        let account = model.accounts.first { $0.id == row.id }
        return Button { controller.perform(.open, on: row) } label: {
            HStack(spacing: 12) {
                OrbView(name: row.name, tint: row.tint, logo: account.flatMap { model.logo(for: $0.identity) }, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.name).font(Theme.Fonts.cardName).foregroundStyle(Theme.Colors.text).lineLimit(1)
                    if let note = row.note {
                        Text(note).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let word = row.word {
                    Text(word).font(Theme.Fonts.caption).foregroundStyle(row.isEnabled ? Theme.Colors.textMuted : Theme.Colors.textFaint)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: Self.rowHeight)
            .background(RoundedRectangle(cornerRadius: Theme.Layout.rowRadius, style: .continuous).fill(picked ? Theme.Colors.selection : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.word.map { "\(row.name), \($0)" } ?? row.name)
    }
}
