# AudioType - Architecture Document

A native macOS application providing instant voice-to-text functionality similar to Wispr Flow.

## Overview

**AudioType** captures voice via a global hotkey, transcribes it locally using whisper.cpp with the base model (142 MB), and simulates keyboard typing to insert text into any application.

### Key Design Goals

1. **Instant activation** - Sub-100ms from hotkey press to recording start
2. **Fast transcription** - Leverage whisper.cpp with Metal/Core ML acceleration on Apple Silicon
3. **Universal text insertion** - Works in any app via keyboard simulation
4. **Minimal footprint** - Menu bar app, no dock icon, lightweight
5. **Fully local** - No cloud APIs, complete privacy

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         AudioType.app                                │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────────┐   │
│  │   HotKey     │───▶│   Audio      │───▶│   Whisper Engine     │   │
│  │   Manager    │    │   Recorder   │    │   (whisper.cpp)      │   │
│  └──────────────┘    └──────────────┘    └──────────────────────┘   │
│         │                   │                       │                │
│         │                   │                       ▼                │
│         │                   │            ┌──────────────────────┐   │
│         │                   │            │   Text Inserter      │   │
│         │                   │            │   (CGEventPost)      │   │
│         │                   │            └──────────────────────┘   │
│         │                   │                       │                │
│         ▼                   ▼                       ▼                │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                    UI Layer (SwiftUI)                        │    │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │    │
│  │  │ Menu Bar    │  │ Recording   │  │ Settings Window     │  │    │
│  │  │ Status Item │  │ Overlay     │  │ (Hotkey, Model)     │  │    │
│  │  └─────────────┘  └─────────────┘  └─────────────────────┘  │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Component Breakdown

### 1. HotKey Manager

**Purpose:** Listen for global keyboard shortcuts to trigger recording.

**Technology:**
- `CGEvent` tap for global hotkey detection
- Runs on a dedicated background thread

**Key APIs:**
```swift
CGEvent.tapCreate(tap:place:options:eventsOfInterest:callback:userInfo:)
CFMachPortCreateRunLoopSource()
CFRunLoopAddSource()
```

**Default Hotkey:** `⌘ + Shift + Space` (configurable)

**States:**
- Idle → Recording (on key down)
- Recording → Processing (on key up)

---

### 2. Audio Recorder

**Purpose:** Capture microphone audio in real-time.

**Technology:**
- `AVAudioEngine` for low-latency capture
- Output format: 16kHz mono PCM (required by Whisper)

**Key Components:**
```swift
class AudioRecorder {
    let audioEngine = AVAudioEngine()
    var audioBuffer: [Float] = []
    
    func startRecording()                // Begin capture
    func stopRecording() -> [Float]      // Return samples
}
```

**Audio Format Requirements:**
- Sample rate: 16,000 Hz
- Channels: 1 (mono)
- Format: Float32

**Permissions Required:**
- Microphone access (`NSMicrophoneUsageDescription`)

---

### 3. Whisper Engine (whisper.cpp)

**Purpose:** Transcribe audio to text locally using whisper.cpp.

**Integration Approach:**
- Compile whisper.cpp as a static library (`.a`) or XCFramework
- Use Swift-C bridging header for interop
- Support both Metal and Core ML backends

#### Model Options

| Model | Disk Size | Memory Usage | Speed |
|-------|-----------|--------------|-------|
| tiny | 75 MB | ~273 MB | Fastest |
| **base** | **142 MB** | **~388 MB** | **Recommended** |
| small | 466 MB | ~852 MB | Slower |
| medium | 1.5 GB | ~2.1 GB | Slow |
| large | 2.9 GB | ~3.9 GB | Slowest |

**Selected Model:** `ggml-base.en.bin` (142 MB)
- Stored in `~/Library/Application Support/AudioType/models/`
- Downloaded on first launch or bundled with app

#### Acceleration Options

##### Metal GPU Acceleration (Default)
- Uses Apple GPU via Metal shaders
- ~3x faster than CPU on Apple Silicon
- Enabled with `WHISPER_METAL=ON`

