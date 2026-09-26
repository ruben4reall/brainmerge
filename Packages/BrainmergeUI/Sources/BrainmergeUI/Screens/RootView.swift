import AppKit
import SwiftUI
import BrainmergeCore

public enum BrainmergeUIInfo { public static let version = BrainmergeInfo.version }

public struct RootView: View {
    public typealias Section = AppSection

    @Bindable var model: AppModel
    /// The guide and the launch clock, built on the window's first body (see `WindowParts`).
    @State private var parts: WindowParts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var section: Section = Section(rawValue: ProcessInfo.processInfo.environment["BRAINMERGE_SCREEN"] ?? "") ?? .accounts   // add opens accounts with the sheet

    /// Reads nothing from the model and builds nothing: SwiftUI runs it inside the scenes' body, at every redraw of them.
    public init(model: AppModel) {
        self.model = model
        _parts = State(initialValue: WindowParts())
    }

    /// With a given clock (tests read what the screens tell it).
    init(model: AppModel, launch: LaunchClock) {
        self.model = model
        _parts = State(initialValue: WindowParts(launch: launch))
    }

    private var onboarding: OnboardingModel { parts.onboarding(for: model) }
    /// The splash and the hand-offs: one clock for the overlay, the screens under it and the creature it lands on.
    private var launch: LaunchClock { parts.launch(for: model) }

    public var body: some View {
        // The splash is an overlay while the first load runs; once ready, the screens are built underneath and fade in on
        // the splash's own clock while its creature leaps into the sidebar (LaunchScene.swift). Reduce Motion: a dissolve.
        ZStack {
            if launch.showsBackdrop { WarmBackground() }
            if model.launchPhase == .ready { screens }
            if !launch.finished { LaunchView(clock: launch) }
        }
        .coordinateSpace(.named(LaunchClock.space))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { launch.windowSize = $0 }
        .environment(launch)
        .frame(minWidth: 960, minHeight: 640)
        .font(Theme.Fonts.body)
        .preferredColorScheme(.dark)
        .task {
            // The first load runs behind the splash once per process; a window opened later finds it done and no splash.
            // The onboarding models built meanwhile decide on their own right before the switch (OnboardingModel.init).
            // The icon and the app menu wait for the creature to land (AppModel.launchSettling).
            let launch = self.launch
            await model.launch { [model] in if !launch.finished { model.launchSettling = true } }
            guard !Task.isCancelled else { return }
            model.offerMoveIfNeeded()
            model.updateWatching()
        }
        .onChange(of: launch.finished) { _, landed in if landed { model.launchSettling = false } }
        // Back in front: Claude may have updated itself in the meantime.
        // And a login may have changed in Claude Code: the emails on the accounts are read again.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.windowBecameActive()
        }
        // The clocks follow the window: all of them while it is open, those the menu bar icon needs once it is closed.
        // The setup finishing is seen by the model's reload, with or without a window.
        .onAppear { model.windowAppeared() }
        .onDisappear { model.launchSettling = false; model.windowDisappeared() }
        // Until the guide is closed, the setup is not done: no menu bar icon, and closing the window quits.
        .onChange(of: showsGuide, initial: true) { _, guide in
            model.setupGuideShown = guide
            showRequestedScreen()
        }
        .onChange(of: model.requestedScreen) { showRequestedScreen() }
        // The splash's only element goes away: VoiceOver hears that the accounts are there.
        .onChange(of: model.launchPhase) { _, phase in
            if phase == .ready {
                launch.ready(at: Date())
                AccessibilityNotification.Announcement(LaunchView.readyAnnouncement).post()
            }
            showRequestedScreen()
        }
        // The menu bar switches screens (Cmd-1 to Cmd-4, Cmd-comma), once the screens are there.
        // Once the creature has landed: a new route rebuilds the app menu, never during the leap.
        .focusedSceneValue(\.brainmergeSection, model.launchPhase == .ready && !model.needsOnboarding && onboarding.finished && launch.finished ? $section : nil)
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

