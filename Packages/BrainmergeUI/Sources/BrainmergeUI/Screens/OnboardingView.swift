import SwiftUI
import BrainmergeCore

public struct OnboardingView: View {
    @Bindable var model: OnboardingModel
    /// The launch lands on the welcome creature; "Open Brainmerge" leaps the All set creature into the sidebar.
    @Environment(LaunchClock.self) private var launch: LaunchClock?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// When All set appeared: its checks come in from there.
    @State private var allSetShown: Date?
    public init(model: OnboardingModel) { self.model = model }

    public var body: some View {
        ZStack {
            WarmBackground()
            // Centered when the step is short. Every step fits the smallest window (960 by 640) whole, its buttons included;
            // the scroll view stays for words longer than planned (a long name, many accounts), which then scroll.
            // Each page fills the height on its own and shares one column with the page it replaces: the old one fades where
            // it is (the button just clicked never moves), then the new one slides 24 points in from the side the guide moves
            // to (see `PageSwap`).
            VStack(spacing: 0) {
                GeometryReader { proxy in
                    ScrollView(.vertical) {
                        ZStack(alignment: .top) {
                            laidOutPage
                                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                                .id(model.step)
                                .transition(reduceMotion ? AnyTransition.opacity : PageSwap.transition(model))
                        }
                        .animation(reduceMotion ? Self.pageFade : Self.pageSlide, value: model.step)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                // The progress dots stay at the same place whatever the step's height, under the pages, never over them.
                dots.padding(.top, Self.dotsTop).padding(.bottom, Self.dotsBottom)
            }
            errorLayer
        }
        .task { await model.detect() }
    }

    /// The step in its column, with the room around it: what the window lays out above the dots.
    var laidOutPage: some View {
        page
            .frame(maxWidth: Self.column(model.step))
            .padding(.horizontal, 40).padding(.top, Self.pageTop).padding(.bottom, Self.pageBottom)
    }
    /// The steps' column: 560 points, All set's wider so its lines stay whole.
    static func column(_ step: OnboardingModel.Step) -> CGFloat { step == .allSet ? 640 : 560 }
    static let pageTop: CGFloat = 20, pageBottom: CGFloat = 12
    /// All set's two lists, under its card.
    static let allSetLists: CGFloat = 600
    static let dotsTop: CGFloat = 14, dotsBottom: CGFloat = 26
    /// The room the dots take under the pages.
    static var dotsRoom: CGFloat { dotsTop + OnboardingModel.Dot.current.height + dotsBottom }

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
    static var pageSlide: Animation { .spring(response: PageSwap.response * Theme.Motion.slow, dampingFraction: PageSwap.damping) }
    static var pageFade: Animation { .linear(duration: 0.18 * Theme.Motion.slow) }
    /// The progress dots: the current one widens into a capsule as its neighbors make room.
    static var dotSpring: Animation { .spring(response: 0.35 * Theme.Motion.slow, dampingFraction: 0.8) }
    static let dotColor = 0.12

    /// On a first run the launch's creature leaps up onto this one: the words under it come in once it has landed, one
    /// after the other, so it never flies over them.
    ///
    /// Shown without that landing (a demo, a capture of the guide, a later window), it greets on its own, once: the creature
    /// wakes, then the words rise in one after the other (`WelcomeEntrance`).
    var welcome: some View {
        let greeting = WelcomeEntrance.plays(launch: launch, reduceMotion: reduceMotion, capture: Theme.Motion.isCapture)
        // Waiting unseen until the welcome appears, then from that moment; once over, never again.
        let since: Date? = greeting ? (model.greetedAt ?? .distantFuture) : nil
        let fresh = greeting && (model.greetedAt.map { Date().timeIntervalSince($0) < 1 } ?? true)
        return VStack(spacing: 20) {
            CreatureView(state: .awake, size: 64, profile: .stage, events: fresh ? [CreatureStamp(.wake, at: WelcomeEntrance.wake)] : [],
                         clockStart: launch?.landed)
                .launchTarget(launch, asleep: false)
            if let missing = model.missingBrainPath {
                Text("Your memory folder is missing.").font(Theme.Fonts.onboardingTitle).multilineTextAlignment(.center).welcomeWord(0, since: since)
                Text("It was at \(missing). Choose where it lives now, or create it again. Your accounts will be attached to it.")
                    .font(.system(size: 16.5)).foregroundStyle(Theme.Colors.textMuted).multilineTextAlignment(.center).welcomeWord(1, since: since)
                Button("Choose the folder") { model.next() }.buttonStyle(.glassProminent).tint(Theme.Colors.button).controlSize(.large).welcomeWord(2, since: since)
            } else {
                Text("Every Claude account, side by side").font(Theme.Fonts.onboardingTitle).multilineTextAlignment(.center).welcomeWord(0, since: since)
                Text("The Claude app knows one account at a time: with two, you log out and back in all day, and what one learns is lost to the other. Brainmerge opens each account in its own window and gives them one memory of your projects, or one each. Claude itself stays exactly as it is.")
                    .font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textMuted).multilineTextAlignment(.center).welcomeWord(1, since: since)
                Button("Continue") { model.next() }.buttonStyle(.glassProminent).tint(Theme.Colors.button).controlSize(.large).welcomeWord(2, since: since)
            }
            Text("Works with Claude. Not made by Anthropic.").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint).welcomeWord(3, since: since)
        }
        .onAppear { if greeting { model.greet(at: Date()) } }
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
                Button("Check again") { Task { await model.checkGit(asked: true) } }.buttonStyle(.glass)
                Button("Install Apple's tools") { model.installAppleTools() }.buttonStyle(.glassProminent).tint(Theme.Colors.button)
            }
            // A "Check again" that finds nothing says so, and shakes the line when asked again.
            ProblemLine(problem: model.gitNote, color: Theme.Colors.textMuted).multilineTextAlignment(.center)
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
                NotesAppPicker(selection: $model.notesApp, found: model.notesApps)
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
        let added = model.addedAccount
        return VStack(spacing: 18) {
            Text("Add a second account").font(Theme.Fonts.onboardingTitle)
            Text("Another Claude account, for work or a client? Give it a name and a color. It opens in its own Claude window where you log in as usual. You can also do this later from the Accounts screen.")
                .font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textMuted).multilineTextAlignment(.center)
            // One card for the form and for the account it made, its orb staying in place: the form's words fade out while
            // the card holds its height, the card settles to its new height, then the account's words fade in. Nothing
            // draws outside the card. With Reduce Motion the step takes its new height at once and the two fade.
            GlassCard {
                VStack(spacing: 12) {
                    HStack(spacing: 14) {
                        OrbView(name: added?.identity.name ?? model.secondAccount.name, tint: added?.identity.tint ?? model.secondAccount.tint, size: 44)
                        ZStack(alignment: .leading) {
                            if let added { addedDetails(added).transition(SecondAccountSwap.incoming(reduceMotion)) }
                            else { nameFields.transition(SecondAccountSwap.outgoing(reduceMotion)) }
                        }
                    }
                    if added == nil {
                        VStack(spacing: 12) {
                            HStack(spacing: 8) {
                                ForEach(Theme.pickableTints, id: \.self) { t in
                                    TintSwatch(tint: t, selected: model.secondAccount.tint == t, size: 22, ring: 2) { model.secondAccount.tint = t }
                                }
                            }
                            HStack(spacing: 12) {
                                choiceCard(title: "Shared memory", detail: "Your first account knows what it learns.", selected: model.secondAccount.memory == .shared) { model.secondAccount.memory = .shared }
                                choiceCard(title: "Its own memory", detail: "A separate folder of notes.", selected: model.secondAccount.memory == .own) { model.secondAccount.memory = .own }
                            }
                        }
                        .transition(SecondAccountSwap.outgoing(reduceMotion))
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            // Its room is kept: the step never jumps as work starts and ends.
            WorkingLine(text: model.app.working, holdsPlace: true)
            // One row for both: only its buttons change. "Add account" dims while work runs, in step with the line above.
            navigation {
                Button("Back") { model.back() }.buttonStyle(.glass)
                if added == nil {
                    Button("Skip for now") { model.next() }.buttonStyle(.glass).transition(SecondAccountSwap.outgoing(reduceMotion))
                    Button("Add account") { Task { if await model.addSecondAccount() { model.error = nil } else { model.error = model.app.message; model.app.message = nil } } }
                        .buttonStyle(.glassProminent).tint(Theme.Colors.button).disabled(model.app.working != nil)
                        .transition(SecondAccountSwap.outgoing(reduceMotion))
                } else {
                    Button("Continue") { model.next() }.buttonStyle(.glassProminent).tint(Theme.Colors.button)
                        .transition(SecondAccountSwap.incoming(reduceMotion))
                }
            }
            .animation(Theme.Motion.unlessReduced(Theme.Motion.out(Theme.Motion.quick), reduceMotion), value: model.app.working == nil)
            if added == nil {
                Text("When it opens, macOS asks once to allow “Claude Safe Storage” (click Always Allow) and may ask to allow access to your Documents folder (click Allow).")
                    .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textFaint).multilineTextAlignment(.center)
                    .transition(SecondAccountSwap.outgoing(reduceMotion))
            }
        }
        // The form gives way to the account it created: the height waits for the form's words to go, then settles.
        .animation(Theme.Motion.layout(Theme.Motion.settle.delay(SecondAccountSwap.hold * Theme.Motion.slow), reduceMotion), value: model.addedSlug)
    }

