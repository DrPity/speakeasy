import Foundation

/// Decides which format the microphone tap must request, checked before every
/// dictation.
///
/// On macOS, `AVAudioEngine` pairs the input device with the output device.
/// When the two run at different sample rates (say the mic at 48 kHz and the
/// speakers at 44.1 kHz), the input node *reports* the output's rate. A tap
/// installed at that reported rate fails without throwing — the engine only
/// logs "Failed to create tap, config change pending!" — so the mic runs but
/// no audio ever reaches the recognizer. Requesting the hardware rate instead
/// works whether or not the rates match.
public enum CaptureFormatPolicy {

    public struct Plan: Equatable, Sendable {
        /// The sample rate the tap must request.
        public let sampleRate: Double
        /// The channel count the tap must request.
        public let channels: UInt32
        /// True when the reported rate disagreed with the hardware and the
        /// hardware rate was chosen instead (worth logging; not an error).
        public let correctedMismatch: Bool
    }

    /// - Parameters:
    ///   - hardwareRate / hardwareChannels: `inputNode.inputFormat(forBus: 0)`,
    ///     what the device actually delivers.
    ///   - reportedRate / reportedChannels: `inputNode.outputFormat(forBus: 0)`,
    ///     what the engine claims it will hand to a tap.
    /// - Returns: `nil` when neither side describes a usable format (typically
    ///   a device that vanished or is still waking up).
    public static func plan(
        hardwareRate: Double,
        hardwareChannels: UInt32,
        reportedRate: Double,
        reportedChannels: UInt32
    ) -> Plan? {
        let hardwareValid = hardwareRate.isFinite && hardwareRate > 0
        let reportedValid = reportedRate.isFinite && reportedRate > 0

        let sampleRate: Double
        if hardwareValid {
            sampleRate = hardwareRate
        } else if reportedValid {
            sampleRate = reportedRate
        } else {
            return nil
        }

        // The reported channel count is what the original pipeline always used
        // (and what multi-channel interfaces need); fall back to the hardware.
        let channels = reportedChannels > 0 ? reportedChannels : hardwareChannels
        guard channels > 0 else { return nil }

        return Plan(
            sampleRate: sampleRate,
            channels: channels,
            correctedMismatch: hardwareValid && reportedValid && hardwareRate != reportedRate
        )
    }
}
