import AppKit
import QuartzCore
import SwiftUI

/// The display's clock (`CACurrentMediaTime`, seconds since the Mac started) as dates. The offset between the two clocks is
/// taken once: two frames a refresh apart are a refresh apart as dates too, whenever each one is converted.
struct DisplayClock: Equatable, Sendable {
    let offset: TimeInterval

    init(now: Date = Date(), media: CFTimeInterval = CACurrentMediaTime()) {
        offset = now.timeIntervalSinceReferenceDate - media
    }

    func date(at media: CFTimeInterval) -> Date { Date(timeIntervalSinceReferenceDate: media + offset) }
}

/// Calls `onFrame` once per frame of the display the view is on, with the moment that frame reaches the screen (the display
/// link's target time): what is worked out for it is where it should be then, however late in the refresh the main thread
/// gets to it, and each frame is a whole number of refreshes after the one before (a timeline's date is the moment its
/// view happens to be updated, which drifts within the refresh with the main thread's load). The link follows the window
/// to another display. Off every screen (a window hosted by a test), where no display link fires, a 60 Hz timer stands
/// in. Never hit, never seen by VoiceOver.
struct DisplayFrames: NSViewRepresentable {
    var running: Bool
    var onFrame: @MainActor (Date) -> Void

    func makeNSView(context: Context) -> FrameLinkView { FrameLinkView() }

    func updateNSView(_ view: FrameLinkView, context: Context) {
        view.onFrame = onFrame
        view.running = running
    }

    static func dismantleNSView(_ view: FrameLinkView, coordinator: ()) { view.stop() }
}

final class FrameLinkView: NSView {
    var onFrame: (@MainActor (Date) -> Void)?
    var running = false { didSet { if running != oldValue { follow() } } }
    private var link: CADisplayLink?
    private var timer: Timer?
    private var clock = DisplayClock()
    private var screenWatch: NSObjectProtocol?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let watch = screenWatch { NotificationCenter.default.removeObserver(watch) }
        screenWatch = window.map { window in
            NotificationCenter.default.addObserver(forName: NSWindow.didChangeScreenNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.follow() }
            }
        }
        follow()
    }

    /// The display link while the window is on a screen, the timer while it is off every screen, nothing when stopped.
    private func follow() {
        let on = running && window != nil
        let onScreen = on && window?.screen != nil
        if onScreen, link == nil {
            let made = displayLink(target: self, selector: #selector(step(_:)))
            clock = DisplayClock()
            made.add(to: .main, forMode: .common)
            link = made
        } else if !onScreen {
            link?.invalidate()
            link = nil
        }
        let offScreen = on && !onScreen
        if offScreen, timer == nil {
            let made = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.onFrame?(Date()) }
            }
            RunLoop.main.add(made, forMode: .common)
            timer = made
        } else if !offScreen {
            timer?.invalidate()
            timer = nil
        }
    }

    @objc private func step(_ link: CADisplayLink) { onFrame?(clock.date(at: link.targetTimestamp)) }

    /// The link holds the view: it goes with the view.
    func stop() {
        running = false
        link?.invalidate()
        link = nil
        timer?.invalidate()
        timer = nil
        if let watch = screenWatch { NotificationCenter.default.removeObserver(watch) }
        screenWatch = nil
    }
}
