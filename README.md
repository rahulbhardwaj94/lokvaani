<img src="assets/icon.png" align="right" width="110" alt="Vani icon — a lightning bolt between voice bars"/>

# Vani <sup>वाणी</sup>

**Fully local, open-source voice dictation for macOS.** Hold a key, speak, and clean text appears in whatever app you're typing in — powered entirely by on-device AI. No cloud, no account, no subscription.

An open-source alternative to Wispr Flow / SuperWhisper, built for Apple Silicon.

> *Vani* (वाणी) — Sanskrit for **"voice, speech."** Your voice, transcribed on your own machine — it never leaves it.

[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://swift.org)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](#requirements)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-native-333333?logo=apple&logoColor=white)](#requirements)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

## Why

Cloud dictation tools send your voice — every email, password hint, and half-formed thought — to someone else's servers, for a monthly fee. A Mac with Apple Silicon can do all of it locally:

- **Whisper large-v3-turbo** running on the Neural Engine via [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) — state-of-the-art transcription, 99 languages, entirely offline.
- **A small local LLM** (via [Ollama](https://ollama.com)) that polishes the raw transcript — punctuation, capitalization, filler-word removal — in ~0.5 s.
- **System-wide injection**: the cleaned text is pasted straight into the focused text field of *any* app.

Your voice never leaves the machine. Ever.

## How it works

```
 Hold Right ⌥ (or tap ⌥⌘D)
        │
        ▼
 🎙  AVAudioEngine ──── 16 kHz mono PCM
        │
        ▼
 🧠  WhisperKit (large-v3-turbo, CoreML / Neural Engine)
        │  raw transcript
        ▼
 🧹  Rule-based cleanup (fillers, punctuation)
        │
        ▼
 ✨  Ollama LLM polish (gemma3:1b) ── optional, silent fallback
        │
        ▼
 📖  Vocabulary corrections ("rb flow" → "rbFlow")
        │
        ▼
 📋  Clipboard-safe paste into the focused app (⌘V, clipboard restored)
```

A minimal monochrome pill shows voice-reactive bars and a live running transcript while you speak, then fades out the moment the text lands. Double-tap the key to go hands-free — dictate as long as you like, then tap once to stop. Esc means never mind.

## Features

- 🎙 **Push-to-talk, hands-free & toggle** — hold Right Option to talk; double-tap it to lock hands-free for long dictations (tap once to stop, or hold ≥1.5 s and release); Esc discards a recording; or use a customizable chord (default ⌥⌘D)
- 🔒 **100% offline** — Whisper + LLM both run on-device; works in airplane mode
- 🌊 **Live waveform HUD** — monochrome, voice-reactive, follows you across displays, never steals focus
- 👀 **Live preview** — a running transcript appears in the pill as you speak, so you catch mishears before you stop (the pasted text always comes from the final pass)
- 🗣 **Spoken commands, English & Hindi** — "new line" / "नई लाइन", "full stop", "question mark", "scratch that" to discard; deterministic rules, never an LLM
- 🌐 **Code-switch aware** — speak English then Hindi in one breath and each part is transcribed in its own language (English in Latin, Hindi in Devanagari), instead of the whole clip being force-decoded as one language
- 📊 **Stats dashboard** — dictations, words, and time saved vs typing by day/week/month/year
- ✨ **Two-stage cleanup** — instant regex pass, plus an optional local-LLM polish with a paraphrase guard (if the LLM rewrites instead of cleaning, its output is discarded)
- 📚 **Dictation history** — searchable, persistent, with one-click copy
- 📖 **Custom vocabulary** — teach it names it mishears; your casing always wins
- 📋 **Clipboard-safe** — saves and restores whatever you had copied
- 🔐 **Secure-input aware** — refuses to inject into password fields, by design
- 🚫 **No Xcode required** — builds with Swift Package Manager + Command Line Tools alone

## Requirements

- Apple Silicon Mac (developed on M4, 16 GB)
- macOS 14 Sonoma or later
- Xcode **Command Line Tools** (`xcode-select --install`) — full Xcode not needed
- [Ollama](https://ollama.com) *(optional — only for the LLM polish pass)*

## Quick start

```sh
git clone https://github.com/rahulbhardwaj94/vani.git
cd vani

# 1. One-time: create a local self-signed signing identity ("Vani Dev").
#    Signing with a stable identity makes macOS permissions persist across rebuilds.
./scripts/setup-signing.sh

# 2. Build & launch
./scripts/build-app.sh
open build/Vani.app

# 3. Optional: the LLM polish model (~815 MB)
ollama pull gemma3:1b
```

On first launch, Vani walks you through the three permissions it needs and then downloads the Whisper model (~1.6 GB, one time).

| Permission | Why |
|---|---|
| **Microphone** | recording your voice while the hotkey is held |
| **Accessibility** | pasting text into the focused app |
| **Input Monitoring** | detecting the hold-to-talk key system-wide |

## Configuration

Everything lives in the menu-bar icon:

- **Settings** — hotkeys, Whisper model (large-v3-turbo ↔ small for low memory), LLM polish on/off, Ollama model tag, launch at login
- **Dashboard** — usage stats (time saved vs typing), browse/search past dictations, add corrections for words it mishears

Optional environment overrides (mainly for terminal runs) — see [.env.example](.env.example):

```sh
cp .env.example .env
set -a; source .env; set +a
swift run Vani
```

## Project layout

```
Sources/Vani/
├── VaniApp.swift          # MenuBarExtra app + status state machine
├── DictationController.swift# pipeline orchestrator
├── Audio/                   # AVAudioEngine capture → 16 kHz mono
├── STT/                     # WhisperKit wrapper (warm-loaded, actor-isolated)
├── Cleanup/                 # regex cleaner + Ollama client w/ paraphrase guard
├── Injection/               # clipboard-safe ⌘V synthesis, secure-input guard
├── Hotkey/                  # CGEventTap PTT + KeyboardShortcuts toggle
├── HUD/                     # floating voice-reactive waveform pill
├── History/                 # persistent transcript store + vocabulary rules
├── Permissions/             # TCC onboarding
└── Settings/                # preferences UI + store
```

## Why another dictation app?

Good local dictation tools exist — [VoiceInk](https://github.com/Beingpax/VoiceInk) (GPL, whisper.cpp), [Handy](https://github.com/cjpais/Handy) (Rust/Tauri, cross-platform), Sotto (closed, $49). Vani's angle is different:

- **It never rewrites you.** Cloud tools pass your speech through a large LLM that paraphrases, drops hedges, and "improves" your words. We A/B tested against Wispr Flow: on a 70-word technical monologue Vani scored **0.0% word error rate** while the cloud tool restructured the text and misheard technical terms. LLM polish exists here, but it's off by default and guarded — if it changes your words, its output is discarded.
- **Hindi is a first-class citizen.** Auto-detect across 99 languages including हिन्दी — not an afterthought behind an English-only default.
- **~1,500 lines of Swift, no Xcode.** The whole app builds with Command Line Tools + SwiftPM and reads in one sitting. It's meant to be forked and understood, not just installed.

## Design notes

- **No Xcode, on purpose.** The `.app` bundle is assembled by [`scripts/build-app.sh`](scripts/build-app.sh) and signed with a self-signed identity so TCC permissions survive rebuilds. `KeyboardShortcuts` is pinned to 1.15.0 because newer versions use `#Preview`, which needs Xcode's macro plugin.
- **The LLM is never trusted blindly.** Small models love to *answer* dictation instead of cleaning it ("testing testing testing" → "The test is being performed."). Vani checks that ≥60% of your spoken words survive the polish; otherwise the LLM output is discarded.
- **The audio tap is real-time.** The capture callback only converts and appends samples; transcription, cleanup, and injection all happen off the main thread.

## Roadmap

In build order — detailed specs in [docs/spec-v0.2.md](docs/spec-v0.2.md):

- [x] Streaming preview while speaking
- [x] Spoken commands, English **and** Hindi ("new line" / "नई लाइन")
- [x] Code-switch detection — per-segment language decode (English + Hindi in one utterance)
- [ ] Hinglish normalization — optional consistent script (romanized ↔ Devanagari) on top of code-switch output
- [ ] Homebrew cask (`brew install --cask …/vani`)
- [ ] Per-app profiles (e.g. no LLM polish in terminals)
- [ ] Vocabulary → Whisper prompt biasing, Esc-to-cancel, scratchpad fallback
- [ ] Parakeet (FluidAudio) as a faster alternative STT engine

## License

[MIT](LICENSE) © 2026 Rahul Bhardwaj
