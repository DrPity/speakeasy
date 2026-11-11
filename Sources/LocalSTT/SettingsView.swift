import LocalSTTCore
import SwiftUI

/// All optional behaviour, disabled unless changed. Opened from the gear icon
/// in the panel. Every row carries a hover explanation (ⓘ + tooltip).
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Binding var screen: PanelScreen

    @State private var loginItemEnabled = false
    @State private var loginItemError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SubscreenHeader(
                title: "Preferences",
                subtitle: "Optional — the defaults just work.",
                onBack: { screen = .main }
            )

            PanelScroll {
                VStack(alignment: .leading, spacing: 14) {
                    dictationSection
                    outputSection
                    vocabularySection
                    overlaySection
                    languageSection
                }
                .padding(.bottom, 2)
            }
        }
        .onAppear { loginItemEnabled = LoginItem.isEnabled }
    }

    // MARK: - Dictation

    private var dictationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Dictation")
            GroupCard {
                SettingRow(
                    title: "Shortcut",
                    help: "Hold to talk: dictate while the key is down, the text is typed when you let go. "
                        + "Tap to toggle: tap once to start, again to finish — easier for long dictation."
                ) {
                    Picker("Shortcut style", selection: inputModeBinding) {
                        ForEach(Settings.InputMode.allCases) { mode in
                            Text(mode.shortLabel).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                HotkeyRecorder()
                SettingRow(
                    title: "Escape discards",
                    help: "Press Escape mid-dictation to throw it away instead of typing it.",
                    footnote: "Only while you’re dictating — Escape works normally otherwise.",
                    showsDivider: false
                ) {
                    Toggle("Escape discards", isOn: cancelBinding).labelsHidden().toggleStyle(.switch)
                }
            }
        }
    }

    private var inputModeBinding: Binding<Settings.InputMode> {
        Binding(
            get: { model.settings.inputMode },
            set: { model.settings.inputMode = $0; model.syncFromSettings() }
        )
    }

    private var cancelBinding: Binding<Bool> {
        Binding(
            get: { model.settings.cancelWithEscape },
            set: { model.settings.cancelWithEscape = $0 }
        )
    }

    // MARK: - Output

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Output")
            GroupCard {
                SettingRow(
                    title: "Deliver text by",
                    help: "Typing sends the text as keystrokes and never touches the clipboard. "
                        + "Pasting is much faster for long text but briefly puts it on the clipboard.",
                    footnote: model.settings.injectionMethod == .paste ? nil : "Typing leaves your clipboard alone.",
                    showsDivider: false
                ) {
                    Picker("Delivery", selection: injectionBinding) {
                        ForEach(Settings.InjectionMethod.allCases) { method in
                            Text(method.shortLabel).tag(method)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                if model.settings.injectionMethod == .paste {
                    Label {
                        Text("While pasting, the transcript sits on the clipboard for a moment, where other apps "
                             + "could read it. Your previous clipboard is put back afterwards.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .background(Theme.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .padding([.horizontal, .bottom], 10)
                }
            }
        }
    }

    private var injectionBinding: Binding<Settings.InjectionMethod> {
        Binding(
            get: { model.settings.injectionMethod },
            set: { model.settings.injectionMethod = $0 }
        )
    }

    // MARK: - Vocabulary

    private var vocabularySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Vocabulary")
            GroupCard {
                SettingRow(
                    title: "Prefer my words",
                    help: "Hands your word list to the recogniser before you speak, so names and jargon "
                        + "come out spelled the way you wrote them."
                ) {
                    Toggle("Prefer my words", isOn: vocabularyBinding).labelsHidden().toggleStyle(.switch)
                }
                SettingRow(
                    title: "Apply find & replace",
                    help: "After you let go, swaps exact phrases in the finished text — say “eye phone”, "
                        + "get “iPhone”. Nothing else is touched."
                ) {
                    Toggle("Apply find & replace", isOn: replacementsBinding).labelsHidden().toggleStyle(.switch)
                }
                Button { screen = .vocabulary } label: {
                    HStack(spacing: 8) {
                        Text("\(model.vocabulary.terms.count) words · \(model.vocabulary.rules.count) rules")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.glass)
                        Spacer()
                        Text("Manage").font(.system(size: 13)).foregroundStyle(Theme.mint)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.mint)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Edit your words and find-and-replace rules")
            }
            if let error = model.vocabularyError {
                Text(error).font(.system(size: 12)).foregroundStyle(Theme.amber)
            }
        }
    }

    private var vocabularyBinding: Binding<Bool> {
        Binding(
            get: { model.settings.vocabularyEnabled },
            set: { model.settings.vocabularyEnabled = $0; model.syncFromSettings() }
        )
    }

    private var replacementsBinding: Binding<Bool> {
        Binding(
            get: { model.settings.replacementsEnabled },
            set: { model.settings.replacementsEnabled = $0 }
        )
    }

    // MARK: - Overlay & history

    private var overlaySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Overlay & history")
            GroupCard {
                SettingRow(
                    title: "Remember recent transcripts",
                    help: "Keeps your last 10 dictations in the panel so you can copy them again. "
                        + "Held in memory only — never written to disk, gone when you quit.",
                    footnote: "The last 10, in memory only. Gone when you quit."
                ) {
                    Toggle("Remember recent transcripts", isOn: historyBinding).labelsHidden().toggleStyle(.switch)
                }
                SettingRow(
                    title: "Glass follows your voice",
                    help: "The coupe in the overlay and menu bar fills with your voice level, so a dead "
                        + "or wrong microphone shows at once. When off, it just animates.",
                    showsDivider: false
                ) {
                    Toggle("Glass follows your voice", isOn: meterBinding).labelsHidden().toggleStyle(.switch)
                }
            }
        }
    }

    private var historyBinding: Binding<Bool> {
        Binding(
            get: { model.settings.historyEnabled },
            set: { enabled in
                model.settings.historyEnabled = enabled
                if !enabled { model.history.clear() }
            }
        )
    }

    private var meterBinding: Binding<Bool> {
        Binding(
            get: { model.settings.levelMeterEnabled },
            set: { model.settings.levelMeterEnabled = $0; model.syncFromSettings() }
        )
    }

    // MARK: - Language & startup

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Language & startup")
            GroupCard {
                SettingRow(
                    title: "Dictation language",
                    help: "The language you speak. Languages not yet installed are downloaded by macOS "
                        + "the first time you pick them — the model, never your voice.",
                    footnote: model.isSwitchingLocale ? "Setting up the language model…" : nil
                ) {
                    Picker("Dictation language", selection: localeBinding) {
                        ForEach(model.supportedLocales, id: \.identifier) { locale in
                            Text(label(for: locale)).tag(locale.identifier(.bcp47))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    // Not fixedSize: a menu picker sizes to its *longest* item,
                    // and some locale names would push the panel off-screen.
                    .frame(maxWidth: 170)
                    .disabled(model.engine.isRecording || model.isSwitchingLocale || model.supportedLocales.isEmpty)
                }
                SettingRow(
                    title: "Open at login",
                    help: "Starts Speakeasy when you log in. Tied to where the app is, so keep it in /Applications.",
                    footnote: loginFootnote,
                    showsDivider: false
                ) {
                    Toggle("Open at login", isOn: Binding(
                        get: { loginItemEnabled },
                        set: { setLoginItem($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                if LoginItem.needsApproval {
                    Button("Open Login Items settings…") { LoginItem.openLoginItemsSettings() }
                        .buttonStyle(GhostButtonStyle())
                        .padding([.horizontal, .bottom], 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .task { await model.refreshLocales() }
    }

    private var loginFootnote: String? {
        if let loginItemError { return loginItemError }
        if LoginItem.needsApproval { return "macOS is waiting for your approval." }
        return nil
    }

    private var localeBinding: Binding<String> {
        Binding(
            get: { model.settings.localeIdentifier },
            set: { identifier in Task { await model.selectLocale(identifier) } }
        )
    }

    private func label(for locale: Locale) -> String {
        let name = TranscriberEngine.displayName(for: locale)
        return model.installedLocaleIdentifiers.contains(locale.identifier(.bcp47))
            ? name
            : "\(name) (downloads)"
    }

    private func setLoginItem(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            loginItemEnabled = LoginItem.isEnabled
            loginItemError = nil
        } catch {
            loginItemEnabled = LoginItem.isEnabled
            loginItemError = "The login item couldn't be updated: \(error.localizedDescription)"
        }
    }
}

extension Settings.InputMode {
    /// Fits a segmented control; `label` stays the long form.
    var shortLabel: String {
        switch self {
        case .pushToTalk: return "Hold to talk"
        case .toggle: return "Tap to toggle"
        }
    }
}

extension Settings.InjectionMethod {
    var shortLabel: String {
        switch self {
        case .keystrokes: return "Typing"
        case .paste: return "Pasting"
        }
    }
}
