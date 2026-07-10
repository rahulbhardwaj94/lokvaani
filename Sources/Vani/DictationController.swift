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

    /// Holding the PTT key at least this long, then releasing, locks into
    /// hands-free mode: recording continues until a single tap of the key.
    private let handsFreeHoldThreshold: TimeInterval = 3.0
    private var pttDownAt: Date?
    private var suppressNextKeyUp = false

    /// The live-preview re-decode loop; runs only while recording.
    private var previewTask: Task<Void, Never>?

    private init() {}

    func start() {
        // Warm-load Whisper in the background so the first dictation is fast.
        Task.detached(priority: .utility) {
            await TranscriptionService.shared.warmUp(model: SettingsStore.shared.whisperModel)
        }
        // Warm the small preview model too (its own instance) so live preview
        // is ready without stalling the first dictation. Lower priority than
        // the main model — the final pass matters more than the preview.
        if SettingsStore.shared.streamingPreview {
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
        pttDownAt = Date()
        beginRecording()
    }

    private func pushToTalkUp() {
        if suppressNextKeyUp {
            suppressNextKeyUp = false
            return
        }
        guard AppState.shared.status == .recording else { return }
        if let downAt = pttDownAt, Date().timeIntervalSince(downAt) >= handsFreeHoldThreshold {
            // Held long enough: release doesn't stop — lock into hands-free
            // so long dictations don't require pinning the key down.
            AppState.shared.isHandsFree = true
            NSSound(named: "Tink")?.play()
            return
        }
        finishRecording()
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
            try recorder.start()
            AppState.shared.status = .recording
            AppState.shared.previewTranscript = nil
            DictationHUD.shared.show()
            NSSound(named: "Pop")?.play()
            startPreviewLoop()
        } catch {
            NSLog("Vani: failed to start recording: \(error.localizedDescription)")
        }
    }

    /// While recording, re-decode the accumulated buffer every ~1.5 s and
    /// publish it as a live partial. Whisper isn't incremental, so we re-run
    /// the whole (capped) buffer each tick; awaiting each pass before sleeping
    /// means a slow pass just skips the next tick instead of queuing. Preview
    /// output is disposable and never inserted.
    private func startPreviewLoop() {
        guard SettingsStore.shared.streamingPreview else { return }
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
        previewTask?.cancel()
        previewTask = nil
        AppState.shared.status = .transcribing
        AppState.shared.previewTranscript = nil
        DictationHUD.shared.setPreviewing(false)
        AppState.shared.audioLevel = 0
        AppState.shared.isHandsFree = false
        pttDownAt = nil

        Task {
            // Grace period: people release the key while the last word is
            // still leaving their mouth. Capture 300 ms more before stopping
            // so the tail isn't clipped ("…on its" instead of "…on its own").
            try? await Task.sleep(for: .milliseconds(300))
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

        let raw: String
        do {
            raw = try await TranscriptionService.shared.transcribe(
                samples: samples, model: settings.whisperModel,
                language: settings.language
            )
        } catch {
            NSLog("Vani: transcription failed: %@", error.localizedDescription)
            return
        }
        guard !raw.isEmpty else { return }

        var text = TextCleaner.clean(raw)
        // The 1B cleanup model helps short dictations (fillers, punctuation)
        // but drops sentences and mangles casing beyond a few sentences —
        // Whisper's own punctuation is already good there, so skip it.
        if settings.llmCleanupEnabled && text.count <= 350 {
            text = await OllamaClient().cleanup(text, model: settings.ollamaModel)
        }
        // Spoken commands ("new line", "full stop", "scratch that") run after
        // the LLM so nothing rewrites the inserted punctuation, and before
        // vocabulary. An empty result means the dictation was discarded.
        if settings.spokenCommandsEnabled {
            text = CommandProcessor.apply(to: text)
        }
        // Vocabulary corrections run last so they override both Whisper and
        // the LLM (exact casing like "Vani" survives).
        text = VocabularyStore.shared.apply(to: text)
        guard !text.isEmpty else { return }

        AppState.shared.status = .injecting
        AppState.shared.lastTranscript = text
        TranscriptStore.shared.add(
            text: text,
            raw: raw,
            audioSeconds: Double(samples.count) / AudioRecorder.targetSampleRate
        )
        _ = await TextInjector.insert(text) // hides the HUD itself at paste time

        NSLog("Vani: dictation done in %.2fs — \"%@\"",
              Date().timeIntervalSince(started), text)
    }
}
