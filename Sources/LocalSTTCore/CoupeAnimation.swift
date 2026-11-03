import Foundation

/// The motion of the coupe glyph (menu-bar icon, panel badge, overlay), as
/// pure numbers in the glyph's 24 × 24 design space so it can be unit-tested.
///
/// Geometry it assumes (matching `Resources/AppIcon.svg`, simplified): the bowl
/// rim sits at y = 6, the bowl bottom at y = 14.5; smaller y is higher up.
public enum CoupeAnimation {

    public enum Mode: Equatable, Sendable {
        /// Ready: empty glass with a resting wave line.
        case idle
        /// Dictating: liquid rises with the voice, sloshes, bubbles rise.
        case listening
        /// Released, transcript still draining: liquid sinks and bobs.
        case finishing
        /// A permission is missing: empty glass plus a badge dot.
        case needsSetup
    }

    public struct Bubble: Equatable, Sendable {
        public let x: Double
        public let y: Double
        public let radius: Double
        /// 0...1
        public let opacity: Double
    }

    /// Liquid surface when silent (just above the bowl bottom) and at full voice
    /// (a little under the rim, so the glass never looks overfull).
    public static let quietSurfaceY = 11.2
    public static let loudSurfaceY = 8.2

    public static let wavelength = 7.6
    public static let bubblePeriod = 1.4
    public static let drainPeriod = 1.1

    /// Where the liquid's surface sits, or `nil` when the glass is empty.
    /// - Parameters:
    ///   - level: smoothed input level in 0...1 (anything outside is clamped).
    ///   - time: seconds; only drives the finishing bob.
    public static func surfaceY(mode: Mode, level: Double, time: Double) -> Double? {
        switch mode {
        case .idle, .needsSetup:
            return nil
        case .listening:
            let clamped = level.isFinite ? min(max(level, 0), 1) : 0
            return quietSurfaceY - (quietSurfaceY - loudSurfaceY) * clamped
        case .finishing:
            // Bob between 11.0 and 12.6: low in the glass, visibly "going".
            return 11.8 + 0.8 * sin(time * 2 * .pi / drainPeriod)
        }
    }

    /// Height of the surface wave; calmer while draining.
    public static func waveAmplitude(mode: Mode) -> Double {
        switch mode {
        case .listening: return 0.7
        case .finishing: return 0.35
        case .idle, .needsSetup: return 0.55
        }
    }

    /// Horizontal shift of the wave, so it travels across the glass.
    public static func waveOffset(time: Double) -> Double {
        let speed = 6.0   // glyph units per second
        return (time * speed).truncatingRemainder(dividingBy: wavelength)
    }

    /// The surface's height at `x` for a wave whose resting line is `baseline`.
    public static func waveY(x: Double, baseline: Double, amplitude: Double, offset: Double) -> Double {
        baseline + amplitude * sin((x + offset) / wavelength * 2 * .pi)
    }

    /// Bubbles above the rim while listening; none otherwise.
    public static func bubbles(mode: Mode, time: Double) -> [Bubble] {
        guard mode == .listening else { return [] }
        return [
            bubble(x: 15.0, radius: 1.1, time: time, delay: 0),
            bubble(x: 17.6, radius: 0.8, time: time, delay: bubblePeriod / 2),
        ]
    }

    private static func bubble(x: Double, radius: Double, time: Double, delay: Double) -> Bubble {
        var progress = ((time + delay) / bubblePeriod).truncatingRemainder(dividingBy: 1)
        if progress < 0 { progress += 1 }
        // Rise from just above the rim (y 5) to above the glass (y 0.8),
        // fading in over the first quarter and out over the rest.
        let y = 5.0 - 4.2 * progress
        let opacity = progress < 0.25 ? progress / 0.25 : 1 - (progress - 0.25) / 0.75
        return Bubble(x: x, y: y, radius: radius, opacity: min(max(opacity, 0), 1))
    }
}
