import SwiftUI

/// "Mint on Ink": the palette of the app icon, used across the panel and the
/// overlay.
enum Theme {
    // Surfaces, darkest first.
    static let ink = Color(hex: 0x0C0F15)        // overlay, inputs
    static let panel = Color(hex: 0x141922)      // panel background
    static let card = Color(hex: 0x1B212C)       // grouped cards
    static let raised = Color(hex: 0x232936)     // badges, chips
    static let selected = Color(hex: 0x2C3442)

    // Text, all ≥ 4.5:1 on `panel`.
    static let glass = Color(hex: 0xE8FFF5)      // primary
    static let secondary = Color(hex: 0xB8C6C0)
    static let tertiary = Color(hex: 0x8FA19A)

    // Accents.
    static let mint = Color(hex: 0x3BEFA6)       // live, done, primary action
    static let amber = Color(hex: 0xFFB547)      // warnings only

    static let hairline = glass.opacity(0.06)
    static let border = glass.opacity(0.10)
    static let controlBorder = glass.opacity(0.14)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Text pieces

/// The small uppercase heading above a group.
struct SectionLabel: View {
    private let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(Theme.tertiary)
            .padding(.horizontal, 4)
    }
}

extension View {
    /// Grey explanatory text under a setting.
    func footnoteStyle() -> some View {
        font(.system(size: 12))
            .foregroundStyle(Theme.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A key drawn as a key: `⌃ Right Control`.
struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Theme.glass)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.controlBorder))
    }
}

/// The coloured dot in front of a status line.
struct StatusDot: View {
    let color: Color
    var body: some View {
        Circle().fill(color).frame(width: 7, height: 7)
    }
}

// MARK: - Groups and rows

/// A rounded card holding rows separated by hairlines.
struct GroupCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// One line of a `GroupCard`: title, an optional ⓘ with a hover explanation,
/// the control on the right, and an optional footnote underneath.
struct SettingRow<Trailing: View>: View {
    let title: String
    var help: String?
    var footnote: String?
    var showsDivider = true
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.glass)
                if let help {
                    InfoBadge(help: help)
                }
                Spacer(minLength: 8)
                trailing
            }
            if let footnote {
                Text(footnote).footnoteStyle()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, footnote == nil ? 0 : 10)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .help(help ?? "")
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle().fill(Theme.hairline).frame(height: 1)
            }
        }
    }
}

/// A small ⓘ that explains a setting on hover (the native tooltip, so it
/// follows the system's delay and accessibility behaviour).
struct InfoBadge: View {
    let help: String

    var body: some View {
        Image(systemName: "info")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(Theme.secondary)
            .frame(width: 16, height: 16)
            .background(Theme.glass.opacity(0.08), in: Circle())
            .help(help)
            .accessibilityLabel(help)
    }
}

// MARK: - Buttons

/// Outlined, quiet button (Copy, Change, Quit).
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(Theme.glass)
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(configuration.isPressed ? Theme.glass.opacity(0.08) : .clear)
            )
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.controlBorder))
            .contentShape(Rectangle())
    }
}

/// Mint, filled: the one primary action on a screen.
struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.mint.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35))
            )
            .contentShape(Rectangle())
    }
}

/// Borderless icon button with a hover/press background.
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Theme.secondary)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(configuration.isPressed ? Theme.glass.opacity(0.10) : .clear)
            )
            .contentShape(Rectangle())
    }
}

// MARK: - Layout

/// Wraps children onto new lines, like text (used for the word chips).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
