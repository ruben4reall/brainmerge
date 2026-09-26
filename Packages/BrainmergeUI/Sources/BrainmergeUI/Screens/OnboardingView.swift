import SwiftUI
import BrainmergeCore

public struct OnboardingView: View {
    @Bindable var model: OnboardingModel
    /// The launch lands on the welcome creature; "Open Brainmerge" leaps the All set creature into the sidebar.
    @Environment(LaunchClock.self) private var launch: LaunchClock?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var allSetFrame: CGRect?
    /// The second account's orb, from the form to the card of the account it created.
    @Namespace private var orbSpace
    public init(model: OnboardingModel) { self.model = model }

    public var body: some View {
        ZStack {
            WarmBackground(accents: [.orange, .blue])
            // Centered when the step is short, scrollable when it is taller than the window (the last step at 640 points).
            // Each page fills the height on its own, so the page leaving and the page arriving overlap without moving the
            // other: the new one slides 24 points in from the side the guide moves to while the old one leaves the other way.
            GeometryReader { proxy in
                ScrollView(.vertical) {
                    ZStack(alignment: .top) {
                        page
                            .frame(maxWidth: 560)
                            .padding(.horizontal, 40).padding(.top, 28).padding(.bottom, 52)
                            .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                            .id(model.step)
                            .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(StepSlide(model: model)))
                    }
                    .animation(reduceMotion ? Self.pageFade : Self.pageSlide, value: model.step)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            // The progress dots stay at the same place whatever the step's height.
            VStack { Spacer(); dots.padding(.bottom, 26) }
            errorLayer
        }
        .task { await model.detect() }
    }

    @ViewBuilder var page: some View {
        switch model.step {
        case .welcome: welcome
        case .howItWorks: howItWorks
        case .brainLocation: location
        case .adopt: adopt
        case .secondAccount: secondAccount
        case .allSet: allSet
        case .git: gitStep
        }
    }

    /// A step to the next page: a spring with no bounce; with Reduce Motion, a crossfade.
    static var pageSlide: Animation { .spring(response: 0.4 * Theme.Motion.slow, dampingFraction: 0.9) }
    static var pageFade: Animation { .linear(duration: 0.18 * Theme.Motion.slow) }
    /// The progress dots: the current one widens into a capsule as its neighbors make room.
    static var dotSpring: Animation { .spring(response: 0.35 * Theme.Motion.slow, dampingFraction: 0.8) }

    var welcome: some View {
        VStack(spacing: 20) {
            CreatureView(state: .awake, size: 64, profile: .stage, clockStart: launch?.landed)
                .launchTarget(launch, asleep: false)
            if let missing = model.missingBrainPath {
                Text("Your memory folder is missing.").font(Theme.Fonts.onboardingTitle).multilineTextAlignment(.center)
                Text("It was at \(missing). Choose where it lives now, or create it again. Your accounts will be attached to it.")
                    .font(.system(size: 16.5)).foregroundStyle(Theme.Colors.textMuted).multilineTextAlignment(.center)
                Button("Choose the folder") { model.next() }.buttonStyle(.glassProminent).tint(Theme.Colors.button).controlSize(.large)
            } else {
                Text("Every Claude account, side by side").font(Theme.Fonts.onboardingTitle).multilineTextAlignment(.center)
                Text("The Claude app knows one account at a time: with two, you log out and back in all day, and what one learns is lost to the other. Brainmerge opens each account in its own window and gives them one memory of your projects, or one each. Claude itself stays exactly as it is.")
                    .font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textMuted).multilineTextAlignment(.center)
                Button("Continue") { model.next() }.buttonStyle(.glassProminent).tint(Theme.Colors.button).controlSize(.large)
            }
            Text("Works with Claude. Not made by Anthropic.").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint)
        }
    }

    var howItWorks: some View {
        VStack(spacing: 18) {
            Text("How it works").font(Theme.Fonts.onboardingTitle)
            // 1:1 and never scaled: the creature's 3 point cells stay whole. The column is 520 points wide.
            HowItWorksView().frame(width: HowItWorksScene.size.width, height: HowItWorksScene.size.height)
            VStack(alignment: .leading, spacing: 8) {
                step(1, "Each account is the official Claude app, opened with its own settings and login.")
                step(2, "Claude Code writes notes about your projects. Brainmerge keeps them in one folder, the memory.")
                step(3, "Every account reads the same notes: what one learns, all of them know.")
            }
            .frame(maxWidth: 520)
            navigation { Button("Back") { model.back() }.buttonStyle(.glass); Button("Continue") { model.next() }.buttonStyle(.glassProminent).tint(Theme.Colors.button) }
        }
    }

    func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.onAccent).frame(width: 20, height: 20).background(Theme.Colors.accent, in: Circle())
            Text(text).font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textMuted).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Only on a Mac without Apple's Command Line Tools: git would otherwise pop Apple's dialog at every save.
    var gitStep: some View {
        VStack(spacing: 20) {
            Text("One free Apple tool first").font(Theme.Fonts.onboardingTitle).multilineTextAlignment(.center)
            Text("Brainmerge keeps your memory's history with git, which comes with Apple's Command Line Tools.")
                .font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textMuted).multilineTextAlignment(.center)
            navigation {
                Button("Back") { model.back() }.buttonStyle(.glass)
                Button("Check again") { Task { await model.checkGit() } }.buttonStyle(.glass)
                Button("Install Apple's tools") { model.installAppleTools() }.buttonStyle(.glassProminent).tint(Theme.Colors.button)
            }
            Text("Opens Apple's installer. The download comes from Apple, not from Brainmerge.")
                .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint).multilineTextAlignment(.center)
        }
        // Checks again every 5 seconds while the step shows: the installer takes a few minutes.
        .task {
            while !Task.isCancelled, model.step == .git {
                try? await Task.sleep(for: .seconds(5))
                await model.checkGit()
            }
        }
    }

    var location: some View {
        VStack(spacing: 20) {
            Text("Where the memory lives").font(Theme.Fonts.onboardingTitle).multilineTextAlignment(.center)
            Text("A folder of plain notes on your Mac.").font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textMuted)
            HStack(spacing: 12) {
                choiceCard(title: "A new folder", detail: "“Brain”, in your home folder. Recommended.", selected: model.choice == .newFolder) { model.choice = .newFolder }
                choiceCard(title: "A folder you already have", detail: "Obsidian, Notes, anything. Nothing gets renamed.", selected: { if case .existing = model.choice { return true }; return false }()) { pickFolder() }
            }
            Toggle("Write the notes in French", isOn: Binding(get: { model.language == .fr }, set: { model.language = $0 ? .fr : .en })).toggleStyle(.switch).tint(Theme.Colors.accent)
            VStack(spacing: 8) {
                Text("Read and edit it with").font(Theme.Fonts.sectionLabel).foregroundStyle(Theme.Colors.textFaint)
                NotesAppPicker(selection: $model.notesApp)
                Text("The notes are plain Markdown files: any app that reads files works. You can change this later in Settings.")
                    .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted).multilineTextAlignment(.center)
            }
            navigation { Button("Back") { model.back() }.buttonStyle(.glass); Button("Continue") { create() }.buttonStyle(.glassProminent).tint(Theme.Colors.button) }
        }
    }

    var adopt: some View {
        VStack(spacing: 20) {
            Text("Your first account").font(Theme.Fonts.onboardingTitle)
            Text("The Claude already installed becomes your first account, with everything it remembers. Give it a name.")
                .font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textMuted).multilineTextAlignment(.center)
            GlassCard {
                HStack(spacing: 16) {
                    OrbView(name: model.primaryName, tint: .orange, size: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Name", text: $model.primaryName).textFieldStyle(.plain).font(.system(size: 16, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Theme.Colors.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Text("Your current Claude\(model.claude.map { " \($0.version)" } ?? "") · \(model.projectCount) projects remembered").foregroundStyle(Theme.Colors.textMuted)
                    }
                }
                .padding(18)
            }
            navigation { Button("Back") { model.back() }.buttonStyle(.glass); Button("Continue") { finish() }.buttonStyle(.glassProminent).tint(Theme.Colors.button) }
            Text("Brainmerge also links its command line at ~/.local/bin/brainmerge: the memory hooks need it.")
                .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint).multilineTextAlignment(.center)
        }
    }

    var secondAccount: some View {
        VStack(spacing: 18) {
            Text("Add a second account").font(Theme.Fonts.onboardingTitle)
            Text("Another Claude account, for work or a client? Give it a name and a color. It opens in its own Claude window where you log in as usual. You can also do this later from the Accounts screen.")
                .font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textMuted).multilineTextAlignment(.center)
            if let added = model.addedAccount {
                GlassCard {
                    HStack(spacing: 14) {
                        OrbView(name: added.identity.name, tint: added.identity.tint, size: 40).secondOrb(orbSpace, moves: !reduceMotion)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(added.identity.name).font(Theme.Fonts.cardName)
                            if !added.needsLogin {
                                Text(added.isRunning ? "Connected. Continue whenever you like." : "Connected. Open it whenever you like.").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted)
                            } else if added.isRunning {
                                Text("Open. Log in in its Claude window (Google or email, like always): this card turns to Connected on its own.").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted)
                            } else if model.othersOpen.isEmpty {
                                Text("Ready. Open it to log in.").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted)
                            } else {
                                Text("Ready. Claude is open for \(model.othersOpen.map(\.identity.name).joined(separator: ", ")): it must be closed first, or the login would land in that window.").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted)
                            }
                        }
                        Spacer()
                        // Each piece comes and goes on its own: the check draws itself on, the words fade.
                        HStack(spacing: 6) {
                            if !added.needsLogin {
                                ConnectedCheck()
                                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(SymbolEffectTransition(effect: .drawOn, options: .default)))
                                Text("Connected").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted).transition(.opacity)
                            } else if added.isRunning {
                                Circle().fill(Theme.Colors.sage).frame(width: 7, height: 7).transition(.opacity)
                                Text("Open").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted).transition(.opacity)
                            } else {
                                Button(model.othersOpen.isEmpty ? "Open \(added.identity.name)" : "Quit Claude and open \(added.identity.name)") { model.openAddedAccount() }.buttonStyle(.glassProminent).tint(Theme.Colors.button)
                                    .transition(.opacity)
                            }
                        }
                        .animation(reduceMotion ? Theme.Motion.reduced : Theme.Motion.pop, value: added.needsLogin)
                    }
                    .padding(16)
                }
                // The card's height follows its sentence as the account opens, then connects.
                .animation(reduceMotion ? Theme.Motion.reduced : Theme.Motion.settle, value: added.isRunning)
                .animation(reduceMotion ? Theme.Motion.reduced : Theme.Motion.settle, value: added.needsLogin)
                navigation { Button("Back") { model.back() }.buttonStyle(.glass); Button("Continue") { model.next() }.buttonStyle(.glassProminent).tint(Theme.Colors.button) }
            } else {
                GlassCard {
                    VStack(spacing: 12) {
                        HStack(spacing: 14) {
                            OrbView(name: model.secondAccount.name, tint: model.secondAccount.tint, size: 44).secondOrb(orbSpace, moves: !reduceMotion)
                            VStack(spacing: 8) {
                                TextField("Name (Work, Studio, a client…)", text: $model.secondAccount.name).textFieldStyle(.plain).font(.system(size: 15))
                                    .padding(8).background(Theme.Colors.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                TextField("Note (optional)", text: $model.secondAccount.note).textFieldStyle(.plain).font(Theme.Fonts.body)
                                    .padding(8).background(Theme.Colors.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                        HStack(spacing: 8) {
                            ForEach(Theme.pickableTints, id: \.self) { t in
                                Button { model.secondAccount.tint = t } label: {
                                    Circle().fill(Theme.color(for: t)).frame(width: 22, height: 22)
                                        .overlay(Circle().strokeBorder(Theme.Colors.text, lineWidth: model.secondAccount.tint == t ? 2 : 0))
                                }.buttonStyle(.plain)
                            }
                        }
                        HStack(spacing: 12) {
                            choiceCard(title: "Shared memory", detail: "Your first account knows what it learns.", selected: model.secondAccount.memory == .shared) { model.secondAccount.memory = .shared }
                            choiceCard(title: "Its own memory", detail: "A separate folder of notes.", selected: model.secondAccount.memory == .own) { model.secondAccount.memory = .own }
                        }
                    }
                    .padding(16)
                }
                if let working = model.app.working { Text(working).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted) }
                navigation {
                    Button("Back") { model.back() }.buttonStyle(.glass)
                    Button("Skip for now") { model.next() }.buttonStyle(.glass)
                    Button("Add account") { Task { if await model.addSecondAccount() { model.error = nil } else { model.error = model.app.message; model.app.message = nil } } }
                        .buttonStyle(.glassProminent).tint(Theme.Colors.button).disabled(model.app.working != nil)
                }
                Text("When it opens, macOS asks once to allow “Claude Safe Storage” (click Always Allow) and may ask to allow access to your Documents folder (click Allow).")
                    .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint).multilineTextAlignment(.center)
            }
        }
        // The form gives way to the account it created: its orb moves into the card, the step settles to its new height.
        .animation(reduceMotion ? Theme.Motion.reduced : Theme.Motion.settle, value: model.addedSlug)
    }

    var allSet: some View {
        VStack(spacing: 14) {
            // A hop with sparkles, 350 ms after the step appears: the setup is done.
            CreatureView(state: .awake, size: 48, profile: .stage, events: [CreatureStamp(.memorySaved, at: 0.35)])
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(LaunchClock.space)) } action: { allSetFrame = $0 }
                .opacity(launch?.hidesSource == true ? 0 : 1)
            Text("All set").font(Theme.Fonts.onboardingTitle)
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    check(model.app.claude != nil, model.app.claude.map { "Claude app \($0.version)" } ?? "Claude app not found")
                    check(model.app.brain != nil, "Memory folder: \(model.app.brain.map { Self.tilde($0.root.path, home: model.app.paths.home.path) } ?? "not chosen") · opens with \(NotesApps.target(for: model.app.notesApp, installed: NotesApps.installed()).label.replacingOccurrences(of: "Open ", with: ""))\(model.app.brains.count > 1 ? " · \(model.app.brains.count) memories" : "")")
                    check(!model.app.accounts.isEmpty, "\(model.app.accounts.count) account\(model.app.accounts.count > 1 ? "s" : ""): \(model.app.accounts.map(\.identity.name).joined(separator: ", "))")
                    check(model.gitFound, model.gitFound ? "git: Found" : "git: Not found")
                    check(model.claudeCodeFound, model.claudeCodeFound ? "Claude Code: Found"
                          : "Claude Code: Not found: your accounts still work in the Claude app. Install Claude Code to use them in a terminal.")
                    check(model.app.commandLineInstalled, model.app.commandLineInstalled ? "Command line linked at ~/.local/bin/brainmerge" : "Command line not linked (Settings)")
                }
                .padding(14)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("WHAT HAPPENS NEXT").font(Theme.Fonts.sectionLabel).foregroundStyle(Theme.Colors.textFaint)
                step(1, "Open an account from the Accounts screen, or from its app in ~/Applications/Brainmerge.")
                step(2, "Work as usual: what Claude Code learns about a project goes into the memory, for every account on it.")
                step(3, "The Memory screen shows who remembered what; the Usage screen what each account spent.")
            }
            .frame(maxWidth: 520)
            VStack(alignment: .leading, spacing: 6) {
                Text("GO FURTHER").font(Theme.Fonts.sectionLabel).foregroundStyle(Theme.Colors.textFaint)
                tip("Keep the memory tidy: one fact per note, a short index. Claude reads it at every start.")
                tip("For big code bases, a local code graph or index saves tokens: Claude asks it where things are.")
                tip("Give a work or client account its own memory: what it learns stays there.")
            }
            .frame(maxWidth: 520)
            Button("Open Brainmerge") {
                launch?.leave(from: allSetFrame, reduceMotion: reduceMotion, at: Date())
                model.complete()
            }.buttonStyle(.glassProminent).tint(Theme.Colors.button).controlSize(.large)
            // A quiet link under the last button, never a prompt of its own.
            Link(MenuBarMenu.starTitle, destination: BrainmergeLinks.repository).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted)
        }
    }

    /// The step's buttons: one row, the same size everywhere.
    func navigation<Content: View>(@ViewBuilder _ buttons: () -> Content) -> some View {
        HStack(spacing: 10) { buttons() }.controlSize(.large)
    }

    static func tilde(_ path: String, home: String) -> String { path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path }

    func tip(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb").foregroundStyle(Theme.Colors.accent).font(.system(size: 12)).frame(width: 20)
            Text(text).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted).fixedSize(horizontal: false, vertical: true)
        }
    }

    func check(_ ok: Bool, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle").foregroundStyle(ok ? Theme.Colors.sage : Theme.Colors.textFaint)
            Text(text).font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textMuted)
        }
    }

    /// The steps behind in the accent, the current one an 18 point capsule, the ones ahead faint. With Reduce Motion the
    /// width changes at once and only the color fades.
    var dots: some View {
        HStack(spacing: 8) {
            ForEach(model.steps, id: \.rawValue) { s in
                let dot = model.dot(for: s)
                Capsule()
                    .animation(reduceMotion ? Theme.Motion.reduced : Self.dotSpring) {
                        $0.foregroundStyle(dot == .future ? Theme.Colors.surfaceLine : Theme.Colors.accent)
                    }
                    .frame(width: dot.width, height: dot.height)
            }
        }
        .animation(reduceMotion ? nil : Self.dotSpring, value: model.step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(model.step.rawValue + 1) of \(OnboardingModel.Step.allCases.count)")
    }

    /// The error banner rises into place and sinks away a little faster; a new message over an old one crossfades.
    var errorLayer: some View {
        VStack {
            Spacer()
            if let error = model.error {
                ZStack { errorBanner(error).id(error.id).transition(.opacity) }
                    .animation(reduceMotion ? Theme.Motion.reduced : Theme.Motion.out(Theme.Motion.quick), value: error.id)
                    .transition(bannerTransition)
            }
        }
        .padding(24).padding(.bottom, 28)
        .animation(reduceMotion ? Theme.Motion.reduced : Theme.Motion.out(0.24), value: model.error == nil)
    }

    var bannerTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(insertion: .opacity.combined(with: .offset(y: 16)),
                           removal: AnyTransition.opacity.combined(with: .offset(y: 8)).animation(Theme.Motion.out(0.16)))
    }

    func choiceCard(title: String, detail: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(Theme.Fonts.cardName)
                Text(detail).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted).multilineTextAlignment(.leading)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? Theme.Colors.accent : Theme.Colors.surfaceLine, lineWidth: selected ? 2 : 1))
    }

    func errorBanner(_ m: UserMessage) -> some View {
        GlassCard(radius: 14) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) { Text(m.title).font(.headline); Text(m.detail).foregroundStyle(Theme.Colors.textMuted) }
                Spacer()
                if m.action == .getClaude { Button(m.actionLabel ?? "Get Claude") { if let url = URL(string: "https://claude.ai/download") { NSWorkspace.shared.open(url) } }.buttonStyle(.glassProminent).tint(Theme.Colors.button) }
                if m.action == .installAppleTools { Button(m.actionLabel ?? "Install Apple's tools") { model.installAppleTools() }.buttonStyle(.glass) }
                Button("Dismiss") { model.error = nil }.buttonStyle(.glass)
            }
            .padding(14)
        }
    }

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = "Use this folder"
        if panel.runModal() == .OK, let url = panel.url { model.choice = .existing(url) }
    }

    /// "Continue": the choice is remembered, nothing is written yet. Except when the brain has disappeared: it is recreated right away and accounts reattached.
    func create() {
        if model.missingBrainPath != nil { do { try model.createBrain() } catch { model.error = AppModel.sentence(for: error) } }
        else { model.next() }
    }
    func finish() { do { try model.finish(); model.next() } catch { model.error = AppModel.sentence(for: error) } }
}

