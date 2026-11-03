import Foundation
import Testing
@testable import LocalSTTCore

@Suite("VocabularyStore")
struct VocabularyStoreTests {

    /// Gives each test a brand-new temp directory, deleted afterwards.
    private func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalSTTCoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        return try body(directory)
    }

    @Test("Reading before any save returns an empty vocabulary")
    func loadsEmptyWhenMissing() throws {
        try withTemporaryDirectory { directory in
            let store = VocabularyStore(directory: directory)
            let loaded = try store.load()
            #expect(loaded == .empty)
        }
    }

    @Test("A vocabulary survives a JSON round trip")
    func roundTrips() throws {
        try withTemporaryDirectory { directory in
            let store = VocabularyStore(directory: directory)
            let vocabulary = Vocabulary(
                terms: ["Miro", "Oplane"],
                rules: [ReplacementRule(find: "gdpr", replaceWith: "GDPR", caseSensitive: false)]
            )
            try store.save(vocabulary)
            let loaded = try store.load()
            #expect(loaded == vocabulary)
        }
    }

    @Test("The written file is owner-only and its folder is locked to others")
    func writesRestrictivePermissions() throws {
        try withTemporaryDirectory { directory in
            let store = VocabularyStore(directory: directory)
            try store.save(Vocabulary(terms: ["secret project name"]))

            let fileAttributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
            #expect(fileAttributes[.posixPermissions] as? Int == 0o600)

            let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
            #expect(directoryAttributes[.posixPermissions] as? Int == 0o700)
        }
    }

    @Test("A second save preserves the restrictive permissions")
    func keepsPermissionsAcrossOverwrite() throws {
        try withTemporaryDirectory { directory in
            let store = VocabularyStore(directory: directory)
            try store.save(Vocabulary(terms: ["one"]))
            try store.save(Vocabulary(terms: ["two"]))

            let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
            #expect(attributes[.posixPermissions] as? Int == 0o600)
            let loaded = try store.load()
            #expect(loaded.terms == ["two"])
        }
    }

    @Test("Contextual words come back trimmed, de-duplicated and capped")
    func normalisesContextualTerms() {
        let vocabulary = Vocabulary(terms: ["  Miro  ", "miro", "", "   ", "Oplane"])
        #expect(vocabulary.contextualTerms == ["Miro", "Oplane"])

        let many = Vocabulary(terms: (0..<(Vocabulary.maxTerms + 50)).map { "term\($0)" })
        #expect(many.contextualTerms.count == Vocabulary.maxTerms)
    }

    @Test("The default folder lives inside Application Support, scoped by bundle ID")
    func buildsDefaultDirectory() {
        let url = VocabularyStore.defaultDirectory(bundleID: "com.example.app")
        #expect(url.lastPathComponent == "com.example.app")
        #expect(url.path.contains("Application Support"))
    }
}
