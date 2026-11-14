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
        let settings = capture(panel(SettingsView(screen: .constant(.settings))))
        settings.map { write($0, "panel-settings", into: directory) }
        // As the window shows it: the scroll area at its real height.
        render(panel(SettingsView(screen: .constant(.settings)), scrolling: true), "panel-settings-window", into: directory)
        let vocabulary = capture(panel(VocabularyEditor(screen: .constant(.vocabulary))))
        vocabulary.map { write($0, "panel-vocabulary", into: directory) }

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

        // README feature cards (scripts/readme-images.sh).
        renderFeatureCards(settings: settings?.cgImage, vocabulary: vocabulary?.cgImage, into: directory)
        engine.finalText = ""
        engine.partialText = ""

        model.settings.historyEnabled = historyWasOn
        model.history.clear()
        isActive = false
    }

    // MARK: - Helpers

    /// `scrolling: false` drops the scroll view to draw the whole screen.
    private static func panel<V: View>(_ view: V, scrolling: Bool = false) -> some View {
        view
            .environment(\.panelScrollCap, scrolling ? PanelScrollCapKey.defaultValue : .infinity)
            .padding(16)
            .frame(width: 380)
            .background(Theme.panel)
            .environment(\.colorScheme, .dark)
            .tint(Theme.mint)
    }

    private static func hud(background: Color = Color(hex: 0x3A4150)) -> some View {
        HUDView().background(background)
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

    // MARK: - README feature cards

    /// Six equal cards for the README's feature grid: the visual on an inset
    /// "screen", title and caption below, rounded corners baked in (GitHub
    /// strips CSS). Crops are pixel rectangles inside a group's background in
    /// the full-length 2× renders, so no hard edge shows on the screen.
    private static func renderFeatureCards(settings: CGImage?, vocabulary: CGImage?, into directory: URL) {
        func crop(_ image: CGImage?, x: Int, y: Int, width: Int, height: Int) -> CGImage? {
            image?.cropping(to: CGRect(x: x, y: y, width: width, height: height))
        }
        func still(_ visual: CGImage?, _ name: String, _ title: String, _ subtitle: String, screen: Color) {
            guard let visual, let card = card(visual, title: title, subtitle: subtitle, screen: screen) else { return }
            writePNG(card, name, into: directory)
        }
        func animated(_ frames: [(image: CGImage, delay: Double)], _ name: String, _ title: String, _ subtitle: String) {
            let cards = frames.compactMap { frame in
                card(frame.image, title: title, subtitle: subtitle, screen: Theme.panel)
                    .flatMap(hardenAlpha)
                    .map { (image: $0, delay: frame.delay) }
            }
            writeGIF(cards, name, into: directory)
        }

        animated(overlayFrames(), "card-overlay", "See the words as you speak", "A live overlay that never steals focus")
        animated(glassFrames(), "card-glass", "The glass fills with your voice", "So a dead microphone is obvious")
        animated(menuBarFrames(), "card-menubar", "Lives in the menu bar", "No window, no Dock icon")
        still(crop(settings, x: 40, y: 186, width: 680, height: 160), "card-talk-key",
              "Your key, your way", "Hold to talk or tap to toggle, any key", screen: Theme.card)
        still(crop(vocabulary, x: 40, y: 236, width: 680, height: 294), "card-vocabulary",
              "Your vocabulary", "Names and jargon spelled your way", screen: Theme.card)
        still(crop(vocabulary, x: 40, y: 792, width: 680, height: 348), "card-find-replace",
              "Find & replace", "“eye phone” becomes “iPhone”", screen: Theme.card)
    }

    private static func card(_ visual: CGImage, title: String, subtitle: String, screen: Color) -> CGImage? {
        let renderer = ImageRenderer(content: FeatureCard(visual: visual, title: title, subtitle: subtitle, screen: screen))
        renderer.scale = 2
        renderer.isOpaque = false
        return renderer.cgImage
    }

    /// GIF transparency is on or off. Left to ImageIO, the card's soft
    /// rounded edge turns into a light ring that shows on dark pages; snapping
    /// each pixel to transparent or to its own colour, fully opaque, keeps the
    /// edge the card's colour on any background.
    private static func hardenAlpha(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let data = context.data else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for offset in stride(from: 0, to: width * height * 4, by: 4) {
            let alpha = Int(pixels[offset + 3])
            if alpha == 255 { continue }
            if alpha < 128 {
                pixels[offset] = 0; pixels[offset + 1] = 0; pixels[offset + 2] = 0; pixels[offset + 3] = 0
            } else {
                for channel in 0..<3 {
                    pixels[offset + channel] = UInt8(min(255, Int(pixels[offset + channel]) * 255 / alpha))
                }
                pixels[offset + 3] = 255
            }
        }
        return context.makeImage()
    }

    private static func writePNG(_ image: CGImage, _ name: String, into directory: URL) {
        write(NSBitmapImageRep(cgImage: image), name, into: directory)
    }

    // MARK: - Animations

    /// The overlay while dictating: listening, words arriving (the newest
    /// still grey), then the ✓ once the text is typed.
    private static func overlayFrames() -> [(image: CGImage, delay: Double)] {
        let model = AppModel.shared
        let engine = model.engine
        var frames: [(image: CGImage, delay: Double)] = []
        func add(_ delay: Double) {
            if let image = capture(hud(background: Theme.panel))?.cgImage { frames.append((image, delay)) }
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
        return frames
    }

    /// The coupe filling and sloshing with a speech-like input level, eased
    /// by the same `LevelSmoother` the app applies to the real microphone.
    private static func glassFrames() -> [(image: CGImage, delay: Double)] {
        let fps = 12.0   // the glass changes every frame, so frames are what costs file size
        var smoother = LevelSmoother()
        var frames: [(image: CGImage, delay: Double)] = []
        for index in 0..<Int(fps * 5) {
            let time = Double(index) / fps
            smoother.update(toward: Float(speechLevel(at: time)))
            let view = CoupeGlyphView(mode: .listening, level: Double(smoother.value), size: 84, frozenTime: time)
                .frame(width: 120, height: 120)
                .background(Theme.raised, in: Circle())
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let image = renderer.cgImage { frames.append((image, 1 / fps)) }
        }
        return frames
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
    private static func menuBarFrames() -> [(image: CGImage, delay: Double)] {
        let fps = 10.0
        var smoother = LevelSmoother()
        var frames: [(image: CGImage, delay: Double)] = []
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
        return frames
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
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: tile.width * 2, height: tile.height), xRadius: 20, yRadius: 20).addClip()
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

/// One README feature card. Every card has the same size and layout, so the
/// grid lines up whatever the visual's shape.
private struct FeatureCard: View {
    let visual: CGImage
    let title: String
    let subtitle: String
    let screen: Color

    static let width: CGFloat = 400
    static let screenSize = CGSize(width: 360, height: 168)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(decorative: visual, scale: 2)
                .resizable()
                .interpolation(.high)
                .frame(width: fitted.width, height: fitted.height)
                .frame(width: Self.screenSize.width, height: Self.screenSize.height)
                .background(screen)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border))
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.glass)
                .padding(.top, 16)
            Text(subtitle)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.tertiary)
                .padding(.top, 4)
        }
        .padding(20)
        .frame(width: Self.width, alignment: .leading)
        .background(Theme.ink)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.border))
        .padding(6)   // transparent gutter, so cards placed side by side keep a gap
        .environment(\.colorScheme, .dark)
    }

    /// The visual at its natural size, shrunk (never enlarged) to sit inside
    /// the screen with a margin.
    private var fitted: CGSize {
        let natural = CGSize(width: CGFloat(visual.width) / 2, height: CGFloat(visual.height) / 2)
        let scale = min(1, Self.screenSize.width * 0.94 / natural.width, Self.screenSize.height * 0.88 / natural.height)
        return CGSize(width: natural.width * scale, height: natural.height * scale)
    }
}
#endif
