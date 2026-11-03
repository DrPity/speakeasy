import Foundation
import Testing
@testable import LocalSTTCore

@Suite("AudioMixdown")
struct AudioMixdownTests {

    @Test("Single-channel input comes through untouched")
    func monoPassthrough() {
        let result = AudioMixdown.mixToMono(channels: [[0.5, -0.5, 0.25]])
        #expect(result.samples == [0.5, -0.5, 0.25])
    }

    @Test("A pair of channels gets blended evenly")
    func averagesTwoChannels() {
        let result = AudioMixdown.mixToMono(channels: [[1, 0], [0, 1]])
        #expect(result.samples == [0.5, 0.5])
    }

    @Test("Channels past the leading two are left out")
    func ignoresChannelsBeyondTheFirstTwo() {
        // The Scarlett 2i2 scenario: channels 2–3 carry loopback and must stay out.
        let result = AudioMixdown.mixToMono(channels: [
            [1, 1],
            [0, 0],
            [9, 9],
            [-9, -9]
        ])
        #expect(result.samples == [0.5, 0.5])
    }

    @Test("RMS reflects the blended signal")
    func measuresRMS() {
        // A full-scale square wave blends to ±1, giving an RMS of 1.
        #expect(AudioMixdown.mixToMono(channels: [[1, -1, 1, -1]]).rms == 1)
        #expect(AudioMixdown.mixToMono(channels: [[0, 0, 0]]).rms == 0)
        // Blending a channel with silence halves the amplitude — and with it the RMS.
        #expect(AudioMixdown.mixToMono(channels: [[1, -1], [0, 0]]).rms == 0.5)
    }

    @Test("Blank and degenerate buffers cause no harm")
    func handlesEmptyInput() {
        #expect(AudioMixdown.mixToMono(channels: []).rms == 0)
        #expect(AudioMixdown.mixToMono(channels: [[]]).samples.isEmpty)
        #expect(AudioMixdown.mixToMono(channels: [[]]).rms == 0)
    }

    @Test("The meter converts amplitude into a 0...1 decibel-scaled height")
    func mapsMeterLevel() {
        #expect(AudioMixdown.meterLevel(rms: 0) == 0)
        #expect(AudioMixdown.meterLevel(rms: 1) == 1)
        // Levels at or under the floor render as empty.
        #expect(AudioMixdown.meterLevel(rms: 0.0005) == 0)
        // -20 dB against a -60 dB floor lands two thirds of the way up.
        let level = AudioMixdown.meterLevel(rms: 0.1)
        #expect(abs(level - 2.0 / 3.0) < 0.001)
        // It rises steadily in between.
        #expect(AudioMixdown.meterLevel(rms: 0.01) < AudioMixdown.meterLevel(rms: 0.1))
    }
}
