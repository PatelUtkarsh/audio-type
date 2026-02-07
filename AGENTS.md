# AGENTS.md — AudioType

> Guidelines for AI coding agents working in this repository.

## Project Overview

AudioType is a **native macOS menu bar app** for voice-to-text. Users hold the `fn` key to record, release to transcribe via Groq's Whisper API, and the result is typed into the focused app. It runs as an `LSUIElement` (no dock icon), built with Swift Package Manager (not Xcode projects).

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

## Project Structure

```
AudioType/
  App/                  # App entry point, menu bar controller, transcription orchestration
    AudioTypeApp.swift  # @main, AppDelegate, onboarding flow
    MenuBarController.swift  # NSStatusItem, state-driven icon tinting, overlay windows
    TranscriptionManager.swift  # State machine (idle→recording→processing→idle/error)
  Core/                 # Business logic
    AudioRecorder.swift     # AVAudioEngine capture, PCM→16kHz resampling, RMS level
    GroqEngine.swift        # Groq Whisper API client, WAV encoding, multipart upload
    HotKeyManager.swift     # CGEventTap for fn key hold detection
    TextInserter.swift      # CGEvent keyboard simulation to type into focused app
    TextPostProcessor.swift # Post-transcription corrections (tech terms, punctuation)
  UI/                   # SwiftUI views
    RecordingOverlay.swift  # Floating waveform (recording) / thinking dots (processing)
    OnboardingView.swift    # First-launch permission + API key setup
    SettingsView.swift      # API key, model picker, permissions, launch-at-login
    Theme.swift             # Brand color system (coral palette, adaptive dark/light)
  Utilities/
    Permissions.swift       # Microphone + Accessibility permission helpers
    KeychainHelper.swift    # File-based secret storage (Application Support, 0600 perms)
  Resources/
    Assets.xcassets/        # Asset catalog (currently empty)
Resources/
  Info.plist              # Bundle config (LSUIElement, mic usage description)
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
- **Classes** for stateful objects with reference semantics: `TranscriptionManager`, `AudioRecorder`
- **Enums** for namespaced constants and error types: `AudioTypeTheme`, `GroqEngineError`, `KeychainHelper`
- **Structs** for SwiftUI views: `RecordingOverlay`, `SettingsView`
- camelCase for properties/methods, PascalCase for types
- Identifier names: min 1 char, max 50 chars; `x`, `y`, `i`, `j`, `k` are allowed

### Error Handling
- Define domain-specific error enums conforming to `Error, LocalizedError`
- Provide human-readable `errorDescription` for every case
- Use `do/catch` or `try?` — never `try!`
- Never force-cast (`as!`) — use `as?` with guard/if-let
- Errors shown to user go through `TranscriptionState.error(String)`

### Patterns Used
- **Singleton**: `TranscriptionManager.shared`, `TextPostProcessor.shared`, `AudioLevelMonitor.shared`
- **`@MainActor`** on `TranscriptionManager` — all state mutations on main thread
- **NotificationCenter** for decoupled state communication (`transcriptionStateChanged`, `audioLevelChanged`)
- **`@Published` + ObservableObject** for SwiftUI reactivity
- **Closures** for callbacks: `HotKeyManager(callback:)`, `audioRecorder.onLevelUpdate`
- **`os.log` Logger** with subsystem `"com.audiotype"` — use per-class categories

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
- API keys stored in `~/Library/Application Support/AudioType/.secrets` with `0600` permissions
- Never commit `.env`, credentials, or API keys
- Audio is recorded in-memory only — never written to disk

## App Bundle
The `.app` bundle is assembled by `make app` (not Xcode):
- Binary: `.build/debug/AudioType` → `AudioType.app/Contents/MacOS/AudioType`
- Plist: `Resources/Info.plist` → `AudioType.app/Contents/Info.plist`
- Icon: `Resources/AppIcon.icns` → `AudioType.app/Contents/Resources/AppIcon.icns`
- Ad-hoc codesigned: `codesign --force --deep --sign -`

When updating the version, change **both** `CFBundleVersion` and `CFBundleShortVersionString` in `Resources/Info.plist` **and** the display string in `SettingsView.swift`.
