import Foundation

/// Turns raw voice-activity ranges (from a VAD) into pause-delimited speech
/// segments: the units the transcriber detects a language for and decodes
/// independently, so a mid-utterance language switch is handled per segment.
///
/// The VAD itself lives in WhisperKit (energy-based); only this merge/pad/prune
/// step is here so it can be unit-tested without loading a model.
public enum SpeechSegmenter {
    /// Merge adjacent voice-active sample ranges into segments.
    /// - Active ranges separated by less than `mergeGapSeconds` are one segment
    ///   (natural within-sentence pauses don't fragment speech).
    /// - Each kept segment is padded by `padSeconds` on both sides (clamped to
    ///   the clip) so a cut doesn't clip word edges.
    /// - Segments shorter than `minSegmentSeconds` after padding are dropped as
    ///   noise blips.
    ///
    /// Returns a single segment (or none) when there's no pause long enough to
    /// split on — the caller then decodes the whole clip in one pass.
    public static func merge(
        activeChunks: [(start: Int, end: Int)],
        totalSamples: Int,
        sampleRate: Int = 16_000,
        mergeGapSeconds: Double = 0.3,
        padSeconds: Double = 0.1,
        minSegmentSeconds: Double = 0.2
    ) -> [(start: Int, end: Int)] {
        let mergeGap = Int(Double(sampleRate) * mergeGapSeconds)
        let pad = Int(Double(sampleRate) * padSeconds)
        let minLen = Int(Double(sampleRate) * minSegmentSeconds)

        var merged: [(start: Int, end: Int)] = []
        for chunk in activeChunks where chunk.end > chunk.start {
            if let last = merged.last, chunk.start - last.end < mergeGap {
                merged[merged.count - 1].end = chunk.end
            } else {
                merged.append(chunk)
            }
        }

        return merged.compactMap { seg in
            let start = max(0, seg.start - pad)
            let end = min(totalSamples, seg.end + pad)
            return end - start >= minLen ? (start: start, end: end) : nil
        }
    }

    /// Collapse adjacent segments that detected the same language into one
    /// span (first start → last end, silence between them included). The
    /// split threshold is deliberately eager so a code-switch with only a
    /// breath-length pause is caught; this regroups the false splits, so the
    /// expensive decode runs once per language *run*, not once per pause —
    /// and each decode keeps cross-pause context for punctuation.
    public static func groupByLanguage(
        segments: [(start: Int, end: Int)],
        languages: [String]
    ) -> [(start: Int, end: Int, language: String)] {
        var groups: [(start: Int, end: Int, language: String)] = []
        for (seg, lang) in zip(segments, languages) {
            if let last = groups.last, last.language == lang {
                groups[groups.count - 1].end = seg.end
            } else {
                groups.append((start: seg.start, end: seg.end, language: lang))
            }
        }
        return groups
    }
}
