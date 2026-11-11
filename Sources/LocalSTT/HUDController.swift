import AppKit
import SwiftUI

/// Sizing constants used by both the panel and the SwiftUI content inside it,
/// keeping the window and its card in agreement about dimensions.
private enum HUDMetrics {
    static let width: CGFloat = 520
    static let leadingPadding: CGFloat = 12
    static let trailingPadding: CGFloat = 18
    static let verticalPadding: CGFloat = 12
    static let cornerRadius: CGFloat = 26
    static let badgeSize: CGFloat = 40
    /// Lines of transcript visible at once; older lines scroll up and away.
    static let maxLines = 2
    /// See-through border around the card that gives the shadow room to draw.
    static let shadowSlack: CGFloat = 24
    /// Gap between the screen's lower edge and the card's lower edge.
    static let bottomInset: CGFloat = 140

    static let font = NSFont.systemFont(ofSize: 16, weight: .medium)

    /// The height of one transcript line, derived from the real font SwiftUI
    /// renders instead of a guess.
    static var lineHeight: CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    static var maxTextHeight: CGFloat {
        lineHeight * CGFloat(maxLines)
    }

    /// Tallest the card can get: two lines of text (or the warning's title and
    /// hint) or the badge, plus padding.
    static var maxCardHeight: CGFloat {
        max(maxTextHeight, badgeSize, 42) + verticalPadding * 2
    }

    static var panelSize: CGSize {
        CGSize(
            width: width + shadowSlack * 2,
            height: maxCardHeight + shadowSlack * 2
        )
    }
}

/// A floating, see-through overlay presenting the live transcript for as long as
/// the shortcut is held. It is built on a non-activating borderless panel so it
/// can't take focus away from the app receiving the dictation, and it swallows
/// no mouse events, letting clicks fall through to whatever sits beneath.
///
/// The panel acts as a **fixed-size transparent canvas**: it is permanently
/// large enough for the tallest card, and SwiftUI controls everything laid out
/// inside. Having the window size itself to its content instead would let
/// `NSHostingView` resize it with every extra transcript line, which animates
/// with a visible stutter.
@MainActor
final class HUDController {
    private var panel: NSPanel?

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.orderFrontRegardless()   // display without taking key or active status
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let hosting = NSHostingView(rootView: HUDView().environment(AppModel.shared))
        let size = HUDMetrics.panelSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // SwiftUI renders the card's shadow itself. A window-level shadow would
        // be computed from the drawn pixels and fall out of date as the card's
        // height changes, tracing the wrong outline.
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }

    /// Horizontally centre the panel toward the bottom of the main screen
    /// (mirroring the system dictation indicator), nudged so the *card's* lower
    /// edge — rather than the transparent panel's — sits at `bottomInset`.
    private func position(_ panel: NSPanel) {
        let size = HUDMetrics.panelSize
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = screen.midX - size.width / 2
        let y = screen.minY + HUDMetrics.bottomInset - HUDMetrics.shadowSlack
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }
}

// MARK: - Content

/// What the overlay displays: a capsule with the coupe badge, up to two lines
/// of transcript and a timer.
struct HUDView: View {
    @Environment(AppModel.self) private var model

    /// The height the transcript naturally wants, captured so the scroll
    /// viewport can be limited to `HUDMetrics.maxLines`.
    @State private var textHeight: CGFloat = 0

    private enum Face {
        case listening
        case live
        case warning(String)
        case delivered(String)
        case nothingHeard
    }

    private var face: Face {
        let engine = model.engine
        if let warning = engine.captureWarning { return .warning(warning) }
        if !engine.displayText.isEmpty { return .live }
        if let delivered = model.hudDelivered { return .delivered(delivered) }
        if engine.isRecording || engine.state == .finalizing { return .listening }
        return .nothingHeard
    }

    var body: some View {
        card
            // A fixed-height container that anchors the card at the bottom,
            // letting it expand upwards while its lower edge stays put.
            .frame(
                width: HUDMetrics.width,
                height: HUDMetrics.maxCardHeight,
                alignment: .bottom
            )
            .padding(HUDMetrics.shadowSlack)
            .environment(\.colorScheme, .dark)
    }

