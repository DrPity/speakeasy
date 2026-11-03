import Foundation

/// The latest transcripts, most recent first.
///
/// **Memory-resident only.** None of this ever touches disk: dictated text is
/// the most delicate data the app deals with, and persisting a history would
/// betray the app's entire privacy promise. The list vanishes with the process.
public struct TranscriptHistory: Equatable {
    public struct Entry: Equatable, Identifiable {
        public let id: UUID
        public let text: String
        public let date: Date

        public init(id: UUID = UUID(), text: String, date: Date) {
            self.id = id
            self.text = text
            self.date = date
        }
    }

    public static let defaultCapacity = 10

    public private(set) var entries: [Entry] = []
    public let capacity: Int

    public init(capacity: Int = defaultCapacity) {
        self.capacity = max(0, capacity)
    }

    /// Store a transcript. Empty text is dropped; once `capacity` is passed,
    /// the eldest entry is pushed out.
    public mutating func record(_ text: String, date: Date = Date()) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, capacity > 0 else { return }
        entries.insert(Entry(text: trimmed, date: date), at: 0)
        if entries.count > capacity {
            entries.removeLast(entries.count - capacity)
        }
    }

    public mutating func clear() {
        entries.removeAll()
    }

    public var isEmpty: Bool { entries.isEmpty }
}
