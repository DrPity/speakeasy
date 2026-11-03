import AppKit
import CoreGraphics
import LocalSTTCore
import SwiftUI

/// Captures the push-to-talk shortcut, including shortcuts made of modifiers
/// alone.
///
/// Listening to `.keyDown` by itself could never register a standalone modifier
/// like Right Control, since modifiers only ever emit `.flagsChanged`. Both
/// event kinds are therefore observed: a pressed modifier turns into a
/// *candidate* and is committed solely when the user releases it without hitting
/// a real key. Pressing F5 while ⌥ is down consequently still stores "⌥F5".
struct HotkeyRecorder: View {
    @Environment(AppModel.self) private var model

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var candidateModifiers: CGEventFlags = []

    var body: some View {
        SettingRow(
            title: "Talk key",
            help: "The key you hold (or tap) to dictate. Click Change, then press it. "
                + "A lone modifier such as Control works too. On laptops, F-keys may need Fn.",
            footnote: isRecording ? "Press any key, or tap and let go of one modifier on its own." : nil
        ) {
            if isRecording {
                Text("Press a key…")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.mint)
            } else {
                KeyCap(text: model.hotkey.shortcut.displayString)
            }
            Button(isRecording ? "Cancel" : "Change") { toggleRecording() }
                .buttonStyle(GhostButtonStyle())
        }
        .onDisappear { stopRecording() }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
            return
        }
        isRecording = true
        candidateModifiers = []
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            switch event.type {
            case .keyDown:
                commit(Shortcut(keyCode: Int64(event.keyCode), modifiers: cgFlags(from: event.modifierFlags)))
                return nil   // consume the key that was captured
            case .flagsChanged:
                let flags = cgFlags(from: event.modifierFlags)
                if flags.isEmpty {
                    // Let go without hitting a key — treat it as a modifier-only shortcut.
                    if !candidateModifiers.isEmpty {
                        commit(Shortcut(keyCode: nil, modifiers: candidateModifiers))
                    }
                } else {
                    candidateModifiers = flags
                }
                return event
            default:
                return event
            }
        }
    }

    private func commit(_ shortcut: Shortcut) {
        guard !shortcut.isEmpty else { return }
        model.hotkey.rebind(shortcut)
        stopRecording()
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isRecording = false
        candidateModifiers = []
    }

    private func cgFlags(from flags: NSEvent.ModifierFlags) -> CGEventFlags {
        var result: CGEventFlags = []
        if flags.contains(.command) { result.insert(.maskCommand) }
        if flags.contains(.shift) { result.insert(.maskShift) }
        if flags.contains(.option) { result.insert(.maskAlternate) }
        if flags.contains(.control) { result.insert(.maskControl) }
        return result
    }
}
