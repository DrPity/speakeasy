import AppKit
import LocalSTTCore
import Observation
import SwiftUI

/// Central coordinator: holds every subsystem and connects the push-to-talk
/// pipeline. Shortcut press → capture → transform → deliver.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let settings = Settings()
    let engine: TranscriberEngine
    let devices = AudioDeviceManager()
    let permissions = PermissionsModel()
    let hotkey = HotkeyManager()
    let hud = HUDController()

    /// Memory-resident only, and filled solely when the user enables history.
    var history = TranscriptHistory()
    private(set) var vocabulary = Vocabulary()
    private(set) var vocabularyError: String?

    /// Languages the speech framework is able to handle, feeding the language picker.
    private(set) var supportedLocales: [Locale] = []
    private(set) var installedLocaleIdentifiers: Set<String> = []
    private(set) var isSwitchingLocale = false

    /// When the current (or last) dictation began; drives the overlay's timer.
    private(set) var sessionStartedAt: Date?
    /// The text just delivered, shown by the overlay until it fades. Memory
    /// only and cleared as soon as the overlay hides.
    private(set) var hudDelivered: String?
    /// Clock for the menu-bar icon animation; advances only while animating.
    private(set) var iconTime: Double = 0
    @ObservationIgnored private var iconTimer: Timer?

    private let vocabularyStore: VocabularyStore
    private var didWire = false
    private var didLaunch = false
    /// Delay before dismissing the HUD once a session ends, leaving the result readable.
    private static let hudLinger: TimeInterval = 1.2

    init() {
        let settings = self.settings
        self.engine = TranscriberEngine(locale: settings.locale)
        self.vocabularyStore = VocabularyStore(
            directory: VocabularyStore.defaultDirectory(
                bundleID: Bundle.main.bundleIdentifier ?? "com.mschade.localstt"
            )
        )

        loadVocabulary()
        syncFromSettings()
        wire()
        // IMPORTANT: permissions must not be requested here — `init` executes
        // prior to launch completing, and a premature TCC prompt may silently
        // come back "denied" without ever appearing. The request is made from
        // `AppDelegate.applicationDidFinishLaunching` (onLaunch), and
        // `refreshAndAdvance` picks things up again when the panel opens or the
        // app becomes active.

        // Re-evaluate permissions and state each time the app comes to the
        // front (say, right after the user flips a switch in System Settings).
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAndAdvance() }
        }
    }

    private func wire() {
        guard !didWire else { return }
        didWire = true

        engine.onFinalText = { [weak self] text in
            guard let self else { return }
            let final = self.settings.replacementsEnabled
                ? TextTransformer.apply(self.vocabulary.rules, to: text)
                : text
            guard !final.isEmpty else { return }
            self.hudDelivered = final
            if self.settings.historyEnabled {
                self.history.record(final)
            }
            let injector = self.injector
            Task { await injector.inject(final) }
        }

        engine.onSessionEnd = { [weak self] in
            guard let self else { return }
            // Leave the overlay visible for a moment so the result can be read,
            // then dismiss it (provided another dictation hasn't begun).
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.hudLinger) { [weak self] in
                guard let self, !self.engine.isRecording else { return }
                self.hud.hide()
                self.hudDelivered = nil
            }
        }

        hotkey.onPress = { [weak self] in
            guard let self, self.engine.modelReady else { return }
            switch self.settings.inputMode {
            case .pushToTalk:
                self.beginSession()
            case .toggle:
                if self.engine.isRecording {
                    self.engine.stop()
                } else {
                    self.beginSession()
                }
            }
        }

        hotkey.onRelease = { [weak self] in
            guard let self, self.settings.inputMode == .pushToTalk else { return }
            self.engine.stop()
        }

        hotkey.onCancel = { [weak self] in
            guard let self else { return }
            self.engine.cancel()
            self.hud.hide()
            self.hudDelivered = nil
        }

        hotkey.shouldInterceptEscape = { [weak self] in
            guard let self else { return false }
            return self.settings.cancelWithEscape && self.engine.isRecording
        }
    }

    /// Pass the engine its settings-derived inputs, then begin capturing.
    private func beginSession() {
        syncFromSettings()
        hudDelivered = nil
        sessionStartedAt = Date()
        hud.show()
        engine.start(deviceID: devices.selectedDeviceID)
        startIconAnimation()
    }

    /// Ask for microphone + speech again (the onboarding checklist's button),
    /// then carry on as far as the grants allow.
    func requestPermissions() {
        Task {
            await permissions.request()
            if permissions.micAndSpeechGranted, !engine.modelReady {
                await engine.prepareModel(locale: settings.locale)
            }
            startHotkeyIfPossible()
        }
    }

    private var injector: TextInjecting {
        switch settings.injectionMethod {
        case .keystrokes: return KeystrokeInjector()
        case .paste: return PasteInjector()
        }
    }

    /// Forward the values the engine cares about. Inexpensive; call freely.
    func syncFromSettings() {
        engine.readyHint = settings.readyHint
        engine.meterEnabled = settings.levelMeterEnabled
        engine.contextualTerms = settings.vocabularyEnabled ? vocabulary.contextualTerms : []
    }

    /// Invoked a single time, right after launch completes.
    func onLaunch() async {
        guard !didLaunch else { return }
        didLaunch = true
        await permissions.request()
        if permissions.micAndSpeechGranted {
            await engine.prepareModel(locale: settings.locale)
        }
        startHotkeyIfPossible()
        await refreshLocales()
    }

    /// Re-read *every* permission from current TCC state and proceed as far as
    /// the existing grants permit. May be called over and over (panel shown, app
    /// activated). Bounces back from a previous refusal once the user enables it
    /// in System Settings.
    func refreshAndAdvance() {
        #if DEBUG
        if SnapshotRenderer.isActive { return }   // never prompt while rendering snapshots
        #endif
        syncFromSettings()
        permissions.recheck()
        if permissions.micAndSpeechGranted {
            if !engine.modelReady {
                Task { await engine.prepareModel(locale: settings.locale) }
            }
        } else if case .unknown = permissions.state {
            // Nothing decided yet — fire the system prompts (again).
            Task {
                await permissions.request()
                if permissions.micAndSpeechGranted, !engine.modelReady {
                    await engine.prepareModel(locale: settings.locale)
                }
                startHotkeyIfPossible()
            }
        }
        startHotkeyIfPossible()
    }

    private func startHotkeyIfPossible() {
        if permissions.accessibilityGranted {
            hotkey.start()
        }
    }

    // MARK: - Vocabulary

    private func loadVocabulary() {
        do {
            vocabulary = try vocabularyStore.load()
            vocabularyError = nil
        } catch {
            vocabulary = .empty
            vocabularyError = "The vocabulary file couldn't be loaded: \(error.localizedDescription)"
        }
    }

    func updateVocabulary(_ newValue: Vocabulary) {
        vocabulary = newValue
        syncFromSettings()
        do {
            try vocabularyStore.save(newValue)
            vocabularyError = nil
        } catch {
            vocabularyError = "The vocabulary couldn't be written: \(error.localizedDescription)"
        }
    }

    // MARK: - Language

    func refreshLocales() async {
        supportedLocales = await TranscriberEngine.supportedLocales()
            .sorted { TranscriberEngine.displayName(for: $0) < TranscriberEngine.displayName(for: $1) }
        installedLocaleIdentifiers = Set(
            await TranscriberEngine.installedLocales().map { $0.identifier(.bcp47) }
        )
    }

    /// Change the transcription language, fetching its model when required.
    func selectLocale(_ identifier: String) async {
        guard !engine.isRecording, identifier != settings.localeIdentifier else { return }
        settings.localeIdentifier = identifier
        isSwitchingLocale = true
        await engine.prepareModel(locale: settings.locale)
        await refreshLocales()
        isSwitchingLocale = false
    }

    // MARK: - Menu-bar icon

    enum IconState {
        case needsPermission
        case ready
        case listening
        case finalizing
    }

    var iconState: IconState {
        if case .denied = permissions.state { return .needsPermission }
        if !permissions.micAndSpeechGranted { return .needsPermission }
        if !permissions.accessibilityGranted { return .needsPermission }
        if engine.isRecording { return .listening }
        if engine.state == .finalizing || engine.state == .cancelling { return .finalizing }
        return .ready
    }

    /// The coupe glyph's mode for the menu bar, the panel badge and the overlay.
    var coupeMode: CoupeAnimation.Mode {
        switch iconState {
        case .needsPermission: return .needsSetup
        case .ready: return .idle
        case .listening: return .listening
        case .finalizing: return .finishing
        }
    }

    /// Indicates whether the menu-bar icon should be animating.
    var isAnimating: Bool {
        iconState == .listening || iconState == .finalizing
    }

    /// The menu-bar label can't run SwiftUI animations itself (macOS snapshots
    /// it into the status item), so a timer advances `iconTime` and the label
    /// redraws its image. ~15 fps, only while dictating; it stops itself.
    private func startIconAnimation() {
        guard iconTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickIcon() }
        }
        RunLoop.main.add(timer, forMode: .common)   // keep ticking while the panel is open
        iconTimer = timer
    }

    private func tickIcon() {
        // `.starting` counts as recording, so the first ticks don't stop it.
        if isAnimating {
            iconTime = Date.timeIntervalSinceReferenceDate
        } else {
            iconTimer?.invalidate()
            iconTimer = nil
            iconTime = 0
        }
    }

    var hotkeyReady: Bool {
        permissions.accessibilityGranted && hotkey.isActive
    }
}

#if DEBUG
extension AppModel {
    /// Snapshot rendering only (`--snapshot`). Never saves the vocabulary.
    func overrideForSnapshot(vocabulary: Vocabulary? = nil, delivered: String?, sessionStart: Date?) {
        if let vocabulary { self.vocabulary = vocabulary }
        hudDelivered = delivered
        sessionStartedAt = sessionStart
    }
}
#endif
