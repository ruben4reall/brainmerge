import AppKit
import SwiftUI
import BrainmergeCore

public enum BrainmergeUIInfo { public static let version = BrainmergeInfo.version }

public struct RootView: View {
    public enum Section: String, CaseIterable, Identifiable {
        case accounts, memory, usage, settings
        public var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var symbol: String {
            switch self { case .accounts: "person.2"; case .memory: "brain"; case .usage: "chart.bar"; case .settings: "slider.horizontal.3" }
        }
    }

    @Bindable var model: AppModel
    @State private var onboarding: OnboardingModel
    @State private var section: Section = Section(rawValue: ProcessInfo.processInfo.environment["BRAINMERGE_SCREEN"] ?? "") ?? .accounts   // add opens accounts with the sheet

    public init(model: AppModel) {
        self.model = model
        _onboarding = State(initialValue: OnboardingModel(app: model))
    }

    public var body: some View {
        Group {
            if model.needsOnboarding || !onboarding.finished {
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
        .frame(minWidth: 960, minHeight: 640)
        .font(Theme.Fonts.body)
        .preferredColorScheme(.dark)
        .task { model.offerMoveIfNeeded(); if !model.needsOnboarding { model.startWatching() } }
        // Back in front: Claude may have updated itself in the meantime.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if !model.needsOnboarding { Task { await model.checkClaudeUpdate() } }
        }
        .onChange(of: model.needsOnboarding) { _, needs in if needs { model.stopWatching() } else { model.startWatching() } }
        .onDisappear { model.stopWatching() }
        .alert(model.message?.title ?? "", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } }), presenting: model.message) { m in
            if m.action != nil { Button(m.actionLabel ?? "OK") { perform(m) } }
            Button(m.action == .moveToApplications ? "Not now" : "OK", role: .cancel) { if m.action == .moveToApplications { Installer.remember(declined: Installer.bundlePath) } }
        } message: { m in
            Text(m.detail)
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

    func navRow(_ s: Section) -> some View {
        Button { section = s } label: {
            Label(s.title, systemImage: s.symbol)
                .font(.system(size: 13.5, weight: section == s ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(section == s ? Theme.Colors.selection : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    func accountRow(_ account: Account) -> some View {
        Button { model.open(account.id) } label: {
            HStack(spacing: 9) {
                OrbView(name: account.identity.name, tint: account.identity.tint, logo: model.logo(for: account.identity), size: 22)
                Text(account.identity.name).font(.system(size: 13)).lineLimit(1)
                Spacer()
                if account.isRunning { Circle().fill(Theme.Colors.sage).frame(width: 6, height: 6).shadow(color: Theme.Colors.sage, radius: 4) }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var creatureState: CreatureState {
        if let last = model.lastMemorySave, Date().timeIntervalSince(last) < 10 { return .glowing }
        if model.openingSlug != nil || !model.openAccounts.isEmpty { return .awake }
        return .asleep
    }

    var creatureLine: String {
        switch creatureState {
        case .glowing: return "Memory saved just now"
        case .awake:
            if model.openingSlug != nil { return "Opening…" }
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
