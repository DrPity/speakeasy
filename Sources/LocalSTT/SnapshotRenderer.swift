#if DEBUG
import AppKit
import ImageIO
import LocalSTTCore
import SwiftUI
import UniformTypeIdentifiers

/// Debug builds only: `LocalSTT --snapshot <dir>` renders every panel screen,
/// every overlay state and the menu-bar icon modes to PNGs, plus animated
/// GIFs of the overlay, the glass and the menu-bar icon, offscreen, then exits.
/// `scripts/readme-images.sh` turns them into the README's feature images. Uses sample data held in memory; nothing is saved, no permission
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
        render(panel(SettingsView(screen: .constant(.settings))), "panel-settings", into: directory)
        render(panel(VocabularyEditor(screen: .constant(.vocabulary))), "panel-vocabulary", into: directory)

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

        // Animations.
        renderOverlayGIF(into: directory)
        renderGlassGIF(into: directory)
        renderMenuBarGIF(into: directory)
        engine.finalText = ""
        engine.partialText = ""

        model.settings.historyEnabled = historyWasOn
        model.history.clear()
        isActive = false
    }

    // MARK: - Helpers

    private static func panel<V: View>(_ view: V) -> some View {
        view
            .environment(\.panelScrollCap, .infinity)   // whole screen, no scroll view
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
        guard let rep = capture(view, height: height) else { return }
        write(rep, name, into: directory)
    }

    /// Lays the view out in an offscreen window and captures it at 2×.
    private static func capture<V: View>(_ view: V, height: CGFloat? = nil) -> NSBitmapImageRep? {
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
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep
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

    // MARK: - Animations

    /// The overlay while dictating: listening, words arriving (the newest
    /// still grey), then the ✓ once the text is typed.
    private static func renderOverlayGIF(into directory: URL) {
        let model = AppModel.shared
        let engine = model.engine
        var frames: [(CGImage, Double)] = []
        func add(_ delay: Double) {
            if let image = capture(hud())?.cgImage { frames.append((image, delay)) }
        }
        let words = "Pair with Lea on the onboarding copy, then review the vocabulary edit before lunch."
            .split(separator: " ").map(String.init)

        engine.finalText = ""
        engine.partialText = ""
        model.overrideForSnapshot(delivered: nil, sessionStart: Date())
        engine.overrideForSnapshot(state: .recording, warning: nil, level: 0.2, ready: true)
        add(0.9)
        for count in 1...words.count {
            let settled = max(0, count - 3)
            engine.finalText = words[..<settled].joined(separator: " ")
            engine.partialText = words[settled..<count].joined(separator: " ")
            let elapsed = 1 + Double(count) * 0.3
            model.overrideForSnapshot(delivered: nil, sessionStart: Date().addingTimeInterval(-elapsed))
            engine.overrideForSnapshot(state: .recording, warning: nil, level: 0.4 + 0.5 * Float(count % 3) / 2, ready: true)
            add(0.28)
        }
        engine.finalText = ""
        engine.partialText = ""
        engine.overrideForSnapshot(state: .idle, warning: nil, level: 0, ready: true)
        model.overrideForSnapshot(delivered: words.joined(separator: " "), sessionStart: Date().addingTimeInterval(-6))
        add(2.2)
        model.overrideForSnapshot(delivered: nil, sessionStart: nil)
        writeGIF(frames, "anim-overlay", into: directory)
    }

    /// The coupe filling and sloshing with a speech-like input level, eased
    /// by the same `LevelSmoother` the app applies to the real microphone.
    private static func renderGlassGIF(into directory: URL) {
        let fps = 20.0
        var smoother = LevelSmoother()
        var frames: [(CGImage, Double)] = []
        for index in 0..<Int(fps * 5) {
            let time = Double(index) / fps
            smoother.update(toward: Float(speechLevel(at: time)))
            let view = CoupeGlyphView(mode: .listening, level: Double(smoother.value), size: 96, frozenTime: time)
                .frame(width: 136, height: 136)
                .background(Theme.raised, in: Circle())
                .padding(20)
                .background(Theme.ink)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let image = renderer.cgImage { frames.append((image, 1 / fps)) }
        }
        writeGIF(frames, "anim-glass", into: directory)
    }

    /// Phrases of syllable-like bursts separated by pauses, 0...1.
    private static func speechLevel(at time: Double) -> Double {
        let phrase = time.truncatingRemainder(dividingBy: 2.5)
        guard phrase < 1.9 else { return 0.02 }
        let syllables = 0.55 + 0.45 * abs(sin(time * 7.3))
        let contour = 0.5 + 0.5 * sin(time * 1.7 + 0.6)
        return min(1, 0.15 + 0.85 * syllables * contour)
    }

    /// The menu-bar icon through its states, on a light and a dark menu bar:
    /// idle → listening (following the voice) → finishing → needs setup.
    private static func renderMenuBarGIF(into directory: URL) {
        let fps = 15.0
        var smoother = LevelSmoother()
        var frames: [(CGImage, Double)] = []
        func add(_ mode: CoupeAnimation.Mode, level: Double, time: Double, delay: Double) {
            if let image = menuBarFrame(MenuBarIcon.image(mode: mode, level: level, time: time)) {
                frames.append((image, delay))
            }
        }
        add(.idle, level: 0, time: 0, delay: 1.2)
        for index in 0..<Int(fps * 3.2) {
            let time = Double(index) / fps
            smoother.update(toward: Float(speechLevel(at: time)))
            add(.listening, level: Double(smoother.value), time: time, delay: 1 / fps)
        }
        for index in 0..<Int(fps * 1.2) {
            add(.finishing, level: 0, time: 3.2 + Double(index) / fps, delay: 1 / fps)
        }
        add(.idle, level: 0, time: 0, delay: 1.0)
        add(.needsSetup, level: 0, time: 0, delay: 1.6)
        writeGIF(frames, "anim-menubar", into: directory)
    }

    /// Two menu-bar tiles side by side, the template icon drawn black on light
    /// and white on dark, as macOS does.
    private static func menuBarFrame(_ icon: NSImage) -> CGImage? {
        let tile = NSSize(width: 240, height: 144), iconSide: CGFloat = 108   // pixels, shown at half size
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(tile.width * 2), pixelsHigh: Int(tile.height), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        for (index, (background, foreground)) in [(NSColor(white: 0.93, alpha: 1), NSColor.black),
                                                  (NSColor(white: 0.16, alpha: 1), NSColor.white)].enumerated() {
            let origin = CGFloat(index) * tile.width
            background.setFill()
            NSRect(x: origin, y: 0, width: tile.width, height: tile.height).fill()
            let rect = NSRect(x: origin + (tile.width - iconSide) / 2, y: (tile.height - iconSide) / 2,
                              width: iconSide, height: iconSide)
            tinted(icon, foreground).draw(in: rect)
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }

    private static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    private static func writeGIF(_ frames: [(image: CGImage, delay: Double)], _ name: String, into directory: URL) {
        let url = directory.appendingPathComponent("\(name).gif")
        guard !frames.isEmpty,
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil)
        else { return }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        for frame in frames {
            CGImageDestinationAddImage(destination, frame.image, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: frame.delay],
            ] as CFDictionary)
        }
        CGImageDestinationFinalize(destination)
    }

    private static func write(_ rep: NSBitmapImageRep, _ name: String, into directory: URL) {
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: directory.appendingPathComponent("\(name).png"))
    }
}
#endif
