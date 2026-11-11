import CoreGraphics
import Testing
@testable import LocalSTTCore

@Suite("PushToTalkMatcher")
struct PushToTalkMatcherTests {

    private let f5: Int64 = 96
    private let optionKey: Int64 = 58
    private let controlKey: Int64 = 59

    @Test("Holding and releasing the plain talk key presses and releases, swallowing both")
    func plainKeyPressRelease() {
        var matcher = PushToTalkMatcher(shortcut: .defaultShortcut)
        #expect(matcher.handle(.keyDown, keyCode: f5, flags: []) == .init(action: .press, consume: true))
        #expect(matcher.isHeld)
        #expect(matcher.handle(.keyUp, keyCode: f5, flags: []) == .init(action: .release, consume: true))
        #expect(!matcher.isHeld)
    }

    @Test("Letting go of the modifier before the key still ends the hold")
    func modifierReleasedFirst() {
        var matcher = PushToTalkMatcher(shortcut: Shortcut(keyCode: f5, modifiers: [.maskAlternate]))
        #expect(matcher.handle(.keyDown, keyCode: f5, flags: [.maskAlternate]).action == .press)
        #expect(matcher.handle(.flagsChanged, keyCode: optionKey, flags: []) == .ignore)
        #expect(matcher.handle(.keyUp, keyCode: f5, flags: []) == .init(action: .release, consume: true))
        #expect(!matcher.isHeld)
    }

    @Test("Touching Shift during the hold neither leaks the key nor blocks the release")
    func extraModifierMidHold() {
        var matcher = PushToTalkMatcher(shortcut: .defaultShortcut)
        _ = matcher.handle(.keyDown, keyCode: f5, flags: [])
        #expect(matcher.handle(.keyDown, keyCode: f5, flags: [.maskShift], isRepeat: true)
                == .init(action: .none, consume: true))
        #expect(matcher.handle(.keyUp, keyCode: f5, flags: [.maskShift]).action == .release)
    }

    @Test("Autorepeat while held is swallowed without a second press")
    func autorepeatIgnored() {
        var matcher = PushToTalkMatcher(shortcut: .defaultShortcut)
        _ = matcher.handle(.keyDown, keyCode: f5, flags: [])
        for _ in 0..<5 {
            #expect(matcher.handle(.keyDown, keyCode: f5, flags: [], isRepeat: true)
                    == .init(action: .none, consume: true))
        }
    }

    @Test("The key with the wrong modifiers is left alone when not held")
    func wrongModifiersPassThrough() {
        var matcher = PushToTalkMatcher(shortcut: Shortcut(keyCode: f5, modifiers: [.maskAlternate]))
        #expect(matcher.handle(.keyDown, keyCode: f5, flags: []) == .ignore)
        #expect(matcher.handle(.keyUp, keyCode: f5, flags: []) == .ignore)
        #expect(!matcher.isHeld)
    }

    @Test("Other keys are never touched")
    func otherKeysIgnored() {
        var matcher = PushToTalkMatcher(shortcut: .defaultShortcut)
        _ = matcher.handle(.keyDown, keyCode: f5, flags: [])
        #expect(matcher.handle(.keyDown, keyCode: 0, flags: []) == .ignore)
        #expect(matcher.handle(.keyUp, keyCode: 0, flags: []) == .ignore)
        #expect(matcher.isHeld)
    }

    @Test("A disabled event tap ends a hold in progress")
    func tapInterruptionReleases() {
        var matcher = PushToTalkMatcher(shortcut: .defaultShortcut)
        #expect(matcher.tapInterrupted() == .none)
        _ = matcher.handle(.keyDown, keyCode: f5, flags: [])
        #expect(matcher.tapInterrupted() == .release)
        #expect(!matcher.isHeld)
        // The late key-up (if it ever arrives) is swallowed but does not release twice.
        #expect(matcher.handle(.keyUp, keyCode: f5, flags: []) == .init(action: .none, consume: true))
    }

    @Test("Rebinding drops a hold in progress")
    func rebindResets() {
        var matcher = PushToTalkMatcher(shortcut: .defaultShortcut)
        _ = matcher.handle(.keyDown, keyCode: f5, flags: [])
        matcher.shortcut = Shortcut(keyCode: 49, modifiers: [])
        #expect(!matcher.isHeld)
    }

    @Test("A modifier-only binding presses and releases without consuming")
    func modifierOnly() {
        var matcher = PushToTalkMatcher(shortcut: Shortcut(keyCode: nil, modifiers: [.maskControl]))
        #expect(matcher.handle(.flagsChanged, keyCode: controlKey, flags: [.maskControl])
                == .init(action: .press, consume: false))
        #expect(matcher.handle(.keyDown, keyCode: 8, flags: [.maskControl]) == .ignore)
        #expect(matcher.handle(.flagsChanged, keyCode: controlKey, flags: [])
                == .init(action: .release, consume: false))
    }
}
