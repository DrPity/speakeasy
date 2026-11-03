import CoreGraphics
import Foundation
import Testing
@testable import LocalSTTCore

@Suite("Shortcut")
struct ShortcutTests {

    /// A disposable suite, keeping tests away from the genuine user defaults.
    private func makeDefaults() -> UserDefaults {
        let name = "LocalSTTCoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("Pristine defaults produce the standard F5 binding")
    func loadsDefaultWhenNothingStored() {
        #expect(ShortcutStore.load(from: makeDefaults()) == .defaultShortcut)
    }

    @Test("A key-and-modifier binding survives a round trip")
    func roundTripsKeyShortcut() {
        let defaults = makeDefaults()
        let shortcut = Shortcut(keyCode: 49, modifiers: [.maskControl, .maskAlternate])
        ShortcutStore.save(shortcut, to: defaults)
        #expect(ShortcutStore.load(from: defaults) == shortcut)
    }

    @Test("A modifier-only binding survives a round trip through the sentinel")
    func roundTripsModifierOnlyShortcut() {
        let defaults = makeDefaults()
        let shortcut = Shortcut(keyCode: nil, modifiers: [.maskControl])
        ShortcutStore.save(shortcut, to: defaults)

        #expect(defaults.integer(forKey: ShortcutStore.keyCodeKey) == ShortcutStore.modifierOnlySentinel)
        let loaded = ShortcutStore.load(from: defaults)
        #expect(loaded.keyCode == nil)
        #expect(loaded == shortcut)
    }

    @Test("Display text sorts modifiers and names recognised keys")
    func formatsDisplayString() {
        #expect(Shortcut(keyCode: 96, modifiers: []).displayString == "F5")
        #expect(Shortcut(keyCode: 49, modifiers: [.maskCommand]).displayString == "⌘Space")
        #expect(Shortcut(keyCode: nil, modifiers: [.maskControl]).displayString == "⌃")
        #expect(Shortcut(keyCode: 200, modifiers: []).displayString == "Key 200")
        #expect(Shortcut(keyCode: nil, modifiers: []).displayString == "—")
        // The canonical sequence is ⌃⌥⇧⌘ regardless of the order they were listed.
        let all = Shortcut(keyCode: nil, modifiers: [.maskCommand, .maskControl, .maskShift, .maskAlternate])
        #expect(all.displayString == "⌃⌥⇧⌘")
    }

    @Test("Modifier checks demand precisely the stored combination")
    func matchesModifiersExactly() {
        let shortcut = Shortcut(keyCode: 96, modifiers: [.maskControl])
        #expect(shortcut.modifiersSatisfied(by: [.maskControl]))
        // Extraneous bits (caps lock) don't matter…
        #expect(shortcut.modifiersSatisfied(by: [.maskControl, .maskAlphaShift]))
        // …yet one additional genuine modifier breaks the match.
        #expect(!shortcut.modifiersSatisfied(by: [.maskControl, .maskCommand]))
        #expect(!shortcut.modifiersSatisfied(by: []))
    }

    @Test("A binding lacking both key and modifiers counts as empty")
    func detectsEmptyShortcut() {
        #expect(Shortcut(keyCode: nil, modifiers: []).isEmpty)
        #expect(!Shortcut(keyCode: nil, modifiers: [.maskControl]).isEmpty)
        #expect(!Shortcut(keyCode: 96, modifiers: []).isEmpty)
    }
}
