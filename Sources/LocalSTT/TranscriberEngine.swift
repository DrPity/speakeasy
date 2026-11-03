import AppKit
import AVFoundation
import CoreAudio
import LocalSTTCore
import Observation
import os
import Speech

/// Runs the audio and speech pipeline: `AVAudioEngine` → `AVAudioConverter` →
/// `SpeechAnalyzer`/`SpeechTranscriber`. Controlled through `start()` / `stop()` / `cancel()`.
@MainActor
@Observable
final class TranscriberEngine {

    /// The lifecycle of a single session. Modelled explicitly instead of with
    /// booleans because the transitions were the historical source of bugs:
    /// `stop()` returns at once while draining continues in the background,
    /// meaning "not capturing" and "idle" are not the same thing.
    enum State: Equatable {
        case idle
        case starting
        case recording
        case finalizing
        case cancelling
    }

    // UI-observable state (mutated exclusively on the main actor).
    var partialText: String = ""
    var finalText: String = ""
    var statusText: String = "Awaiting permissions…"
    private(set) var state: State = .idle
    var modelReady: Bool = false
    /// Microphone level in 0...1 feeding the HUD meter. Refreshed solely while `meterEnabled`.
    private(set) var level: Float = 0
    /// Set mid-session when the microphone delivers no audio at all, so the HUD
    /// can say so while the key is still held. Cleared when a session starts.
    private(set) var captureWarning: String?

    /// Called on the main actor with the completed transcript after a capture
    /// has finished and drained entirely. The coordinator connects this to delivery.
    var onFinalText: ((String) -> Void)?
    /// Called after a session has ended completely (completed, thrown away or failed).
    var onSessionEnd: (() -> Void)?

    /// Words that steer the recognizer during the next session. Provided by the coordinator.
    var contextualTerms: [String] = []
    /// Controls whether the input level gets computed and published.
    var meterEnabled: Bool = true
    /// The idle status line; varies with the input mode, which is owned by Settings.
    var readyHint: String = "Ready — keep the key held and speak."

    private(set) var locale: Locale

    /// The maximum time draining may run before the analyzer is shut down
    /// forcibly. It used to be unbounded, which could leave the UI stuck on its
    /// finishing message indefinitely.
    private static let finalizeTimeout: Duration = .seconds(3)
    private static let tapBufferSize: AVAudioFrameCount = 4096
    /// Comfortable slack above `tapBufferSize`, letting an oversized engine
    /// buffer be processed with no extra allocation.
    private static let mixBufferCapacity: AVAudioFrameCount = tapBufferSize * 8
    /// Upper bound on how frequently the meter reports to the main actor.
    private static let meterInterval: CFAbsoluteTime = 1.0 / 20.0
    /// A running engine delivers its first buffer within ~100 ms; after this
    /// long with nothing, capture is broken rather than slow.
    private static let noAudioTimeout: Duration = .milliseconds(750)
    static let noAudioMessage = "No audio from the microphone — check the input in Audio MIDI Setup or pick another mic."

    private static let log = Logger(subsystem: "com.mschade.localstt", category: "capture")

    private var engine = AVAudioEngine()

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var converter: AVAudioConverter?
    private var analyzerFormat: AVAudioFormat?
    private var resultsTask: Task<Void, Never>?
    private var finalizeTask: Task<Void, Never>?
    /// Eases the published level so the HUD waveform stays fluid at the meter's
    /// 20 Hz reporting rate.
    private var levelSmoother = LevelSmoother()
    /// Shared between tap callbacks: it serves purely as the converter's input,
    /// which is drained synchronously, making reuse safe. (The converter's
    /// *output* buffer is still created fresh each callback — it is passed to
    /// the analyzer and read after the callback returns, so reuse would be wrong.)
    private var mixBuffer: AVAudioPCMBuffer?
    /// Flipped by the tap (audio thread) on the first buffer of a session.
    @ObservationIgnored private var audioArrived = OSAllocatedUnfairLock(initialState: false)
    @ObservationIgnored private var noAudioTask: Task<Void, Never>?

    init(locale: Locale = Locale(identifier: Settings.defaultLocaleIdentifier)) {
        self.locale = locale
    }

    /// True for as long as a session appears active to the user.
    var isRecording: Bool { state == .starting || state == .recording }

    /// What the UI displays: the settled segments followed by the still-volatile tail.
    var displayText: String {
        if partialText.isEmpty { return finalText }
        return finalText.isEmpty ? partialText : finalText + " " + partialText
    }

    // MARK: - Model assets

