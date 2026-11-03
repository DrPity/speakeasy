import CoreGraphics
import Foundation

/// A stored push-to-talk binding: a virtual key code together with the modifier
/// flags it demands. A `keyCode` of `nil` denotes a modifier-only binding (say,
/// Control by itself).
public struct Shortcut: Equatable {
    public var keyCode: Int64?
    public var modifiers: CGEventFlags

    public init(keyCode: Int64?, modifiers: CGEventFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// The factory default: F5 (virtual key 96) without modifiers.
    public static let defaultShortcut = Shortcut(keyCode: 96, modifiers: [])

    /// The modifier bits taken into account during comparison. Device-specific
    /// left/right bits and caps lock are intentionally left out — `CGEventFlags`
    /// carries no left/right information, meaning "Right Control" can only ever
    /// match "Control".
    public static let relevantModifiers: CGEventFlags = [
        .maskCommand, .maskShift, .maskAlternate, .maskControl
    ]

    /// True while precisely the stored modifier combination is down.
    public func modifiersSatisfied(by flags: CGEventFlags) -> Bool {
        flags.intersection(Self.relevantModifiers) == modifiers.intersection(Self.relevantModifiers)
    }

    /// True when the binding holds neither a key nor modifiers — in other words
    /// it can never trigger.
    public var isEmpty: Bool {
        keyCode == nil && modifiers.intersection(Self.relevantModifiers).isEmpty
    }
}

// MARK: - Display

extension Shortcut {
    /// The user-facing representation, such as "⌥F5", "Space" or "⌃".
    public var displayString: String {
        var parts = ""
        if modifiers.contains(.maskControl) { parts += "⌃" }
        if modifiers.contains(.maskAlternate) { parts += "⌥" }
        if modifiers.contains(.maskShift) { parts += "⇧" }
        if modifiers.contains(.maskCommand) { parts += "⌘" }
        if let keyCode {
            parts += Self.keyName(for: keyCode)
        }
        return parts.isEmpty ? "—" : parts
    }

    private static func keyName(for code: Int64) -> String {
        if let name = specialKeys[code] { return name }
        return "Key \(code)"
    }

    private static let specialKeys: [Int64: String] = [
        49: "Space", 36: "↩", 48: "⇥", 53: "⎋", 51: "⌫",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15"
    ]
}

// MARK: - Persistence

/// Reads and writes a `Shortcut` inside a `UserDefaults` suite. The suite arrives
/// as a parameter (instead of hardcoding `.standard`) so tests can supply a
/// disposable one.
public enum ShortcutStore {
    public static let keyCodeKey = "hotkeyKeyCode"
    public static let modifiersKey = "hotkeyModifiers"
    /// Written in lieu of a key code for modifier-only bindings.
    public static let modifierOnlySentinel = -1

    public static func load(from defaults: UserDefaults) -> Shortcut {
        guard defaults.object(forKey: keyCodeKey) != nil else {
            return .defaultShortcut
        }
        let storedKey = defaults.integer(forKey: keyCodeKey)
        let modifiers = CGEventFlags(rawValue: UInt64(defaults.integer(forKey: modifiersKey)))
        let keyCode: Int64? = storedKey == modifierOnlySentinel ? nil : Int64(storedKey)
        return Shortcut(keyCode: keyCode, modifiers: modifiers)
    }

    public static func save(_ shortcut: Shortcut, to defaults: UserDefaults) {
        defaults.set(Int(shortcut.keyCode ?? Int64(modifierOnlySentinel)), forKey: keyCodeKey)
        defaults.set(Int(shortcut.modifiers.rawValue), forKey: modifiersKey)
    }
}