    var nameFields: some View {
        VStack(spacing: 8) {
            TextField("Name (Work, Studio, a client…)", text: $model.secondAccount.name).textFieldStyle(.plain).font(.system(size: 15))
                .padding(8).background(Theme.Colors.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            TextField("Note (optional)", text: $model.secondAccount.note).textFieldStyle(.plain).font(Theme.Fonts.body)
                .padding(8).background(Theme.Colors.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    /// The account the step made: its name with what it is now (Open, then Connected) on the right, the sentence that says
    /// what to do next, whole, and the button that opens it on a row of its own: the check never draws over the button it
    /// replaces, and a sentence that goes gives way before the next one comes (`SwappingText`).
    func addedDetails(_ added: Account) -> some View {
        let card = AddedCard.of(name: added.identity.name, needsLogin: added.needsLogin, isRunning: added.isRunning,
                                opened: model.openedAdded, othersOpen: model.othersOpen.map(\.identity.name))
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(added.identity.name).font(Theme.Fonts.cardName).lineLimit(1)
                Spacer(minLength: 8)
                // Each piece comes and goes on its own: the check draws itself on, the words swap.
                HStack(spacing: 6) {
                    if !added.needsLogin {
                        ConnectedCheck(rings: { model.ringsForConnection(of: added.id) })
                            .transition(reduceMotion ? .fade(true) : AnyTransition(SymbolEffectTransition(effect: .drawOn, options: .default)))
                        Text("Connected").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted).transition(SwapText.transition(reduceMotion))
                    } else if added.isRunning {
                        Circle().fill(Theme.Colors.sage).frame(width: 7, height: 7).transition(SwapText.transition(reduceMotion))
                        Text("Open").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted).transition(SwapText.transition(reduceMotion))
                    }
                }
                .animation(Theme.Motion.layout(Theme.Motion.pop, reduceMotion), value: added.needsLogin)
                .animation(Theme.Motion.layout(Theme.Motion.pop, reduceMotion), value: added.isRunning)
            }
            SwappingText(text: card.sentence)
                .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            // Gone from the click: the waiting line under the card says what runs (quitting the others, opening).
            if let label = card.button {
                Button(label) { model.openAddedAccount() }
                    .buttonStyle(.glassProminent).tint(Theme.Colors.button)
                    .padding(.top, 4)
                    .transition(SwapText.transition(reduceMotion))
            }
        }
        // The card's height follows its sentence and its button as the account opens, then connects: the old words go
        // first, the height settles, the new ones come in.
        .animation(Theme.Motion.layout(Theme.Motion.settle, reduceMotion), value: card)
    }

