import Foundation

/// Words that steer the recognizer, together with exact-match replacement rules
/// applied afterwards.
public struct Vocabulary: Codable, Equatable {
    public var terms: [String]
    public var rules: [ReplacementRule]

    public init(terms: [String] = [], rules: [ReplacementRule] = []) {
        self.terms = terms
        self.rules = rules
    }

    public static let empty = Vocabulary()

    /// A protective ceiling on how many words get passed to the speech recognizer.
    public static let maxTerms = 200

    /// The trimmed, duplicate-free, capped word list — precisely what enters the
    /// analyzer's contextual strings.
    public var contextualTerms: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for term in terms {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            result.append(trimmed)
            if result.count == Self.maxTerms { break }
        }
        return result
    }
}

/// Loads and persists the vocabulary as JSON inside Application Support.
///
/// The contents are usually names and in-house jargon, so the file is written
/// `0600` (readable by the owner alone) inside a `0700` directory, and it is
/// never synchronized anywhere.
public struct VocabularyStore {
    public let fileURL: URL

    public init(directory: URL, fileName: String = "vocabulary.json") {
        self.fileURL = directory.appendingPathComponent(fileName)
    }

    /// Resolves to `~/Library/Application Support/<bundleID>/`
    public static func defaultDirectory(
        bundleID: String,
        fileManager: FileManager = .default
    ) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(bundleID, isDirectory: true)
    }

    /// Hands back an empty vocabulary if nothing has been saved yet.
    public func load(fileManager: FileManager = .default) throws -> Vocabulary {
        guard fileManager.fileExists(atPath: fileURL.path) else { return .empty }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(Vocabulary.self, from: data)
    }

    public func save(_ vocabulary: Vocabulary, fileManager: FileManager = .default) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(vocabulary).write(to: fileURL, options: .atomic)
        // Because an atomic write swaps in a fresh file, permissions are
        // tightened after writing instead of before.
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
