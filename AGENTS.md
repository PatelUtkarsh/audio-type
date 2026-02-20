# AGENTS.md — AudioType

> Guidelines for AI coding agents working in this repository.

## Project Overview

AudioType is a **native macOS menu bar app** for voice-to-text. Users hold the `fn` key to record, release to transcribe, and the result is typed into the focused app. It supports three transcription backends: **Groq Whisper** (cloud), **OpenAI Whisper** (cloud), and **Apple Speech** (on-device). If no cloud API key is configured, the app falls back to Apple's on-device `SFSpeechRecognizer` automatically. It runs as an `LSUIElement` (no dock icon), built with Swift Package Manager (not Xcode projects).

## Build Commands

```bash
# Debug build (used during development)
swift build

# Release build
swift build -c release

# Build + create .app bundle (debug)
make app

# Full dev cycle: kill running app, reset Accessibility, rebuild, install to /Applications, launch
make dev

# Clean all build artifacts
make clean
```

**There is no Xcode project.** The app is built entirely via `Package.swift` + `Makefile`. Do not create `.xcodeproj` or `.xcworkspace` files.

## Lint

```bash
# Run SwiftLint (must pass before merge — CI blocks on failure)
swiftlint lint AudioType

# Format code with swift-format
swift-format -i -r AudioType

# Install lint tools
make setup
```

SwiftLint config is in `.swiftlint.yml`. Key rules:
- **`force_cast`** is an error — always use `as?` with guard/if-let
- **`opening_brace`** — opening braces must be on the same line, preceded by a space
- `trailing_whitespace`, `line_length`, `function_body_length`, `file_length`, `type_body_length` are **disabled**
- See `.swiftlint.yml` for the full opt-in rule list

## Tests

```bash
# Run all tests
swift test

# Run a single test (by filter)
swift test --filter TestClassName
swift test --filter TestClassName/testMethodName
```

Note: the test target may be empty. CI runs `swift test` with `continue-on-error: true`.

## CI Pipeline

CI runs on every push/PR to `main` (`.github/workflows/ci.yml`):
1. **Lint** — `swiftlint lint AudioType` (must pass; blocks Build and Test)
2. **Build** — `swift build` (debug) + `swift build -c release` + `make app` + codesign verify
3. **Test** — `swift test` (soft failure allowed)

Releases (`.github/workflows/release.yml`) trigger on `v*` tags and produce `AudioType.dmg` + `AudioType.zip`.

## Architecture

### Transcription Engine System

The app uses a **protocol-based engine abstraction** with a shared base class to support multiple speech-to-text backends:

```
TranscriptionEngine (protocol)
├── WhisperAPIEngine (base class) — shared WAV encoding, multipart HTTP, response parsing
│   ├── GroqEngine      — Cloud, Groq Whisper API, requires API key
│   └── OpenAIEngine    — Cloud, OpenAI Whisper/GPT-4o API, requires API key
└── AppleSpeechEngine   — On-device, Apple SFSpeechRecognizer, no API key needed
```

**`EngineResolver`** selects the active engine at runtime based on user preference (`TranscriptionEngineType`):

| Mode | Behavior |
|------|----------|
| **Auto** (default) | Groq if key exists → OpenAI if key exists → Apple Speech |
| **Groq Whisper** | Always use Groq (fails if no key) |
| **OpenAI Whisper** | Always use OpenAI (fails if no key) |
| **Apple Speech** | Always use on-device recognition |

All engines implement a single method: `transcribe(samples: [Float]) async throws -> String` — accepting 16 kHz mono Float32 PCM samples from `AudioRecorder`.

### Data Flow

```
fn key held → HotKeyManager → TranscriptionManager.startRecording()
                                    ↓
                              AudioRecorder (AVAudioEngine, 16kHz mono PCM)
                                    ↓
fn key released → TranscriptionManager.stopRecordingAndTranscribe()
                                    ↓
                        EngineResolver.resolve() → TranscriptionEngine
                     ↓                  ↓                     ↓
                GroqEngine         OpenAIEngine        AppleSpeechEngine
             (WhisperAPIEngine   (WhisperAPIEngine   (SFSpeechAudioBuffer-
              → Groq API)         → OpenAI API)       RecognitionRequest)
                     ↓                  ↓                     ↓
                              transcribed text
                                    ↓
                         TextPostProcessor (corrections)
                                    ↓
                         TextInserter (CGEvent keyboard simulation)
                                    ↓
                           text typed into focused app
```

