import AppKit
import VaniCore

/// Orchestrates the dictation pipeline:
/// hotkey → record → transcribe → clean → inject, updating AppState throughout.
@MainActor
final class DictationController {
    static let shared = DictationController()

    private let recorder = AudioRecorder()
    private let hotkeys = HotkeyManager()

    /// Discard blips shorter than this (accidental key taps).
    private let minimumSamples = Int(AudioRecorder.targetSampleRate * 0.3)

    /// Fallback: holding the PTT key at least this long, then releasing,
    /// locks into hands-free mode (double-tap is the primary way in).
    private let handsFreeHoldThreshold: TimeInterval = 1.5
    /// A press shorter than this is a "tap"; two taps within the window lock
    /// hands-free. 0.35 s tracks the feel of the system double-click time.
    private let tapMaxDuration: TimeInterval = 0.35
    private let doubleTapWindow: TimeInterval = 0.35
    private var pttDownAt: Date?
    private var suppressNextKeyUp = false
    /// Set between the first tap's release and the double-tap deadline; the
    /// recording started by that tap keeps running so a completed double-tap
    /// loses no audio. If no second tap lands, the recording is discarded.
    private var awaitingSecondTap: Task<Void, Never>?

    /// Hot-mic guard (hands-free only): a locked mic that hears this much
    /// trailing silence stops itself. Push-to-talk needs no guard — the key
    /// is physically held. Guards against the accidental open mic that
    /// transcribes a private conversation into whatever field has focus.
    private let silenceAutoStopSeconds = 30.0
    private let silenceCheckCadence = 5.0
    private var silenceMonitor: Task<Void, Never>?

    /// The live-preview re-decode loop; runs only while recording.
    private var previewTask: Task<Void, Never>?
    /// Decodes closed chunks in the background during long dictations so
    /// stopping only waits for the tail.
    private var incremental: IncrementalTranscriber?
    /// Last pasted text + when, for spotting quick re-dictation corrections.
    private var lastPaste: (text: String, at: Date)?

    private init() {}

    func start() {
        // Warm-load Whisper in the background so the first dictation is fast.
        Task.detached(priority: .utility) {
            await TranscriptionService.shared.warmUp(model: SettingsStore.shared.whisperModel)
        }
        // Warm the small preview model too (its own instance) so live preview
        // is ready without stalling the first dictation. Lower priority than
        // the main model — the final pass matters more than the preview.
        // (With the flag off, the code-switch path still warms this model
        // lazily the first time it needs a fast language detector.)
        if FeatureFlags.streamingPreview, SettingsStore.shared.streamingPreview {
            Task.detached(priority: .background) {
                await TranscriptionService.preview.warmUp(model: SettingsStore.previewModel)
            }
        }

        recorder.onInterruption = { [weak self] in
            // Input device changed mid-recording (e.g. AirPods connected):
            // capture is frozen, so finish with what we have.
            guard AppState.shared.status == .recording else { return }
            self?.finishRecording()
        }

        hotkeys.onPushToTalkDown = { [weak self] in self?.pushToTalkDown() }
        hotkeys.onPushToTalkUp = { [weak self] in self?.pushToTalkUp() }
        hotkeys.onEscape = { [weak self] in
            // Esc = never mind: discard the in-progress dictation entirely.
            self?.cancelRecording()
        }
        hotkeys.onToggle = { [weak self] in
            guard let self else { return }
            AppState.shared.status == .recording ? finishRecording() : beginRecording()
        }
        hotkeys.start()
    }

    // MARK: - Push-to-talk with hands-free lock

    private func pushToTalkDown() {
        if AppState.shared.isHandsFree {
            // Single tap while hands-free: stop. Swallow the matching key-up
            // so it isn't misread as the end of a fresh hold.
            suppressNextKeyUp = true
            finishRecording()
            return
        }
        if awaitingSecondTap != nil {
            // Second tap inside the window: lock hands-free. The recording
            // from the first tap never stopped, so nothing is lost.
            awaitingSecondTap?.cancel()
            awaitingSecondTap = nil
            suppressNextKeyUp = true
            AppState.shared.isHandsFree = true
            NSSound(named: "Tink")?.play()
            return
        }
        pttDownAt = Date()
        beginRecording()
    }

