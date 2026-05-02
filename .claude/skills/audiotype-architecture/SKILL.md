---
name: audiotype-architecture
description: Architecture reference for the AudioType macOS app (Swift/SwiftUI menu-bar voice-to-text). Use whenever working in this repo on tasks that touch app structure, transcription engines (Groq, OpenAI, Apple Speech), the hotkey + audio + insert pipeline, settings/onboarding UI, permissions/Keychain, or when deciding where new code belongs. Load before adding files, refactoring components, modifying engine selection, changing the record→transcribe→insert flow, or answering questions about how AudioType is organized.
---

# AudioType Architecture

Native macOS menu-bar app: hold `fn` → record mic → transcribe (Groq / OpenAI / Apple Speech) → simulate keystrokes into the focused app.

Authoritative architecture doc: [`references/architecture.md`](references/architecture.md). Read it for the full picture (component breakdown, sequence diagram, error table, build config). This skill body is the fast index + decision guide.

## Pipeline (must respect this order)

```
HotKeyManager → AudioRecorder → EngineResolver → {Groq|OpenAI|AppleSpeech}Engine
              → TextPostProcessor → TextInserter
```

All engines consume identical input: **16 kHz mono Float32 PCM `[Float]`** from `AudioRecorder`. Do not change this contract without updating every engine.

## Where code lives

```
AudioType/AudioType/
├── App/        AudioTypeApp.swift, MenuBarController.swift, TranscriptionManager.swift
├── Core/       HotKeyManager, AudioRecorder, TranscriptionEngine (protocol+resolver),
│               WAVEncoder (also hosts WhisperAPIEngine base class),
│               GroqEngine, OpenAIEngine, AppleSpeechEngine,
│               TextPostProcessor, TextInserter
├── UI/         SettingsView, RecordingOverlay, OnboardingView, Theme
├── Utilities/  Permissions, KeychainHelper
└── Resources/  Assets.xcassets
```

`Resources/` at repo root holds `Info.plist` and `AppIcon.icns`. Build via `make app` (or `swift build`). No external Swift packages — `Package.swift` is dependency-free on purpose.

### Decision: where does new code go?

| Adding… | Put it in |
|---|---|
| New transcription backend | `Core/<Name>Engine.swift`, conform to `TranscriptionEngine`; if cloud + OpenAI-compatible, subclass `WhisperAPIEngine` (in `WAVEncoder.swift`) |
| New global hotkey behavior | `Core/HotKeyManager.swift` |
| Audio capture / format change | `Core/AudioRecorder.swift` (then audit every engine) |
| Text cleanup rule / voice command | `Core/TextPostProcessor.swift` |
| Settings field | `UI/SettingsView.swift` (+ persistence in UserDefaults or `KeychainHelper` for secrets) |
| Onboarding step | `UI/OnboardingView.swift` |
| New permission check | `Utilities/Permissions.swift` |
| Secret storage | `Utilities/KeychainHelper.swift` — never UserDefaults, never logs |
| Orchestration glue | `App/TranscriptionManager.swift` |

## Engine system (the part most changes touch)

Protocol + resolver in `Core/TranscriptionEngine.swift`:

```swift
protocol TranscriptionEngine {
    var displayName: String { get }
    var isAvailable: Bool { get }
    func transcribe(samples: [Float]) async throws -> String
}
```

Hierarchy:
- `WhisperAPIEngine` (base, in `WAVEncoder.swift`) — WAV encoding, multipart POST, bearer auth, error mapping
  - `GroqEngine` → `https://api.groq.com/openai/v1/audio/transcriptions`
  - `OpenAIEngine` → `https://api.openai.com/v1/audio/transcriptions`
- `AppleSpeechEngine` — `SFSpeechRecognizer`, prefers on-device, falls back to Apple server-based

`EngineResolver.resolve()` selects per `TranscriptionEngineType`:

| Mode | Selection |
|---|---|
| Auto (default) | Groq key → OpenAI key → Apple Speech |
| Groq Whisper | Groq only (fail if no key) |
| OpenAI Whisper | OpenAI only (fail if no key) |
| Apple Speech | On-device only |

When adding a cloud engine: subclass `WhisperAPIEngine`, override `config: WhisperAPIConfig` and `currentModel`. Don't reimplement WAV/multipart.

## Invariants — don't break these

1. **Audio format**: 16 kHz mono Float32 PCM end-to-end.
2. **No API key required**: app must work via Apple Speech alone. Auto mode must always have a viable fallback.
3. **Keys in Keychain only**: never `UserDefaults`, never logs, never disk.
4. **Menu-bar only**: `LSUIElement = true`. No dock icon, no main window on launch.
5. **No external deps**: keep `Package.swift` free of remote packages.
6. **Permissions are explicit**: Microphone, Accessibility (for `CGEventPost`), Speech Recognition (for Apple engine). Surface failures via onboarding/settings, not silent.
7. **Text insertion via `CGEventPost`** to `.cgSessionEventTap` — works system-wide, requires Accessibility trust.

## Required Info.plist keys

`NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`, `LSUIElement=true`. Add new permission strings here when introducing new capabilities.

## Error model (see `architecture.md` §Error Handling)

Engines throw typed errors → `TranscriptionManager` maps to UI state (idle/recording/processing/error) and triggers fallbacks in Auto mode. 401 → settings prompt; 429 → retry-with-delay; network → reset to idle; speech-not-authorized → re-request.

## Common task playbook

- **"Add a new model to Groq/OpenAI"**: extend the model enum in `GroqEngine.swift` / `OpenAIEngine.swift`, expose in `SettingsView` picker, persist via UserDefaults (model id is not a secret).
- **"Support a new language"**: extend `TranscriptionLanguage` (in `GroqEngine.swift`), map to `Locale` in `AppleSpeechEngine`, expose in Settings.
- **"Change the hotkey"**: `HotKeyManager.swift` only. Keep the hold-to-record state machine (down → record, up → process).
- **"Add a third cloud provider"**: new file `Core/<X>Engine.swift` subclassing `WhisperAPIEngine` if compatible; extend `TranscriptionEngineType` and `EngineResolver`; add Settings UI + Keychain entry; update Auto-mode precedence intentionally.

## When in doubt

Read `references/architecture.md` and the relevant `Core/` file before editing. The architecture doc and this skill must stay consistent with `AudioType/AudioType/Core/`.
