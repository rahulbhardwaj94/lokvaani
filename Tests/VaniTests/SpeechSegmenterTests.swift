import Foundation
import VaniCore

/// Sample-rate the segmenter defaults to; keeps the fixtures readable in seconds.
private let sr = 16_000

/// Renders segments as "start-end,…" in whole samples for easy assertions.
private func fmt(_ segments: [(start: Int, end: Int)]) -> String {
    segments.map { "\($0.start)-\($0.end)" }.joined(separator: ",")
}

func speechSegmenterTests() {
    // A short pause (< 0.3 s) between two active runs stays a single segment.
    // Runs: [1.0s..2.0s] and [2.2s..3.0s], gap 0.2s → merged, then padded 0.1s.
    expect(
        fmt(SpeechSegmenter.merge(
            activeChunks: [(sr, sr * 2), (sr * 22 / 10, sr * 3)],
            totalSamples: sr * 4
        )),
        "14400-49600" // (1.0-0.1)s .. (3.0+0.1)s
    )

    // A breath-length pause (≥ 0.3 s) splits — the code-switch case. Real
    // switches rarely come with a long pause, so the threshold is eager.
    // Runs: [1.0s..2.0s] and [2.4s..3.4s], gap 0.4s → two segments.
    expect(
        fmt(SpeechSegmenter.merge(
            activeChunks: [(sr, sr * 2), (sr * 24 / 10, sr * 34 / 10)],
            totalSamples: sr * 4
        )),
        "14400-33600,36800-56000"
    )

    // Padding clamps to the clip bounds (no negative start, no overrun).
    expect(
        fmt(SpeechSegmenter.merge(
            activeChunks: [(0, sr)],
            totalSamples: sr
        )),
        "0-16000"
    )

    // Noise blip shorter than 0.2 s is dropped.
    expect(
        fmt(SpeechSegmenter.merge(
            activeChunks: [(sr, sr + sr / 20)], // 0.05 s of audio
            totalSamples: sr * 2,
            padSeconds: 0 // isolate the min-length prune from padding
        )),
        ""
    )

    // Empty input → no segments.
    expect(fmt(SpeechSegmenter.merge(activeChunks: [], totalSamples: sr * 2)), "")

    // Three runs, first two close, third after a long gap → two segments.
    expect(
        fmt(SpeechSegmenter.merge(
            activeChunks: [(sr, sr * 2), (sr * 22 / 10, sr * 3), (sr * 4, sr * 5)],
            totalSamples: sr * 6,
            padSeconds: 0
        )),
        "16000-48000,64000-80000"
    )

    // ── groupByLanguage ──
    func fmtG(_ groups: [(start: Int, end: Int, language: String)]) -> String {
        groups.map { "\($0.start)-\($0.end):\($0.language)" }.joined(separator: ",")
    }

    // Adjacent same-language segments collapse into one span (silence between
    // them included) — en,en,en,hi over four pauses becomes two decodes.
    expect(
        fmtG(SpeechSegmenter.groupByLanguage(
            segments: [(0, 100), (150, 250), (300, 400), (450, 550)],
            languages: ["en", "en", "en", "hi"]
        )),
        "0-400:en,450-550:hi"
    )

    // Alternating languages stay separate groups.
    expect(
        fmtG(SpeechSegmenter.groupByLanguage(
            segments: [(0, 100), (150, 250), (300, 400)],
            languages: ["en", "hi", "en"]
        )),
        "0-100:en,150-250:hi,300-400:en"
    )

    // Single segment passes through; empty input yields nothing.
    expect(
        fmtG(SpeechSegmenter.groupByLanguage(segments: [(0, 100)], languages: ["hi"])),
        "0-100:hi"
    )
    expect(fmtG(SpeechSegmenter.groupByLanguage(segments: [], languages: [])), "")
}
