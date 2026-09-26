import AppKit
import Foundation
import Observation

/// Where a per-Mac setting lives: the app's own defaults, a plain dictionary in tests, captures and demos (never a
/// preferences file there).
public protocol SettingsStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}
extension UserDefaults: SettingsStore {}

/// Settings kept in memory only, gone when the app quits.
public final class EphemeralSettings: SettingsStore {
    private var values: [String: Any] = [:]
    public init() {}
    public func object(forKey key: String) -> Any? { values[key] }
    public func set(_ value: Any?, forKey key: String) { values[key] = value }
}

/// Settings, Quick opener: a shortcut that brings up the accounts from any app. Off by default, suggesting
/// Control-Option-Space. Kept in this Mac's defaults, not in state.json: a shortcut belongs to a keyboard and its apps.
@MainActor @Observable
public final class QuickOpener {
    public static let sectionTitle = "Quick opener"
    public static let settingTitle = "Show the quick opener with"
    public static let caption = "Brings up your accounts from any app. Needs no special permission."
    public static let recordingLabel = "Type a shortcut"
    public static let needsModifier = "Use ⌘, ⌃ or ⌥ with a key."
    public static let taken = "Another app already uses this shortcut. Choose another one."
    public static let appCommand = "Apps use ⌘ and a letter for their own commands. Add ⌃ or ⌥."

    enum Keys {
        static let on = "quickOpener.on", keyCode = "quickOpener.keyCode", modifiers = "quickOpener.modifiers", key = "quickOpener.key"
    }

    public private(set) var isOn: Bool
    public private(set) var shortcut: HotKeyShortcut
    /// The next key typed becomes the shortcut; the current one is let go meanwhile, so it can be typed again.
    public private(set) var isRecording = false
    /// Why the last key or shortcut was not taken, in one line.
    public private(set) var problem: String?
    /// The shortcut is registered now: the panel comes up from any app.
    public private(set) var isActive = false
    /// What a press does (the panel, see QuickOpenerPanelController).
    @ObservationIgnored public var onPress: @MainActor () -> Void = {}
    @ObservationIgnored private let defaults: any SettingsStore
    @ObservationIgnored private var hotKey: HotKey?

    public init(defaults: any SettingsStore, registrar: any HotKeyRegistrar) {
        self.defaults = defaults
        isOn = defaults.object(forKey: Keys.on) as? Bool ?? false
        shortcut = Self.saved(in: defaults) ?? .suggested
        hotKey = HotKey(registrar: registrar) { [weak self] in self?.onPress() }
    }

    /// This Mac's defaults, except in a capture or a demo, which start off and never write them.
    public nonisolated static func settings(environment: [String: String]) -> any SettingsStore {
        AppLifecycle.isCaptureOrDemo(environment: environment) ? EphemeralSettings() : UserDefaults.standard
    }

    /// At launch: registers the saved shortcut when the opener is on.
    public func start() { apply() }

    public func setOn(_ on: Bool) {
        isOn = on
        defaults.set(on, forKey: Keys.on)
        isRecording = false
        problem = nil
        apply()
    }

    public func beginRecording() {
        isRecording = true
        problem = nil
        apply()
    }

    public func cancelRecording() {
        isRecording = false
        problem = nil
        apply()
    }

    /// A key typed while recording. True once the recording is over (a new shortcut, taken or refused, or Esc).
    @discardableResult
    public func record(keyCode: UInt16, characters: String?, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard isRecording else { return false }
        switch HotKeyShortcut.record(keyCode: keyCode, characters: characters, modifiers: modifiers) {
        case .cancel:
            cancelRecording()
        case .needsModifier:
            problem = Self.needsModifier
            return false
        case .appCommand:
            problem = Self.appCommand
            return false
        case .shortcut(let new):
            isRecording = false
            // While off it cannot be tried: it is saved, and tried when the opener is turned on.
            if !isOn || hotKey?.set(new) == true {
                shortcut = new
                save(new)
                problem = nil
            } else {
                problem = Self.taken
            }
            apply()
        }
        return true
    }

    /// Brainmerge is being removed: the shortcut goes, and this Mac forgets it.
    public func forget() {
        isOn = false
        isRecording = false
        problem = nil
        apply()
        for key in [Keys.on, Keys.keyCode, Keys.modifiers, Keys.key] { defaults.set(nil, forKey: key) }
    }

    private func apply() {
        let wanted = isOn && !isRecording ? shortcut : nil
        if hotKey?.set(wanted) == false { problem = Self.taken }
        let active = hotKey?.registered != nil
        if active != isActive { isActive = active }
    }

    private func save(_ shortcut: HotKeyShortcut) {
        defaults.set(Int(shortcut.keyCode), forKey: Keys.keyCode)
        defaults.set(Int(shortcut.modifiers), forKey: Keys.modifiers)
        defaults.set(shortcut.key, forKey: Keys.key)
    }

    /// The saved shortcut, when it is a valid one.
    static func saved(in defaults: any SettingsStore) -> HotKeyShortcut? {
        guard let code = defaults.object(forKey: Keys.keyCode) as? Int, let bits = defaults.object(forKey: Keys.modifiers) as? Int,
              let key = defaults.object(forKey: Keys.key) as? String, (0..<128).contains(code), (0...0xFFFF).contains(bits) else { return nil }
        let shortcut = HotKeyShortcut(keyCode: UInt32(code), modifiers: UInt32(bits), key: key)
        return shortcut.isValid ? shortcut : nil
    }
}

/// What a press of the shortcut does: the panel comes up, or goes when it shows. Before the screens are there (the
/// splash, the guide, an unreadable list of accounts) there is nothing to list: the window comes forward instead.
public enum QuickOpenerPress: Equatable, Sendable {
    case showPanel, closePanel, showWindow
    public static func response(setupDone: Bool, panelShown: Bool) -> QuickOpenerPress {
        if panelShown { return .closePanel }
        return setupDone ? .showPanel : .showWindow
    }
}
