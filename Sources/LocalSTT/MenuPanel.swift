import AppKit
import LocalSTTCore
import SwiftUI

/// Identifies the screen the dropdown currently presents.
enum PanelScreen {
    case main
    case settings
    case vocabulary
}

/// The dropdown that opens from the menu-bar icon.
struct MenuPanel: View {
    @Environment(AppModel.self) private var model
    @State private var screen: PanelScreen = .main

    var body: some View {
        Group {
            switch screen {
            case .main:
                mainScreen
            case .settings:
                SettingsView(screen: $screen)
            case .vocabulary:
                VocabularyEditor(screen: $screen)
            }
        }
        .padding(16)
        .frame(width: 380)
        .background(Theme.panel)
        .environment(\.colorScheme, .dark)
        .tint(Theme.mint)
        .onAppear { model.refreshAndAdvance() }
    }

    private var setupComplete: Bool {
        model.permissions.micAndSpeechGranted && model.permissions.accessibilityGranted
    }

    private var mainScreen: some View {
        VStack(alignment: .leading, spacing: 16) {
            MainHeader(onPreferences: { screen = .settings })
            if setupComplete {
                ReadyHero()
                MicrophoneSection()
                TranscriptSection()
            } else {
                OnboardingChecklist()
                PrivacyNote()
            }
            footer
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("\(TranscriberEngine.displayName(for: model.settings.locale)) · on-device")
                .font(.system(size: 12))
                .foregroundStyle(Theme.tertiary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
                .padding(.horizontal, 6)
                .frame(minHeight: 28)
                .keyboardShortcut("q")
        }
        .padding(.top, 12)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}

// MARK: - Header

private struct MainHeader: View {
    @Environment(AppModel.self) private var model
    let onPreferences: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CoupeGlyphView(mode: model.coupeMode, level: Double(model.engine.level), size: 22)
                .frame(width: 36, height: 36)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text("Speakeasy")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.glass)
                HStack(spacing: 6) {
                    StatusDot(color: status.color)
                    Text(status.text)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button(action: onPreferences) {
                Image(systemName: "gearshape").font(.system(size: 15))
            }
            .buttonStyle(IconButtonStyle())
            .help("Preferences")
            .accessibilityLabel("Preferences")
        }
    }

    /// One short line: "Ready", "Listening…", "Needs setup", or whatever the
    /// engine is reporting (downloading a model, an error).
    private var status: (text: String, color: Color) {
        let engine = model.engine
        if !(model.permissions.micAndSpeechGranted && model.permissions.accessibilityGranted) {
            return ("Needs setup", Theme.amber)
        }
        if engine.captureWarning != nil { return ("No audio from the microphone", Theme.amber) }
        if engine.isRecording { return ("Listening…", Theme.mint) }
        if engine.modelReady, engine.statusText == engine.readyHint { return ("Ready", Theme.mint) }
        let isProblem = engine.statusText.hasPrefix("Failed") || engine.statusText.hasPrefix("No audio")
            || engine.statusText.contains("couldn't") || engine.statusText.contains("failed")
        return (engine.statusText, isProblem ? Theme.amber : (engine.modelReady ? Theme.mint : Theme.tertiary))
    }
}

// MARK: - Ready

private struct ReadyHero: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(model.settings.inputMode == .pushToTalk ? "Hold" : "Tap")
                KeyCap(text: model.hotkey.shortcut.displayString)
                Text(model.settings.inputMode == .pushToTalk ? "and speak" : "to start and stop")
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Theme.glass)
            Text("The text is typed wherever your cursor is.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct MicrophoneSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let selection = Binding(
            get: { model.devices.selectedUID },
            set: { model.devices.selectedUID = $0 }
        )
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Microphone")
            HStack(spacing: 10) {
                Picker("Microphone", selection: selection) {
                    ForEach(model.devices.devices) { device in
                        Label(device.name, systemImage: "mic").tag(device.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(model.engine.isRecording)
                .help("The input Speakeasy listens to. Changes apply from the next dictation.")
                if model.engine.isRecording {
                    LevelBars(level: model.settings.levelMeterEnabled ? Double(model.engine.level) : 0.4)
                }
            }
        }
    }
}

/// Five bars showing the input level (visible only while dictating, since the
/// microphone is off otherwise).
private struct LevelBars: View {
    let level: Double

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                let weights: [Double] = [0.35, 0.7, 1, 0.6, 0.3]
                Capsule()
                    .fill(Theme.mint)
                    .frame(width: 3, height: 4 + 14 * CGFloat(min(max(level, 0), 1) * weights[index]))
            }
        }
        .frame(height: 20)
        .animation(.easeOut(duration: 0.1), value: level)
        .accessibilityLabel("Input level")
    }
}