/// A page of the guide slides 24 points along the way the guide moves and fades. The direction is read from the model
/// when the transition runs, not when the page was last drawn: the page leaving on "Back" goes right even though it came
/// in going on.
struct StepSlide: Transition {
    let model: OnboardingModel
    static let distance: CGFloat = 24

    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .offset(x: Self.shift(phase, direction: model.direction))
            .opacity(phase.isIdentity ? 1 : 0)
    }

    /// The new page starts on the side the guide moves to (willAppear is -1), the old one leaves the other way (didDisappear is 1).
    static func shift(_ phase: TransitionPhase, direction: Int) -> CGFloat { -phase.value * CGFloat(direction) * distance }
}

/// The "Connected" check of the guide's second account: it draws itself on, and one sage ring spreads from it once.
struct ConnectedCheck: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spread = false

    var body: some View {
        let rings = !reduceMotion && !Theme.Motion.isCapture
        Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(Theme.Colors.sage)
            .background {
                Circle().stroke(Theme.Colors.sage, lineWidth: 1.5)
                    .padding(spread ? -7 : 0)
                    .opacity(rings && !spread ? 0.8 : 0)
            }
            .onAppear {
                guard rings else { return }
                withAnimation(Theme.Motion.out(0.6)) { spread = true }
            }
    }
}

extension View {
    /// The second account's orb, matched from the form to the card (never with Reduce Motion: it would travel).
    @ViewBuilder func secondOrb(_ space: Namespace.ID, moves: Bool) -> some View {
        if moves { matchedGeometryEffect(id: "secondOrb", in: space) } else { self }
    }
}
