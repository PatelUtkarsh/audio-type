# AudioType - Architecture Document

A native macOS application providing instant voice-to-text functionality.

## Overview

**AudioType** captures voice via a global hotkey, transcribes it using **Groq Whisper** (cloud), **OpenAI Whisper** (cloud), or **Apple Speech** (on-device), and simulates keyboard typing to insert text into any application. If no cloud API key is configured, the app falls back to Apple's on-device `SFSpeechRecognizer` automatically.

### Key Design Goals

1. **Instant activation** - Sub-100ms from hotkey press to recording start
2. **High-quality transcription** - Whisper Large V3 via Groq or GPT-4o via OpenAI for best accuracy
3. **Works without an API key** - Apple Speech provides on-device fallback
4. **Universal text insertion** - Works in any app via keyboard simulation
5. **Minimal footprint** - Menu bar app, no dock icon, lightweight
6. **Self-serve** - Users can optionally provide their own Groq (free) or OpenAI API key

---

## System Architecture

```
+---------------------------------------------------------------------+
|                         AudioType.app                               |
+---------------------------------------------------------------------+
|                                                                     |
|  +--------------+    +--------------+    +----------------------+   |
|  |   HotKey     |--->|   Audio      |--->|   Engine Resolver    |   |
|  |   Manager    |    |   Recorder   |    | (Auto/Groq/OpenAI/  |   |
|  +--------------+    +--------------+    |  Apple Speech)       |   |
|         |                   |            +----------------------+   |
|         |                   |              |       |         |      |
|         |                   |              v       v         v      |
|         |                   |         +------+ +------+ +-------+  |
|         |                   |         | Groq | |OpenAI| | Apple |  |
|         |                   |         |Engine| |Engine| | Speech|  |
|         |                   |         |(Cloud)| |(Cloud)| |(Local)|  |
|         |                   |         +------+ +------+ +-------+  |
|         |                   |              |       |         |      |
|         |                   |              v       v         v      |
|         |                   |         +----------------------+      |
|         |                   |         |   Text Inserter      |      |
|         |                   |         |   (CGEventPost)      |      |
|         |                   |         +----------------------+      |
|         v                   v                    v                  |
|  +-------------------------------------------------------------+   |
|  |                    UI Layer (SwiftUI)                         |   |
|  |  +-------------+  +-------------+  +---------------------+  |   |
|  |  | Menu Bar    |  | Recording   |  | Settings Window     |  |   |
|  |  | Status Item |  | Overlay     |  | (Engine, Keys,      |  |   |
|  |  +-------------+  +-------------+  |  Models, Language)   |  |   |
|  |                                    +---------------------+  |   |
|  +-------------------------------------------------------------+   |
|                                                                     |
+---------------------------------------------------------------------+
```

---

## Component Breakdown

### 1. HotKey Manager

**Purpose:** Listen for global keyboard shortcuts to trigger recording.

**Technology:**
- `CGEvent` tap for global hotkey detection
- Runs on a dedicated background thread

**Default Hotkey:** Hold `fn` key

**States:**
- Idle -> Recording (on key down)
- Recording -> Processing (on key up)

---

### 2. Audio Recorder

**Purpose:** Capture microphone audio in real-time.

**Technology:**
- `AVAudioEngine` for low-latency capture
- Output format: 16kHz mono PCM Float32 (optimal for Whisper and SFSpeechRecognizer)

**Key Components:**
```swift
class AudioRecorder {
    let audioEngine = AVAudioEngine()
    var audioBuffer: [Float] = []

    func startRecording()               // Begin capture
    func stopRecording() -> [Float]     // Return samples
}
```

**Permissions Required:**
- Microphone access (`NSMicrophoneUsageDescription`)

---

### 3. Transcription Engine System

The app uses a **protocol-based engine abstraction** with a shared base class to support multiple backends:

```swift
protocol TranscriptionEngine {
    var displayName: String { get }
    var isAvailable: Bool { get }
    func transcribe(samples: [Float]) async throws -> String
}
```