private struct TranscriptSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let live = model.engine.displayText
        let entries = model.settings.historyEnabled ? model.history.entries : []

        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(live.isEmpty ? "Last dictation" : "Now")
                if !live.isEmpty {
                    TranscriptCard(text: live, detail: "Listening…", onCopy: nil)
                } else if let latest = entries.first {
                    TranscriptCard(text: latest.text, detail: detail(for: latest)) {
                        model.engine.copyToClipboard(latest.text)
                    }
                } else {
                    Text(model.settings.historyEnabled
                         ? "Your words appear here while you speak."
                         : "Your words appear here while you speak. Turn on “Remember recent transcripts” in Preferences to keep the last few.")
                        .footnoteStyle()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
                }
            }

            if entries.count > (live.isEmpty ? 1 : 0) {
                recent(Array(entries.dropFirst(live.isEmpty ? 1 : 0).prefix(4)))
            }
        }
    }

    private func recent(_ items: [TranscriptHistory.Entry]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                SectionLabel("Recent")
                Image(systemName: "lock")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.tertiary)
                Text("memory only").font(.system(size: 12)).foregroundStyle(Theme.tertiary)
                Spacer()
                Button("Clear all") { model.history.clear() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.mint)
                    .help("Forget every remembered transcript now")
            }
            ForEach(items) { entry in
                HStack(spacing: 8) {
                    Text(entry.text)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.glass.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        model.engine.copyToClipboard(entry.text)
                    } label: {
                        Image(systemName: "doc.on.doc").font(.system(size: 12))
                    }
                    .buttonStyle(IconButtonStyle())
                    .help("Copy this entry")
                    .accessibilityLabel("Copy entry")
                }
                .frame(minHeight: 36)
                .overlay(alignment: .bottom) {
                    if entry.id != items.last?.id {
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                    }
                }
            }
        }
    }

    private func detail(for entry: TranscriptHistory.Entry) -> String {
        let words = entry.text.split(whereSeparator: \.isWhitespace).count
        let when = entry.date.timeIntervalSinceNow > -60
            ? "just now"
            : entry.date.formatted(.relative(presentation: .named))
        return "\(words) word\(words == 1 ? "" : "s") · \(when)"
    }
}

private struct TranscriptCard: View {
    let text: String
    let detail: String
    let onCopy: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.glass)
                .lineLimit(5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.tertiary)
                Spacer()
                if let onCopy {
                    Button("Copy", action: onCopy)
                        .buttonStyle(GhostButtonStyle())
                        .help("Copy this transcript to the clipboard")
                }
            }
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
    }
}

// MARK: - Onboarding

/// The three permissions, in order, with the next step highlighted.
private struct OnboardingChecklist: View {
    @Environment(AppModel.self) private var model

    private enum StepState { case done, current, waiting }

    var body: some View {
        let permissions = model.permissions
        let done = [permissions.microphone == .granted, permissions.speech == .granted, permissions.accessibilityGranted]
        let doneCount = done.filter { $0 }.count
        let current = done.firstIndex(of: false)

        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text(doneCount == 2 ? "One step left before you can dictate" : "A few permissions before you can dictate")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.glass)
                HStack(spacing: 10) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.ink)
                            Capsule().fill(Theme.mint)
                                .frame(width: geometry.size.width * CGFloat(doneCount) / 3)
                        }
                    }
                    .frame(height: 6)
                    .accessibilityElement()
                    .accessibilityLabel("Setup progress")
                    .accessibilityValue("\(doneCount) of 3")
                    Text("\(doneCount) of 3")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                }
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))

            VStack(spacing: 4) {
                step(1, "Microphone",
                     explanation: "So Speakeasy can hear you. Audio is processed on this Mac only.",
                     state: state(done[0], index: 0, current: current),
                     grant: permissions.microphone,
                     open: { permissions.openMicrophoneSettings() })
                step(2, "Speech Recognition",
                     explanation: "Turns your voice into text with Apple’s on-device model.",
                     state: state(done[1], index: 1, current: current),
                     grant: permissions.speech,
                     open: { permissions.openSpeechSettings() })
                step(3, "Accessibility",
                     explanation: "Lets the talk key work in every app and types the text for you. Turn on Speakeasy in the list.",
                     state: state(done[2], index: 2, current: current),
                     grant: permissions.accessibilityGranted ? .granted : .denied,
                     open: {
                         permissions.promptAccessibility()
                         permissions.openAccessibilitySettings()
                     })
            }
        }
    }

    private func state(_ isDone: Bool, index: Int, current: Int?) -> StepState {
        if isDone { return .done }
        return index == current ? .current : .waiting
    }

    @ViewBuilder
    private func step(
        _ number: Int,
        _ title: String,
        explanation: String,
        state: StepState,
        grant: PermissionsModel.Grant,
        open: @escaping () -> Void
    ) -> some View {
        switch state {
        case .done:
            HStack(spacing: 12) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 22, height: 22)
                    .background(Theme.mint, in: Circle())
                Text(title).font(.system(size: 14)).foregroundStyle(Theme.glass)
                Spacer()
                Text("Allowed").font(.system(size: 12)).foregroundStyle(Theme.tertiary)
            }
            .frame(minHeight: 44)
        case .waiting:
            HStack(spacing: 12) {
                numberBadge(number, color: Theme.tertiary)
                Text(title).font(.system(size: 14)).foregroundStyle(Theme.secondary)
                Spacer()
            }
            .frame(minHeight: 44)
        case .current:
            HStack(alignment: .top, spacing: 12) {
                numberBadge(number, color: Theme.amber)
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.glass)
                    Text(explanation)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if grant == .undetermined {
                        Button("Allow…") { model.requestPermissions() }
                            .buttonStyle(AccentButtonStyle())
                    } else {
                        Button("Open System Settings…", action: open)
                            .buttonStyle(AccentButtonStyle())
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Theme.amber.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.amber.opacity(0.4)))
        }
    }

    private func numberBadge(_ number: Int, color: Color) -> some View {
        Text("\(number)")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(color)
            .frame(width: 22, height: 22)
            .overlay(Circle().stroke(color, lineWidth: 2))
    }
}

private struct PrivacyNote: View {
    var body: some View {
        Label {
            Text("Audio and text never leave this Mac.")
        } icon: {
            Image(systemName: "shield")
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.tertiary)
    }
}

// MARK: - Sub-screen header

/// Back button, title and subtitle for Preferences and Vocabulary.
struct SubscreenHeader: View {
    let title: String
    let subtitle: String
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(IconButtonStyle())
            .help("Go back")
            .accessibilityLabel("Back")
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.glass)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            Spacer()
        }
    }
}
