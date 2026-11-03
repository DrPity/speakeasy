import Foundation
import Testing
@testable import LocalSTTCore

@Suite("TextTransformer")
struct TextTransformerTests {

    @Test("Without rules the text is untouched")
    func noRulesIsIdentity() {
        #expect(TextTransformer.apply([], to: "hello world") == "hello world")
    }

    @Test("Rules run sequentially, letting later rules observe earlier results")
    func appliesRulesInOrder() {
        let rules = [
            ReplacementRule(find: "a", replaceWith: "b"),
            ReplacementRule(find: "b", replaceWith: "c")
        ]
        #expect(TextTransformer.apply(rules, to: "a") == "c")
    }

    @Test("Case handling is decided per rule")
    func honoursCaseSensitivity() {
        let insensitive = [ReplacementRule(find: "miro", replaceWith: "Miro")]
        #expect(TextTransformer.apply(insensitive, to: "MIRO and miro") == "Miro and Miro")

        let sensitive = [ReplacementRule(find: "miro", replaceWith: "Miro", caseSensitive: true)]
        #expect(TextTransformer.apply(sensitive, to: "MIRO and miro") == "MIRO and Miro")
    }

    @Test("Inactive rules and empty patterns are bypassed")
    func skipsDisabledAndBlankRules() {
        let rules = [
            ReplacementRule(find: "x", replaceWith: "y", isEnabled: false),
            ReplacementRule(find: "", replaceWith: "!!!")
        ]
        #expect(TextTransformer.apply(rules, to: "x") == "x")
    }

    @Test("Matches are exact, never regex")
    func treatsPatternsAsLiteral() {
        // A regex engine would match everything in this case; exact matching must not.
        let wildcard = [ReplacementRule(find: ".*", replaceWith: "GONE")]
        #expect(TextTransformer.apply(wildcard, to: "keep me") == "keep me")
        #expect(TextTransformer.apply(wildcard, to: "a .* b") == "a GONE b")

        // Any metacharacters in the replacement land verbatim.
        let dollar = [ReplacementRule(find: "price", replaceWith: "$1")]
        #expect(TextTransformer.apply(dollar, to: "price") == "$1")

        let brackets = [ReplacementRule(find: "[a]", replaceWith: "ok")]
        #expect(TextTransformer.apply(brackets, to: "[a]") == "ok")
        #expect(TextTransformer.apply(brackets, to: "a") == "a")
    }
}