    /// Make sure the speech model for `newLocale` (or the current language) is
    /// present, fetching it when it isn't.
    func prepareModel(locale newLocale: Locale? = nil) async {
        if let newLocale, newLocale.identifier(.bcp47) != locale.identifier(.bcp47) {
            // Release the previous reservation ahead of claiming another; the OS
            // caps how many may be held at once.
            _ = await AssetInventory.release(reservedLocale: locale)
            locale = newLocale
            modelReady = false
        }
        let target = locale
        statusText = "Verifying the language model…"

        let supported = await SpeechTranscriber.supportedLocales
        guard supported.contains(where: { $0.identifier(.bcp47) == target.identifier(.bcp47) }) else {
            statusText = "\(Self.displayName(for: target)) can't be used on this Mac."
            return
        }

        // Claim (allocate) the locale for this process *ahead of* constructing
        // any analyzer. Required even if the asset is already on disk — without
        // it, SpeechAnalyzer logs "Cannot use modules with unallocated locales"
        // and quietly produces no results at all. (The claim persists for the
        // process's lifetime.)
        await releaseSurplusReservations(keeping: target)
        do {
            _ = try await AssetInventory.reserve(locale: target)
        } catch {
            statusText = "The language model couldn't be reserved: \(error.localizedDescription)"
            return
        }

        let installed = await SpeechTranscriber.installedLocales
        if !installed.contains(where: { $0.identifier(.bcp47) == target.identifier(.bcp47) }) {
            statusText = "Fetching the language model…"
            let probe = SpeechTranscriber(locale: target, preset: .progressiveTranscription)
            do {
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [probe]) {
                    try await request.downloadAndInstall()
                }
            } catch {
                statusText = "The model download failed: \(error.localizedDescription)"
                return
            }
        }

