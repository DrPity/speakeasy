import Foundation
import Testing
@testable import LocalSTTCore

@Suite("TranscriptHistory")
struct TranscriptHistoryTests {

    @Test("A fresh history holds nothing")
    func startsEmpty() {
        #expect(TranscriptHistory().isEmpty)
    }

    @Test("The newest entry comes first")
    func ordersNewestFirst() {
        var history = TranscriptHistory()
        history.record("first")
        history.record("second")
        #expect(history.entries.map(\.text) == ["second", "first"])
    }

    @Test("Eldest entries are pushed out at capacity")
    func evictsAtCapacity() {
        var history = TranscriptHistory(capacity: 3)
        for index in 1...5 { history.record("\(index)") }
        #expect(history.entries.count == 3)
        #expect(history.entries.map(\.text) == ["5", "4", "3"])
    }

    @Test("Empty transcripts are dropped")
    func ignoresBlankText() {
        var history = TranscriptHistory()
        history.record("")
        history.record("   \n\t ")
        #expect(history.isEmpty)
    }

    @Test("Stored text has its whitespace removed")
    func trimsWhitespace() {
        var history = TranscriptHistory()
        history.record("  hello  ")
        #expect(history.entries.first?.text == "hello")
    }

    @Test("Clearing wipes the list")
    func clears() {
        var history = TranscriptHistory()
        history.record("something")
        history.clear()
        #expect(history.isEmpty)
    }

    @Test("Zero capacity retains nothing")
    func zeroCapacityRecordsNothing() {
        var history = TranscriptHistory(capacity: 0)
        history.record("dropped")
        #expect(history.isEmpty)
    }

    @Test("Duplicate transcripts remain separate entries")
    func keepsDuplicatesSeparate() {
        var history = TranscriptHistory()
        history.record("same")
        history.record("same")
        #expect(history.entries.count == 2)
        #expect(history.entries[0].id != history.entries[1].id)
    }
}
