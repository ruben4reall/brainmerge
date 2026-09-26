import AppKit
import Foundation
import Testing
@testable import BrainmergeUI

/// Stands in for RegisterEventHotKey: tests never take a shortcut on the Mac.
@MainActor final class FakeRegistrar: HotKeyRegistrar {
    private(set) var live: [UInt32: (shortcut: HotKeyShortcut, press: @MainActor () -> Void)] = [:]
    private(set) var log: [String] = []
    /// Shortcuts another app holds.
    var taken: Set<String> = []
    private var next: UInt32 = 1

    var registered: [HotKeyShortcut] { live.keys.sorted().compactMap { live[$0]?.shortcut } }

    func register(_ shortcut: HotKeyShortcut, onPress: @escaping @MainActor () -> Void) -> HotKeyRegistration? {
        log.append("register \(shortcut.display)")
        guard !taken.contains(shortcut.display) else { return nil }
        defer { next += 1 }
        live[next] = (shortcut, onPress)
        return HotKeyRegistration(id: next)
    }

    func unregister(_ registration: HotKeyRegistration) {
        guard let entry = live.removeValue(forKey: registration.id) else { Issue.record("unregistered twice: \(registration.id)"); return }
        log.append("unregister \(entry.shortcut.display)")
    }

    /// The person presses a shortcut: only a registered one does anything.
    func press(_ display: String) { for entry in live.values where entry.shortcut.display == display { entry.press() } }
}

@MainActor @Suite struct HotKeyTests {
    // Carbon's modifier bits, by hand: command 256, shift 512, option 2048, control 4096.
    let commandOptionK = HotKeyShortcut(keyCode: 40, modifiers: 256 + 2048, key: "K")
    let controlSpace = HotKeyShortcut(keyCode: 49, modifiers: 4096, key: "Space")

    @Test func shortcutsShowAsMacMenusDo() {
        #expect(HotKeyShortcut.suggested.display == "⌃⌥Space")
        #expect(HotKeyShortcut.suggested.keyCode == 49 && HotKeyShortcut.suggested.modifiers == 4096 + 2048)
        #expect(commandOptionK.display == "⌥⌘K")
        #expect(HotKeyShortcut(keyCode: 0, modifiers: 256 + 512 + 2048 + 4096, key: "A").display == "⌃⌥⇧⌘A")
    }

    // MARK: The wrapper

    final class Presses { var count = 0 }

    @Test func aShortcutIsRegisteredOnceAndItsPressIsHeard() {
        let fake = FakeRegistrar(), presses = Presses()
        let hotKey = HotKey(registrar: fake) { presses.count += 1 }
        #expect(hotKey.set(commandOptionK))
        #expect(hotKey.set(commandOptionK))
        #expect(fake.log == ["register ⌥⌘K"])
        fake.press("⌥⌘K")
        #expect(presses.count == 1)
        #expect(hotKey.registered == commandOptionK)
    }

    @Test func changingTheShortcutUnregistersTheOldOne() {
        let fake = FakeRegistrar()
        let hotKey = HotKey(registrar: fake) {}
        hotKey.set(commandOptionK)
        hotKey.set(controlSpace)
        #expect(fake.log == ["register ⌥⌘K", "unregister ⌥⌘K", "register ⌃Space"])
        #expect(fake.registered == [controlSpace])
    }

    @Test func turningItOffUnregisters() {
        let fake = FakeRegistrar(), presses = Presses()
        let hotKey = HotKey(registrar: fake) { presses.count += 1 }
        hotKey.set(commandOptionK)
        #expect(hotKey.set(nil))
        #expect(fake.registered.isEmpty)
        #expect(hotKey.registered == nil)
        fake.press("⌥⌘K")
        #expect(presses.count == 0)
        hotKey.set(nil)
        #expect(fake.log == ["register ⌥⌘K", "unregister ⌥⌘K"])
    }

    /// Another app holds the new one: the old shortcut keeps working.
    @Test func aRefusedShortcutKeepsTheOldOne() {
        let fake = FakeRegistrar()
        fake.taken = ["⌃Space"]
        let hotKey = HotKey(registrar: fake) {}
        hotKey.set(commandOptionK)
        #expect(!hotKey.set(controlSpace))
        #expect(fake.registered == [commandOptionK])
        #expect(hotKey.registered == commandOptionK)
    }

