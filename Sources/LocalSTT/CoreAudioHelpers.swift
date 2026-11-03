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

    /// True for an aggregate device flagged private: one an app (or Core Audio
    /// on its behalf) created for itself, invisible in Audio MIDI Setup.
    static func isPrivateAggregate(uid: String) -> Bool {
        guard let id = deviceID(forUID: uid) else { return false }

        var transportAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &transportAddress, 0, nil, &size, &transport) == noErr,
              transport == kAudioDeviceTransportTypeAggregate else { return false }

        var compositionAddress = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyComposition,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var composition: Unmanaged<CFDictionary>?
        size = UInt32(MemoryLayout<Unmanaged<CFDictionary>?>.size)
        guard AudioObjectGetPropertyData(id, &compositionAddress, 0, nil, &size, &composition) == noErr,
              let dictionary = composition?.takeRetainedValue() as? [String: Any] else { return false }
        return (dictionary[kAudioAggregateDeviceIsPrivateKey] as? NSNumber)?.boolValue ?? false
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
