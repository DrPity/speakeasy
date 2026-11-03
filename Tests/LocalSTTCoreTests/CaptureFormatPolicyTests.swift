import Foundation
import Testing
@testable import LocalSTTCore

@Suite("CaptureFormatPolicy")
struct CaptureFormatPolicyTests {

    @Test("Matching rates pass straight through")
    func matchingRates() {
        let plan = CaptureFormatPolicy.plan(
            hardwareRate: 48_000, hardwareChannels: 1,
            reportedRate: 48_000, reportedChannels: 1
        )
        #expect(plan == .init(sampleRate: 48_000, channels: 1, correctedMismatch: false))
    }

    @Test("Mic at 48 kHz, speakers at 44.1 kHz: the hardware rate wins")
    func mismatchUsesHardwareRate() {
        // The exact situation that silently broke dictation on 2026-11-03.
        let plan = CaptureFormatPolicy.plan(
            hardwareRate: 48_000, hardwareChannels: 1,
            reportedRate: 44_100, reportedChannels: 1
        )
        #expect(plan?.sampleRate == 48_000)
        #expect(plan?.correctedMismatch == true)
    }

    @Test("The reported channel count is kept for multi-channel interfaces")
    func keepsReportedChannels() {
        let plan = CaptureFormatPolicy.plan(
            hardwareRate: 48_000, hardwareChannels: 2,
            reportedRate: 48_000, reportedChannels: 4
        )
        #expect(plan?.channels == 4)
    }

    @Test("An unknown hardware rate falls back to the reported one")
    func fallsBackToReportedRate() {
        let plan = CaptureFormatPolicy.plan(
            hardwareRate: 0, hardwareChannels: 0,
            reportedRate: 44_100, reportedChannels: 1
        )
        #expect(plan == .init(sampleRate: 44_100, channels: 1, correctedMismatch: false))
    }

    @Test("A device with no usable format is rejected", arguments: [
        (0.0, UInt32(1), 0.0, UInt32(1)),          // no rate anywhere
        (48_000.0, UInt32(0), 48_000.0, UInt32(0)), // no channels anywhere
        (Double.nan, UInt32(1), 0.0, UInt32(1)),    // garbage rate
    ])
    func rejectsUnusableDevice(hwRate: Double, hwChannels: UInt32, repRate: Double, repChannels: UInt32) {
        #expect(CaptureFormatPolicy.plan(
            hardwareRate: hwRate, hardwareChannels: hwChannels,
            reportedRate: repRate, reportedChannels: repChannels
        ) == nil)
    }
}
