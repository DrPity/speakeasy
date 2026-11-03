import Foundation

/// Mixes multi-channel input down to mono and gauges its level.
///
/// The mix is performed manually instead of delegating to `AVAudioConverter`,
/// whose channel reduction returns silence for devices with discrete,
/// layout-less channels (for instance the Scarlett 2i2's four).
public enum AudioMixdown {
    /// The maximum number of physical channels included in the mix. On the
    /// Scarlett 2i2 4th Gen, channels 0–1 are the analog inputs (the microphone
    /// sits on one of those), whereas channels 2–3 carry loopback/playback and
    /// have to be left out.
    public static let maxMixChannels = 2

    /// Blend the leading `maxMixChannels` channels into `output` and hand back
    /// the RMS of the blended signal.
    ///
    /// Written accessor-style (and `@inlinable`) so the audio-thread caller
    /// specializes down to plain buffer indexing with zero closure allocation,
    /// while tests may supply ordinary arrays. RMS accumulates during the same
    /// traversal as the mix, making metering free of extra passes.
    @inlinable
    @inline(__always)
    public static func mixToMono(
        frameCount: Int,
        channelCount: Int,
        sample: (Int, Int) -> Float,
        output: (Int, Float) -> Void
    ) -> Float {
        guard frameCount > 0, channelCount > 0 else { return 0 }
        let mixCount = min(maxMixChannels, channelCount)
        let scale = Float(1.0 / Double(mixCount))
        var sumSquares: Float = 0
        for frame in 0..<frameCount {
            var sum: Float = 0
            for channel in 0..<mixCount {
                sum += sample(channel, frame)
            }
            let value = sum * scale
            output(frame, value)
            sumSquares += value * value
        }
        return (sumSquares / Float(frameCount)).squareRoot()
    }

    /// An array-based convenience wrapper around the identical implementation.
    /// `channels` is channel-major; all channels need matching frame counts.
    public static func mixToMono(channels: [[Float]]) -> (samples: [Float], rms: Float) {
        let frameCount = channels.first?.count ?? 0
        var samples = [Float](repeating: 0, count: frameCount)
        let rms = mixToMono(
            frameCount: frameCount,
            channelCount: channels.count,
            sample: { channels[$0][$1] },
            output: { samples[$0] = $1 }
        )
        return (samples, rms)
    }

    /// Convert an RMS amplitude into a 0...1 bar height on a decibel scale,
    /// keeping soft speech visible. `floorDB` marks the level rendered as empty.
    public static func meterLevel(rms: Float, floorDB: Float = -60) -> Float {
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        guard db > floorDB else { return 0 }
        return min(1, (db - floorDB) / -floorDB)
    }
}
