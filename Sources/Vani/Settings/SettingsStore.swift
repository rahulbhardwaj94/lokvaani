import AppKit
import Foundation

/// UserDefaults-backed app settings.
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    /// WhisperKit model names as they appear in argmaxinc/whisperkit-coreml.
    static let whisperModels = [
        "openai_whisper-large-v3-v20240930",        // large-v3-turbo, best accuracy (~1.6 GB)
        "openai_whisper-large-v3-v20240930_626MB",  // compressed turbo (~0.6 GB)
        "openai_whisper-small",                     // low-latency / low-memory fallback
        "openai_whisper-base",
    ]

    /// The live preview runs on this small/fast model (~0.5 GB) on its own
    /// WhisperKit instance, so it stays responsive and never competes with the
    /// large-v3-turbo final pass. Preview output is disposable, so a lighter
    /// model is the right trade — the pasted text always comes from `whisperModel`.
    static let previewModel = "openai_whisper-small"

    /// Spoken-language options: Whisper language codes, or "auto" to detect
    /// per dictation (large-v3-turbo supports 99 languages including Hindi).
    static let languages: [(code: String, label: String)] = [
        ("auto", "Auto-detect"),
        ("en", "English"),
        ("hi", "Hindi (हिन्दी)"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("ja", "Japanese"),
    ]

    @Published var whisperModel: String {
        didSet { UserDefaults.standard.set(whisperModel, forKey: "whisperModel") }
    }
    @Published var language: String {
        didSet { UserDefaults.standard.set(language, forKey: "language") }
    }
    @Published var llmCleanupEnabled: Bool {
        didSet { UserDefaults.standard.set(llmCleanupEnabled, forKey: "llmCleanupEnabled") }
    }
    @Published var spokenCommandsEnabled: Bool {
        didSet { UserDefaults.standard.set(spokenCommandsEnabled, forKey: "spokenCommandsEnabled") }
    }
    @Published var hinglishNormalize: Bool {
        didSet { UserDefaults.standard.set(hinglishNormalize, forKey: "hinglishNormalize") }
    }
    @Published var streamingPreview: Bool {
        didSet { UserDefaults.standard.set(streamingPreview, forKey: "streamingPreview") }
    }
    @Published var codeModeEnabled: Bool {
        didSet { UserDefaults.standard.set(codeModeEnabled, forKey: "codeModeEnabled") }
    }
    @Published var whisperModeEnabled: Bool {
        didSet { UserDefaults.standard.set(whisperModeEnabled, forKey: "whisperModeEnabled") }
    }
    @Published var contextBoostEnabled: Bool {
        didSet { UserDefaults.standard.set(contextBoostEnabled, forKey: "contextBoostEnabled") }
    }
    @Published var handsFreeSilenceGuard: Bool {
        didSet { UserDefaults.standard.set(handsFreeSilenceGuard, forKey: "handsFreeSilenceGuard") }
    }
    @Published var showDockIcon: Bool {
        didSet {
            UserDefaults.standard.set(showDockIcon, forKey: "showDockIcon")
            NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
        }
    }

    /// Bundle ids treated as code contexts: terminals, editors, IDEs.
    /// Prefix match so JetBrains' per-IDE ids are covered in one entry.
    static let codeAppBundlePrefixes = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp",
        "com.github.wez.wezterm", "net.kovidgoyal.kitty", "io.alacritty",
        "com.mitchellh.ghostty", "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "dev.zed.Zed", "com.apple.dt.Xcode", "com.sublimetext",
        "com.jetbrains.", "org.vim.MacVim", "com.neovide.neovide",
    ]
    @Published var ollamaModel: String {
        didSet { UserDefaults.standard.set(ollamaModel, forKey: "ollamaModel") }
    }

    private init() {
        let defaults = UserDefaults.standard
        whisperModel = defaults.string(forKey: "whisperModel") ?? Self.whisperModels[0]
        language = defaults.string(forKey: "language") ?? "auto"
        // Default OFF: A/B testing vs Wispr Flow showed the 1B cleanup model
        // drops words ("I think"), swaps meaning ("and"→"or"), and stutters —
        // while the LLM-free path scored 0% WER on long-form. Rule-based
        // cleanup + Whisper's own punctuation is the trustworthy baseline;
        // the LLM stays available as an opt-in.
        llmCleanupEnabled = defaults.object(forKey: "llmCleanupEnabled") as? Bool ?? false
        spokenCommandsEnabled = defaults.object(forKey: "spokenCommandsEnabled") as? Bool ?? true
        hinglishNormalize = defaults.object(forKey: "hinglishNormalize") as? Bool ?? true
        streamingPreview = defaults.object(forKey: "streamingPreview") as? Bool ?? true
        codeModeEnabled = defaults.object(forKey: "codeModeEnabled") as? Bool ?? true
        whisperModeEnabled = defaults.object(forKey: "whisperModeEnabled") as? Bool ?? false
        contextBoostEnabled = defaults.object(forKey: "contextBoostEnabled") as? Bool ?? false
        handsFreeSilenceGuard = defaults.object(forKey: "handsFreeSilenceGuard") as? Bool ?? true
        showDockIcon = defaults.object(forKey: "showDockIcon") as? Bool ?? false
        ollamaModel = defaults.string(forKey: "ollamaModel") ?? "gemma3:1b"
    }
}
