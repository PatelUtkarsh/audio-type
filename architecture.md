# AudioType - Architecture Document

A native macOS application providing instant voice-to-text functionality.

## Overview

**AudioType** captures voice via a global hotkey, sends audio to the Groq API (Whisper Large V3) for cloud transcription, and simulates keyboard typing to insert text into any application.

### Key Design Goals

1. **Instant activation** - Sub-100ms from hotkey press to recording start
2. **High-quality transcription** - Whisper Large V3 via Groq for best accuracy
3. **Universal text insertion** - Works in any app via keyboard simulation
4. **Minimal footprint** - Menu bar app, no dock icon, lightweight
5. **Self-serve** - Users provide their own free Groq API key

---

## System Architecture

```
+---------------------------------------------------------------------+
|                         AudioType.app                               |
+---------------------------------------------------------------------+
|                                                                     |
|  +--------------+    +--------------+    +----------------------+   |
|  |   HotKey     |--->|   Audio      |--->|   Groq Engine        |   |
|  |   Manager    |    |   Recorder   |    |   (Cloud API)        |   |
|  +--------------+    +--------------+    +----------------------+   |
|         |                   |                       |               |
|         |                   |                       v               |
|         |                   |            +----------------------+   |
|         |                   |            |   Text Inserter      |   |
|         |                   |            |   (CGEventPost)      |   |
|         |                   |            +----------------------+   |
|         |                   |                       |               |
|         v                   v                       v               |
|  +-------------------------------------------------------------+   |
|  |                    UI Layer (SwiftUI)                         |   |
|  |  +-------------+  +-------------+  +---------------------+  |   |
|  |  | Menu Bar    |  | Recording   |  | Settings Window     |  |   |
|  |  | Status Item |  | Overlay     |  | (API Key, Model)    |  |   |
|  |  +-------------+  +-------------+  +---------------------+  |   |
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
- Output format: 16kHz mono PCM Float32 (optimal for Whisper)

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

### 3. Groq Engine (Cloud API)

**Purpose:** Transcribe audio to text using Groq's hosted Whisper models.

**Integration:**
- Converts PCM Float32 samples to WAV data in-memory
- Sends multipart/form-data POST to `https://api.groq.com/openai/v1/audio/transcriptions`
- Parses JSON response containing transcribed text

#### API Details

| Parameter | Value |
|-----------|-------|
| Endpoint | `POST /openai/v1/audio/transcriptions` |
| Auth | `Bearer <GROQ_API_KEY>` |
| File format | WAV (16-bit PCM, mono, 16kHz) |
| Max file size | 25 MB (free tier) |
| Response | `{"text": "..."}` |

#### Model Options

| Model | Speed | Accuracy | Cost |
|-------|-------|----------|------|
| `whisper-large-v3-turbo` | Faster (216x real-time) | Good | $0.04/hr |
| `whisper-large-v3` | Fast (189x real-time) | Best | $0.111/hr |

**Default Model:** `whisper-large-v3-turbo`

#### API Key Management

- Stored in macOS Keychain via `Security` framework
- Service identifier: `com.audiotype.app`
- Never written to UserDefaults or logged
- User provides their own key (self-serve)

```swift
class GroqEngine {
    func transcribe(samples: [Float]) async throws -> String
    static func setApiKey(_ key: String) throws
    static var apiKey: String?
    static var isConfigured: Bool
}
```

#### Free Tier Rate Limits

| Limit | Value |
|-------|-------|
| Requests per minute | 20 |
| Requests per day | 2,000 |
| Audio seconds per hour | 7,200 (~2 hrs) |
| Audio seconds per day | 28,800 (~8 hrs) |

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
- Small floating window showing "Recording..." or "Processing..."
- Positioned at bottom center of screen

#### Settings Window
- Groq API key management (SecureField + Keychain storage)
- Model selection (Turbo / Large V3)
- Launch at login toggle
- Permission status display

#### Onboarding Window
- First-launch flow: Microphone -> Accessibility -> API Key
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
|   |   |-- GroqEngine.swift            # Groq API client + WAV encoding
|   |   |-- TextPostProcessor.swift     # Text corrections
|   |   +-- TextInserter.swift          # Keyboard simulation
|   |
|   |-- UI/
|   |   |-- SettingsView.swift          # Settings window
|   |   |-- RecordingOverlay.swift      # Recording indicator
|   |   +-- OnboardingView.swift        # First-launch setup
|   |
|   |-- Utilities/
|   |   |-- Permissions.swift           # Check/request permissions
|   |   +-- KeychainHelper.swift        # Keychain read/write for API key
|   |
|   +-- Resources/
|       |-- Assets.xcassets
|       +-- Info.plist
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
| GroqEngine          |<------ Show "processing" indicator
| encode WAV          |
| POST to Groq API   |
| parse response      |
+---------------------+
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
| API key not configured | User hasn't set key | Show onboarding / settings prompt |
| Unauthorized (401) | Invalid API key | Prompt to check key in Settings |
| Rate limited (429) | Too many requests | Auto-retry after delay, show message |
| Network error | No internet | Show error, auto-reset to idle |
| No microphone permission | User denied | Show onboarding with Settings link |
| No accessibility permission | User didn't enable | Show alert with Settings button |
| Transcription failed | Server error | Log error, show "Try again" |

---

## Dependencies

| Dependency | Purpose |
|------------|---------|
| Swift 5.9+ | Primary language |
| SwiftUI (macOS 13+) | UI framework |
| AVFoundation | Audio capture |
| Security | Keychain API key storage |
| ApplicationServices | Keyboard simulation |

**External service:** [Groq API](https://groq.com/) (user-provided API key)

---

## Summary

AudioType provides a native Mac voice-to-text experience that:

- Activates instantly via fn key hold
- Uses Groq's cloud Whisper Large V3 for high-accuracy transcription
- Self-serve: users bring their own free Groq API key
- Securely stores API key in macOS Keychain
- Simulates keyboard typing to insert text into any app
- Runs as a lightweight menu bar app
- Requires internet connection for transcription
- Distributes as notarized DMG or build from source with `make app`
