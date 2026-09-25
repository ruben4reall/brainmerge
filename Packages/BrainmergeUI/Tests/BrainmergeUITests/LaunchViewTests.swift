import AppKit
import CoreGraphics
import SwiftUI
import Testing
@testable import BrainmergeUI

@Suite struct LaunchViewTests {
    @Test func splashFeetOnWholePoints() {
        // Odd and fractional window sizes too: a half-point origin blurs the pixel edges on a 1x display.
        for size in [CGSize(width: 960, height: 640), CGSize(width: 1001, height: 677), CGSize(width: 1280.5, height: 803.5)] {
            let feet = AssembleScene.splashFeet(in: size)
            let unit = Theme.Launch.unit
            #expect(feet.x == feet.x.rounded() && feet.y == feet.y.rounded(), "\(size)")
            #expect((feet.x - 8 * unit) == (feet.x - 8 * unit).rounded() && (feet.y - 11 * unit) == (feet.y - 11 * unit).rounded())
            #expect(feet.x == (size.width / 2).rounded(.down))
            #expect(feet.y == (size.height / 2 - Theme.Launch.lift + 38).rounded(.down))
            // The body's middle sits `lift` above the window's middle, within the floor's point and a half.
            #expect(abs(feet.y - 11 * unit / 2 - (size.height / 2 - Theme.Launch.lift)) <= 1.5)
        }
    }

    @Test func aTargetIsTheCreaturesFeetOnWholePoints() {
        // The sidebar footer's creature: its layout frame is its grid, 16 by 11 cells of 2 pt.
        let target = LaunchTarget(frame: CGRect(x: 26, y: 580.4, width: 32, height: 22), asleep: true)
        #expect(target.unit == 2 && target.feet == CGPoint(x: 42, y: 602) && target.asleep)
        let welcome = LaunchTarget(frame: CGRect(x: 447.5, y: 120, width: 64, height: 44), asleep: false)
        #expect(welcome.unit == 4 && welcome.feet == CGPoint(x: 480, y: 164))
    }

    /// The creature a launch lands on publishes where it is on its first layout, in the window's coordinates, and stays
    /// hidden until the leap is over.
    @MainActor @Test func aTargetIsOfferedOnItsFirstLayout() {
        let clock = LaunchClock(slow: 1, capture: false)
        clock.begin(at: Date(), reduceMotion: false)
        clock.ready(at: Date())
        let view = VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 100)
            CreatureView(state: .asleep, size: 32).launchTarget(clock, asleep: true)
        }
        .padding(.leading, 26)
        .frame(width: 300, height: 300, alignment: .topLeading)
        .coordinateSpace(.named(LaunchClock.space))
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 300, height: 300)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        #expect(clock.target == LaunchTarget(feet: CGPoint(x: 42, y: 122), unit: 2, asleep: true))
        #expect(clock.hidesTarget)
    }

    /// The screens come in at 98.5% of their size: the creature under them must still be measured where it will be once
    /// they are whole, or the overlay would land a few points off and the real creature would jump when it shows.
    @MainActor @Test func aTargetUnderTheRevealIsMeasuredAtFullSize() {
        // Twenty times slower than the clock: the scene is the same, and a busy machine has 1.5 s to lay the view out.
        let now = Date(), slow = 20.0
        let clock = LaunchClock(slow: slow, capture: false)
        clock.begin(at: now.addingTimeInterval(-0.485 * slow), reduceMotion: false)
        clock.ready(at: now.addingTimeInterval(-0.285 * slow))                 // ready at 0.2 s: the hand-off started at 0.48 s
        #expect(abs(clock.reveal(.main, at: now).scale - 0.985) < 1e-3)
        let screens = VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 500)
            CreatureView(state: .awake, size: 32).launchTarget(clock, asleep: false)
        }
        .padding(.leading, 26)
        .frame(width: 800, height: 600, alignment: .topLeading)
        .launchReveal(clock, role: .main)
        .coordinateSpace(.named(LaunchClock.space))
        let host = NSHostingView(rootView: screens)
        host.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        #expect(clock.target == LaunchTarget(feet: CGPoint(x: 42, y: 522), unit: 2, asleep: false))
    }
}
