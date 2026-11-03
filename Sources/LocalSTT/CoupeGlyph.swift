import AppKit
import LocalSTTCore
import SwiftUI

/// The coupe from the app icon as a glyph, drawn from one geometry for all
/// three places it appears: the menu-bar icon (an `NSImage`), the panel badge
/// and the overlay (SwiftUI). Motion comes from `CoupeAnimation`.
enum CoupeGeometry {
    /// All coordinates are in a 24 × 24 design space (smaller y is higher).
    static let designSize: CGFloat = 24

    static let bowl: CGPath = {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 4, y: 6))
        path.addLine(to: CGPoint(x: 20, y: 6))
        path.addCurve(to: CGPoint(x: 12, y: 14.5), control1: CGPoint(x: 20, y: 11.6), control2: CGPoint(x: 16.4, y: 14.5))
        path.addCurve(to: CGPoint(x: 4, y: 6), control1: CGPoint(x: 7.6, y: 14.5), control2: CGPoint(x: 4, y: 11.6))
        path.closeSubpath()
        return path
    }()

    static let stemAndBase: CGPath = {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 12, y: 14.5))
        path.addLine(to: CGPoint(x: 12, y: 20))
        path.move(to: CGPoint(x: 8.5, y: 20.5))
        path.addLine(to: CGPoint(x: 15.5, y: 20.5))
        return path
    }()

    /// The liquid: everything in the bowl below a travelling wave.
    static func liquid(surfaceY: Double, amplitude: Double, offset: Double) -> CGPath {
        let wave = CGMutablePath()
        let start = 2.0, end = 22.0, step = 0.5
        wave.move(to: CGPoint(x: start, y: CoupeAnimation.waveY(x: start, baseline: surfaceY, amplitude: amplitude, offset: offset)))
        for x in stride(from: start + step, through: end, by: step) {
            wave.addLine(to: CGPoint(x: x, y: CoupeAnimation.waveY(x: x, baseline: surfaceY, amplitude: amplitude, offset: offset)))
        }
        wave.addLine(to: CGPoint(x: end, y: 16))
        wave.addLine(to: CGPoint(x: start, y: 16))
        wave.closeSubpath()
        return wave.intersection(bowl)
    }

    /// The thin resting line in an empty glass.
    static func restingWave(offset: Double) -> CGPath {
        let path = CGMutablePath()
        let y = 9.6
        path.move(to: CGPoint(x: 5.6, y: CoupeAnimation.waveY(x: 5.6, baseline: y, amplitude: 0.55, offset: offset)))
        for x in stride(from: 6.0, through: 18.4, by: 0.4) {
            path.addLine(to: CGPoint(x: x, y: CoupeAnimation.waveY(x: x, baseline: y, amplitude: 0.55, offset: offset)))
        }
        return path
    }

    /// The setup badge: a dot over the top-right of the rim.
    static let badgeCenter = CGPoint(x: 19.5, y: 4)
    static let badgeRadius: CGFloat = 3.4
}

// MARK: - SwiftUI

/// The glyph as a SwiftUI view. Animates on its own (TimelineView) while the
/// mode is listening or finishing; static otherwise.
struct CoupeGlyphView: View {
    var mode: CoupeAnimation.Mode
    /// 0...1, the smoothed microphone level (fills the glass while listening).
    var level: Double = 0
    var size: CGFloat = 24
    var outline: Color = Theme.glass
    var liquid: Color = Theme.mint
    var badge: Color = Theme.amber

    private var isMoving: Bool { mode == .listening || mode == .finishing }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isMoving)) { context in
            Canvas { graphics, canvasSize in
                draw(in: &graphics, size: canvasSize, time: context.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func draw(in graphics: inout GraphicsContext, size canvasSize: CGSize, time: Double) {
        let scale = canvasSize.width / CoupeGeometry.designSize
        graphics.scaleBy(x: scale, y: scale)
        let stroke = StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
        let offset = CoupeAnimation.waveOffset(time: isMoving ? time : 0)

        if let surface = CoupeAnimation.surfaceY(mode: mode, level: level, time: time) {
            let path = CoupeGeometry.liquid(surfaceY: surface, amplitude: CoupeAnimation.waveAmplitude(mode: mode), offset: offset)
            graphics.fill(Path(path), with: .color(liquid.opacity(mode == .finishing ? 0.7 : 1)))
        } else {
            graphics.stroke(Path(CoupeGeometry.restingWave(offset: offset)), with: .color(outline), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        }
        graphics.stroke(Path(CoupeGeometry.bowl), with: .color(outline), style: stroke)
        graphics.stroke(Path(CoupeGeometry.stemAndBase), with: .color(outline), style: stroke)

        for bubble in CoupeAnimation.bubbles(mode: mode, time: time) {
            let rect = CGRect(x: bubble.x - bubble.radius, y: bubble.y - bubble.radius, width: bubble.radius * 2, height: bubble.radius * 2)
            graphics.fill(Path(ellipseIn: rect), with: .color(liquid.opacity(bubble.opacity)))
        }

        if mode == .needsSetup {
            let c = CoupeGeometry.badgeCenter, r = CoupeGeometry.badgeRadius
            graphics.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(badge))
        }
    }
}

// MARK: - Menu bar

/// Renders the menu-bar icon. It is a *template* image, so macOS tints it to
/// match light, dark and tinted menu bars; activity shows as motion, not colour.
enum MenuBarIcon {
    static let pointSize = NSSize(width: 18, height: 18)

    static func image(mode: CoupeAnimation.Mode, level: Double, time: Double) -> NSImage {
        let image = NSImage(size: pointSize, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let scale = rect.width / CoupeGeometry.designSize
            ctx.scaleBy(x: scale, y: scale)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            let moving = mode == .listening || mode == .finishing
            let offset = CoupeAnimation.waveOffset(time: moving ? time : 0)

            if let surface = CoupeAnimation.surfaceY(mode: mode, level: level, time: time) {
                ctx.addPath(CoupeGeometry.liquid(surfaceY: surface, amplitude: CoupeAnimation.waveAmplitude(mode: mode), offset: offset))
                ctx.fillPath()
            }
            // Heavier than the in-app glyph so it holds up at 18 pt.
            ctx.setLineWidth(2)
            ctx.addPath(CoupeGeometry.bowl)
            ctx.addPath(CoupeGeometry.stemAndBase)
            ctx.strokePath()

            for bubble in CoupeAnimation.bubbles(mode: mode, time: time) {
                ctx.setAlpha(bubble.opacity)
                ctx.fillEllipse(in: CGRect(x: bubble.x - bubble.radius, y: bubble.y - bubble.radius, width: bubble.radius * 2, height: bubble.radius * 2))
            }
            ctx.setAlpha(1)

            if mode == .needsSetup {
                // Knock a ring out of the rim, then fill the dot, so the badge
                // reads as separate from the glass at menu-bar size.
                let c = CoupeGeometry.badgeCenter, r = CoupeGeometry.badgeRadius
                ctx.setBlendMode(.clear)
                ctx.fillEllipse(in: CGRect(x: c.x - r - 1.4, y: c.y - r - 1.4, width: (r + 1.4) * 2, height: (r + 1.4) * 2))
                ctx.setBlendMode(.normal)
                ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Speakeasy"
        return image
    }
}