##### Core ML / Apple Neural Engine (Optional)
- Runs encoder on Apple Neural Engine (ANE)
- Can be faster and more power-efficient than Metal
- Requires pre-converted Core ML model (`.mlmodelc`)

**Core ML Setup:**
```bash
# Install dependencies
pip install ane_transformers openai-whisper coremltools

# Generate Core ML model
./models/generate-coreml-model.sh base.en
# Output: models/ggml-base.en-encoder.mlmodelc
```

**First run note:** Core ML compiles the model to a device-specific format on first use, causing a one-time delay.

#### Key C API (from whisper.h)

```c
struct whisper_context * whisper_init_from_file(const char * path);
int whisper_full(struct whisper_context * ctx, 
                 struct whisper_full_params params,
                 const float * samples, 
                 int n_samples);
const char * whisper_full_get_segment_text(struct whisper_context * ctx, int i);
void whisper_free(struct whisper_context * ctx);
```

#### Swift Wrapper

```swift
enum AccelerationMode {
    case cpu
    case metal      // GPU via Metal
    case coreML     // ANE via Core ML
    case auto       // Let whisper.cpp decide
}

class WhisperEngine {
    private var context: OpaquePointer?
    
    init(modelPath: String, coreMLModelPath: String? = nil, mode: AccelerationMode = .auto)
    func transcribe(samples: [Float]) -> String
    deinit  // Call whisper_free
}
```

#### Performance Settings

```swift
var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
params.n_threads = 4          // Use multiple CPU threads
params.speed_up = true        // Enable 2x speed optimization
params.language = "en"        // English only for faster processing
params.single_segment = true  // Don't split into segments
```

---

### 4. Text Inserter

**Purpose:** Type transcribed text into the currently focused application.

**Technology:**
- `CGEventPost` to simulate keyboard events
- Post to `.cgSessionEventTap` for system-wide injection

**Implementation:**
```swift
class TextInserter {
    func insertText(_ text: String) {
        for char in text {
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            
            var utf16 = Array(String(char).utf16)
            keyDown?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            keyUp?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            
            keyDown?.post(tap: .cgSessionEventTap)
            keyUp?.post(tap: .cgSessionEventTap)
        }
    }
}
```

**Permissions Required:**
- Accessibility access (`AXIsProcessTrusted()`)

---

### 5. UI Layer (SwiftUI)

#### Menu Bar Status Item
- Shows recording state (🎤 idle, 🔴 recording, ⏳ processing)
- Dropdown menu: Settings, About, Quit

#### Recording Overlay (Optional)
- Small floating window showing "Recording..." or waveform
- Positioned near cursor or center of screen
- Disappears after transcription

#### Settings Window
- Hotkey configuration
- Model selection (tiny/base/small)
- Acceleration mode (Metal/Core ML/Auto)
- Launch at login toggle
- Audio input device selection

---

## File Structure