    private var card: some View {
        let face = face
        return HStack(alignment: .top, spacing: 12) {
            badge(for: face)
            content(for: face)
                .padding(.top, (HUDMetrics.badgeSize - HUDMetrics.lineHeight) / 2 - 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing(for: face)
                .padding(.top, (HUDMetrics.badgeSize - 16) / 2)
        }
        .padding(.leading, HUDMetrics.leadingPadding)
        .padding(.trailing, HUDMetrics.trailingPadding)
        .padding(.vertical, HUDMetrics.verticalPadding)
        .frame(width: HUDMetrics.width, alignment: .leading)
        .background(Theme.ink.opacity(0.94), in: RoundedRectangle(cornerRadius: HUDMetrics.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: HUDMetrics.cornerRadius)
                .stroke(isWarning(face) ? Theme.amber.opacity(0.5) : Theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 15, y: 6)
    }

    // MARK: Pieces

    @ViewBuilder
    private func badge(for face: Face) -> some View {
        let size = HUDMetrics.badgeSize
        switch face {
        case .warning:
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .frame(width: size, height: size)
                .background(Theme.amber.opacity(0.14), in: Circle())
        case .delivered:
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: size, height: size)
                .background(Theme.mint, in: Circle())
        case .nothingHeard:
            CoupeGlyphView(mode: .idle, size: 24)
                .frame(width: size, height: size)
                .background(Theme.raised, in: Circle())
        case .listening, .live:
            CoupeGlyphView(
                mode: model.engine.state == .finalizing ? .finishing : .listening,
                level: meterLevel,
                size: 24
            )
            .frame(width: size, height: size)
            .background(Theme.raised, in: Circle())
        }
    }

    /// The real level, or a gentle constant when the user turned metering off.
    private var meterLevel: Double {
        model.settings.levelMeterEnabled ? Double(model.engine.level) : 0.45
    }

    @ViewBuilder
    private func content(for face: Face) -> some View {
        switch face {
        case .listening:
            let hint = Text(model.settings.cancelWithEscape ? "  esc discards" : "").font(.system(size: 13))
            Text("Listening…\(hint)")
                .font(Font(HUDMetrics.font))
                .foregroundStyle(Theme.tertiary)
        case .live:
            scrollingText(liveText)
        case .delivered(let text):
            scrollingText(Text(text).foregroundStyle(Theme.glass))
        case .warning(let message):
            VStack(alignment: .leading, spacing: 1) {
                Text("No audio from the microphone")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                Text(message == TranscriberEngine.noAudioMessage
                     ? "Check the input in Audio MIDI Setup, or pick another mic."
                     : message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
        case .nothingHeard:
            Text("Didn’t catch anything")
                .font(Font(HUDMetrics.font))
                .foregroundStyle(Theme.tertiary)
        }
    }

    /// Settled words in full colour, the still-changing tail in grey.
    private var liveText: Text {
        let settled = model.engine.finalText
        let volatile = model.engine.partialText
        let joiner = settled.isEmpty || volatile.isEmpty ? "" : " "
        let settledText = Text(settled).foregroundStyle(Theme.glass)
        let volatileText = Text(joiner + volatile).foregroundStyle(Theme.secondary)
        return Text("\(settledText)\(volatileText)")
    }

    @ViewBuilder
    private func trailing(for face: Face) -> some View {
        switch face {
        case .listening, .live, .warning:
            if let start = model.sessionStartedAt {
                TimelineView(.periodic(from: start, by: 1)) { context in
                    Text(Self.elapsed(from: start, to: context.date))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.tertiary)
                }
            }
        case .delivered:
            Text(model.settings.injectionMethod == .paste ? "Pasted" : "Typed")
                .font(.system(size: 12))
                .foregroundStyle(Theme.tertiary)
        case .nothingHeard:
            EmptyView()
        }
    }

    private static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func isWarning(_ face: Face) -> Bool {
        if case .warning = face { return true }
        return false
    }

    /// Grows with the transcript up to two lines, then stays put and scrolls,
    /// keeping the latest words visible.
    private func scrollingText(_ text: Text) -> some View {
        ScrollView(.vertical) {
            text
                .font(Font(HUDMetrics.font))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    // A ScrollView takes whatever height it is given and
                    // therefore can't size itself to its content. Capture the
                    // text's intrinsic height and drive the viewport from that.
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: TranscriptHeightKey.self,
                            value: geometry.size.height
                        )
                    }
                )
        }
        .frame(height: min(max(textHeight, HUDMetrics.lineHeight), HUDMetrics.maxTextHeight))
        .scrollIndicators(.never)
        .scrollDisabled(true)
        .defaultScrollAnchor(.bottom)
        .onPreferenceChange(TranscriptHeightKey.self) { height in
            textHeight = height
        }
    }
}

private struct TranscriptHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