    // MARK: Recording a shortcut

    @Test func aRecordedKeyNeedsCommandControlOrOption() {
        func record(_ code: UInt16, _ characters: String?, _ modifiers: NSEvent.ModifierFlags) -> HotKeyShortcut.Recording {
            HotKeyShortcut.record(keyCode: code, characters: characters, modifiers: modifiers)
        }
        #expect(record(40, "k", [.command, .option]) == .shortcut(commandOptionK))
        #expect(record(49, " ", [.control, .option]) == .shortcut(.suggested))
        #expect(record(40, "k", []) == .needsModifier)
        #expect(record(40, "K", [.shift]) == .needsModifier)
        #expect(record(53, "\u{1b}", []) == .cancel)
        // ⌘ and a letter or a digit is every app's own command (⌘Q, ⌘C): taking it would break them everywhere.
        #expect(record(12, "q", [.command]) == .appCommand)
        #expect(record(18, "1", [.command]) == .appCommand)
        #expect(record(49, " ", [.command]) == .shortcut(HotKeyShortcut(keyCode: 49, modifiers: 256, key: "Space")))
        #expect(record(12, "q", [.command, .control]) == .shortcut(HotKeyShortcut(keyCode: 12, modifiers: 256 + 4096, key: "Q")))
        // The function keys carry their own flags, which are not modifiers.
        #expect(record(122, nil, [.function, .control]) == .shortcut(HotKeyShortcut(keyCode: 122, modifiers: 4096, key: "F1")))
        #expect(record(125, nil, [.function, .numericPad, .command]) == .shortcut(HotKeyShortcut(keyCode: 125, modifiers: 256, key: "↓")))
    }

    // MARK: The setting, per Mac

    func opener(_ store: EphemeralSettings = EphemeralSettings(), _ fake: FakeRegistrar = FakeRegistrar()) -> QuickOpener {
        QuickOpener(defaults: store, registrar: fake)
    }

    @Test func offByDefaultSuggestingControlOptionSpace() {
        let fake = FakeRegistrar()
        let q = opener(EphemeralSettings(), fake)
        q.start()
        #expect(!q.isOn && !q.isActive)
        #expect(q.shortcut.display == "⌃⌥Space")
        #expect(fake.log.isEmpty)
    }

    @Test func turningItOnRegistersAndIsRememberedOnThisMac() {
        let store = EphemeralSettings(), fake = FakeRegistrar()
        let q = opener(store, fake)
        q.start()
        q.setOn(true)
        #expect(q.isOn && q.isActive)
        #expect(fake.registered == [.suggested])
        let next = FakeRegistrar()
        let again = opener(store, next)
        #expect(next.log.isEmpty, "nothing is registered before start")
        again.start()
        #expect(again.isOn && next.registered == [.suggested])
    }

    @Test func turningItOffUnregistersAndIsRemembered() {
        let store = EphemeralSettings(), fake = FakeRegistrar()
        let q = opener(store, fake)
        q.setOn(true)
        #expect(fake.registered == [.suggested])
        q.setOn(false)
        #expect(!q.isActive && fake.registered.isEmpty)
        #expect(fake.log == ["register ⌃⌥Space", "unregister ⌃⌥Space"])
        let next = FakeRegistrar()
        opener(store, next).start()
        #expect(next.log.isEmpty)
    }

    /// While recording, the current shortcut is let go, so it can be typed again; the new one replaces it.
    @Test func aRecordedShortcutReplacesTheOldOne() {
        let store = EphemeralSettings(), fake = FakeRegistrar()
        let q = opener(store, fake)
        q.setOn(true)
        q.beginRecording()
        #expect(q.isRecording && fake.registered.isEmpty)
        #expect(q.record(keyCode: 40, characters: "k", modifiers: [.command, .option]))
        #expect(!q.isRecording && q.shortcut == commandOptionK)
        #expect(fake.registered == [commandOptionK])
        #expect(fake.log == ["register ⌃⌥Space", "unregister ⌃⌥Space", "register ⌥⌘K"])
        let next = FakeRegistrar()
        let again = opener(store, next)
        again.start()
        #expect(again.shortcut == commandOptionK && next.registered == [commandOptionK])
    }