```
AudioType/
├── AudioType.xcodeproj
├── AudioType/
│   ├── App/
│   │   ├── AudioTypeApp.swift          # @main entry point
│   │   ├── AppDelegate.swift           # NSApplicationDelegate
│   │   └── MenuBarController.swift     # Status item management
│   │
│   ├── Core/
│   │   ├── HotKeyManager.swift         # Global hotkey handling
│   │   ├── AudioRecorder.swift         # Microphone capture
│   │   ├── WhisperEngine.swift         # whisper.cpp wrapper
│   │   └── TextInserter.swift          # Keyboard simulation
│   │
│   ├── UI/
│   │   ├── SettingsView.swift          # Settings window
│   │   ├── RecordingOverlay.swift      # Recording indicator
│   │   └── OnboardingView.swift        # First-launch permissions
│   │
│   ├── Utilities/
│   │   ├── Permissions.swift           # Check/request permissions
│   │   ├── ModelDownloader.swift       # Download ggml model
│   │   └── Preferences.swift           # UserDefaults wrapper
│   │
│   ├── Resources/
│   │   ├── Assets.xcassets
│   │   └── Info.plist
│   │
│   └── Bridging/
│       ├── AudioType-Bridging-Header.h
│       └── WhisperWrapper.h            # C interface for Swift
│
├── whisper.cpp/                        # Submodule or vendored
│   ├── include/
│   │   └── whisper.h
│   ├── src/
│   │   └── whisper.cpp
│   ├── ggml/
│   │   ├── include/
│   │   │   └── ggml.h
│   │   └── src/
│   │       ├── ggml.c
│   │       └── ggml-metal.metal
│   └── models/
│       └── generate-coreml-model.sh
│
├── Models/                             # Downloaded models (git-ignored)
│   ├── ggml-base.en.bin
│   └── ggml-base.en-encoder.mlmodelc/  # Core ML model (optional)
│
└── Scripts/
    ├── download-model.sh               # Fetch whisper model
    ├── generate-coreml-model.sh        # Convert to Core ML
    └── build-whisper.sh                # Compile whisper.cpp
```

---

## Build Configuration

### Requirements
- Xcode 15+
- macOS 13.0+ (Ventura) deployment target
- Swift 5.9+
- CMake (for building whisper.cpp)
- Python 3.10+ (for Core ML model generation)

### Info.plist Entries

```xml
<!-- Microphone access -->
<key>NSMicrophoneUsageDescription</key>
<string>AudioType needs microphone access to transcribe your speech.</string>

<!-- Hide from dock -->
<key>LSUIElement</key>
<true/>

<!-- Minimum macOS version -->
<key>LSMinimumSystemVersion</key>
<string>13.0</string>
```

### Entitlements

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" 
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Hardened runtime (required for notarization) -->
    <key>com.apple.security.hardened-runtime</key>
    <true/>
    
    <!-- Microphone access -->
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
```

**Note:** Keyboard simulation via `CGEventPost` requires Accessibility permissions, which work with hardened runtime but NOT with App Sandbox. Distribute via notarized DMG, not Mac App Store.

---

## Building whisper.cpp

### Option A: As Static Library (Recommended for Development)

```bash
#!/bin/bash
# Scripts/build-whisper.sh

cd whisper.cpp
mkdir -p build && cd build

cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DWHISPER_METAL=ON \
    -DWHISPER_COREML=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0

cmake --build . --config Release -j$(sysctl -n hw.ncpu)

# Output: libwhisper.a
```

### Option B: As XCFramework (Recommended for Distribution)

```bash
#!/bin/bash
# Use whisper.cpp's built-in script
cd whisper.cpp
./build-xcframework.sh

# Output: whisper.xcframework
```

### Xcode Integration

1. Add `libwhisper.a` (or `whisper.xcframework`) to "Link Binary With Libraries"
2. Add whisper.cpp headers to "Header Search Paths": `$(PROJECT_DIR)/whisper.cpp/include`
3. Add to "Other Linker Flags": `-lc++`
4. Add required frameworks:
   - `Accelerate.framework`
   - `Metal.framework`
   - `MetalKit.framework`
   - `CoreML.framework` (if using Core ML)

### Bridging Header

```c
// AudioType-Bridging-Header.h
#include "whisper.h"
```

---

## Downloading Models

### Script: download-model.sh

```bash
#!/bin/bash
# Scripts/download-model.sh

MODEL=${1:-base.en}
MODELS_DIR="$HOME/Library/Application Support/AudioType/models"
mkdir -p "$MODELS_DIR"

WHISPER_MODELS_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

echo "Downloading ggml-${MODEL}.bin..."
curl -L "${WHISPER_MODELS_URL}/ggml-${MODEL}.bin" \
    -o "${MODELS_DIR}/ggml-${MODEL}.bin" \
    --progress-bar

echo "Model downloaded to: ${MODELS_DIR}/ggml-${MODEL}.bin"
```

### Generating Core ML Model (Optional)

```bash
#!/bin/bash
# Scripts/generate-coreml-model.sh