    /// The added account's card: where it stands, what it says to do next, and its button while there is one to click.
    /// Once "Open" (or "Quit Claude and open") is clicked, it never asks for it again: the account opens, then Claude's
    /// window asks for the login.
    struct AddedCard: Equatable {
        enum Phase: Equatable { case ready, opening, open, connected }
        let phase: Phase
        let sentence: String
        let button: String?

        static func of(name: String, needsLogin: Bool, isRunning: Bool, opened: Bool, othersOpen: [String]) -> AddedCard {
            if !needsLogin {
                return AddedCard(phase: .connected, sentence: isRunning ? "Connected. Continue whenever you like." : "Connected. Open it whenever you like.", button: nil)
            }
            if isRunning {
                return AddedCard(phase: .open, sentence: "Open. Log in in its Claude window (Google or email, like always): this card turns to Connected on its own.", button: nil)
            }
            if opened {
                return AddedCard(phase: .opening, sentence: "Opening. Log in in its Claude window as it comes up (Google or email, like always): this card turns to Connected on its own.", button: nil)
            }
            if othersOpen.isEmpty { return AddedCard(phase: .ready, sentence: "Ready. Open it to log in.", button: "Open \(name)") }
            return AddedCard(phase: .ready, sentence: "Ready. Claude is open for \(othersOpen.joined(separator: ", ")): it must be closed first, or the login would land in that window.",
                             button: "Quit Claude and open \(name)")
        }
    }

