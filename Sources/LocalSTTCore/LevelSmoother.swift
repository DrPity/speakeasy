import Foundation

/// Eases a jittery input level into something visually pleasing.
///
/// Speech RMS jumps around sharply between frames, and with the engine reporting
/// only ~20 times a second, piping it straight into the UI appears shaky. Rise
/// and fall are intentionally uneven — fast to chase a peak, slow to settle —
/// mirroring how audio meters have always worked and why they feel responsive
/// instead of jumpy.
public struct LevelSmoother {
    /// The share of the outstanding gap closed per update on the way up.
    /// At the engine's ~20 Hz that covers most of the gap within roughly 150 ms.
    public static let defaultAttack: Float = 0.6
    /// The equivalent on the way down: a decay of about 300 ms.
    public static let defaultRelease: Float = 0.12

    /// Under this gap the value snaps, letting bars genuinely come to rest
    /// instead of decaying toward zero eternally.
    private static let snapThreshold: Float = 0.001

    public let attack: Float
    public let release: Float
    public private(set) var value: Float = 0

    public init(attack: Float = defaultAttack, release: Float = defaultRelease) {
        self.attack = min(max(attack, 0), 1)
        self.release = min(max(release, 0), 1)
    }

    /// Move one step nearer `target` (limited to 0...1) and hand back the
    /// resulting value.
    @discardableResult
    public mutating func update(toward target: Float) -> Float {
        let clamped = min(max(target, 0), 1)
        let coefficient = clamped > value ? attack : release
        value += (clamped - value) * coefficient
        if abs(clamped - value) < Self.snapThreshold {
            value = clamped
        }
        return value
    }

    public mutating func reset() {
        value = 0
    }
}
