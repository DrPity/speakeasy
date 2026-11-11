import CoreGraphics

/// Turns raw keyboard events into "pressed" and "released" for the talk key.
///
/// Kept free of the event tap itself so the rules can be unit-tested. The one
/// rule that matters most: **once the key is held, its key-up always ends the
/// hold**, whatever modifiers are down by then. Releasing ⌥ a moment before F5
/// (for an ⌥F5 binding), or touching Shift mid-dictation, must never leave the
/// microphone running.
public struct PushToTalkMatcher {

    public enum EventKind: Sendable {
        case keyDown
        case keyUp
        case flagsChanged
    }

    public enum Action: Equatable, Sendable {
        case none
        case press
        case release
    }

    public struct Decision: Equatable, Sendable {
        public let action: Action
        /// True when the event belongs to the talk key and must not reach the
        /// focused app.
        public let consume: Bool

        public init(action: Action, consume: Bool) {
            self.action = action
            self.consume = consume
        }

        public static let ignore = Decision(action: .none, consume: false)
    }

    public var shortcut: Shortcut {
        didSet { isHeld = false }
    }

    public private(set) var isHeld = false

    public init(shortcut: Shortcut) {
        self.shortcut = shortcut
    }

    public mutating func handle(
        _ kind: EventKind,
        keyCode: Int64,
        flags: CGEventFlags,
        isRepeat: Bool = false
    ) -> Decision {
        if let target = shortcut.keyCode {
            guard keyCode == target else { return .ignore }
            switch kind {
            case .keyDown:
                // While held, every down event of the key (autorepeat, or one
                // whose modifiers changed mid-hold) is ours and is swallowed.
                if isHeld { return Decision(action: .none, consume: true) }
                guard shortcut.modifiersSatisfied(by: flags) else { return .ignore }
                if isRepeat { return Decision(action: .none, consume: true) }
                isHeld = true
                return Decision(action: .press, consume: true)
            case .keyUp:
                // The key-up ends the hold on key code alone; requiring the
                // modifiers here is what used to leave dictation running.
                if isHeld {
                    isHeld = false
                    return Decision(action: .release, consume: true)
                }
                return shortcut.modifiersSatisfied(by: flags)
                    ? Decision(action: .none, consume: true)
                    : .ignore
            case .flagsChanged:
                return .ignore
            }
        }

        // Modifier-only binding, recognised through flagsChanged. Modifier
        // events are never consumed.
        guard kind == .flagsChanged else { return .ignore }
        let relevant = shortcut.modifiers.intersection(Shortcut.relevantModifiers)
        guard !relevant.isEmpty else { return .ignore }
        let pressed = flags.isSuperset(of: relevant)
        if pressed, !isHeld {
            isHeld = true
            return Decision(action: .press, consume: false)
        }
        if !pressed, isHeld {
            isHeld = false
            return Decision(action: .release, consume: false)
        }
        return .ignore
    }

    /// macOS switched the event tap off (it does so when the tap stalls, or on
    /// some user input). Any key-up sent meanwhile is lost, so a hold in
    /// progress is ended rather than left running with nobody to stop it.
    public mutating func tapInterrupted() -> Action {
        guard isHeld else { return .none }
        isHeld = false
        return .release
    }

    public mutating func reset() {
        isHeld = false
    }
}