```
TranscriptionEngine (protocol)
├── WhisperAPIEngine (base class) — WAV encoding, multipart HTTP, response parsing
│   ├── GroqEngine      — Groq Whisper API
│   └── OpenAIEngine    — OpenAI Whisper / GPT-4o API
└── AppleSpeechEngine   — Apple SFSpeechRecognizer (on-device)
```

All engines accept the same input: 16 kHz mono Float32 PCM samples from `AudioRecorder`.

#### Engine Resolver

`EngineResolver` selects the active engine at runtime based on user preference (`TranscriptionEngineType`):

| Mode | Behavior |
|------|----------|
| **Auto** (default) | Groq if key exists → OpenAI if key exists → Apple Speech |
| **Groq Whisper** | Always use Groq (fails if no key) |
| **OpenAI Whisper** | Always use OpenAI (fails if no key) |
| **Apple Speech** | Always use on-device recognition |

```swift
enum EngineResolver {
    static func resolve() -> TranscriptionEngine
    static var anyEngineAvailable: Bool
}
```

#### 3a. WhisperAPIEngine (Shared Base Class)

**Purpose:** Shared logic for any cloud engine that speaks the OpenAI-compatible `POST /v1/audio/transcriptions` multipart protocol.

**Handles:**
- Converting PCM Float32 samples to WAV data in-memory (`WAVEncoder`)
- Building multipart/form-data HTTP requests
- Bearer token authentication
- HTTP response parsing and error handling

Subclasses only need to override `config` (with `WhisperAPIConfig`) and `currentModel`.

#### 3b. Groq Engine (Cloud API)

**Purpose:** Transcribe audio to text using Groq's hosted Whisper models.

**Integration:**
- Subclass of `WhisperAPIEngine`
- Sends to `https://api.groq.com/openai/v1/audio/transcriptions`

##### Model Options

| Model | Speed | Accuracy | Cost |
|-------|-------|----------|------|
| `whisper-large-v3-turbo` | Faster (216x real-time) | Good | $0.04/hr |
| `whisper-large-v3` | Fast (189x real-time) | Best | $0.111/hr |

**Default Model:** `whisper-large-v3-turbo`

##### Free Tier Rate Limits

| Limit | Value |
|-------|-------|
| Requests per minute | 20 |
| Requests per day | 2,000 |
| Audio seconds per hour | 7,200 (~2 hrs) |
| Audio seconds per day | 28,800 (~8 hrs) |

#### 3c. OpenAI Engine (Cloud API)

**Purpose:** Transcribe audio to text using OpenAI's Whisper and GPT-4o transcription models.

**Integration:**
- Subclass of `WhisperAPIEngine`
- Sends to `https://api.openai.com/v1/audio/transcriptions`

##### Model Options

| Model | Quality | Cost |
|-------|---------|------|
| `gpt-4o-mini-transcribe` | Balanced (default) | Lower |
| `gpt-4o-transcribe` | Best | Higher |
| `whisper-1` | Good (cheapest) | Lowest |

**Default Model:** `gpt-4o-mini-transcribe`

#### 3d. Apple Speech Engine (On-Device)

**Purpose:** Transcribe audio to text using Apple's `SFSpeechRecognizer` — no API key or internet required (when on-device recognition is available).

**Integration:**
- Converts `[Float]` PCM samples into an `AVAudioPCMBuffer`
- Feeds the buffer to `SFSpeechAudioBufferRecognitionRequest`
- Prefers on-device recognition (`requiresOnDeviceRecognition = true`) when supported
- Falls back to server-based Apple recognition if on-device is unavailable
- Maps the app's `TranscriptionLanguage` to a `Locale` for the recognizer
- Requests authorization on first use if status is `.notDetermined`

```swift
class AppleSpeechEngine: TranscriptionEngine {
    func transcribe(samples: [Float]) async throws -> String
    static var isSupported: Bool
    static func requestAuthorization() async -> Bool
}
```