    /// The guided setup, or the main window once everything is in place. Both while the guide ends: it fades out over the
    /// main window (built under All set already) as the All set creature leaps into the sidebar, then goes. An unreadable list of accounts has its own
    /// screen instead of either, fading in under the launch's leap like the main window.
    var screens: some View {
        ZStack {
            if let problem = model.stateProblem {
                StateProblemView(model: model, problem: problem).launchReveal(launch, role: .main).transition(.opacity)
            } else {
                // All set builds the main window under the guide, unseen and out of reach: "Open Brainmerge" then only
                // reveals it, and nothing is laid out for the first time while the creature is in the air.
                let preparing = showsGuide && onboarding.step == .allSet && launch.finished
                if !showsGuide || preparing {
                    ZStack {
                        WarmBackground()
                        HStack(spacing: 0) {
                            sidebar.padding(12)
                            detail
                        }
                    }
                    .opacity(preparing ? 0 : 1)
                    .allowsHitTesting(!preparing)
                    .accessibilityHidden(preparing)
                    .launchReveal(launch, role: .main)
                }
                if showsGuide || launch.leavingGuide {
                    OnboardingView(model: onboarding).launchReveal(launch, role: .guide)
                }
            }
        }
        // A list of accounts put back (or read again) replaces its screen with a crossfade, never a cut. The launch's own
        // reveal handles the first appearance.
        .animation(launch.finished ? Theme.Motion.unlessReduced(Theme.Motion.out(Theme.Launch.fade), reduceMotion) : nil,
                   value: model.stateProblem == nil)
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
            // Every word and row here is an obstacle the launch's leap flies around, down to the footer.
            Text("Brainmerge").font(.system(size: 14, weight: .semibold, design: .serif)).launchObstacle("sidebar.title")
                .padding(.horizontal, 10).padding(.top, 30).padding(.bottom, 8)
            ForEach(Section.allCases) { s in navRow(s).launchObstacle("sidebar.\(s.rawValue)") }
            Text("ACCOUNTS").font(Theme.Fonts.sectionLabel).foregroundStyle(Theme.Colors.textFaint).launchObstacle("sidebar.accounts")
                .padding(.horizontal, 10).padding(.top, 16).padding(.bottom, 4)
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
                // The running dot pops in as the account opens and fades as it quits.
                HStack(spacing: 6) {
                    if let label = action.label { SidebarRowHint(text: label) }
                    if account.isRunning {
                        Circle().fill(Theme.Colors.sage).frame(width: 6, height: 6).shadow(color: Theme.Colors.sage, radius: 4)
                            .transition(reduceMotion ? .fade(true) : .asymmetric(
                                insertion: .scale(scale: 0.4).combined(with: .opacity).animation(Theme.Motion.pop),
                                removal: .opacity.animation(Theme.Motion.out(Theme.Motion.quick))))
                    }
                }
                .animation(Theme.Motion.layout(Theme.Motion.pop, reduceMotion), value: account.isRunning)
            }
            .launchObstacle("sidebar.row.\(account.id)")
            .padding(.horizontal, 10).padding(.vertical, 5)
        }
        .buttonStyle(SidebarRowStyle())
        .disabled(!action.isEnabled)
        .help(help)
        .accessibilityLabel(action.accessibilityLabel(for: account))
        .accessibilityHint(help)
    }

    /// The creature and its line: it walks while an account opens, waves when it is open, hops when the memory saves a
    /// note (and glows for exactly 4 s, redrawn once more when they are over), startles at an error, wakes and dozes.
    var creatureFooter: some View {
        TimelineView(GlowSchedule(ends: model.glowEnds)) { context in
            let state = model.creatureState(at: context.date), line = model.creatureLine(at: context.date)
            HStack(spacing: 8) {
                CreatureView(state: state, size: 32, moments: model.creatureMoments(at: context.date), walking: !model.opening.isEmpty,
                             clockStart: launch.landed)
                    .launchTarget(launch, asleep: state == .asleep)
                // A new line lifts in after the old one has gone: never two sentences printed over each other.
                SwappingText(text: line).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted).lineLimit(1)
                    .launchObstacle("sidebar.line")
            }
            .padding(.horizontal, 6).padding(.bottom, 2)
        }
    }

    func perform(_ m: UserMessage) {
        switch m.action {
        case .quit(let slug): model.quit(slug)
        case .quitOthersThenOpen(let slug): model.quitOthers(then: slug)
        case .getClaude: if let url = URL(string: "https://claude.ai/download") { NSWorkspace.shared.open(url) }
        case .openSettings: section = .settings
        case .moveToApplications: Installer.moveAndRelaunch { error in model.present(error) }
        case .installAppleTools: model.installAppleTools()
        case nil: break
        }
    }
}

/// What a window builds once, on its first body: its guide and its launch clock. Never in `RootView.init`, which SwiftUI runs
/// inside the scenes' body at every redraw of the scenes: a model read there makes the scenes depend on it, work there runs
/// again each time (the guide looks up the notes apps on the Mac), and a change there redraws the scenes, which build the
/// window again (at launch, a loop: the window never showed).
@MainActor final class WindowParts {
    private var onboarding: OnboardingModel?
    private var launch: LaunchClock?

    init(launch: LaunchClock? = nil) { self.launch = launch }

    func onboarding(for app: AppModel) -> OnboardingModel {
        if let onboarding { return onboarding }
        let made = OnboardingModel(app: app)
        onboarding = made
        return made
    }

    /// Only the first window of a process shows the splash: captures, demos and a window opened later find the load done.
    func launch(for app: AppModel) -> LaunchClock {
        if let launch { return launch }
        let made = LaunchClock(finished: app.launchPhase == .ready)
        launch = made
        return made
    }
}

/// When the sidebar's creature and its line change on their own: now, just after the glow of the last save ends, then a
/// far-future wait. SwiftUI draws a schedule's first entry at once, even a future one, and never its last one: the first is
/// the moment it (re)starts, so a save is drawn glowing and a window reopened later never shows a glow that is over.
struct GlowSchedule: TimelineSchedule {
    var ends: Date?
    func entries(from start: Date, mode: TimelineScheduleMode) -> [Date] {
        var dates = [start]
        if let ends, ends > start { dates.append(ends.addingTimeInterval(0.001)) }
        return dates + [.distantFuture]
    }
}