### Permission Requirements

| Permission | Required for | Plist key |
|------------|-------------|-----------|
| Microphone | Audio recording | `NSMicrophoneUsageDescription` |
| Accessibility | Keyboard simulation (TextInserter) | Granted via System Settings |
| Speech Recognition | Apple Speech engine (on-device) | `NSSpeechRecognitionUsageDescription` |

Speech recognition permission is requested on-demand the first time the Apple Speech engine is used. Cloud engines (Groq, OpenAI) do not require this permission.

## Project Structure

```
AudioType/
  App/                  # App entry point, menu bar controller, transcription orchestration
    AudioTypeApp.swift  # @main, AppDelegate, onboarding flow
    MenuBarController.swift  # NSStatusItem, state-driven icon tinting, overlay windows
    TranscriptionManager.swift  # State machine (idle→recording→processing→idle/error)
  Core/                 # Business logic & transcription engines
    AudioRecorder.swift       # AVAudioEngine capture, PCM→16kHz resampling, RMS level
    TranscriptionEngine.swift # TranscriptionEngine protocol, TranscriptionEngineType, EngineResolver
    WAVEncoder.swift          # WhisperAPIEngine base class, WAVEncoder, WhisperAPIConfig, Data helpers
    GroqEngine.swift          # GroqEngine subclass, GroqModel enum, TranscriptionLanguage
    OpenAIEngine.swift        # OpenAIEngine subclass, OpenAIModel enum
    AppleSpeechEngine.swift   # Apple SFSpeechRecognizer on-device transcription
    HotKeyManager.swift       # CGEventTap for fn key hold detection
    TextInserter.swift        # CGEvent keyboard simulation to type into focused app
    TextPostProcessor.swift   # Post-transcription corrections (tech terms, punctuation)
  UI/                   # SwiftUI views
    RecordingOverlay.swift  # Floating waveform (recording) / thinking dots (processing)
    OnboardingView.swift    # First-launch permission setup (API key optional)
    SettingsView.swift      # Engine picker, API keys, models, language, permissions
    Theme.swift             # Brand color system (coral palette, adaptive dark/light)
  Utilities/
    Permissions.swift       # Microphone, Accessibility, Speech Recognition permission helpers
    KeychainHelper.swift    # macOS Keychain-based secret storage
  Resources/
    Assets.xcassets/        # Asset catalog (currently empty)
Resources/
  Info.plist              # Bundle config (LSUIElement, mic + speech recognition usage descriptions)
  AppIcon.icns            # App icon (coral gradient)
```

## Code Style

### Imports
- Sort alphabetically: `import AppKit`, `import Foundation`, `import SwiftUI`
- Use specific submodule imports where appropriate: `import os.log` (not `import os`)
- Only import what the file actually uses

### Formatting
- **2-space indentation** (no tabs)
- Opening braces on the **same line** as the declaration
- No trailing whitespace (rule disabled in linter, but keep it clean)
- Use `// MARK: -` sections to organize classes (`// MARK: - Private`, `// MARK: - Transcription`)

### Types & Naming
- **Protocols** for abstractions with multiple implementations: `TranscriptionEngine`
- **Classes** for stateful objects with reference semantics: `TranscriptionManager`, `AudioRecorder`, `WhisperAPIEngine`, `GroqEngine`, `OpenAIEngine`, `AppleSpeechEngine`
- **Enums** for namespaced constants and error types: `AudioTypeTheme`, `WhisperAPIError`, `AppleSpeechError`, `TranscriptionEngineType`, `KeychainHelper`
- **Structs** for SwiftUI views and config: `RecordingOverlay`, `SettingsView`, `WhisperAPIConfig`
- camelCase for properties/methods, PascalCase for types
- Identifier names: min 1 char, max 50 chars; `x`, `y`, `i`, `j`, `k` are allowed