    @Test func escapeCancelsAndPutsTheOldOneBack() {
        let fake = FakeRegistrar()
        let q = opener(EphemeralSettings(), fake)
        q.setOn(true)
        q.beginRecording()
        #expect(q.record(keyCode: 53, characters: "\u{1b}", modifiers: []))
        #expect(!q.isRecording && q.shortcut == .suggested)
        #expect(fake.registered == [.suggested])
    }

    @Test func aBareKeyKeepsRecordingAndSaysWhy() {
        let fake = FakeRegistrar()
        let q = opener(EphemeralSettings(), fake)
        q.setOn(true)
        q.beginRecording()
        #expect(!q.record(keyCode: 40, characters: "k", modifiers: []))
        #expect(q.isRecording && q.problem == QuickOpener.needsModifier)
        #expect(fake.registered.isEmpty)
    }

    @Test func anAppsOwnCommandKeepsRecordingAndSaysWhy() {
        let fake = FakeRegistrar()
        let q = opener(EphemeralSettings(), fake)
        q.beginRecording()
        #expect(!q.record(keyCode: 12, characters: "q", modifiers: [.command]))
        #expect(q.isRecording && q.problem == QuickOpener.appCommand)
        #expect(q.shortcut == .suggested)
    }

    /// Recorded while off: saved, nothing registered until it is turned on.
    @Test func recordingWhileOffRegistersNothing() {
        let store = EphemeralSettings(), fake = FakeRegistrar()
        let q = opener(store, fake)
        q.beginRecording()
        q.record(keyCode: 40, characters: "k", modifiers: [.command, .option])
        #expect(q.shortcut == commandOptionK && fake.log.isEmpty)
        q.setOn(true)
        #expect(fake.registered == [commandOptionK])
    }

    @Test func aShortcutAnotherAppHoldsIsSaidAndTheOldOneStays() {
        let store = EphemeralSettings(), fake = FakeRegistrar()
        fake.taken = ["⌥⌘K"]
        let q = opener(store, fake)
        q.setOn(true)
        q.beginRecording()
        q.record(keyCode: 40, characters: "k", modifiers: [.command, .option])
        #expect(q.problem == QuickOpener.taken)
        #expect(q.shortcut == .suggested && fake.registered == [.suggested])
        #expect(opener(store).shortcut == .suggested)
    }

    @Test func aSavedShortcutAnotherAppHoldsIsSaidAtLaunch() {
        let store = EphemeralSettings(), fake = FakeRegistrar()
        opener(store).setOn(true)
        fake.taken = ["⌃⌥Space"]
        let q = opener(store, fake)
        q.start()
        #expect(q.isOn && !q.isActive)
        #expect(q.problem == QuickOpener.taken)
    }

    @Test func thePressReachesTheOpener() {
        let fake = FakeRegistrar(), presses = Presses()
        let q = opener(EphemeralSettings(), fake)
        q.onPress = { presses.count += 1 }
        q.setOn(true)
        fake.press("⌃⌥Space")
        #expect(presses.count == 1)
    }

    /// A damaged or hand-edited value never registers a shortcut without ⌘, ⌃ or ⌥.
    @Test func anInvalidSavedShortcutFallsBackToTheSuggestion() {
        let store = EphemeralSettings()
        store.set(40, forKey: "quickOpener.keyCode")
        store.set(2304, forKey: "quickOpener.modifiers")
        store.set("K", forKey: "quickOpener.key")
        #expect(opener(store).shortcut == commandOptionK)
        store.set(512, forKey: "quickOpener.modifiers")
        store.set("K", forKey: "quickOpener.key")
        #expect(opener(store).shortcut == .suggested)
    }

    /// A capture or a demo never reads or writes this Mac's setting, and starts off.
    @Test func aCaptureOrADemoKeepsTheSettingInMemory() {
        #expect(QuickOpener.settings(environment: ["BRAINMERGE_HOME": "/tmp/demo"]) is EphemeralSettings)
        #expect(QuickOpener.settings(environment: ["BRAINMERGE_CAPTURE": "1"]) is EphemeralSettings)
        // Outside them, the app's own defaults (only looked at here, never written).
        #expect(!(QuickOpener.settings(environment: [:]) is EphemeralSettings))
    }
}
