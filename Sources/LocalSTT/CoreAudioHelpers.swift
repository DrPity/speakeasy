import AVFoundation
import CoreAudio

/// CoreAudio plumbing that feeds a selected input device into an `AVAudioEngine`.
enum CoreAudioHelpers {

    /// Convert an `AVCaptureDevice.uniqueID` (a CFString UID) to a CoreAudio
    /// `AudioDeviceID` through `kAudioHardwarePropertyTranslateUIDToDevice`.
    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioDeviceID(0)
        var cfUID = uid as CFString
        let inSize = UInt32(MemoryLayout<CFString>.size)
        var outSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = withUnsafeMutablePointer(to: &cfUID) { uidPtr -> OSStatus in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                inSize,
                uidPtr,
                &outSize,
                &deviceID
            )
        }

        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    /// Assign the engine's input device. Has to run prior to installing any tap
    /// or starting the engine.
    static func setInputDevice(_ id: AudioDeviceID, on engine: AVAudioEngine) throws {
        guard let audioUnit = engine.inputNode.audioUnit else {
            throw NSError(domain: "LocalSTT", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "The input node exposes no audio unit."])
        }
        var deviceID = id
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Could not assign the input device (status \(status))."])
        }
    }
}
