import AppKit
import SwiftUI
import BrainmergeCore

public struct AccountsView: View {
    @Bindable var model: AppModel
    @State private var query = ""
    /// BRAINMERGE_SCREEN=add opens the sheet at launch (screenshots, demos).
    @State private var showAdd = ProcessInfo.processInfo.environment["BRAINMERGE_SCREEN"] == "add"
    @State private var pendingRemoval: Account?
    /// The account a new memory is created for (nil: none).
    @State private var newMemoryFor: Account?
    @State private var showNewMemory = false
    @State private var editing: Account?
    /// The apps the person made that open the account being edited, found before its sheet opens.
    @State private var editingApps: [ExistingApp] = []
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Two to four cards per row that always fill the width (300 to 400 wide).
    let columns = [GridItem(.adaptive(minimum: 300, maximum: 400), spacing: 12)]

    public init(model: AppModel) { self.model = model }

    var shown: [Account] { AccountsFilter.apply(model.accounts, query: query) }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Every word, orb and button here is an obstacle the launch's leap flies around; the cards' empty edges are
                // not, so the leap can rise from the splash just under them. A banner drops in and the grid slides down.
                if let warning = model.memoryWarning {
                    memoryBanner(warning).launchObstacle("accounts.memoryBanner").modifier(ReducedFadeIn()).transition(.banner(reduceMotion))
                }
                if let banner = model.updateBanner {
                    updateBanner(banner).launchObstacle("accounts.updateBanner").modifier(ReducedFadeIn()).transition(.banner(reduceMotion))
                }
                ScreenHeader("Accounts", subtitle: subtitle, busy: model.working != nil, changeKey: subtitleWords) {
                    HStack(spacing: 10) {
                        searchField
                        Button("Add account") { showAdd = true }.buttonStyle(.glassProminent).tint(Theme.Colors.button)
                    }
                }
                .launchObstacle("accounts.header")
                // A card added or removed scales a touch and fades while the others make room; a search filters at once
                // (only the accounts themselves animate the grid, never the query). With Reduce Motion the cards take their
                // new places at once and the card itself fades in or out where it is.
                // The cards keep the sidebar's order: an account that opens never moves (AccountsFilter). Any reflow left
                // (an account added or removed) slides.
                GlassEffectContainer(spacing: 12) {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(shown) { account in
                            card(account).transition(reduceMotion ? .fade(true) : .opacity.combined(with: .scale(scale: 0.96)))
                        }
                    }
                }
                .animation(Theme.Motion.layout(Theme.Motion.settle, reduceMotion), value: query.isEmpty ? shown.map(\.id) : [])
                if shown.isEmpty, !query.isEmpty {
                    Text("No account matches “\(query)”.").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted)
                }
            }
            .padding(Theme.Layout.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            // With Reduce Motion the grid moves at once and the banner only fades (ReducedFadeIn).
            .animation(reduceMotion ? nil : Theme.Motion.out(0.22), value: model.memoryWarning)
            .animation(reduceMotion ? nil : Theme.Motion.out(0.22), value: model.updateBanner)
        }
        .sheet(isPresented: $showAdd) { AddAccountSheet(model: model, isPresented: $showAdd) }
        .sheet(isPresented: $showNewMemory) { NewMemorySheet(model: model, isPresented: $showNewMemory, attach: newMemoryFor) }
        .sheet(item: $editing) { account in
            EditAccountSheet(model: model, isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } }), account: account, otherApps: editingApps)
        }
        // The search field does not grab the keyboard on its own: nothing should swallow a keystroke at launch.
        // BRAINMERGE_SCREEN=edit opens the edit sheet of the first secondary account (screenshots, demos).
        .onAppear {
            DispatchQueue.main.async { searchFocused = false }
            if ProcessInfo.processInfo.environment["BRAINMERGE_SCREEN"] == "edit", editing == nil,
               let first = model.accounts.first(where: { !$0.identity.isPrimary }) {
                startEditing(first)
            }
        }
        .confirmationDialog("Remove \(pendingRemoval?.identity.name ?? "")?", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }), presenting: pendingRemoval) { account in
            Button("Remove, keep its files") { Task { await model.remove(account.id, deleteData: false) } }
            if canDeleteFiles(account) {
                Button("Remove and delete its files", role: .destructive) { Task { await model.remove(account.id, deleteData: true) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: { account in
            Text(canDeleteFiles(account)
                 ? "The memory keeps everything this account wrote. Deleting its files logs it out of Claude on this Mac."
                 : "The memory keeps everything this account wrote. Its folders were there before Brainmerge, so they stay as they are.")
        }
    }

    var subtitle: String {
        if let working = model.working { return working }
        let open = model.openAccounts
        if let a = model.accounts.first(where: { model.opening.contains($0.id) }) { return "Opening \(a.identity.name)…" }
        if open.isEmpty { return "\(model.accounts.count) accounts, none open" }
        let memory = model.totalRAMBytes > 0 ? ", \(ByteFormat.ram(model.totalRAMBytes))" : ""
        return open.count == 1 ? "1 account open\(memory)" : "\(open.count) accounts open\(memory)"
    }

    /// The subtitle without its RAM figure: the figure moves every few seconds and never animates (a new state crossfades).
    var subtitleWords: String {
        model.working ?? model.accounts.first(where: { model.opening.contains($0.id) }).map { "opening \($0.id)" } ?? "\(model.openAccounts.count) open"
    }

    var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.Colors.textFaint)
            TextField("Search", text: $query).textFieldStyle(.plain).font(.system(size: 13)).focused($searchFocused)
        }
        .padding(.horizontal, 9)
        .frame(width: 200, height: 26)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// A compact card: swatch, name, note, status; the primary action and the "more" menu on the right.
    /// While its account opens, a stroke in its own color turns around it; once open, its dot pops sage and rings once.
    func card(_ account: Account) -> some View {
        let opening = model.opening.contains(account.id)
        let memory = model.ramBytes(of: account.id)
        let sameAs = model.duplicateCodeAccount(of: account.id)?.identity.name
        let othersOpen = model.openAccounts.contains { $0.id != account.id }
        let action = SidebarAccountAction.of(account: account, opening: model.opening, busy: model.accountsBusy,
                                             othersOpen: othersOpen, appExists: model.appURL(of: account.id) != nil)
        let tint = Theme.color(for: account.identity.tint)
        let status = Self.status(of: account, memory: memory)
        return ZStack {
            HStack(spacing: 12) {
                OrbView(name: account.identity.name, tint: account.identity.tint, logo: model.logo(for: account.identity), size: 40)
                    // A card added while the app runs: one ring in its color around the orb.
                    .overlay { RingPulseView(ring: .added, start: model.addedAt[account.id], color: tint) }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(account.identity.name).font(Theme.Fonts.cardName).lineLimit(1)
                            .help(Self.nameHelp(of: account) ?? "")
                        // One Claude account used twice: a small mark, the whole sentence on hover and for VoiceOver.
                        if let sameAs {
                            Image(systemName: "person.2.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.Colors.accentLight)
                                .help(Self.duplicateHelp(sameAs: sameAs))
                                .accessibilityLabel(Self.duplicateHelp(sameAs: sameAs))
                        }
                    }
                    // The note or email keeps a few characters at least; the memory's name gives way after it.
                    HStack(spacing: 0) {
                        Text(Self.subtitle(of: account)).lineLimit(1)
                            .truncationMode(account.identity.note == nil ? .middle : .tail)
                            .frame(minWidth: 44, alignment: .leading)
                            .layoutPriority(1)
                        let suffix = memorySuffix(account)
                        if !suffix.isEmpty { Text(suffix).lineLimit(1) }
                    }
                    .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted)
                    .help(Self.subtitleHelp(of: account) ?? "")
                    HStack(spacing: 5) {
                        statusDot(account, updating: action == .updating, opened: model.openedAt[account.id])
                        // Open, closed, opening: the new words come in once the old ones have gone; the RAM figure that follows
                        // moves at once, never rolls.
                        SwappingText(text: status, key: Self.status(of: account, memory: 0))
                            .font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textMuted).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                // One width for Open, Opening…, Show and Update: a new word never reflows the text beside it. The old word
                // goes before the new one comes.
                let button = Self.cardButton(for: account, action: action)
                if let button {
                    ZStack(alignment: .trailing) {
                        cardButton(button, for: account, action: action).id(button.label).transition(SwapText.transition(reduceMotion))
                    }
                    .frame(minWidth: Self.buttonSlot, alignment: .trailing)
                    .animation(Theme.Motion.out(SwapText.insertion), value: button.label)
                }
                moreMenu(account)
            }
            .launchObstacle("accounts.card.\(account.id)")
            .padding(14)
            // Inside the card's glass, as its content: drawn over by the glass container, the stroke did not show.
            .overlay {
                ZStack { if opening { OpeningStrokeView(tint: tint).transition(.opacity) } }
                    .animation(Theme.Motion.unlessReduced(Theme.Motion.out(opening ? OpeningStroke.fadeIn : OpeningStroke.fadeOut), reduceMotion),
                               value: opening)
            }
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Layout.cardRadius, style: .continuous))
        }
        .contextMenu { actions(account) }
        // The apps made by hand for the account are looked for as the pointer comes: "Edit…" opens its sheet at once.
        .onHover { inside in if inside { Task { await model.prefetchOtherApps(account.id) } } }
    }

    /// The sheet opens with the apps made by hand for the account already known (looked for as the pointer came over the
    /// card): at once and at its full size, nothing moving under the pointer afterwards. Not known yet (the keyboard, the
    /// edit screen at launch): found first, a few milliseconds.
    func startEditing(_ account: Account) {
        if let known = model.knownOtherApps(account.id) {
            editingApps = known
            editing = account
            return
        }
        Task {
            editingApps = await model.otherApps(opening: account.id)
            editing = account
        }
    }

    /// The card's main button, in the sidebar's words: prominent to start something, plain to show a running window.
    @ViewBuilder func cardButton(_ button: CardButton, for account: Account, action: SidebarAccountAction) -> some View {
        let run: @MainActor () -> Void = {
            switch button.run {
            case .update: Task { await model.updateAccount(account.id) }
            case .rebuild, .open: Task { await model.perform(action, on: account.id) }
            }
        }
        let help = button.run == .update
            ? (account.isRunning ? "Quits this account, rebuilds its copy of Claude for the version installed, and opens it again" : "Rebuilds this account's copy of Claude for the version installed, then you can open it")
            : action.help(for: account, othersOpen: model.openAccounts.contains { $0.id != account.id })
        if button.isProminent {
            Button(button.label, action: run).buttonStyle(.glassProminent).tint(Theme.Colors.button).controlSize(.small)
                .disabled(!button.isEnabled).help(help)
        } else {
            Button(button.label, action: run).buttonStyle(.glass).controlSize(.small).disabled(!button.isEnabled).help(help)
        }
    }

    /// The visible entry to the card's actions (the context menu offers the same ones).
    func moreMenu(_ account: Account) -> some View {
        Menu { actions(account) } label: {
            Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.Colors.textMuted)
                .frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("More actions for \(account.identity.name)")
    }

    /// The switch from the menu, then one sentence: the notes already written stay where they are.
    func switchMemory(of account: Account, to folder: MemoryFolder) async {
        let previous = model.brainName(of: account.identity) ?? "its previous memory"
        guard folder.name != previous else { return }
        if await model.setBrain(of: account.id, to: folder.id) == nil {
            model.message = UserMessage(title: "\(account.identity.name) now writes to \(folder.name)",
                                        detail: "What it wrote so far stays in \(previous). It goes on with what \(folder.name) already holds.")
        }
    }

    /// With several memories, the note line says which one the account writes to.
    func memorySuffix(_ account: Account) -> String {
        guard model.brains.count > 1, let name = model.brainName(of: account.identity) else { return "" }
        return " · \(name) memory"
    }

    @ViewBuilder func actions(_ account: Account) -> some View {
        Button("Edit…") { startEditing(account) }
        Menu("Memory") {
            let current = model.brainName(of: account.identity)
            ForEach(model.brains) { folder in
                Button { Task { await switchMemory(of: account, to: folder) } } label: {
                    if folder.name == current { Label(folder.name, systemImage: "checkmark") } else { Text(folder.name) }
                }
            }
            Divider()
            Button("New memory…") { newMemoryFor = account; showNewMemory = true }
        }
        if model.appURL(of: account.id) != nil { Button("Show in Finder") { model.revealApp(account.id) } }
        if account.isOutdated { Button("Update for Claude") { Task { await model.updateAccount(account.id) } } }
        if !account.identity.isPrimary { Button(account.identity.iconMode == .tintedClone ? "Rebuild icon" : "Rebuild launcher") { Task { await model.rebuild(account.id) } } }
        else if account.identity.appURL(in: model.paths) != nil { Button("Rebuild app") { Task { await model.rebuild(account.id) } } }
        if account.isRunning { Button("Quit") { model.quit(account.id) } }
        Divider()
        Button("Remove from Brainmerge…", role: .destructive) { pendingRemoval = account }
    }

    /// Under the name: the person's note, else the email Claude Code uses for this account, else what the account is.
    nonisolated static func subtitle(of account: Account) -> String {
        account.identity.note ?? account.codeAccount?.email ?? (account.identity.isPrimary ? "Primary" : "Account")
    }

    /// With a note on the second line, the email moves to the name's tooltip.
    nonisolated static func nameHelp(of account: Account) -> String? {
        guard account.identity.note != nil, let email = account.codeAccount?.email else { return nil }
        return "Claude Code is logged in as \(email)"
    }

    /// Open or closed, and whether the account still has to log in (its Claude data folder holds no session yet).
    /// A Claude Code only account has no window to open or close.
    nonisolated static func status(of account: Account, memory: Int64) -> String {
        if !account.identity.surfaces.desktop { return "Claude Code only" }
        if case .outdated(let installed, let built) = account.claudeVersion {
            return account.isRunning ? "Open · runs Claude \(built), \(installed) installed" : "Closed · built for Claude \(built), \(installed) installed"
        }
        switch (account.isRunning, account.needsLogin) {
        case (true, true): return "Open · log in from its window"
        case (true, false): return memory > 0 ? "Open · \(ByteFormat.ram(memory))" : "Open"
        case (false, true): return "Not logged in yet"
        case (false, false): return "Closed"
        }
    }

    /// The room for the card's button, as wide as its widest word ("Opening…").
    static let buttonSlot: CGFloat = 76

    /// The card's main button.
    struct CardButton: Equatable {
        enum Run: Equatable { case open, rebuild, update }
        let label: String
        let run: Run
        let isEnabled: Bool
        let isProminent: Bool
    }

    /// Open or closed: sage or faint, 0.2 s either way. The moment its account opens from here, the dot pops from 0.4 of its
    /// size and one sage ring spreads from it; while its app is being updated, a small spinner takes its place.
    func statusDot(_ account: Account, updating: Bool, opened: Date?) -> some View {
        ZStack {
            if updating {
                ProgressView().controlSize(.mini).transition(.opacity)
            } else {
                BeatView(start: opened, duration: PopIn.duration) { elapsed in
                    Circle().fill(account.isRunning ? Theme.Colors.sage : Theme.Colors.textFaint)
                        .animation(Theme.Motion.unlessReduced(Theme.Motion.out(0.2), reduceMotion), value: account.isRunning)
                        .scaleEffect(PopIn.scale(elapsed: elapsed, reduceMotion: reduceMotion))
                        .opacity(PopIn.opacity(elapsed: elapsed, reduceMotion: reduceMotion))
                }
                .overlay { RingPulseView(ring: .opened, start: opened, color: Theme.Colors.sage) }
                .transition(.opacity)
            }
        }
        .frame(width: 6, height: 6)
        .animation(Theme.Motion.unlessReduced(Theme.Motion.out(Theme.Motion.quick), reduceMotion), value: updating)
    }

    /// The sidebar's word for the account (see SidebarAccountAction), with its disabled states: the card never offers a
    /// click the sidebar refuses. Only the card offers "Update" for an outdated copy (it quits, rebuilds and reopens).
    /// A Claude Code only account has no window: no button.
    nonisolated static func cardButton(for account: Account, action: SidebarAccountAction) -> CardButton? {
        if account.isOutdated, action != .opening, action != .updating {
            return CardButton(label: "Update", run: .update, isEnabled: true, isProminent: true)
        }
        guard let label = action.label else { return nil }
        return CardButton(label: label, run: action == .rebuild ? .rebuild : .open, isEnabled: action.isEnabled, isProminent: action != .show)
    }

    /// The mark next to the name of an account whose Claude Code uses the same email as another one.
    nonisolated static func duplicateHelp(sameAs name: String) -> String { "Same Claude account as \(name)" }

    /// The second line whole, for when a narrow card cuts it.
    nonisolated static func subtitleHelp(of account: Account) -> String? {
        account.identity.note ?? account.codeAccount?.email
    }

    /// The folders of the primary account and adopted accounts existed before Brainmerge: nothing to delete.
    func canDeleteFiles(_ account: Account) -> Bool {
        !account.identity.isPrimary && account.identity.cliProfilePath == nil && account.identity.desktopDataPath == nil
    }

    /// Claude moved on; some tinted copies did not yet.
    func updateBanner(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(Theme.Colors.accent)
            Text(text).font(Theme.Fonts.secondary)
            Spacer()
            Button("Update all") { Task { await model.updateAll() } }.buttonStyle(.glassProminent).tint(Theme.Colors.button).controlSize(.small)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    func memoryBanner(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "memorychip").foregroundStyle(Theme.Colors.textMuted)
            Text(text).font(Theme.Fonts.secondary)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
