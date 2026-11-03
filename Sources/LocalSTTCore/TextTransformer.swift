import Foundation

/// One exact-match find/replace operation run against the completed transcript.
public struct ReplacementRule: Codable, Equatable, Identifiable {
    public var id: UUID
    public var find: String
    public var replaceWith: String
    public var caseSensitive: Bool
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        find: String,
        replaceWith: String,
        caseSensitive: Bool = false,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.find = find
        self.replaceWith = replaceWith
        self.caseSensitive = caseSensitive
        self.isEnabled = isEnabled
    }
}

/// Runs replacement rules over transcribed text.
///
/// Matching stays **exact** — regular expressions are never involved — so a rule
/// cannot inadvertently hit far beyond what the user intended, and no
/// user-authored pattern ever ends up inside a regex engine on the delivery path.
public enum TextTransformer {
    /// Run `rules` sequentially. Rules that are off, or whose `find` is empty,
    /// are ignored.
    public static func apply(_ rules: [ReplacementRule], to text: String) -> String {
        rules.reduce(text) { partial, rule in
            guard rule.isEnabled, !rule.find.isEmpty else { return partial }
            return partial.replacingOccurrences(
                of: rule.find,
                with: rule.replaceWith,
                options: rule.caseSensitive ? [] : [.caseInsensitive]
            )
        }
    }
}