    private func pushToTalkUp() {
        if suppressNextKeyUp {
            suppressNextKeyUp = false
            return
        }
        guard AppState.shared.status == .recording else { return }
        guard let downAt = pttDownAt else { return finishRecording() }
        let held = Date().timeIntervalSince(downAt)

        if FeatureFlags.holdToLockHandsFree, held >= handsFreeHoldThreshold {
            // Fallback: held long enough that release locks into hands-free.
            AppState.shared.isHandsFree = true
            NSSound(named: "Tink")?.play()
            return
        }
        if held < tapMaxDuration {
            // A tap, not a hold: keep recording and wait for a second tap.
            // None arrives → it was a stray tap; drop the recording outright
            // (transcribing ~1 s of key-click audio invites hallucinations).
            let window = doubleTapWindow
            awaitingSecondTap = Task { [weak self] in
                try? await Task.sleep(for: .seconds(window))
                guard !Task.isCancelled, let self else { return }
                self.awaitingSecondTap = nil
                self.cancelRecording()
            }
            return
        }
        finishRecording()
    }

    /// Discard an in-progress recording: no transcription, no paste, no
    /// history. Used for stray single taps and Esc.
    private func cancelRecording() {
        guard AppState.shared.status == .recording else { return }
        awaitingSecondTap?.cancel()
        awaitingSecondTap = nil
        previewTask?.cancel()
        previewTask = nil
        silenceMonitor?.cancel()
        silenceMonitor = nil
        incremental?.cancel()
        incremental = nil
        _ = recorder.stop()
        AppState.shared.status = .idle
        AppState.shared.recordingStartedAt = nil
        AppState.shared.previewTranscript = nil
        AppState.shared.audioLevel = 0
        AppState.shared.isHandsFree = false
        pttDownAt = nil
        DictationHUD.shared.setPreviewing(false)
        DictationHUD.shared.hide()
    }

    private func beginRecording() {
        guard AppState.shared.status == .idle else { return }
        guard PermissionsManager.shared.microphone == .granted else {
            OnboardingWindow.shared.show()
            return
        }
        do {
            recorder.onLevel = { level in
                Task { @MainActor in
                    // Smooth the meter so the bars don't flicker.
                    let previous = AppState.shared.audioLevel
                    AppState.shared.audioLevel = previous * 0.6 + level * 0.4
                }
            }
            // Whisper mode: 4× input gain (clamped) so near-silent speech in
            // a shared space still clears the VAD and decodes cleanly.
            try recorder.start(gain: SettingsStore.shared.whisperModeEnabled ? 4 : 1)
            // Refresh the decoder's glossary from the vocabulary so this
            // dictation is biased toward the user's own words.
            if FeatureFlags.promptBias {
                let terms = VocabularyStore.shared.rules.map(\.replace)
                Task.detached { await TranscriptionService.shared.setBiasTerms(terms) }
            }
            AppState.shared.status = .recording
            AppState.shared.recordingStartedAt = Date()
            AppState.shared.previewTranscript = nil
            DictationHUD.shared.show()
            NSSound(named: "Pop")?.play()
            startPreviewLoop()
            let inc = IncrementalTranscriber(
                model: SettingsStore.shared.whisperModel,
                language: SettingsStore.shared.language,
                snapshot: { [recorder] in recorder.snapshot() }
            )
            inc.start()
            incremental = inc
            startSilenceGuard()
        } catch {
            NSLog("Vani: failed to start recording: \(error.localizedDescription)")
        }
    }

