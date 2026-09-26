import AppKit
import SwiftUI
import Testing
import BrainmergeCore
import BrainmergeTestSupport
@testable import BrainmergeUI

@MainActor @Suite struct OnboardingViewTests {
    /// Going on, the new page comes in from the right; going back, from the left. The old page fades where it is: the
    /// button just clicked never moves from under the pointer.
    @Test func pagesSlideTheWayTheGuideMoves() {
        #expect(StepSlide.shift(.willAppear, direction: 1) == 24 && StepSlide.shift(.willAppear, direction: -1) == -24)
        #expect(StepSlide.shift(.didDisappear, direction: 1) == 0 && StepSlide.shift(.didDisappear, direction: -1) == 0)
        #expect(StepSlide.shift(.identity, direction: 1) == 0 && StepSlide.shift(.identity, direction: -1) == 0)
    }

    /// The two pages share one column: the old one is gone before the new one shows, never two pages half drawn.
    @Test func theOldPageIsGoneBeforeTheNewOneShows() {
        for i in 0...120 {
            let t = Double(i) / 240, o = PageSwap.opacities(at: t)
            #expect(min(o.old, o.new) < 0.2, "t \(t): old \(o.old), new \(o.new)")
        }
        #expect(PageSwap.opacities(at: 0).old == 1 && PageSwap.opacities(at: 0).new == 0)
        #expect(PageSwap.opacities(at: PageSwap.removal).old == 0 && PageSwap.opacities(at: 1).new > 0.99)
    }

    /// The line that says work is running keeps its place when there is none: the step never jumps as it comes and goes.
    @Test func theWorkingLineHoldsItsPlace() {
        let empty = NSHostingView(rootView: WorkingLine(text: nil, holdsPlace: true).frame(width: 400)).fittingSize
        let busy = NSHostingView(rootView: WorkingLine(text: "Adding Work…", holdsPlace: true).frame(width: 400)).fittingSize
        #expect(empty.height > 10 && empty.height == busy.height)
        #expect(NSHostingView(rootView: WorkingLine(text: nil).frame(width: 400)).fittingSize.height == 0)
    }

    /// All set says what opens the memory in plain words: "opens in Obsidian", "opens in Finder".
    @Test func allSetSaysWhatOpensTheMemory() {
        let obsidian = NotesApp(name: "Obsidian", bundleIdentifier: "md.obsidian", website: URL(string: "https://obsidian.md")!)
        #expect(OnboardingView.opensIn(.app(obsidian)) == "opens in Obsidian")
        #expect(OnboardingView.opensIn(.folder) == "opens in Finder")
        #expect(OnboardingView.opensIn(.custom(URL(fileURLWithPath: "/Applications/Bear.app"))) == "opens in Bear")
    }