        modelReady = true
        statusText = readyHint
    }

    /// The languages present on this Mac, used by the language picker.
    static func installedLocales() async -> [Locale] {
        await SpeechTranscriber.installedLocales
    }

    static func supportedLocales() async -> [Locale] {
        await SpeechTranscriber.supportedLocales
    }

    static func displayName(for locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier)
            ?? locale.identifier(.bcp47)
    }

    /// Shed reservations once the system cap is reached, preventing repeated
    /// language switching from breaking.
    private func releaseSurplusReservations(keeping target: Locale) async {
        let reserved = await AssetInventory.reservedLocales
        guard reserved.count >= AssetInventory.maximumReservedLocales else { return }
        for reservation in reserved
        where reservation.identifier(.bcp47) != target.identifier(.bcp47) {
            _ = await AssetInventory.release(reservedLocale: reservation)
        }
    }

    // MARK: - Session control

    func start(deviceID: AudioDeviceID?) {
        guard modelReady else { return }
        switch state {
        case .idle, .finalizing, .cancelling:
            break
        case .starting, .recording:
            return
        }

        state = .starting
        statusText = "Warming up…"
        let pending = finalizeTask

        Task {
            // Allow any still-running finalization to complete first. It owns
            // the old analyzer and must still hand over the old transcript;
            // constructing a replacement pipeline beneath it used to silently
            // break the second dictation in a row.
            await pending?.value

            switch state {
            case .starting:
                break
            case .finalizing, .cancelling:
                // The key was let go before a pipeline existed at all — there
                // is nothing to drain.
                state = .idle
                statusText = readyHint
                onSessionEnd?()
                return
            default:
                return
            }

            partialText = ""
            finalText = ""
            captureWarning = nil
            level = 0
            levelSmoother.reset()

            do {
                try await beginPipeline(deviceID: deviceID)
            } catch {
                state = .idle
                statusText = "Failed: \(error.localizedDescription)"
                cleanup()
                onSessionEnd?()
                return
            }

            switch state {
            case .starting:
                state = .recording
                statusText = "Listening…"
            case .finalizing:
                // The key came up while the pipeline was still being assembled.
                beginFinalize(cancelled: false)
            case .cancelling:
                beginFinalize(cancelled: true)
            default:
                teardownAudio()
                cleanup()
            }
        }
    }

    /// End the session and hand over the transcript.
    func stop() {
        switch state {
        case .recording:
            state = .finalizing
            beginFinalize(cancelled: false)
        case .starting:
            // The pipeline is still being assembled; `start` drains once it lands.
            state = .finalizing
        default:
            break
        }
    }

    /// Throw the session away and hand over nothing.
    func cancel() {
        switch state {
        case .recording:
            state = .cancelling
            beginFinalize(cancelled: true)
        case .starting:
            state = .cancelling
        default:
            break
        }
    }

    private func beginFinalize(cancelled: Bool) {
        teardownAudio()
        let analyzer = self.analyzer
        let results = self.resultsTask
        statusText = cancelled ? "Throwing away…" : "Finishing up…"

        finalizeTask = Task {
            await Self.drain(analyzer: analyzer, results: results, cancelled: cancelled)

            let result = cancelled ? "" : finalText
            partialText = ""
            finalText = ""
            level = 0
            levelSmoother.reset()
            cleanup()

            // Return to idle solely when no follow-up session began meanwhile
            // (a quick re-press would have left us in `.starting`).
            if state == .finalizing || state == .cancelling {
                state = .idle
            }

            if cancelled {
                statusText = "Thrown away."
            } else if result.isEmpty, !audioArrived.withLock({ $0 }) {
                statusText = Self.noAudioMessage
            } else if result.isEmpty {
                statusText = "Ready — nothing was heard."
            } else {
                statusText = "Finished."
                onFinalText?(result)
            }
            onSessionEnd?()
        }
    }

    /// Shut the analyzer down gracefully and await the results stream's end,
    /// guarded by a watchdog so a stuck analyzer can't freeze the session for good.
    private static func drain(
        analyzer: SpeechAnalyzer?,
        results: Task<Void, Never>?,
        cancelled: Bool
    ) async {
        guard let analyzer else {
            await results?.value
            return
        }

        let finish = Task {
            if cancelled {
                await analyzer.cancelAndFinishNow()
            } else {
                try? await analyzer.finalizeAndFinishThroughEndOfInput()
            }
        }
        let watchdog = Task {
            try? await Task.sleep(for: finalizeTimeout)
            guard !Task.isCancelled else { return }
            await analyzer.cancelAndFinishNow()
            results?.cancel()
        }

        await finish.value
        await results?.value
        watchdog.cancel()
    }

    // MARK: - Pipeline

    private func beginPipeline(deviceID: AudioDeviceID?) async throws {
        // Build a NEW engine per recording. Keeping one long-lived AVAudioEngine
        // across input-device changes retains stale format/device bindings —
        // the visible symptom was capture falling silent after switching mics
        // until the app relaunched. A fresh engine attaches the selected device
        // cleanly every time.
        let engine = AVAudioEngine()
        self.engine = engine

        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.transcriber = transcriber
        self.analyzer = analyzer

        // Steer the recognizer toward the user's personal vocabulary. It must be
        // applied ahead of analysis, and since the `modules:` initialiser accepts
        // no context, it is attached in a separate call.
        if !contextualTerms.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = contextualTerms
            try await analyzer.setContext(context)
        }

        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        self.analyzerFormat = format

        // Point the engine at the selected input device PRIOR TO installing the
        // tap or starting.
        if let deviceID {
            try CoreAudioHelpers.setInputDevice(deviceID, on: engine)
        }

        let inputNode = engine.inputNode

        // Preflight: ask for the device's *real* format, not the one the node
        // reports. When the input and output devices run at different rates,
        // the reported one is wrong and a tap installed at it never fires
        // (see CaptureFormatPolicy).
        let hardware = inputNode.inputFormat(forBus: 0)
        let reported = inputNode.outputFormat(forBus: 0)
        guard let plan = CaptureFormatPolicy.plan(
                  hardwareRate: hardware.sampleRate,
                  hardwareChannels: hardware.channelCount,
                  reportedRate: reported.sampleRate,
                  reportedChannels: reported.channelCount
              ),
              let tapFormat = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: plan.sampleRate,
                  channels: plan.channels,
                  interleaved: false
              )
        else {
            Self.log.error("Unusable input format: hardware \(hardware, privacy: .public), reported \(reported, privacy: .public)")
            throw NSError(domain: "LocalSTT", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "The microphone reports no usable audio format. Reconnect it or pick another input.",
            ])
        }
        if plan.correctedMismatch {
            Self.log.notice("Input reports \(reported.sampleRate, privacy: .public) Hz but the hardware runs at \(hardware.sampleRate, privacy: .public) Hz; tapping at the hardware rate")
        }

        // Multi-channel input is mixed down to mono *manually* inside the tap
        // (refer to AudioMixdown): AVAudioConverter's own channel reduction
        // produces silence for devices exposing discrete, layout-less channels
        // (such as the Scarlett 2i2's four). The converter therefore handles
        // sample-rate conversion alone: mono(tap rate) → mono(analyzer).
        guard let mixFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: plan.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(domain: "LocalSTT", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Could not set up a \(Int(plan.sampleRate)) Hz mono mix format.",
            ])
        }

        if let format {
            converter = AVAudioConverter(from: mixFormat, to: format)
        }
        mixBuffer = AVAudioPCMBuffer(pcmFormat: mixFormat, frameCapacity: Self.mixBufferCapacity)

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputContinuation = continuation

        // Drain the transcription results.
        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    let isFinal = result.isFinal
                    await MainActor.run {
                        guard let self else { return }
                        if isFinal {
                            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                self.finalText += (self.finalText.isEmpty ? "" : " ") + trimmed
                            }
                            self.partialText = ""
                        } else {
                            self.partialText = text
                        }
                    }
                }
            } catch is CancellationError {
                // Interrupted by the drain watchdog; nothing here needs surfacing.
            } catch {
                await MainActor.run {
                    self?.statusText = "Transcription failed: \(error.localizedDescription)"
                }
            }
        }

        try await analyzer.start(inputSequence: stream)

        // The tap executes on the audio thread; only Sendable locals may be captured.
        let converter = self.converter
        let analyzerFormat = self.analyzerFormat
        let mixBuffer = self.mixBuffer
        let meterEnabled = self.meterEnabled
        var lastMeterPublish: CFAbsoluteTime = 0
        let audioArrived = OSAllocatedUnfairLock(initialState: false)
        self.audioArrived = audioArrived

        inputNode.installTap(onBus: 0, bufferSize: Self.tapBufferSize, format: tapFormat) { [weak self] buffer, _ in
            audioArrived.withLock { $0 = true }
            guard let converter, let analyzerFormat, let mixBuffer,
                  let channelData = buffer.floatChannelData,
                  let mixData = mixBuffer.floatChannelData else {
                continuation.yield(AnalyzerInput(buffer: buffer))
                return
            }
            let frames = Int(buffer.frameLength)
            guard frames > 0, frames <= Int(mixBuffer.frameCapacity) else { return }

            mixBuffer.frameLength = AVAudioFrameCount(frames)
            let out = mixData[0]
            // Mix down and measure level in one pass across the samples.
            let rms = AudioMixdown.mixToMono(
                frameCount: frames,
                channelCount: Int(buffer.format.channelCount),
                sample: { channelData[$0][$1] },
                output: { out[$0] = $1 }
            )

            if meterEnabled {
                let now = CFAbsoluteTimeGetCurrent()
                if now - lastMeterPublish >= Self.meterInterval {
                    lastMeterPublish = now
                    let value = AudioMixdown.meterLevel(rms: rms)
                    Task { @MainActor [weak self] in
                        guard let self, self.isRecording else { return }
                        self.level = self.levelSmoother.update(toward: value)
                    }
                }
            }

            let ratio = analyzerFormat.sampleRate / mixBuffer.format.sampleRate
            let capacity = AVAudioFrameCount(Double(frames) * ratio) + 1024
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity) else { return }

            var fed = false
            var error: NSError?
            converter.convert(to: outBuffer, error: &error) { _, statusPtr in
                if fed {
                    statusPtr.pointee = .noDataNow
                    return nil
                }
                fed = true
                statusPtr.pointee = .haveData
                return mixBuffer
            }
            if error == nil, outBuffer.frameLength > 0 {
                continuation.yield(AnalyzerInput(buffer: outBuffer))
            }
        }

        engine.prepare()
        try engine.start()

        // Safety net for causes the preflight can't foresee: a running engine
        // that delivers nothing gets flagged while the key is still held.
        noAudioTask = Task { [weak self] in
            try? await Task.sleep(for: Self.noAudioTimeout)
            guard !Task.isCancelled, let self, self.isRecording,
                  !audioArrived.withLock({ $0 }) else { return }
            Self.log.error("No audio buffers \(Self.noAudioTimeout, privacy: .public) after start (hardware \(hardware, privacy: .public), tap \(tapFormat, privacy: .public))")
            self.captureWarning = Self.noAudioMessage
        }
    }

    /// Halt audio capture. Kept apart from `cleanup` since the analyzer must
    /// survive this step to finish draining.
    private func teardownAudio() {
        noAudioTask?.cancel()
        noAudioTask = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        inputContinuation?.finish()
        inputContinuation = nil
    }

    /// Tear down the speech pipeline, letting the following session begin from
    /// a blank slate.
    private func cleanup() {
        resultsTask = nil
        inputContinuation = nil
        converter = nil
        analyzerFormat = nil
        analyzer = nil
        transcriber = nil
        mixBuffer = nil
    }

    // MARK: - Clipboard helpers

    func copyToClipboard(_ string: String) {
        guard !string.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    func clear() {
        partialText = ""
        finalText = ""
        if modelReady { statusText = readyHint }
    }
}

#if DEBUG
extension TranscriberEngine {
    /// Snapshot rendering only (`--snapshot`).
    func overrideForSnapshot(state: State, warning: String?, level: Float, ready: Bool) {
        self.state = state
        captureWarning = warning
        self.level = level
        modelReady = ready
        if ready { statusText = readyHint }
    }
}
#endif
