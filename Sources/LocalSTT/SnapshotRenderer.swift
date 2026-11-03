#if DEBUG
import AppKit
import LocalSTTCore
import SwiftUI

/// Debug builds only: `LocalSTT --snapshot <dir>` renders every panel screen,
/// every overlay state and the menu-bar icon modes to PNGs, offscreen, then
/// exits. Uses sample data held in memory; nothing is saved, no permission
/// prompt is triggered (refreshes are suppressed while it runs).
@MainActor
enum SnapshotRenderer {
    static private(set) var isActive = false

    static func run(into directory: URL) {
        isActive = true
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = AppModel.shared
        let engine = model.engine
        let historyWasOn = model.settings.historyEnabled

        // Sample content (memory only).
        model.overrideForSnapshot(
            vocabulary: Vocabulary(
                terms: ["Speakeasy", "SwiftUI", "Johnny.Decimal", "SpeechAnalyzer", "Scarlett 2i2", "Lea", "TCC", "Kubernetes"],
                rules: [
                    ReplacementRule(find: "eye phone", replaceWith: "iPhone"),
                    ReplacementRule(find: "swift UI", replaceWith: "SwiftUI"),
                    ReplacementRule(find: "at sign", replaceWith: "@", caseSensitive: true),
                    ReplacementRule(find: "gonna", replaceWith: "going to", isEnabled: false),
                ]
            ),
            delivered: nil,
            sessionStart: nil
        )
        model.settings.historyEnabled = true
        model.history.clear()
        model.history.record("git commit message: fix silent tap failure on rate mismatch", date: Date().addingTimeInterval(-3600))
        model.history.record("Thanks, that works for me. Let’s talk Thursday at ten.", date: Date().addingTimeInterval(-900))
        model.history.record("Ship the capture fix before the Friday build.", date: Date().addingTimeInterval(-300))
        model.history.record("Pair with Lea on the onboarding copy, then review the vocabulary edit.")

        let allowed = { model.permissions.overrideForSnapshot(microphone: .granted, speech: .granted, accessibility: true) }

        // Panel screens.
        allowed()
        engine.overrideForSnapshot(state: .idle, warning: nil, level: 0, ready: true)
        render(panel(MenuPanel()), "panel-ready", into: directory)
        model.permissions.overrideForSnapshot(microphone: .granted, speech: .granted, accessibility: false)
        render(panel(MenuPanel()), "panel-onboarding-step3", into: directory)
        model.permissions.overrideForSnapshot(microphone: .undetermined, speech: .undetermined, accessibility: false)
        render(panel(MenuPanel()), "panel-onboarding-step1", into: directory)
        allowed()
        render(panel(SettingsView(screen: .constant(.settings))), "panel-settings", into: directory, height: 900)
        render(panel(VocabularyEditor(screen: .constant(.vocabulary))), "panel-vocabulary", into: directory, height: 900)

        // Overlay states.
        let start = Date().addingTimeInterval(-4)
        model.overrideForSnapshot(delivered: nil, sessionStart: start)
        engine.overrideForSnapshot(state: .recording, warning: nil, level: 0.15, ready: true)
        render(hud(), "hud-1-listening", into: directory)
        engine.finalText = "pair with Lea on the onboarding copy, then"
        engine.partialText = "review the vocabulary edit before lunch and send the notes to everyone"
        engine.overrideForSnapshot(state: .recording, warning: nil, level: 0.8, ready: true)
        render(hud(), "hud-2-live", into: directory)
        engine.finalText = ""
        engine.partialText = ""
        engine.overrideForSnapshot(state: .recording, warning: TranscriberEngine.noAudioMessage, level: 0, ready: true)
        render(hud(), "hud-3-no-audio", into: directory)
        engine.overrideForSnapshot(state: .idle, warning: nil, level: 0, ready: true)
        model.overrideForSnapshot(delivered: "pair with Lea on the onboarding copy, then review the vocabulary edit before lunch.", sessionStart: start)
        render(hud(), "hud-4-delivered", into: directory)
        model.overrideForSnapshot(delivered: nil, sessionStart: start)
        render(hud(), "hud-5-nothing-heard", into: directory)

        // Menu-bar icon modes (template image, drawn black; 4×).
        let modes: [(String, CoupeAnimation.Mode, Double)] = [
            ("idle", .idle, 0), ("listening-quiet", .listening, 0.1),
            ("listening-loud", .listening, 0.9), ("finishing", .finishing, 0), ("needs-setup", .needsSetup, 0),
        ]
        for (name, mode, level) in modes {
            writeIcon(MenuBarIcon.image(mode: mode, level: level, time: 0.35), "icon-\(name)", into: directory)
        }

        model.settings.historyEnabled = historyWasOn
        model.history.clear()
        isActive = false
    }

    // MARK: - Helpers

    private static func panel<V: View>(_ view: V) -> some View {
        view
            .padding(16)
            .frame(width: 380)
            .background(Theme.panel)
            .environment(\.colorScheme, .dark)
            .tint(Theme.mint)
    }

    private static func hud() -> some View {
        HUDView().background(Color(hex: 0x3A4150))
    }

    private static func render<V: View>(_ view: V, _ name: String, into directory: URL, height: CGFloat? = nil) {
        let hosting = NSHostingView(rootView: view.environment(AppModel.shared))
        var size = hosting.fittingSize
        if let height { size.height = max(size.height, height) }
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        hosting.frame.size = hosting.fittingSize.height > 0 && height == nil ? hosting.fittingSize : size
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        write(rep, name, into: directory)
    }

    private static func writeIcon(_ image: NSImage, _ name: String, into directory: URL) {
        let pixels = 72
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(white: 0.93, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        write(rep, name, into: directory)
    }

    private static func write(_ rep: NSBitmapImageRep, _ name: String, into directory: URL) {
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: directory.appendingPathComponent("\(name).png"))
    }
}
#endif