    /// Once the page has landed, the checks come in one by one down the list, then the creature by the way in hops with
    /// its sparkles (`AllSetBeat`): the eye travels down the setup to it.
    ///
    /// It fits the window at its default size whole, "Open Brainmerge" and the link under it included: its column is wider
    /// than the other steps' (its lines stay whole) and its blocks sit closer.
    var allSet: some View {
        let target = NotesApps.target(for: model.app.notesApp, installed: model.notesApps?.apps ?? [])
        return VStack(spacing: 10) {
            Text("All set").font(Theme.Fonts.onboardingTitle)
            GlassCard {
                VStack(alignment: .leading, spacing: 6) {
                    check(0, model.app.claude != nil, model.app.claude.map { "Claude app \($0.version)" } ?? "Claude app not found")
                    check(1, model.app.brain != nil, "Memory folder: \(model.app.brain.map { Self.tilde($0.root.path, home: model.app.paths.home.path) } ?? "not chosen") · \(Self.opensIn(target))\(model.app.brains.count > 1 ? " · \(model.app.brains.count) memories" : "")")
                    check(2, !model.app.accounts.isEmpty, "\(model.app.accounts.count) account\(model.app.accounts.count > 1 ? "s" : ""): \(model.app.accounts.map(\.identity.name).joined(separator: ", "))")
                    check(3, model.gitFound, model.gitFound ? "git: Found" : "git: Not found")
                    check(4, model.claudeCodeFound, model.claudeCodeFound ? "Claude Code: Found"
                          : "Claude Code: Not found: your accounts still work in the Claude app. Install Claude Code to use them in a terminal.")
                    check(5, model.app.commandLineInstalled, model.app.commandLineInstalled ? "Command line linked at ~/.local/bin/brainmerge" : "Command line not linked (Settings)")
                }
                .padding(14)
            }
            .onAppear { allSetShown = Date() }
            VStack(alignment: .leading, spacing: 6) {
                Text("WHAT HAPPENS NEXT").font(Theme.Fonts.sectionLabel).foregroundStyle(Theme.Colors.textFaint)
                step(1, "Open an account from the Accounts screen, or from its app in ~/Applications/Brainmerge.")
                step(2, "Work as usual: what Claude Code learns about a project goes into the memory, for every account on it.")
                step(3, "The Memory screen shows who remembered what; the Usage screen what each account spent.")
            }
            // Both lists start at one left edge, under each other.
            .frame(maxWidth: Self.allSetLists, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                Text("GO FURTHER").font(Theme.Fonts.sectionLabel).foregroundStyle(Theme.Colors.textFaint)
                tip("Keep the memory tidy: one fact per note, a short index. Claude reads it at every start.")
                tip("For big code bases, a local code graph or index saves tokens: Claude asks it where things are.")
                tip("Give a work or client account its own memory: what it learns stays there.")
            }
            .frame(maxWidth: Self.allSetLists, alignment: .leading)
            // The creature waits beside the way in: it hops with sparkles once the checks are in (the setup is done), and
            // "Open Brainmerge" sends it leaping into the sidebar from here, low in the window, where no words or rows lie in
            // its way. The button stays centered: an empty spot as wide as the creature balances it. The row keeps its
            // sparkles clear of the last tip above.
            HStack(alignment: .bottom, spacing: 16) {
                CreatureView(state: .awake, size: 48, profile: .stage, events: [CreatureStamp(.memorySaved, at: AllSetBeat.hop)])
                    // Kept on the clock, outside observation: a scroll never redraws the guide for it.
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(LaunchClock.space)) } action: { launch?.allSetFrame = $0 }
                    .opacity(launch?.hidesSource == true ? 0 : 1)
                Button("Open Brainmerge") {
                    launch?.leave(from: launch?.allSetFrame, reduceMotion: reduceMotion, at: Date())
                    // The icon and the app menu wait for the landing, as at launch.
                    if launch?.finished == false { model.app.launchSettling = true }
                    model.complete()
                }.buttonStyle(.glassProminent).tint(Theme.Colors.button).controlSize(.large)
                Color.clear.frame(width: 48, height: 1).accessibilityHidden(true)
            }
            .padding(.top, 14)
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

