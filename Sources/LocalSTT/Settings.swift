import Foundation
import Observation

/// All of the app's optional behaviour, stored in `UserDefaults`.
///
/// The defaults intentionally mirror how the app originally behaved:
/// hold-to-talk, keystroke delivery, en-US, and no vocabulary, history or login
/// item. Anyone who never visits the preferences notices no difference. The
/// single exception is the input level meter, enabled because it neither costs
/// nor exposes anything.
@MainActor
@Observable
final class Settings {

    enum InputMode: String, CaseIterable, Identifiable {
        case pushToTalk
        case toggle

        var id: String { rawValue }
        var label: String {
            switch self {
            case .pushToTalk: return "Hold the key to speak"
            case .toggle: return "Tap once to begin, tap again to end"
            }
        }
    }

    enum InjectionMethod: String, CaseIterable, Identifiable {
        case keystrokes
        case paste

        var id: String { rawValue }
        var label: String {
            switch self {
            case .keystrokes: return "Simulated typing"
            case .paste: return "Clipboard paste"
            }
        }
    }

    private enum Key {
        static let inputMode = "inputMode"
        static let cancelWithEscape = "cancelWithEscape"
        static let injectionMethod = "injectionMethod"
        static let vocabularyEnabled = "vocabularyEnabled"
        static let replacementsEnabled = "replacementsEnabled"
        static let historyEnabled = "historyEnabled"
        static let levelMeterEnabled = "levelMeterEnabled"
        static let localeIdentifier = "localeIdentifier"
    }

    nonisolated static let defaultLocaleIdentifier = "en-US"

    private let defaults: UserDefaults

    var inputMode: InputMode {
        didSet { defaults.set(inputMode.rawValue, forKey: Key.inputMode) }
    }

    /// Lets Escape throw away the active dictation rather than typing it.
    /// Disabled by default: switching this on means the app consumes Escape —
    /// though solely during the brief window a dictation runs.
    var cancelWithEscape: Bool {
        didSet { defaults.set(cancelWithEscape, forKey: Key.cancelWithEscape) }
    }

    var injectionMethod: InjectionMethod {
        didSet { defaults.set(injectionMethod.rawValue, forKey: Key.injectionMethod) }
    }

    var vocabularyEnabled: Bool {
        didSet { defaults.set(vocabularyEnabled, forKey: Key.vocabularyEnabled) }
    }

    var replacementsEnabled: Bool {
        didSet { defaults.set(replacementsEnabled, forKey: Key.replacementsEnabled) }
    }

    var historyEnabled: Bool {
        didSet { defaults.set(historyEnabled, forKey: Key.historyEnabled) }
    }

    var levelMeterEnabled: Bool {
        didSet { defaults.set(levelMeterEnabled, forKey: Key.levelMeterEnabled) }
    }

    var localeIdentifier: String {
        didSet { defaults.set(localeIdentifier, forKey: Key.localeIdentifier) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.inputMode = InputMode(rawValue: defaults.string(forKey: Key.inputMode) ?? "") ?? .pushToTalk
        self.cancelWithEscape = defaults.bool(forKey: Key.cancelWithEscape)
        self.injectionMethod = InjectionMethod(rawValue: defaults.string(forKey: Key.injectionMethod) ?? "") ?? .keystrokes
        self.vocabularyEnabled = defaults.bool(forKey: Key.vocabularyEnabled)
        self.replacementsEnabled = defaults.bool(forKey: Key.replacementsEnabled)
        self.historyEnabled = defaults.bool(forKey: Key.historyEnabled)
        // The one preference whose default is true, so it requires an explicit
        // "has never been stored" test rather than the false returned by
        // `bool(forKey:)`.
        self.levelMeterEnabled = defaults.object(forKey: Key.levelMeterEnabled) as? Bool ?? true
        self.localeIdentifier = defaults.string(forKey: Key.localeIdentifier) ?? Self.defaultLocaleIdentifier
    }

    var locale: Locale { Locale(identifier: localeIdentifier) }

    /// The status-line hint appropriate for the active input mode.
    var readyHint: String {
        switch inputMode {
        case .pushToTalk: return "Ready — keep the key held and speak."
        case .toggle: return "Ready — tap the key once to begin."
        }
    }
}
