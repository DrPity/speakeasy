import LocalSTTCore
import SwiftUI

/// Manages the words that steer the recognizer plus the exact-match replacement
/// rules applied afterwards.
struct VocabularyEditor: View {
    @Environment(AppModel.self) private var model
    @Binding var screen: PanelScreen

    @State private var newTerm = ""
    @State private var newFind = ""
    @State private var newReplacement = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SubscreenHeader(
                title: "Vocabulary",
                subtitle: "Stored on this Mac, readable only by you.",
                onBack: { screen = .settings }
            )

            PanelScroll {
                VStack(alignment: .leading, spacing: 14) {
                    termsSection
                    rulesSection
                }
                .padding(.bottom, 2)
            }

            if let error = model.vocabularyError {
                Text(error).font(.system(size: 12)).foregroundStyle(Theme.amber)
            }
        }
    }

    // MARK: - Words

    private var termsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                SectionLabel("Words")
                InfoBadge(help: "Names and jargon handed to the recogniser before you speak (when “Prefer my words” "
                          + "is on). Up to \(Vocabulary.maxTerms).")
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Names and jargon the recogniser should expect.").footnoteStyle()

                if model.vocabulary.terms.isEmpty {
                    Text("No words yet.").footnoteStyle()
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(Array(model.vocabulary.terms.enumerated()), id: \.offset) { index, term in
                            chip(term) { removeTerm(at: index) }
                        }
                    }
                }

                HStack(spacing: 8) {
                    TextField("Add a word or name", text: $newTerm)
                        .inkField()
                        .onSubmit { addTerm() }
                    Button("Add") { addTerm() }
                        .buttonStyle(AccentButtonStyle())
                        .disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func chip(_ term: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 2) {
            Text(term).font(.system(size: 13)).foregroundStyle(Theme.glass)
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.secondary)
            .frame(width: 22, height: 22)
            .contentShape(Circle())
            .help("Remove “\(term)”")
            .accessibilityLabel("Remove \(term)")
        }
        .padding(.leading, 10)
        .padding(.trailing, 3)
        .frame(height: 28)
        .background(Theme.raised, in: Capsule())
    }

    private func addTerm() {
        let trimmed = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var vocabulary = model.vocabulary
        vocabulary.terms.append(trimmed)
        model.updateVocabulary(vocabulary)
        newTerm = ""
    }

    private func removeTerm(at index: Int) {
        var vocabulary = model.vocabulary
        guard vocabulary.terms.indices.contains(index) else { return }
        vocabulary.terms.remove(at: index)
        model.updateVocabulary(vocabulary)
    }

    // MARK: - Replacement rules

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                SectionLabel("Find & replace")
                InfoBadge(help: "Run on the finished text, top to bottom, when “Apply find & replace” is on. "
                          + "Exact text only — never patterns. Aa makes a rule case-sensitive.")
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("Applied to the finished text, top to bottom. Exact matches only, never patterns.")
                    .footnoteStyle()
                    .padding([.horizontal, .top], 12)
                    .padding(.bottom, 4)

                if model.vocabulary.rules.isEmpty {
                    Text("No rules yet.").footnoteStyle().padding(.horizontal, 12).padding(.vertical, 8)
                } else {
                    ForEach(model.vocabulary.rules) { rule in
                        ruleRow(rule)
                    }
                }

                HStack(spacing: 8) {
                    TextField("When I say…", text: $newFind).inkField()
                    TextField("…type", text: $newReplacement)
                        .inkField()
                        .onSubmit { addRule() }
                    Button("Add") { addRule() }
                        .buttonStyle(AccentButtonStyle())
                        .disabled(newFind.isEmpty)
                }
                .padding(12)
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func ruleRow(_ rule: ReplacementRule) -> some View {
        HStack(spacing: 8) {
            Toggle("Rule on", isOn: Binding(
                get: { rule.isEnabled },
                set: { setEnabled(rule, $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help(rule.isEnabled ? "This rule is on" : "This rule is off")

            Text(rule.find)
                .font(.system(size: 13))
                .foregroundStyle(rule.isEnabled ? Theme.secondary : Theme.tertiary)
                .lineLimit(1)
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.tertiary)
            Text(rule.replaceWith.isEmpty ? "(nothing)" : rule.replaceWith)
                .font(.system(size: 13, weight: rule.isEnabled ? .semibold : .regular))
                .foregroundStyle(rule.isEnabled && !rule.replaceWith.isEmpty ? Theme.glass : Theme.tertiary)
                .lineLimit(1)
            Spacer(minLength: 4)

            Button {
                toggleCaseSensitivity(rule)
            } label: {
                Text("Aa")
                    .font(.system(size: 11, weight: rule.caseSensitive ? .semibold : .regular))
                    .foregroundStyle(rule.caseSensitive ? Theme.ink : Theme.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(rule.caseSensitive ? Theme.glass : .clear)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(rule.caseSensitive ? .clear : Theme.controlBorder))
            }
            .buttonStyle(.plain)
            .help(rule.caseSensitive ? "Case matters — click to ignore case" : "Case is ignored — click to match case")

            Button {
                removeRule(rule)
            } label: {
                Image(systemName: "trash").font(.system(size: 11))
            }
            .buttonStyle(IconButtonStyle())
            .help("Delete this rule")
            .accessibilityLabel("Delete rule")
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    private func addRule() {
        guard !newFind.isEmpty else { return }
        var vocabulary = model.vocabulary
        vocabulary.rules.append(ReplacementRule(find: newFind, replaceWith: newReplacement))
        model.updateVocabulary(vocabulary)
        newFind = ""
        newReplacement = ""
    }

    private func removeRule(_ rule: ReplacementRule) {
        var vocabulary = model.vocabulary
        vocabulary.rules.removeAll { $0.id == rule.id }
        model.updateVocabulary(vocabulary)
    }

    private func setEnabled(_ rule: ReplacementRule, _ isEnabled: Bool) {
        mutate(rule) { $0.isEnabled = isEnabled }
    }

    private func toggleCaseSensitivity(_ rule: ReplacementRule) {
        mutate(rule) { $0.caseSensitive.toggle() }
    }

    private func mutate(_ rule: ReplacementRule, _ change: (inout ReplacementRule) -> Void) {
        var vocabulary = model.vocabulary
        guard let index = vocabulary.rules.firstIndex(where: { $0.id == rule.id }) else { return }
        change(&vocabulary.rules[index])
        model.updateVocabulary(vocabulary)
    }
}

private extension View {
    /// The dark input field from the design.
    func inkField() -> some View {
        textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(Theme.glass)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.controlBorder))
    }
}