    func check(_ index: Int, _ ok: Bool, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            BeatView(start: allSetShown, duration: AllSetBeat.end) { elapsed in
                let look = AllSetBeat.check(index, elapsed: elapsed ?? (allSetShown == nil && !Theme.Motion.isCapture ? 0 : nil), reduceMotion: reduceMotion)
                Image(systemName: ok ? "checkmark.circle.fill" : "circle").foregroundStyle(ok ? Theme.Colors.sage : Theme.Colors.textFaint)
                    .scaleEffect(look.scale).opacity(look.opacity)
            }
            Text(text).font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textMuted)
        }
    }

    /// What opens the memory, in plain words: "opens in Obsidian", "opens in Finder".
    static func opensIn(_ target: NotesTarget) -> String {
        switch target {
        case .folder: return "opens in Finder"
        case .app(let app): return "opens in \(app.name)"
        case .custom(let url): return "opens in \(url.deletingPathExtension().lastPathComponent)"
        }
    }

    /// The steps behind in the accent, the current one an 18 point capsule, the ones ahead faint. With Reduce Motion the
    /// width changes at once and only the color fades.
    var dots: some View {
        HStack(spacing: 8) {
            ForEach(model.steps, id: \.rawValue) { s in
                let dot = model.dot(for: s)
                // The color turns at once (0.12 s), the width on the spring: the new step reads bright as it widens.
                Capsule()
                    .animation(reduceMotion ? Theme.Motion.reduced : Theme.Motion.out(Self.dotColor)) {
                        $0.foregroundStyle(dot == .future ? Theme.Colors.surfaceLine : Theme.Colors.accent)
                    }
                    .frame(width: dot.width, height: dot.height)
            }
        }
        .animation(reduceMotion ? nil : Self.dotSpring, value: model.step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.progressLabel)
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
        .choiceStroke(selected: selected, reduceMotion: reduceMotion)
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
    func finish() { Task { await model.finish() } }
}

/// A page of the guide comes in 24 points from the side the guide moves to, fading in. The direction is read from the
/// model when the transition runs, not when the page was last drawn. A page leaving never moves (see `PageSwap`).
struct StepSlide: Transition {
    let model: OnboardingModel
    static let distance: CGFloat = 24

    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .offset(x: Self.shift(phase, direction: model.direction))
            .opacity(phase.isIdentity ? 1 : 0)
    }

    /// The new page starts on the side the guide moves to (willAppear is -1); the old one stays where it is.
    static func shift(_ phase: TransitionPhase, direction: Int) -> CGFloat {
        phase == .willAppear ? -phase.value * CGFloat(direction) * distance : 0
    }
}

/// One page gives way to the next in the same column: the old one fades out where it is in 0.12 s (the button just
/// clicked, under the pointer, never moves), and the new one slides in on the page spring from 0.08 s, once the old one
/// is nearly gone. Two pages are never drawn over each other at half strength.
enum PageSwap {
    static let removal = 0.12, insertionDelay = 0.08
    static let response = 0.4, damping = 0.9

    static func opacities(at t: Double) -> (old: Double, new: Double) {
        let new = t <= insertionDelay ? 0 : min(1, Ease.spring(t - insertionDelay, response: response, damping: damping))
        return (1 - Ease.out(Ease.progress(t, from: 0, over: removal)), new)
    }

    @MainActor static func transition(_ model: OnboardingModel) -> AnyTransition {
        let slow = Theme.Motion.slow
        return .asymmetric(
            insertion: AnyTransition(StepSlide(model: model))
                .animation(.spring(response: response * slow, dampingFraction: damping).delay(insertionDelay * slow)),
            removal: AnyTransition.opacity.animation(Theme.Motion.out(removal)))
    }
}

/// The second account's card, from the form to the account it made: the form's words go first (0.12 s) while the card
/// holds its height, then the height settles and the account's words come in.
enum SecondAccountSwap {
    static let hold = 0.12
    static func outgoing(_ reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .fade(true) : AnyTransition.opacity.animation(Theme.Motion.out(hold))
    }
    static func incoming(_ reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .fade(true) : AnyTransition.opacity.animation(Theme.Motion.out(0.2).delay(hold * Theme.Motion.slow))
    }
}