MODEL=${1:-base.en}
MODELS_DIR="$HOME/Library/Application Support/AudioType/models"

# Ensure dependencies
pip install ane_transformers openai-whisper coremltools

# Generate Core ML model
cd whisper.cpp/models
python3 generate-coreml-model.py --model ${MODEL}

# Move to app models directory
mv ggml-${MODEL}-encoder.mlmodelc "${MODELS_DIR}/"

echo "Core ML model generated: ${MODELS_DIR}/ggml-${MODEL}-encoder.mlmodelc"
```

---

## Workflow Sequence

```
User presses ⌘+Shift+Space
         │
         ▼
┌─────────────────────┐
│ HotKeyManager       │
│ detects key down    │
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│ AudioRecorder       │
│ starts capture      │◀────── Show recording indicator
└─────────────────────┘
         │
    (user speaks)
         │
         ▼
User releases ⌘+Shift+Space
         │
         ▼
┌─────────────────────┐
│ AudioRecorder       │
│ stops, returns PCM  │
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│ WhisperEngine       │◀────── Show "processing" indicator
│ transcribe(samples) │
│ (Metal or Core ML)  │
└─────────────────────┘
         │
         ▼
┌─────────────────────┐
│ TextInserter        │
│ insertText(result)  │◀────── Hide indicator
└─────────────────────┘
         │
         ▼
   Text appears in
   focused application
```

---

## Performance Optimizations

### 1. Pre-load Whisper Model
- Load model at app startup, keep in memory
- First transcription is instant (no model loading delay)
- Memory footprint: ~388 MB for base model

### 2. GPU/ANE Acceleration
- **Metal:** GPU acceleration via Metal shaders (~3x faster than CPU)
- **Core ML:** Apple Neural Engine acceleration (power-efficient, fast)
- Automatically selected based on availability

### 3. Streaming Audio Buffer
- Use circular buffer for audio capture
- Avoid memory allocations during recording
- Pre-allocate for 30 seconds of audio

### 4. Greedy Decoding
- Use `WHISPER_SAMPLING_GREEDY` instead of beam search
- Faster inference, slightly less accurate
- Good enough for dictation use case

### 5. English-Only Model
- `base.en` is faster than multilingual `base`
- Skips language detection step
- Optimized specifically for English

### 6. Single Segment Mode
- Set `single_segment = true`
- Returns result as soon as transcription completes
- No need to iterate over multiple segments

---

## Permissions & Onboarding

### Required Permissions

1. **Microphone** - Requested via standard macOS prompt
2. **Accessibility** - Required for keyboard simulation, user must enable in System Settings

### Permission Check Code

```swift
class Permissions {
    static func checkMicrophone() async -> Bool {
        return await AVCaptureDevice.requestAccess(for: .audio)
    }
    