**Permissions Required:**
- Speech Recognition (`NSSpeechRecognitionUsageDescription`)

**Limitations compared to cloud engines:**
- Lower accuracy for technical terms and mixed-language speech
- On-device model availability depends on macOS version and downloaded languages
- No model selection (uses system default)

##### API Key Management

- Stored in macOS Keychain via `KeychainHelper` (Security framework)
- Never written to UserDefaults or logged
- User provides their own key (self-serve, optional)

---

### 4. Text Post-Processor

**Purpose:** Clean up and correct transcribed text.

- Fixes common misheard tech terms (e.g. "git hub" -> "GitHub")
- Capitalizes first letter of sentences
- Supports voice commands ("new line", "period", etc.)
- User-defined custom word replacements (persisted in UserDefaults)

---

### 5. Text Inserter

**Purpose:** Type transcribed text into the currently focused application.

**Technology:**
- `CGEventPost` to simulate keyboard events
- Post to `.cgSessionEventTap` for system-wide injection

**Permissions Required:**
- Accessibility access (`AXIsProcessTrusted()`)

---

### 6. UI Layer (SwiftUI)

#### Menu Bar Status Item
- Shows state via icon (idle, recording, processing, error)
- Dropdown menu: Settings, Quit

#### Recording Overlay
- Small floating window showing waveform (recording) or thinking dots (processing)
- Positioned at bottom center of screen

#### Settings Window
- Engine picker (Auto / Groq Whisper / OpenAI Whisper / Apple Speech)
- Groq API key management (SecureField + Keychain storage)
- OpenAI API key management (SecureField + Keychain storage)
- Model selection per provider
- Language selection
- Apple Speech status and permission grant
- Launch at login toggle
- Permission status display

#### Onboarding Window
- First-launch flow: Microphone -> Accessibility -> Speech Recognition -> API Key (optional)
- API key step can be skipped to use Apple Speech
- Shows which engine will be active based on configuration
- Link to get free Groq API key

---

## File Structure

```
AudioType/
|-- AudioType/
|   |-- App/
|   |   |-- AudioTypeApp.swift          # @main entry point
|   |   |-- MenuBarController.swift     # Status item management
|   |   +-- TranscriptionManager.swift  # Orchestrates record -> transcribe -> insert
|   |
|   |-- Core/
|   |   |-- HotKeyManager.swift         # Global hotkey handling
|   |   |-- AudioRecorder.swift         # Microphone capture
|   |   |-- TranscriptionEngine.swift   # Protocol, EngineType enum, EngineResolver
|   |   |-- WAVEncoder.swift            # WhisperAPIEngine base class, WAVEncoder, config, errors
|   |   |-- GroqEngine.swift            # GroqEngine subclass, GroqModel, TranscriptionLanguage
|   |   |-- OpenAIEngine.swift          # OpenAIEngine subclass, OpenAIModel
|   |   |-- AppleSpeechEngine.swift     # Apple SFSpeechRecognizer on-device engine
|   |   |-- TextPostProcessor.swift     # Text corrections
|   |   +-- TextInserter.swift          # Keyboard simulation
|   |
|   |-- UI/
|   |   |-- SettingsView.swift          # Settings window (engine, API keys, models, etc.)
|   |   |-- RecordingOverlay.swift      # Recording indicator
|   |   |-- OnboardingView.swift        # First-launch setup (API key optional)
|   |   +-- Theme.swift                 # Brand color system
|   |
|   |-- Utilities/
|   |   |-- Permissions.swift           # Mic, Accessibility, Speech Recognition helpers
|   |   +-- KeychainHelper.swift        # macOS Keychain-based secret storage
|   |
|   +-- Resources/
|       +-- Assets.xcassets
|
|-- Resources/
|   |-- Info.plist
|   +-- AppIcon.icns
|
|-- Package.swift
|-- Makefile
+-- README.md
```

---

## Build Configuration