    /// All set: the checks come in one by one once the page has landed, then the creature hops for the whole list.
    @Test func theChecksComeInOneByOneThenTheCreatureHops() {
        #expect(AllSetBeat.check(0, elapsed: AllSetBeat.checksFrom - 0.01, reduceMotion: false).opacity == 0)
        #expect(AllSetBeat.check(0, elapsed: AllSetBeat.checksFrom + 0.1, reduceMotion: false).opacity > 0.5)
        let last = AllSetBeat.checksFrom + 5 * AllSetBeat.checkStagger
        #expect(AllSetBeat.check(5, elapsed: last - 0.01, reduceMotion: false).opacity == 0)
        #expect(AllSetBeat.check(5, elapsed: last + 0.1, reduceMotion: false).opacity > 0.5)
        #expect(AllSetBeat.hop >= last + 0.15 && AllSetBeat.hop < 1.2)
        for i in 0..<6 {
            let done = AllSetBeat.check(i, elapsed: 1.6, reduceMotion: false)
            #expect(done.opacity == 1 && done.scale == 1)
            #expect(AllSetBeat.check(i, elapsed: nil, reduceMotion: false) == .init(scale: 1, opacity: 1))
            // Reduce Motion: they fade, never scale.
            for t in stride(from: 0.0, to: 1.6, by: 0.02) { #expect(AllSetBeat.check(i, elapsed: t, reduceMotion: true).scale == 1) }
        }
    }

    /// A welcome shown without the launch landing on it (a demo, a capture of the guide, a later window) still greets: the
    /// creature wakes, then the words rise in one after the other. Once only: never again on Back.
    @Test func theWelcomeGreetsWithoutTheLaunch() {
        #expect(WelcomeEntrance.word(0, elapsed: 0.29).opacity == 0)
        #expect(WelcomeEntrance.word(0, elapsed: 0.30 + 0.30).opacity == 1 && WelcomeEntrance.word(0, elapsed: 0.6).rise == 0)
        #expect(WelcomeEntrance.word(3, elapsed: 0.30 + 3 * 0.05 - 0.001).opacity == 0)
        #expect(WelcomeEntrance.word(1, elapsed: 0.40).rise > 0 && WelcomeEntrance.word(1, elapsed: 0.40).rise <= 6)
        #expect(WelcomeEntrance.word(2, elapsed: nil) == .init(opacity: 1, rise: 0))
        #expect(WelcomeEntrance.wake == 0.15)
        #expect(WelcomeEntrance.plays(launch: nil, reduceMotion: false, capture: false))
        #expect(!WelcomeEntrance.plays(launch: nil, reduceMotion: true, capture: false))
        #expect(!WelcomeEntrance.plays(launch: nil, reduceMotion: false, capture: true))
        // The launch's own landing brings the words in: no second entrance.
        #expect(!WelcomeEntrance.plays(launch: LaunchClock(slow: 1, capture: false), reduceMotion: false, capture: false))
        #expect(WelcomeEntrance.plays(launch: LaunchClock(finished: true, slow: 1, capture: false), reduceMotion: false, capture: false))
    }

    /// Every step fits the window at its default size (960 by 640) whole, with nothing to scroll: its buttons are never
    /// cut by the bottom edge, and All set's "Open Brainmerge" and its link are on screen. Measured with the longest lines
    /// the steps take: five accounts and two memories, Claude Code, git and the command line all missing, and the second
    /// account's card, added while Claude is open for another account, with its long sentence and its button.
    @Test func everyStepFitsTheDefaultWindow() async throws {
        let ps = CoreWorkTests.FakePS("")
        let (e, app, onboarding) = try OnboardingModelTests().setup(monitor: ProcessMonitor(psOutput: { ps.output }))
        defer { e.home.remove() }
        let room = 640 - OnboardingView.dotsRoom
        func height() -> CGFloat {
            NSHostingView(rootView: OnboardingView(model: onboarding).laidOutPage.frame(width: 960)).fittingSize.height
        }
        onboarding.primaryName = "Personal"
        await onboarding.finish()
        for name in ["Studio", "Client", "Work"] { _ = try e.manager.add(IdentityManager.AddRequest(name: name)) }
        _ = try e.manager.addBrain(name: "Clients", path: nil, language: .en)
        ps.output = "  900 1 120000 \(e.claude.executable.path)\n"
        app.reload()
        #expect(app.brains.count == 2 && app.openAccounts.count == 1)
        onboarding.step = .secondAccount
        #expect(height() <= room, "the second account's form: \(height()) for \(room)")
        onboarding.secondAccount.name = "Freelance"
        #expect(await onboarding.addSecondAccount())
        #expect(app.accounts.count == 5 && !onboarding.othersOpen.isEmpty)
        for step in OnboardingModel.Step.allCases {
            onboarding.step = step
            #expect(height() <= room, "\(step): \(height()) for \(room)")
        }
    }

    /// The added account's card says what to do next and never asks again for what was just done: once its button is
    /// clicked, the button goes and the card says to log in as its window comes up, whether or not it is seen running yet.
    @Test func theAddedCardNeverAsksForWhatWasJustDone() {
        typealias Card = OnboardingView.AddedCard
        let ready = Card.of(name: "Work", needsLogin: true, isRunning: false, opened: false, othersOpen: [])
        #expect(ready.sentence == "Ready. Open it to log in." && ready.button == "Open Work")
        let blocked = Card.of(name: "Work", needsLogin: true, isRunning: false, opened: false, othersOpen: ["Personal", "Studio"])
        #expect(blocked.sentence == "Ready. Claude is open for Personal, Studio: it must be closed first, or the login would land in that window.")
        #expect(blocked.button == "Quit Claude and open Work")
        for others in [[], ["Personal"]] {
            let opening = Card.of(name: "Work", needsLogin: true, isRunning: false, opened: true, othersOpen: others)
            #expect(opening.button == nil && !opening.sentence.contains("Open it") && opening.sentence.contains("Log in"), "\(opening)")
        }
        let open = Card.of(name: "Work", needsLogin: true, isRunning: true, opened: true, othersOpen: [])
        #expect(open.button == nil && open.sentence.hasPrefix("Open. Log in in its Claude window"))
        let connected = Card.of(name: "Work", needsLogin: false, isRunning: true, opened: true, othersOpen: [])
        #expect(connected.sentence == "Connected. Continue whenever you like." && connected.button == nil)
        #expect(Card.of(name: "Work", needsLogin: false, isRunning: false, opened: true, othersOpen: []).sentence == "Connected. Open it whenever you like.")
        let opening = Card.of(name: "Work", needsLogin: true, isRunning: false, opened: true, othersOpen: [])
        #expect([ready, opening, open, connected].map(\.phase) == [.ready, .opening, .open, .connected])
    }

    /// All set builds the main window under the guide. Until "Open Brainmerge" reveals it, it is out of sight and out of
    /// reach: no click, nothing from the keyboard (its controls are off: no Return, Space, Tab or shortcut reaches them)
    /// and nothing for VoiceOver.
    @Test func theMainWindowUnderAllSetIsOutOfReachUntilRevealed() {
        #expect(HeldUnderGuide.Look(held: true) == .init(opacity: 0, hittable: false, enabled: false, accessible: false))
        #expect(HeldUnderGuide.Look(held: false) == .init(opacity: 1, hittable: true, enabled: true, accessible: true))
    }

    /// How it works is drawn 1:1 inside the step's column: never scaled nor clipped, so its 3 point cells stay whole.
    /// The page, laid out as the guide lays it out (560 points wide), holds the scene drawn alone, pixel for pixel.
    @Test func howItWorksFitsTheColumnAtItsOwnSize() throws {
        #expect(HowItWorksScene.size == CGSize(width: 520, height: 224))
        #expect(HowItWorksScene.creatureUnit == HowItWorksScene.creatureUnit.rounded())
        let (e, _, onboarding) = try OnboardingModelTests().setup()
        defer { e.home.remove() }
        let page = try #require(HowItWorksViewTests.render(OnboardingView(model: onboarding).howItWorks.frame(width: 560)))
        let alone = try #require(HowItWorksViewTests.render(
            HowItWorksCanvas(frame: HowItWorksScene.frame(at: 0), texts: HowItWorksTexts()).frame(width: 520, height: 224)))
        #expect(alone.pixelsWide == 1040 && alone.pixelsHigh == 448)
        // Centered in the column (20 points each side), under the title: find the row where it sits.
        let match = (0...240).first { y in HowItWorksViewTests.differing(page, alone, at: CGPoint(x: 40, y: y)) < 400 }
        #expect(match != nil, "the scene is not drawn at its own size in the page")
    }

    // MARK: Filmed

    /// The second account's step, as the guide shows it, over a first account already made: Personal, whose Claude window
    /// `ps` shows open when `personalOpen` (at a pid above macOS's limit, 99,999: no real process is ever matched).
    func secondAccountStep(personalOpen: Bool = false) throws -> (ManagerEnv, AppModel, OnboardingModel, CoreWorkTests.FakePS) {
        let ps = CoreWorkTests.FakePS("")
        let (e, app, onboarding) = try OnboardingModelTests().setup(withBrain: true, monitor: ProcessMonitor(psOutput: { ps.output }))
        _ = try e.manager.adoptPrimary(name: "Personal")
        if personalOpen { ps.output = "4000001 1 120000 \(e.claude.executable.path)\n" }
        app.reload()
        // Never the Mac's own: a quit empties the fake list, a launch does nothing.
        app.quitAccount = { _, _ in ps.output = "" }
        app.launchAccount = { _, _ in }
        onboarding.step = .secondAccount
        onboarding.secondAccount.name = "Freelance"
        return (e, app, onboarding, ps)
    }

    /// The second account's step alone, drawn again as the model changes (its body reads the model).
    struct SecondAccountPage: View {
        let model: OnboardingModel
        var body: some View { OnboardingView(model: model).secondAccount.frame(width: 560).padding(20) }
    }

    /// As "Add account" is done, the form gives way to the account it made: "Skip for now" and "Add account" fade where
    /// they are, and the row of buttons settles with the card once they have gone (the step's settle, after
    /// SecondAccountSwap.hold). Back never moves on the 0.15 s dimming of "Add account", which slid it across "Skip for
    /// now" while that one still faded: drawn before the hold, it is where it was, and it is still on its way to its new
    /// place a quarter of a second after the add.
    @Test func backMovesWithTheCardOnceTheFormsButtonsHaveGone() async throws {
        let (e, _, onboarding, _) = try secondAccountStep(); defer { e.home.remove() }
        let film = Film(SecondAccountPage(model: onboarding), size: CGSize(width: 600, height: 780))
        defer { film.close() }
        film.run(for: 0.4)
        let before = film.shot()
        // The row of buttons is the lowest black line (the words under it are cream); Back is its first word.
        func back(_ shot: Film.Shot) -> Film.PixelRect? {
            shot.darkLines().last.flatMap { shot.darkWords(in: $0, gap: Int(8 * shot.scale)).first }
        }
        let row = try #require(before.darkLines().last, "no row of buttons drawn")
        #expect(before.darkWords(in: row, gap: Int(8 * before.scale)).count == 3, "Back, Skip for now, Add account")
        let start = try #require(back(before)).x
        // Filmed from the moment the account is added: the run loop has not drawn the change yet.
        #expect(await onboarding.addSecondAccount())
        let shots = film.shots(for: 0.9)
        let end = try #require(shots.last.flatMap { back($0.shot) }).x
        #expect(end - start > Int(20 * before.scale), "Back never moved: \(start) to \(end)")
        for (time, shot) in shots where time < SecondAccountSwap.hold - 0.03 {
            let x = back(shot)?.x
            #expect(x.map { abs($0 - start) <= 2 } == true, "Back moved \(Int(time * 1000)) ms after the add: \(start) to \(x ?? -1)")
        }
        let quarter = shots.filter { $0.time >= 0.25 && $0.time <= 0.4 }.compactMap { back($0.shot)?.x }
        #expect(!quarter.isEmpty && quarter.contains { $0 < end - Int(2 * before.scale) },
                "Back had arrived before the form's words had gone and the card settled: \(quarter) for \(start) to \(end)")
    }
}
