import AppKit
import SwiftUI
import BrainmergeCore

public enum BrainmergeUIInfo { public static let version = BrainmergeInfo.version }

public struct RootView: View {
    public typealias Section = AppSection

    @Bindable var model: AppModel
    @State private var onboarding: OnboardingModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var section: Section = Section(rawValue: ProcessInfo.processInfo.environment["BRAINMERGE_SCREEN"] ?? "") ?? .accounts   // add opens accounts with the sheet

    public init(model: AppModel) {
        self.model = model
        _onboarding = State(initialValue: OnboardingModel(app: model))
    }

    public var body: some View {
        // The splash while the first load runs, then a crossfade to the screens (a plain, shorter dissolve with Reduce Motion).
        ZStack {
            switch model.launchPhase {
            case .loading: LaunchView().transition(.opacity)
            case .ready: screens.transition(.opacity)
            }
        }
        .animation(reduceMotion ? .linear(duration: Theme.Launch.reducedFade) : .easeOut(duration: Theme.Launch.fade), value: model.launchPhase)
        .frame(minWidth: 960, minHeight: 640)
        .font(Theme.Fonts.body)
        .preferredColorScheme(.dark)
        .task {
            // The first load runs behind the splash once per process; a window opened later finds it done and no splash.
            // The onboarding models built meanwhile decide on their own right before the switch (OnboardingModel.init).
            await model.launch()
            guard !Task.isCancelled else { return }
            model.offerMoveIfNeeded()
            model.updateWatching()
        }
        // Back in front: Claude may have updated itself in the meantime.
        // And a login may have changed in Claude Code: the emails on the accounts are read again.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.windowBecameActive()
        }
        // The clocks follow the window: all of them while it is open, those the menu bar icon needs once it is closed.
        // The setup finishing is seen by the model's reload, with or without a window.
        .onAppear { model.windowAppeared() }
        .onDisappear { model.windowDisappeared() }
        // Until the guide is closed, the setup is not done: no menu bar icon, and closing the window quits.
        .onChange(of: showsGuide, initial: true) { _, guide in
            model.setupGuideShown = guide
            showRequestedScreen()
        }
        .onChange(of: model.requestedScreen) { showRequestedScreen() }
        // The splash's only element goes away: VoiceOver hears that the accounts are there.
        .onChange(of: model.launchPhase) { _, phase in
            if phase == .ready { AccessibilityNotification.Announcement(LaunchView.readyAnnouncement).post() }
            showRequestedScreen()
        }
        // The menu bar switches screens (Cmd-1 to Cmd-4, Cmd-comma), once the screens are there.
        .focusedSceneValue(\.brainmergeSection, model.launchPhase == .ready && !model.needsOnboarding && onboarding.finished ? $section : nil)
        .alert(model.message?.title ?? "", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } }), presenting: model.message) { m in
            if m.action != nil { Button(m.actionLabel ?? "OK") { perform(m) } }
            Button(m.action == .moveToApplications ? "Not now" : "OK", role: .cancel) { if m.action == .moveToApplications { Installer.remember(declined: Installer.bundlePath) } }
        } message: { m in
            Text(m.detail)
        }
    }

    var showsGuide: Bool { model.stateProblem == nil && (model.needsOnboarding || !onboarding.finished) }

    /// A screen the menu bar asked for, once the screens are there; never over the splash or the guide.
    static func screenToShow(requested: Section?, phase: LaunchPhase, showsGuide: Bool) -> Section? {
        guard let requested, phase == .ready, !showsGuide else { return nil }
        return requested
    }

    func showRequestedScreen() {
        guard let screen = Self.screenToShow(requested: model.requestedScreen, phase: model.launchPhase, showsGuide: showsGuide) else { return }
        section = screen
        model.requestedScreen = nil
    }

    /// The guided setup, or the main window once everything is in place.
    @ViewBuilder var screens: some View {
        if let problem = model.stateProblem {
            StateProblemView(model: model, problem: problem)
        } else if showsGuide {
            OnboardingView(model: onboarding)
        } else {
            ZStack {
                WarmBackground(accents: model.openAccounts.map(\.identity.tint))
                HStack(spacing: 0) {
                    sidebar.padding(12)
                    detail
                }
            }
        }
    }

    @ViewBuilder var detail: some View {
        switch section {
        case .accounts: AccountsView(model: model)
        case .memory: MemoryView(model: model)
        case .usage: UsageView(model: model)
        case .settings: SettingsView(model: model)
        }
    }

    // MARK: Sidebar: a glass panel, the screens, the accounts, the creature.

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Brainmerge").font(.system(size: 14, weight: .semibold, design: .serif)).padding(.horizontal, 10).padding(.top, 30).padding(.bottom, 8)
            ForEach(Section.allCases) { s in navRow(s) }
            Text("ACCOUNTS").font(Theme.Fonts.sectionLabel).foregroundStyle(Theme.Colors.textFaint).padding(.horizontal, 10).padding(.top, 16).padding(.bottom, 4)
            ScrollView { VStack(spacing: 2) { ForEach(model.accounts) { account in accountRow(account) } } }
            Spacer(minLength: 8)
            creatureFooter
        }
        .padding(8)
        .frame(width: 220)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// A screen: the whole row switches to it; the View menu too, with Cmd-1 to Cmd-4 (BrainmergeCommands).
    func navRow(_ s: Section) -> some View {
        let selected = section == s
        return Button { section = s } label: {
            Label(s.title, systemImage: s.symbol)
                .font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                .padding(.horizontal, 10).padding(.vertical, 7)
        }
        .buttonStyle(SidebarRowStyle(selected: selected))
        .help("\(s.title) (Command-\(String(s.digit)))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// An account: the word on the right says what a click does (see SidebarAccountAction).
    func accountRow(_ account: Account) -> some View {
        let othersOpen = model.openAccounts.contains { $0.id != account.id }
        let action = SidebarAccountAction.of(account: account, opening: model.opening, busy: model.accountsBusy,
                                             othersOpen: othersOpen, appExists: model.appURL(of: account.id) != nil)
        let help = action.help(for: account, othersOpen: othersOpen)
        return Button { Task { await model.perform(action, on: account.id) } } label: {
            HStack(spacing: 9) {
                OrbView(name: account.identity.name, tint: account.identity.tint, logo: model.logo(for: account.identity), size: 22)
                Text(account.identity.name).font(.system(size: 13)).lineLimit(1)
                Spacer(minLength: 4)
                HStack(spacing: 6) {
                    if let label = action.label { SidebarRowHint(text: label) }
                    if account.isRunning { Circle().fill(Theme.Colors.sage).frame(width: 6, height: 6).shadow(color: Theme.Colors.sage, radius: 4) }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
        }
        .buttonStyle(SidebarRowStyle())
        .disabled(!action.isEnabled)
        .help(help)
        .accessibilityLabel(action.accessibilityLabel(for: account))
        .accessibilityHint(help)
    }

    var creatureState: CreatureState {
        if let last = model.lastMemorySave, Date().timeIntervalSince(last) < 10 { return .glowing }
        if !model.opening.isEmpty || !model.openAccounts.isEmpty { return .awake }
        return .asleep
    }

    var creatureLine: String {
        switch creatureState {
        case .glowing: return "Memory saved just now"
        case .awake:
            if !model.opening.isEmpty { return "Opening…" }
            let n = model.openAccounts.count
            return n == 1 ? "1 account open" : "\(n) accounts open"
        case .asleep: return "No account open"
        }
    }

    var creatureFooter: some View {
        HStack(spacing: 8) {
            CreatureView(state: creatureState, size: 28)
            Text(creatureLine).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted).lineLimit(1)
        }
        .padding(.horizontal, 6).padding(.bottom, 2)
    }

    func perform(_ m: UserMessage) {
        switch m.action {
        case .quit(let slug): model.quit(slug)
        case .quitOthersThenOpen(let slug): model.quitOthers(then: slug)
        case .getClaude: if let url = URL(string: "https://claude.ai/download") { NSWorkspace.shared.open(url) }
        case .openSettings: section = .settings
        case .moveToApplications: Installer.moveAndRelaunch { error in model.present(error) }
        case nil: break
        }
    }
}