/// All set's beat once its page has landed: the six checks pop in one by one, 60 ms apart from 0.4 s (0.6 to 1 of their
/// size on the pop spring, fading in over 0.12 s), then the creature hops for the whole list. Nothing seen arriving (a
/// capture): in place. Reduce Motion: they fade in, in the same order, never scale.
enum AllSetBeat {
    static let checksFrom = 0.4, checkStagger = 0.06
    static let pop = Ease.Spring(response: 0.35, damping: 0.6)
    /// The hop: the last check in, then a beat.
    static let hop = checksFrom + 6 * checkStagger + 0.15
    /// Every check at rest.
    static let end = checksFrom + 5 * checkStagger + 0.9

    struct Look: Equatable { var scale: CGFloat; var opacity: Double }

    static func check(_ index: Int, elapsed: Double?, reduceMotion: Bool) -> Look {
        guard let elapsed else { return Look(scale: 1, opacity: 1) }
        let local = elapsed - (checksFrom + Double(index) * checkStagger)
        guard local > 0 else { return Look(scale: reduceMotion ? 1 : 0.6, opacity: 0) }
        if reduceMotion { return Look(scale: 1, opacity: Ease.progress(local, from: 0, over: Theme.Motion.reducedDuration)) }
        guard local < 0.9 else { return Look(scale: 1, opacity: 1) }
        return Look(scale: CGFloat(0.6 + 0.4 * pop.value(local)), opacity: Ease.out(Ease.progress(local, from: 0, over: 0.12)))
    }
}

/// The welcome's own entrance, when no launch lands on it: the creature wakes at 0.15 s, then the four words rise 6 points
/// into place, 0.30 s each, 0.05 s apart from 0.30 s. Never with Reduce Motion, nor in a capture; never while the launch
/// runs (its landing brings the words in) or once it has landed there.
enum WelcomeEntrance {
    static let wake = 0.15
    static let wordsFrom = 0.30, stagger = 0.05, fade = 0.30, rise: CGFloat = 6
    static var end: Double { wordsFrom + 3 * stagger + fade }

    struct Look: Equatable { var opacity: Double; var rise: CGFloat }

    static func word(_ index: Int, elapsed: Double?) -> Look {
        guard let elapsed else { return Look(opacity: 1, rise: 0) }
        let k = Ease.out(Ease.progress(elapsed, from: wordsFrom + Double(index) * stagger, over: fade))
        return Look(opacity: k, rise: rise * CGFloat(1 - k))
    }

    @MainActor static func plays(launch: LaunchClock?, reduceMotion: Bool, capture: Bool) -> Bool {
        guard !reduceMotion, !capture else { return false }
        guard let launch else { return true }
        return launch.finished && launch.landed == nil
    }
}

/// One of the welcome's words: after the launch's landing (`launchWords`), or on the welcome's own entrance from `since`
/// (`.distantFuture`: the welcome has not appeared yet, the word waits unseen).
struct WelcomeWord: ViewModifier {
    let index: Int
    let since: Date?

    func body(content: Content) -> some View {
        if let since {
            if since == .distantFuture {
                content.opacity(0)
            } else {
                BeatView(start: since, duration: WelcomeEntrance.end) { elapsed in
                    let look = WelcomeEntrance.word(index, elapsed: elapsed)
                    content.opacity(look.opacity).offset(y: look.rise)
                }
            }
        } else {
            content.launchWords(index)
        }
    }
}

/// The "Connected" check of the guide's second account: it draws itself on, and one sage ring spreads from it, once per
/// account (`rings` answers true the first time only): going back over the step shows the check still.
struct ConnectedCheck: View {
    let rings: () -> Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spread = false
    @State private var ringing = false

    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(Theme.Colors.sage)
            .background {
                Circle().stroke(Theme.Colors.sage, lineWidth: 1.5)
                    .padding(spread ? -7 : 0)
                    .opacity(ringing && !spread ? 0.8 : 0)
            }
            .onAppear {
                guard !reduceMotion, !Theme.Motion.isCapture, rings() else { return }
                ringing = true
                withAnimation(Theme.Motion.out(0.6)) { spread = true }
            }
    }
}

extension View {
    func welcomeWord(_ index: Int, since: Date?) -> some View { modifier(WelcomeWord(index: index, since: since)) }
}
