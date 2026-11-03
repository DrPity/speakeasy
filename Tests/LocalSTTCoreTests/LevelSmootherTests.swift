import Foundation
import Testing
@testable import LocalSTTCore

@Suite("LevelSmoother")
struct LevelSmootherTests {

    @Test("Begins at silence")
    func startsAtZero() {
        #expect(LevelSmoother().value == 0)
    }

    @Test("Climbs toward the goal and never overshoots")
    func risesTowardTarget() {
        var smoother = LevelSmoother()
        #expect(smoother.update(toward: 1) > 0)

        // It neither drops nor crosses the goal, and arrives within a few
        // updates instead of crawling.
        var previous = smoother.value
        for _ in 0..<10 {
            let value = smoother.update(toward: 1)
            #expect(value >= previous)
            #expect(value <= 1)
            previous = value
        }
        #expect(smoother.value == 1)
    }

    @Test("Decay is slower than attack")
    func decaysSlowerThanItAttacks() {
        var rising = LevelSmoother()
        let riseStep = rising.update(toward: 1)

        var falling = LevelSmoother()
        // Drive it to maximum, then observe a single decay step.
        for _ in 0..<60 { falling.update(toward: 1) }
        let peak = falling.value
        let fallStep = peak - falling.update(toward: 0)

        #expect(riseStep > fallStep)
    }

    @Test("Lands precisely on the goal instead of approaching it forever")
    func settlesOnTarget() {
        var smoother = LevelSmoother()
        for _ in 0..<200 { smoother.update(toward: 0.5) }
        #expect(smoother.value == 0.5)

        for _ in 0..<200 { smoother.update(toward: 0) }
        #expect(smoother.value == 0)
    }

    @Test("Values beyond the range get clamped")
    func clampsInput() {
        var smoother = LevelSmoother()
        for _ in 0..<200 { smoother.update(toward: 5) }
        #expect(smoother.value == 1)

        for _ in 0..<200 { smoother.update(toward: -3) }
        #expect(smoother.value == 0)
    }

    @Test("Resetting mutes it at once")
    func resets() {
        var smoother = LevelSmoother()
        for _ in 0..<10 { smoother.update(toward: 1) }
        smoother.reset()
        #expect(smoother.value == 0)
    }

    @Test("Coefficients stay within a sensible range")
    func clampsCoefficients() {
        #expect(LevelSmoother(attack: 9, release: -2).attack == 1)
        #expect(LevelSmoother(attack: 9, release: -2).release == 0)

        // With a zero release it can never decay.
        var stuck = LevelSmoother(attack: 1, release: 0)
        stuck.update(toward: 1)
        stuck.update(toward: 0)
        #expect(stuck.value == 1)
    }
}