    /// Watches a hands-free recording for a long run of trailing silence.
    /// Something was said earlier → stop normally and paste it; the whole
    /// recording is silent → discard it (an accidental lock has nothing
    /// worth pasting, and decoding minutes of room tone invites
    /// hallucinations). Reuses the field-tested adaptive VAD.
    private func startSilenceGuard() {
        silenceMonitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.silenceCheckCadence ?? 5))
                guard !Task.isCancelled, let self else { return }
                guard AppState.shared.status == .recording,
                      AppState.shared.isHandsFree,
                      SettingsStore.shared.handsFreeSilenceGuard else { continue }

                let samples = self.recorder.snapshot()
                let windowSamples = Int(self.silenceAutoStopSeconds * AudioRecorder.targetSampleRate)
                guard samples.count >= windowSamples else { continue }
                let tail = Array(samples.suffix(windowSamples))
                // DSP over ~30 s of floats — cheap, but keep it off the
                // main actor alongside HUD animation.
                let tailSpeech = await Task.detached {
                    TranscriptionService.speechSegments(in: tail)
                }.value
                guard tailSpeech.isEmpty, !Task.isCancelled,
                      AppState.shared.status == .recording else { continue }

                let anySpeech = await Task.detached {
                    !TranscriptionService.speechSegments(in: samples).isEmpty
                }.value
                guard !Task.isCancelled, AppState.shared.status == .recording else { return }
                if anySpeech {
                    VaniLog.log(String(format:
                        "hot-mic guard: %.0fs of silence after speech → auto-stop",
                        self.silenceAutoStopSeconds))
                    self.finishRecording()
                } else {
                    VaniLog.log("hot-mic guard: nothing but silence → discarded")
                    self.cancelRecording()
                    NSSound(named: "Basso")?.play()
                }
                return
            }
        }
    }

    /// While recording, re-decode the accumulated buffer every ~1.5 s and
    /// publish it as a live partial. Whisper isn't incremental, so we re-run
    /// the whole (capped) buffer each tick; awaiting each pass before sleeping
    /// means a slow pass just skips the next tick instead of queuing. Preview
    /// output is disposable and never inserted.
    private func startPreviewLoop() {
        guard FeatureFlags.streamingPreview, SettingsStore.shared.streamingPreview else { return }
        let model = SettingsStore.previewModel
        let language = SettingsStore.shared.language
        // Show something within ~0.5 s of the first words, then update ~every
        // second. Kick in as soon as there's a little audio.
        let minSamples = Int(AudioRecorder.targetSampleRate * 0.4)
        let firstDelay = Duration.milliseconds(500)
        let cadence = Duration.milliseconds(900)
        // Decode only the last few seconds: whisper-small does ~7 s in ~0.3 s,
        // but past ~10 s a pass can spiral to several seconds and the preview
        // freezes. The pill shows a single tail line anyway, and the final
        // (full-buffer) pass is what actually gets pasted.
        let windowSamples = Int(AudioRecorder.targetSampleRate * 7)

        previewTask = Task { [weak self] in
            var delay = firstDelay
            while !Task.isCancelled {
                try? await Task.sleep(for: delay)
                delay = cadence
                guard !Task.isCancelled, let self else { return }
                guard AppState.shared.status == .recording else { return }

                let samples = self.recorder.snapshot()
                guard samples.count >= minSamples else { continue }
                let window = samples.count > windowSamples
                    ? Array(samples.suffix(windowSamples)) : samples

                // Runs on the dedicated preview instance/model, so it never
                // blocks the final large-v3-turbo pass. Awaiting each pass
                // means a slow one skips the next tick instead of queuing.
                let partial = await TranscriptionService.preview.transcribePreview(
                    samples: window, model: model, language: language
                )
                guard !Task.isCancelled,
                      AppState.shared.status == .recording,
                      !partial.isEmpty else { continue }
                AppState.shared.previewTranscript = partial
                DictationHUD.shared.setPreviewing(true)
            }
        }
    }

    private func finishRecording() {
        guard AppState.shared.status == .recording else { return }
        awaitingSecondTap?.cancel()
        awaitingSecondTap = nil
        previewTask?.cancel()
        previewTask = nil
        silenceMonitor?.cancel()
        silenceMonitor = nil
        AppState.shared.status = .transcribing
        AppState.shared.recordingStartedAt = nil
        AppState.shared.previewTranscript = nil
        DictationHUD.shared.setPreviewing(false)
        AppState.shared.audioLevel = 0
        AppState.shared.isHandsFree = false
        pttDownAt = nil

        // Overlap the grace window with tail language detection: the answer
        // is usually ready before the recorder even stops.
        incremental?.prepareFinish()

        Task {
            // Grace period: people release the key while the last word is
            // still leaving their mouth. Capture 200 ms more before stopping
            // so the tail isn't clipped ("…on its" instead of "…on its own").
            try? await Task.sleep(for: .milliseconds(200))
            let samples = recorder.stop()
            NSSound(named: "Bottle")?.play()

            guard samples.count >= minimumSamples else {
                AppState.shared.status = .idle
                DictationHUD.shared.hide()
                return
            }
            await process(samples: samples)
            // Success path already hid the pill at paste time; this covers
            // failures (empty transcript, injection fallback).
            DictationHUD.shared.hide()
            AppState.shared.status = .idle
        }
    }

    private func process(samples: [Float]) async {
        let settings = SettingsStore.shared
        let started = Date()

        // No voiced audio at all (accidental tap/lock in a quiet room):
        // decoding room tone yields hallucinated stock phrases ("Thank
        // you."), so there is nothing legitimate to paste. Bail before
        // spending a decode on it.
        let voiced = TranscriptionService.speechSegments(in: samples)
        let speechSeconds = voiced.reduce(0.0) {
            $0 + Double($1.end - $1.start) / AudioRecorder.targetSampleRate
        }
        guard !voiced.isEmpty else {
            VaniLog.log(String(format: "no speech in %.1fs recording → discarded",
                Double(samples.count) / AudioRecorder.targetSampleRate))
            return
        }

        // Long dictation: most chunks were decoded while speaking, so this
        // only waits for the tail. Short dictation (or a failed incremental
        // run): the classic single pass, with its code-switch grouping.
        let pending = incremental
        incremental = nil
        var raw = ""
        var path = "classic"
        if let pending {
            raw = await pending.finish(fullSamples: samples) ?? ""
            if !raw.isEmpty { path = "incremental" }
        }
        if raw.isEmpty {
            do {
                raw = try await TranscriptionService.shared.transcribe(
                    samples: samples, model: settings.whisperModel,
                    language: settings.language
                )
            } catch {
                VaniLog.log("transcription failed: \(error.localizedDescription)")
                return
            }
        }
        VaniLog.log(String(format: "dictation %.1fs audio → %d chars via %@ in %.2fs",
            Double(samples.count) / AudioRecorder.targetSampleRate,
            raw.count, path, Date().timeIntervalSince(started)))
        guard !raw.isEmpty else { return }
        // A stock phrase decoded from a recording with under ~1.5 s of
        // voiced audio is Whisper hallucinating on room tone, not speech.
        if WhisperArtifacts.isSilenceHallucination(raw, speechSeconds: speechSeconds) {
            VaniLog.log("silence hallucination \"\(raw)\" (\(String(format: "%.1f", speechSeconds))s voiced) → discarded")
            return
        }

        // Code mode: the paste target is a terminal/editor, so prose
        // conventions (auto-caps, trailing period, LLM polish) get out of
        // the way and spoken casing ("camel case user name") switches on.
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        let codeMode = settings.codeModeEnabled
            && SettingsStore.codeAppBundlePrefixes.contains(where: bundleID.hasPrefix)
        if codeMode { VaniLog.log("code mode for \(bundleID)") }

        var text = TextCleaner.clean(raw, codeMode: codeMode)
        // Code-switch script repair: Whisper transliterates embedded English
        // words into Devanagari when a segment decodes as Hindi ("ship it
        // now" → "शिप इट नौ"). Dictionary-exact restores only — real Hindi
        // is never touched.
        if settings.hinglishNormalize {
            text = HinglishNormalizer.normalize(text)
        }
        // The 1B cleanup model helps short dictations (fillers, punctuation)
        // but drops sentences and mangles casing beyond a few sentences —
        // Whisper's own punctuation is already good there, so skip it.
        if settings.llmCleanupEnabled && text.count <= 350 && !codeMode {
            text = await OllamaClient().cleanup(text, model: settings.ollamaModel)
        }
        // Spoken commands ("new line", "full stop", "scratch that") run after
        // the LLM so nothing rewrites the inserted punctuation, and before
        // vocabulary. An empty result means the dictation was discarded.
        if settings.spokenCommandsEnabled {
            text = CommandProcessor.apply(to: text)
        }
        if codeMode {
            // Numbers first ("dash one" needs the digit before dash glues),
            // then symbols, then casing — whose capture stops at the
            // punctuation symbols introduce ("…user name dot js" → userName.js).
            text = NumberWords.apply(to: text)
            text = SymbolCommands.apply(to: text)
            text = CasingCommands.apply(to: text)
        }
        // Context boost (experimental): snap near-miss words to distinctive
        // terms from the clipboard and recent dictations — the things
        // demonstrably on the user's mind. Local only; runs before
        // vocabulary so explicit rules still win.
        if settings.contextBoostEnabled {
            let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
            let recent = TranscriptStore.shared.entries.prefix(3).map(\.text).joined(separator: " ")
            let terms = ContextBoost.terms(from: clipboard + " " + recent)
            text = ContextBoost.correct(text, terms: terms)
        }

        // Snippets expand before vocabulary so corrections also apply inside
        // an expansion's trigger match (not its saved text).
        text = SnippetStore.shared.apply(to: text)
        // Vocabulary corrections run last so they override both Whisper and
        // the LLM (exact casing like "Vani" survives).
        text = VocabularyStore.shared.apply(to: text)
        guard !text.isEmpty else { return }

        AppState.shared.status = .injecting
        AppState.shared.lastTranscript = text
        TranscriptStore.shared.add(
            text: text,
            raw: raw,
            audioSeconds: Double(samples.count) / AudioRecorder.targetSampleRate,
            processingSeconds: Date().timeIntervalSince(started),
            engine: path,
            correctedWords: TranscriptDiff.correctedWordCount(raw: raw, final: text)
        )
        // Auto-learning dictionary: a short utterance right after a paste
        // that nearly repeats part of it is the user re-dictating a mishear
        // — queue the differing words as a suggested correction.
        if let last = lastPaste, Date().timeIntervalSince(last.at) < 20 {
            for pair in CorrectionDetector.candidates(previous: last.text, current: text) {
                VocabularyStore.shared.suggest(find: pair.heard, replace: pair.expected)
            }
        }
        lastPaste = (text, Date())

        _ = await TextInjector.insert(text) // hides the HUD itself at paste time

        NSLog("Vani: dictation done in %.2fs — \"%@\"",
              Date().timeIntervalSince(started), text)
    }
}
