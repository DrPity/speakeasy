import AVFoundation
import CoreAudio
import LocalSTTCore
import Observation

/// Discovers audio input devices, remembers which one is selected (persisted),
/// and resolves its CoreAudio `AudioDeviceID`.
@MainActor
@Observable
final class AudioDeviceManager {
    struct Device: Identifiable, Hashable {
        let id: String      // maps to AVCaptureDevice.uniqueID
        let name: String
    }

    private static let defaultsKey = "selectedMicUID"

    var devices: [Device] = []
    var selectedUID: String = "" {
        didSet {
            guard selectedUID != oldValue else { return }
            UserDefaults.standard.set(selectedUID, forKey: Self.defaultsKey)
        }
    }

    init() {
        refresh()

        // Re-scan the device list on hot-plug events, allowing a microphone
        // attached mid-session to appear with no restart.
        let nc = NotificationCenter.default
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    /// Scan for input devices (again) and settle on a usable selection.
    func refresh() {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        devices = session.devices
            .filter {
                !DeviceSelectionPolicy.isHidden(
                    uid: $0.uniqueID,
                    isPrivateAggregate: CoreAudioHelpers.isPrivateAggregate(uid: $0.uniqueID)
                )
            }
            .map { Device(id: $0.uniqueID, name: $0.localizedName) }

        selectedUID = DeviceSelectionPolicy.resolve(
            saved: UserDefaults.standard.string(forKey: Self.defaultsKey),
            available: devices.map(\.id),
            systemDefault: AVCaptureDevice.default(for: .audio)?.uniqueID
        )
    }

    /// The CoreAudio id behind the current selection, when it can be resolved.
    var selectedDeviceID: AudioDeviceID? {
        guard !selectedUID.isEmpty else { return nil }
        return CoreAudioHelpers.deviceID(forUID: selectedUID)
    }
}