### Error Handling
- Define domain-specific error enums conforming to `Error, LocalizedError`
- Provide human-readable `errorDescription` for every case
- Use `do/catch` or `try?` — never `try!`
- Never force-cast (`as!`) — use `as?` with guard/if-let
- Errors shown to user go through `TranscriptionState.error(String)`

### Patterns Used
- **Protocol abstraction**: `TranscriptionEngine` with `WhisperAPIEngine` base class and `AppleSpeechEngine`
- **Inheritance for shared logic**: `WhisperAPIEngine` base class handles WAV encoding, multipart HTTP, response parsing; `GroqEngine` and `OpenAIEngine` are thin subclasses supplying config
- **Resolver pattern**: `EngineResolver.resolve()` picks the engine at runtime based on config
- **Singleton**: `TranscriptionManager.shared`, `TextPostProcessor.shared`, `AudioLevelMonitor.shared`
- **`@MainActor`** on `TranscriptionManager` — all state mutations on main thread
- **NotificationCenter** for decoupled state communication (`transcriptionStateChanged`, `audioLevelChanged`)
- **`@Published` + ObservableObject** for SwiftUI reactivity
- **Closures** for callbacks: `HotKeyManager(callback:)`, `audioRecorder.onLevelUpdate`
- **`os.log` Logger** with subsystem `"com.audiotype"` — use per-class categories

### Adding a New Cloud Transcription Provider
1. Create a new subclass of `WhisperAPIEngine` in `AudioType/Core/`
2. Override `config` (with `WhisperAPIConfig`) and `currentModel` — that's it for the engine
3. Add a model enum if the provider has multiple models
4. Add static convenience methods (`isConfigured`, `setApiKey`, `clearApiKey`)
5. Add a case to `TranscriptionEngineType` and update `EngineResolver.resolve()`
6. Update `EngineResolver.anyEngineAvailable` if the engine has standalone availability
7. Add UI in `SettingsView.swift` (API key field, model picker)

### Adding a Non-Whisper Engine
1. Create a new class conforming to `TranscriptionEngine` in `AudioType/Core/`
2. Implement `displayName`, `isAvailable`, and `transcribe(samples:)`
3. Add a case to `TranscriptionEngineType` and update `EngineResolver.resolve()`
4. Update `EngineResolver.anyEngineAvailable` if the engine has standalone availability
5. Add any needed permissions to `Permissions.swift` and `Info.plist`

### Colors & Theming
All colors live in `AudioType/UI/Theme.swift` (`AudioTypeTheme` enum). Never use hardcoded color literals in views. The palette:
- **Coral** `#FF6B6B` — brand color, waveform bars, accents, checkmarks
- **Amber** `#FFB84D` — processing state (thinking dots, menu bar icon)
- **Recording red** `#FF4D4D` — menu bar icon while recording
- Adaptive variants for dark mode (coralLight, amberLight)

### Menu Bar Icon States
- **Idle**: SF Symbol `waveform.circle.fill`, `isTemplate = true` (follows OS appearance)
- **Recording**: same symbol, tinted `nsRecordingRed`, `isTemplate = false`
- **Processing**: `ellipsis.circle.fill`, tinted `nsAmber`, `isTemplate = false`
- **Error**: `exclamationmark.triangle.fill`, tinted `.systemRed`

### Security
- API keys stored in macOS Keychain via `KeychainHelper` (Security framework)
- Never commit `.env`, credentials, or API keys
- Audio is recorded in-memory only — never written to disk

## App Bundle
The `.app` bundle is assembled by `make app` (not Xcode):
- Binary: `.build/debug/AudioType` → `AudioType.app/Contents/MacOS/AudioType`
- Plist: `Resources/Info.plist` → `AudioType.app/Contents/Info.plist`
- Icon: `Resources/AppIcon.icns` → `AudioType.app/Contents/Resources/AppIcon.icns`
- Ad-hoc codesigned: `codesign --force --deep --sign -`

When updating the version, change **both** `CFBundleVersion` and `CFBundleShortVersionString` in `Resources/Info.plist` **and** the display string in `SettingsView.swift`.
