import AppKit
import CoreGraphics
import Foundation
import LocalSTTCore

/// Hands completed text off to whichever application has focus.
protocol TextInjecting {
    func inject(_ text: String) async
}

/// The application the output is destined for.
///
/// Delivery takes time, so the destination is captured up front and the whole
/// operation aborts if focus shifts. Without that check, changing apps halfway
/// through would pour the remainder of a transcript into whatever app happened
/// to end up frontmost.
enum InjectionTarget {
    static func currentPID() async -> pid_t? {
        await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier }
    }
}

// MARK: - Keystrokes (default)

/// Emits text by fabricating keyboard events.
///
/// It fills each event's Unicode string payload instead of using virtual key
/// codes, which allows arbitrary text on any keyboard layout and **leaves the
/// clipboard untouched**. Needs Accessibility permission (the same grant the
/// shortcut tap uses).
struct KeystrokeInjector: TextInjecting {
    /// Each event is filled with characters up to this UTF-16 allowance. Sending
    /// one event per character produces roughly 20× more events than needed; a
    /// 600-character transcript once consumed about a second of fabricated
    /// keystrokes that way.
    var maxUTF16PerEvent = TextChunker.defaultMaxUTF16
    /// A short pause between events so quick terminals and editors don't lose characters.
    var interChunkDelay: Duration = .milliseconds(3)

    func inject(_ text: String) async {
        guard !text.isEmpty else { return }
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        guard let target = await InjectionTarget.currentPID() else { return }

        for chunk in TextChunker.chunks(of: text, maxUTF16: maxUTF16PerEvent) {
            guard await InjectionTarget.currentPID() == target else { return }
            post(chunk, source: source)
            try? await Task.sleep(for: interChunkDelay)
        }
    }

    private func post(_ chunk: String, source: CGEventSource) {
        var utf16 = Array(chunk.utf16)
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else { return }

        // Drop any inherited modifier state. The event source begins from the
        // real-time hardware flags, meaning a physically held ⌘ or ⌥ would
        // convert each emitted character into a shortcut.
        keyDown.flags = []
        keyUp.flags = []

        keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

// MARK: - Paste (opt-in)

/// Places the text on the clipboard, issues ⌘V, then puts back what was there
/// before.
///
/// Much quicker than typing for long transcripts, though it unavoidably exposes
/// the content: while it occupies the general pasteboard, any process owned by
/// this user may read it. That exposure is intrinsic to pasting, so the mode is
/// opt-in and the preferences UI displays a warning.
struct PasteInjector: TextInjecting {
    /// The nspasteboard.org convention flag signalling "do not store this".
    /// Polite clipboard managers skip entries tagged with it. Consider it a
    /// courtesy rather than protection.
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    /// The interval the text remains on the pasteboard before the earlier
    /// contents return. Sized so the receiving app has time to complete the paste.
    var restoreDelay: Duration = .milliseconds(150)

    private struct SavedItem {
        let contents: [(type: NSPasteboard.PasteboardType, data: Data)]
    }

    func inject(_ text: String) async {
        guard !text.isEmpty else { return }
        guard let target = await InjectionTarget.currentPID() else { return }

        let saved = await MainActor.run { Self.snapshot(NSPasteboard.general) }
        await MainActor.run { Self.write(text, to: NSPasteboard.general) }

        if await InjectionTarget.currentPID() == target {
            postCommandV()
            try? await Task.sleep(for: restoreDelay)
        }

        await MainActor.run { Self.restore(saved, to: NSPasteboard.general) }
    }

    // MARK: Pasteboard handling

    /// Take a deep copy of the present items: `clearContents()` invalidates the
    /// originals, so the bytes must be held ourselves.
    @MainActor
    private static func snapshot(_ pasteboard: NSPasteboard) -> [SavedItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            SavedItem(contents: item.types.compactMap { type in
                item.data(forType: type).map { (type: type, data: $0) }
            })
        }
    }

    @MainActor
    private static func write(_ text: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setString("", forType: concealedType)
        pasteboard.writeObjects([item])
    }

    /// A best-effort restoration. Promised (lazy) pasteboard types can't be
    /// rebuilt from a byte snapshot, so an item another app supplied lazily
    /// might return incomplete.
    @MainActor
    private static func restore(_ items: [SavedItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restored = items.compactMap { saved -> NSPasteboardItem? in
            guard !saved.contents.isEmpty else { return nil }
            let item = NSPasteboardItem()
            for entry in saved.contents {
                item.setData(entry.data, forType: entry.type)
            }
            return item
        }
        guard !restored.isEmpty else { return }
        pasteboard.writeObjects(restored)
    }

    private func postCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let vKey: CGKeyCode = 9   // the ANSI "V" key code
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else { return }

        // Command alone — regardless of what the user is physically holding.
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