### Requirements
- Xcode 15+ / Swift 5.9+
- macOS 13.0+ (Ventura) deployment target
- No external dependencies (no cmake, no submodules)

### Build Steps

```bash
# Build and create app bundle
make app

# Or manually
swift build
```

### Info.plist Entries

```xml
<key>NSMicrophoneUsageDescription</key>
<string>AudioType needs microphone access to transcribe your speech.</string>

<key>NSSpeechRecognitionUsageDescription</key>
<string>AudioType uses on-device speech recognition to transcribe your voice
when no cloud API key is configured.</string>

<key>LSUIElement</key>
<true/>
```

---

## Workflow Sequence

```
User holds fn key
         |
         v
+---------------------+
| HotKeyManager       |
| detects key down    |
+---------------------+
         |
         v
+---------------------+
| AudioRecorder       |
| starts capture      |<------ Show recording indicator
+---------------------+
         |
    (user speaks)
         |
         v
User releases fn key
         |
         v
+---------------------+
| AudioRecorder       |
| stops, returns PCM  |
+---------------------+
         |
         v
+---------------------+
| EngineResolver      |<------ Show "processing" indicator
| picks engine based  |
| on user preference  |
+---------------------+
         |
    +----+--------+
    |    |        |
    v    v        v
+------+ +------+ +----------+
| Groq | |OpenAI| | Apple    |
|Engine| |Engine| | Speech   |
| (WAV→| | (WAV→| | (PCMBuf→ |
|  API)| |  API)| |  SFSpeech)|
+------+ +------+ +----------+
    |    |        |
    +----+--------+
         |
         v
+---------------------+
| TextPostProcessor   |
| clean up text       |
+---------------------+
         |
         v
+---------------------+
| TextInserter        |
| insertText(result)  |<------ Hide indicator
+---------------------+
         |
         v
   Text appears in
   focused application
```

---

## Error Handling

| Error | Cause | Resolution |
|-------|-------|------------|
| API key not configured | User hasn't set key (cloud mode) | Fall back to Apple Speech in Auto; show settings prompt in explicit mode |
| Unauthorized (401) | Invalid API key | Prompt to check key in Settings |
| Rate limited (429) | Too many requests | Auto-retry after delay, show message |
| Network error | No internet (cloud engines) | Show error, auto-reset to idle |
| Speech not authorized | User denied speech recognition | Request authorization on next attempt; show Settings link |
| Speech not available | SFSpeechRecognizer unavailable | Show error, suggest configuring a cloud API key |
| No microphone permission | User denied | Show onboarding with Settings link |
| No accessibility permission | User didn't enable | Show alert with Settings button |
| No engine available | No cloud key AND speech denied | Show error prompting to configure either |
| Transcription failed | Engine error | Log error, show "Try again", auto-reset |

---

## Dependencies

| Dependency | Purpose |
|------------|---------|
| Swift 5.9+ | Primary language |
| SwiftUI (macOS 13+) | UI framework |
| AVFoundation | Audio capture |
| Speech | On-device speech recognition (Apple Speech engine) |
| Security | Keychain-based API key storage |
| ApplicationServices | Keyboard simulation |

**External services (optional, user-provided API keys):**
- [Groq API](https://groq.com/) — cloud Whisper transcription
- [OpenAI API](https://openai.com/) — cloud Whisper / GPT-4o transcription

---

## Summary

AudioType provides a native Mac voice-to-text experience that:

- Activates instantly via fn key hold
- Supports three transcription backends: Groq Whisper (cloud), OpenAI Whisper (cloud), and Apple Speech (on-device)
- Works out of the box without an API key using Apple's on-device speech recognition
- Optionally uses Groq's cloud Whisper Large V3 or OpenAI's GPT-4o for higher accuracy
- Automatically selects the best available engine (Auto mode: Groq → OpenAI → Apple Speech)
- Securely stores API keys in macOS Keychain
- Simulates keyboard typing to insert text into any app
- Runs as a lightweight menu bar app
- Distributes as notarized DMG or build from source with `make app`
