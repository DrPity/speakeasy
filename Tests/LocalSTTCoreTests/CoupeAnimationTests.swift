import Foundation
import Testing
@testable import LocalSTTCore

@Suite("CoupeAnimation")
struct CoupeAnimationTests {

    @Test("An idle or blocked glass is empty")
    func emptyWhenNotDictating() {
        #expect(CoupeAnimation.surfaceY(mode: .idle, level: 1, time: 0) == nil)
        #expect(CoupeAnimation.surfaceY(mode: .needsSetup, level: 1, time: 0) == nil)
    }

    @Test("Louder voice raises the liquid, within the bowl")
    func liquidFollowsLevel() throws {
        let quiet = try #require(CoupeAnimation.surfaceY(mode: .listening, level: 0, time: 0))
        let half = try #require(CoupeAnimation.surfaceY(mode: .listening, level: 0.5, time: 0))
        let loud = try #require(CoupeAnimation.surfaceY(mode: .listening, level: 1, time: 0))
        #expect(quiet > half && half > loud)   // smaller y is higher
        #expect(loud >= 6 && quiet <= 14.5)     // rim … bottom
    }

    @Test("Out-of-range levels are clamped", arguments: [-3.0, 7.0, Double.nan, Double.infinity])
    func clampsLevel(level: Double) throws {
        let y = try #require(CoupeAnimation.surfaceY(mode: .listening, level: level, time: 0))
        #expect(y >= CoupeAnimation.loudSurfaceY && y <= CoupeAnimation.quietSurfaceY)
    }

    @Test("Draining stays low in the glass")
    func finishingBob() throws {
        for step in 0..<20 {
            let y = try #require(CoupeAnimation.surfaceY(mode: .finishing, level: 1, time: Double(step) * 0.07))
            #expect(y >= 10.9 && y <= 12.7)
        }
    }

    @Test("Bubbles appear only while listening, rise, and stay visible-range")
    func bubblesRise() {
        #expect(CoupeAnimation.bubbles(mode: .idle, time: 0.3).isEmpty)
        #expect(CoupeAnimation.bubbles(mode: .finishing, time: 0.3).isEmpty)

        let early = CoupeAnimation.bubbles(mode: .listening, time: 0.1)[0]
        let later = CoupeAnimation.bubbles(mode: .listening, time: 0.9)[0]
        #expect(later.y < early.y)
        for t in stride(from: 0.0, to: 3.0, by: 0.05) {
            for bubble in CoupeAnimation.bubbles(mode: .listening, time: t) {
                #expect(bubble.opacity >= 0 && bubble.opacity <= 1)
                #expect(bubble.y <= 5 && bubble.y >= 0.8)
            }
        }
    }

    @Test("The wave offset wraps instead of growing without bound")
    func waveOffsetWraps() {
        let offset = CoupeAnimation.waveOffset(time: 10_000)
        #expect(offset >= 0 && offset < CoupeAnimation.wavelength)
    }
}
