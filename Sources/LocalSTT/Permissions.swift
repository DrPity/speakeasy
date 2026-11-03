import AppKit
import ApplicationServices
import AVFoundation
import Observation
import Speech

/// Asks for and monitors the app's macOS permissions.
/// - Microphone and Speech Recognition gate the transcription itself.
/// - Accessibility gates the system-wide shortcut plus auto-typing.
@MainActor
@Observable
final class PermissionsModel {
    enum State {
        case unknown
        case requesting
        case granted
        case denied(String)
    }

    /// State of the microphone and speech-recognition gate.
    var state: State = .unknown

    /// Each permission on its own, for the onboarding checklist.
    enum Grant: Equatable {
        case granted
        case denied
        case undetermined
    }
    private(set) var microphone: Grant = PermissionsModel.micGrant()
    private(set) var speech: Grant = PermissionsModel.speechGrant()

    /// State of the Accessibility (control-the-computer) gate behind the event
    /// tap and typing.
    var accessibilityGranted: Bool = AXIsProcessTrusted()

    // MARK: - Microphone + Speech

    func request() async {
        state = .requesting

        defer { refreshGrants() }
        let micGranted = await AVCaptureDevice.requestAccess(for: .audio)
        guard micGranted else {
            state = .denied("Microphone permission was refused. Turn it on via System Settings ▸ Privacy & Security ▸ Microphone.")
            return
        }

        let speechStatus = await Self.requestSpeechAuthorization()
        switch speechStatus {
        case .authorized:
            state = .granted
        case .denied, .restricted:
            state = .denied("Speech Recognition permission was refused. Turn it on via System Settings ▸ Privacy & Security ▸ Speech Recognition.")
        case .notDetermined:
            state = .denied("Speech Recognition permission came back undecided. Please retry.")
        @unknown default:
            state = .denied("Speech Recognition can't be used.")
        }
    }

    /// Refresh the *current* mic and speech authorisation state silently.
    /// Bounces back from a previous "refused" state once the user enables the
    /// toggle in System Settings — no restart required.
    func recheck() {
        accessibilityGranted = AXIsProcessTrusted()
        refreshGrants()

        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        let speech = SFSpeechRecognizer.authorizationStatus()

        if mic == .authorized && speech == .authorized {
            state = .granted
        } else if mic == .denied || mic == .restricted {
            state = .denied("Microphone permission was refused. Allow Speakeasy under System Settings ▸ Privacy & Security ▸ Microphone, then open this panel again.")
        } else if speech == .denied || speech == .restricted {
            state = .denied("Speech Recognition permission was refused. Allow Speakeasy under System Settings ▸ Privacy & Security ▸ Speech Recognition, then open this panel again.")
        } else if case .granted = state {
            // It had been granted, yet a status regressed to notDetermined; start over.
            state = .unknown
        }
        // In every other case keep .unknown/.requesting so request() may still prompt.
    }

    private func refreshGrants() {
        microphone = Self.micGrant()
        speech = Self.speechGrant()
    }

    private static func micGrant() -> Grant {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .undetermined
        @unknown default: return .undetermined
        }
    }

    private static func speechGrant() -> Grant {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .undetermined
        @unknown default: return .undetermined
        }
    }

    private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    var micAndSpeechGranted: Bool {
        if case .granted = state { return true }
        return false
    }

    // MARK: - Accessibility

    /// Refresh the trust state (following a change the user made in System Settings).
    @discardableResult
    func refreshAccessibility() -> Bool {
        accessibilityGranted = AXIsProcessTrusted()
        return accessibilityGranted
    }

    /// Trigger the system's "allow Accessibility" dialog. The user still has to
    /// enable the app inside System Settings; it cannot be granted programmatically.
    func promptAccessibility() {
        let options: NSDictionary = ["AXTrustedCheckOptionPrompt": true]
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - System Settings deep links

    func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openMicrophoneSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    func openSpeechSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

#if DEBUG
extension PermissionsModel {
    /// Snapshot rendering only (`--snapshot`): pretend these grants.
    func overrideForSnapshot(microphone: Grant, speech: Grant, accessibility: Bool) {
        self.microphone = microphone
        self.speech = speech
        accessibilityGranted = accessibility
        state = microphone == .granted && speech == .granted ? .granted : .unknown
    }
}
#endif
