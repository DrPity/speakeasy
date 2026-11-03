import Foundation

/// Breaks text into segments compact enough to travel on one fabricated
/// keyboard event each.
///
/// Emitting an event per character is wastefully slow (a 600-character
/// transcript burns ~1s in fabricated events), so several characters are bundled
/// per event. Splits fall strictly on `Character` boundaries — never
/// mid-grapheme — leaving emoji and combining marks whole.
public enum TextChunker {
    /// A deliberately conservative default. Certain apps choke on lengthy
    /// unicode payloads attached to a single key event, so this stays far below
    /// every documented ceiling.
    public static let defaultMaxUTF16 = 20

    public static func chunks(of text: String, maxUTF16: Int = defaultMaxUTF16) -> [String] {
        guard maxUTF16 > 0 else { return text.isEmpty ? [] : [text] }
        var chunks: [String] = []
        var current = ""
        var currentLength = 0

        for character in text {
            let length = String(character).utf16.count
            // A lone character exceeding the allowance still receives its own
            // segment instead of being torn in two.
            if currentLength > 0, currentLength + length > maxUTF16 {
                chunks.append(current)
                current = ""
                currentLength = 0
            }
            current.append(character)
            currentLength += length
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