    static func checkAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
```

### First Launch Flow

```
┌─────────────────────────────────────┐
│         Welcome to AudioType        │
│                                     │
│  AudioType needs two permissions:   │
│                                     │
│  🎤 Microphone Access               │
│     To hear your voice              │
│                                     │
│  ⌨️ Accessibility Access            │
│     To type text into other apps    │
│                                     │
│        [Continue Setup]             │
└─────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│  1. Request Microphone Permission   │
│     (standard macOS dialog)         │
└─────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│  2. Open Accessibility Settings     │
│     Guide user to enable AudioType  │
└─────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│  3. Download whisper model          │
│     (if not bundled)                │
│     Progress: ████████░░ 80%        │
└─────────────────────────────────────┘
              │
              ▼
         Ready to use!
```

---

## Distribution

### Notarized DMG (Recommended)

Full functionality including keyboard simulation. Requires Apple Developer account ($99/year).

**Build Steps:**

```bash
# 1. Archive
xcodebuild -scheme AudioType -configuration Release \
    -archivePath build/AudioType.xcarchive archive

# 2. Export
xcodebuild -exportArchive \
    -archivePath build/AudioType.xcarchive \
    -exportPath build/export \
    -exportOptionsPlist ExportOptions.plist

# 3. Create DMG
hdiutil create -volname "AudioType" \
    -srcfolder build/export/AudioType.app \
    -ov -format UDZO \
    build/AudioType.dmg

# 4. Notarize
xcrun notarytool submit build/AudioType.dmg \
    --apple-id "your@email.com" \
    --password "@keychain:AC_PASSWORD" \
    --team-id "TEAM_ID" \
    --wait

# 5. Staple
xcrun stapler staple build/AudioType.dmg
```

### Why Not Mac App Store?

- App Sandbox prevents `CGEventPost` for keyboard simulation
- Would require alternative approach (e.g., Services menu, which is slower)
- Less "instantaneous" feel

---

## Dependencies

| Dependency | Version | Purpose |
|------------|---------|---------|
| whisper.cpp | v1.8.x | Speech-to-text engine |
| Swift | 5.9+ | Primary language |
| SwiftUI | macOS 13+ | UI framework |
| AVFoundation | - | Audio capture |
| Metal | - | GPU acceleration |
| Core ML | - | ANE acceleration (optional) |
| Accelerate | - | CPU vector operations |

---

## Testing Strategy

### Unit Tests
- `WhisperEngineTests` - Test transcription with sample audio files
- `AudioRecorderTests` - Test format conversion (44.1kHz → 16kHz)
- `HotKeyManagerTests` - Test key combination parsing
- `TextInserterTests` - Test character escaping

### Integration Tests
- End-to-end: Record → Transcribe → Insert
- Test with various audio durations (1s, 5s, 30s, 60s)
- Test with background noise

### Performance Tests
- Measure time from key release to text insertion
- Target: < 2 seconds for 10 seconds of audio (base model)

### Manual Testing Checklist
- [ ] Hotkey works in all apps (Safari, VS Code, Notes, Terminal, Slack)
- [ ] Text insertion preserves special characters
- [ ] Recording indicator appears/disappears correctly
- [ ] Settings persist across restarts
- [ ] Launch at login works
- [ ] Model download completes successfully
- [ ] Core ML model compiles on first run
- [ ] App handles microphone disconnection gracefully

---

## Error Handling

### Common Errors

| Error | Cause | Resolution |
|-------|-------|------------|
| No microphone permission | User denied | Show onboarding, guide to Settings |
| No accessibility permission | User didn't enable | Show alert with Settings button |
| Model not found | Download failed | Retry download, show progress |
| Transcription failed | Corrupt audio | Log error, show "Try again" |
| Text insertion failed | App not responding | Fallback to clipboard paste |

### Logging

```swift
import os.log

extension Logger {
    static let audio = Logger(subsystem: "com.audiotype", category: "Audio")
    static let whisper = Logger(subsystem: "com.audiotype", category: "Whisper")
    static let hotkey = Logger(subsystem: "com.audiotype", category: "HotKey")
}
```

---

## Future Enhancements (Post-MVP)

1. **LLM text enhancement** - Clean up transcription with GPT/Claude
2. **Custom vocabulary** - Add technical terms, names
3. **Multiple languages** - Switch to multilingual model
4. **Voice commands** - "Delete last sentence", "New paragraph"
5. **Streaming transcription** - Show text as you speak
6. **Dictation history** - Log of recent transcriptions
7. **Per-app settings** - Different behavior for different apps
8. **Keyboard shortcut to cancel** - Escape to abort recording

---

## Summary

AudioType provides a native Mac voice-to-text experience that:

- Activates instantly via global hotkey (Cmd+Shift+Space)
- Uses whisper.cpp (base.en model, 142 MB) for local transcription
- Supports Metal GPU and Core ML ANE acceleration
- Simulates keyboard typing to insert text into any app
- Runs as a lightweight menu bar app
- Requires no cloud APIs - complete privacy
- Distributes as notarized DMG for full functionality
