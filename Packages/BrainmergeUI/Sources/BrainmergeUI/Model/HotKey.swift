import AppKit
import Carbon.HIToolbox
import Foundation

/// A keyboard shortcut for RegisterEventHotKey: the key's code, Carbon's modifier bits, and what the key shows.
public struct HotKeyShortcut: Equatable, Hashable, Sendable {
    public let keyCode: UInt32
    /// Carbon's bits: cmdKey, shiftKey, optionKey, controlKey.
    public let modifiers: UInt32
    /// The key as the person saw it when recording ("Space", "K"): a code alone does not say which letter a layout puts there.
    public let key: String

    public init(keyCode: UInt32, modifiers: UInt32, key: String) { self.keyCode = keyCode; self.modifiers = modifiers; self.key = key }

    /// Control-Option-Space, what Settings suggests.
    public static let suggested = HotKeyShortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey), key: "Space")

    /// In the order Mac menus write them: ⌃⌥⇧⌘, then the key.
    public var display: String {
        let marks: [(Int, String)] = [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
        return marks.filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined() + key
    }

    /// At least one of ⌘, ⌃ or ⌥: a bare key or Shift and a key would take typing away from every app.
    public var isValid: Bool { modifiers & UInt32(cmdKey | controlKey | optionKey) != 0 && keyCode < 128 && !key.isEmpty }

    public enum Recording: Equatable, Sendable { case shortcut(HotKeyShortcut), cancel, needsModifier, appCommand }

    /// What a key pressed while recording gives: Esc alone cancels, a key without ⌘, ⌃ or ⌥ is refused, and so is ⌘
    /// with a letter, a digit or a sign, which is every app's own command (⌘Q, ⌘C): taking it would break them all.
    public static func record(keyCode: UInt16, characters: String?, modifiers: NSEvent.ModifierFlags) -> Recording {
        let held = modifiers.intersection([.command, .control, .option, .shift])
        if keyCode == UInt16(kVK_Escape), held.isEmpty { return .cancel }
        if held == .command, namedKeys[Int(keyCode)] == nil { return .appCommand }
        var bits = 0
        if held.contains(.command) { bits |= cmdKey }
        if held.contains(.shift) { bits |= shiftKey }
        if held.contains(.option) { bits |= optionKey }
        if held.contains(.control) { bits |= controlKey }
        let shortcut = HotKeyShortcut(keyCode: UInt32(keyCode), modifiers: UInt32(bits), key: name(keyCode: keyCode, characters: characters))
        return shortcut.isValid ? .shortcut(shortcut) : .needsModifier
    }

    /// Keys that type nothing are named; the others show their character, as the layout in use typed it.
    static let namedKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "Return", kVK_ANSI_KeypadEnter: "Enter", kVK_Tab: "Tab", kVK_Delete: "Delete",
        kVK_ForwardDelete: "⌦", kVK_Escape: "Esc", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑",
        kVK_Home: "Home", kVK_End: "End", kVK_PageUp: "Page Up", kVK_PageDown: "Page Down",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    static func name(keyCode: UInt16, characters: String?) -> String {
        if let name = namedKeys[Int(keyCode)] { return name }
        let typed = (characters ?? "").trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        return typed.isEmpty ? "Key \(keyCode)" : typed.uppercased()
    }
}

/// One shortcut registered with macOS.
public struct HotKeyRegistration: Hashable, Sendable {
    public let id: UInt32
    public init(id: UInt32) { self.id = id }
}

/// Registers shortcuts with macOS; a fake in tests, which never take a shortcut on the Mac.
@MainActor public protocol HotKeyRegistrar: AnyObject {
    /// Nil when macOS refused it (another app holds it).
    func register(_ shortcut: HotKeyShortcut, onPress: @escaping @MainActor () -> Void) -> HotKeyRegistration?
    func unregister(_ registration: HotKeyRegistration)
}

/// One shortcut at a time: setting another one lets the first go, nil lets it go. Needs no Accessibility or Input
/// Monitoring permission: RegisterEventHotKey only hears its own shortcut, never other keys.
@MainActor public final class HotKey {
    private let registrar: any HotKeyRegistrar
    private let onPress: @MainActor () -> Void
    private var registration: HotKeyRegistration?
    /// The shortcut registered now.
    public private(set) var registered: HotKeyShortcut?

    public init(registrar: any HotKeyRegistrar, onPress: @escaping @MainActor () -> Void) {
        self.registrar = registrar; self.onPress = onPress
    }

    /// Registers `shortcut` in place of the current one, or none. False when macOS refused it: the previous one is
    /// registered again, so the opener keeps working.
    @discardableResult
    public func set(_ shortcut: HotKeyShortcut?) -> Bool {
        guard shortcut != registered else { return true }
        let previous = registered
        release()
        guard let shortcut else { return true }
        if take(shortcut) { return true }
        if let previous { _ = take(previous) }
        return false
    }

    private func take(_ shortcut: HotKeyShortcut) -> Bool {
        let onPress = self.onPress
        guard let registration = registrar.register(shortcut, onPress: onPress) else { return false }
        self.registration = registration
        registered = shortcut
        return true
    }

    private func release() {
        if let registration { registrar.unregister(registration) }
        registration = nil
        registered = nil
    }
}

/// The real registrar: Carbon's RegisterEventHotKey, and one handler on the app's own event target for its presses.
@MainActor public final class CarbonHotKeyRegistrar: HotKeyRegistrar {
    /// "BMRG": marks Brainmerge's shortcuts among the app's hot key events.
    static let signature: OSType = 0x424D_5247
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var presses: [UInt32: @MainActor () -> Void] = [:]
    private var nextID: UInt32 = 1
    private var handler: EventHandlerRef?

    public init() {}

    public func register(_ shortcut: HotKeyShortcut, onPress: @escaping @MainActor () -> Void) -> HotKeyRegistration? {
        guard installHandler() else { return nil }
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: Self.signature, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return nil }
        refs[id] = ref
        presses[id] = onPress
        return HotKeyRegistration(id: id)
    }

    public func unregister(_ registration: HotKeyRegistration) {
        if let ref = refs.removeValue(forKey: registration.id) { UnregisterEventHotKey(ref) }
        presses[registration.id] = nil
    }

    fileprivate func pressed(_ id: EventHotKeyID) {
        guard id.signature == Self.signature else { return }
        presses[id.id]?()
    }

    /// Once: Carbon calls it on the main thread for each press of a shortcut this app registered.
    private func installHandler() -> Bool {
        guard handler == nil else { return true }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let read = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                         MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard read == noErr else { return read }
            let registrar = Unmanaged<CarbonHotKeyRegistrar>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { registrar.pressed(id) }
            return noErr
        }, 1, &type, context, &handler)
        return status == noErr
    }
}
