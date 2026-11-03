import Foundation
import Testing
@testable import LocalSTTCore

@Suite("TextChunker")
struct TextChunkerTests {

    @Test("Blank text produces zero segments")
    func emptyTextYieldsNothing() {
        #expect(TextChunker.chunks(of: "").isEmpty)
    }

    @Test("Text under the allowance remains a single segment")
    func shortTextIsOneChunk() {
        #expect(TextChunker.chunks(of: "hello", maxUTF16: 20) == ["hello"])
    }

    @Test("Segments honour the UTF-16 allowance and reassemble into the source")
    func splitsOnBudget() {
        let text = "abcdefghij"
        let chunks = TextChunker.chunks(of: text, maxUTF16: 4)
        #expect(chunks == ["abcd", "efgh", "ij"])
        #expect(chunks.joined() == text)
    }

    @Test("Grapheme clusters stay whole")
    func keepsGraphemeClustersIntact() {
        // One flag emoji spans 4 UTF-16 units; a family emoji spans much more.
        // Given an allowance of 4, each must still emerge intact.
        let text = "🇩🇪🇩🇪"
        let chunks = TextChunker.chunks(of: text, maxUTF16: 4)
        #expect(chunks == ["🇩🇪", "🇩🇪"])
        #expect(chunks.joined() == text)

        // A lone character exceeding the allowance receives its own segment
        // instead of being ripped apart.
        let family = "👨‍👩‍👧‍👦"
        let familyChunks = TextChunker.chunks(of: family, maxUTF16: 4)
        #expect(familyChunks == [family])

        // Combining marks remain glued to their base character.
        let combining = "e\u{301}e\u{301}"
        let combiningChunks = TextChunker.chunks(of: combining, maxUTF16: 2)
        #expect(combiningChunks.count == 2)
        #expect(combiningChunks.joined() == combining)
    }

    @Test("Splitting a realistic transcript reproduces it exactly")
    func preservesLongText() {
        let text = "The quick brown fox jumps over the lazy dog, repeatedly and with feeling."
        let chunks = TextChunker.chunks(of: text)
        #expect(chunks.joined() == text)
        #expect(chunks.allSatisfy { $0.utf16.count <= TextChunker.defaultMaxUTF16 })
        // Substantially fewer events than one apiece per character.
        #expect(chunks.count < text.count / 4)
    }

    @Test("A non-positive allowance falls back to one segment")
    func handlesZeroBudget() {
        #expect(TextChunker.chunks(of: "abc", maxUTF16: 0) == ["abc"])
    }
}
