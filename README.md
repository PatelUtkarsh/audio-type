# AudioType

A native macOS menu bar app for voice-to-text. Hold **fn** to record, release to transcribe and type.

## Features

- **Hold fn key** to record voice, release to transcribe and insert text
- **100% local processing** - uses [whisper.cpp](https://github.com/ggerganov/whisper.cpp) with Metal GPU acceleration
- **Works in any app** - types transcribed text into the focused application
- **Multiple model sizes** - choose from tiny, base, small, or medium models
- **Lightweight** - runs in menu bar, no dock icon

## Privacy

**All processing happens locally on your Mac.** 

- No audio is ever sent to the cloud
- No internet connection required for transcription
- Audio is processed in memory and never saved to disk
- Models are downloaded once and stored locally

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon Mac (M1/M2/M3) recommended for best performance
- ~150MB-1.5GB disk space depending on model size

## Installation

### Download Release

1. Download the latest `.dmg` from [Releases](https://github.com/PatelUtkarsh/audio-type/releases)
2. Open the DMG and drag AudioType to Applications
3. Launch AudioType from Applications

### Build from Source

```bash
# Clone with submodules
git clone --recursive https://github.com/PatelUtkarsh/audio-type.git
cd audio-type

# Build whisper.cpp and create app bundle
make app

# Run the app
open AudioType.app
```

## Permissions

AudioType requires the following permissions:

| Permission | Purpose |
|------------|---------|
| **Microphone** | Record voice for transcription |
| **Accessibility** | Detect fn key and type text into apps |

On first launch, you'll be prompted to grant these permissions in System Settings.

## Usage

1. **Launch AudioType** - appears in menu bar with a waveform icon
2. **Hold fn key** - starts recording (overlay shows "Recording...")
3. **Release fn key** - processes audio and types the result
4. **Click menu bar icon** - access Settings or Quit

### Settings

- **Model Selection** - choose transcription model:
  - `tiny` (~75MB) - fastest, lower accuracy
  - `base` (~142MB) - good balance (default)
  - `small` (~466MB) - better accuracy
  - `medium` (~1.5GB) - best accuracy, slower

Models are downloaded automatically on first use.

## How It Works

```
fn key held -> Record audio -> Release fn key
                                    |
                                    v
                            whisper.cpp transcribes
                                    |
                                    v
                            Text post-processing
                            (capitalization, corrections)
                                    |
                                    v
                            Simulate keyboard typing
                            into focused app
```

## Tech Stack

- **Swift** - native macOS app
- **whisper.cpp** - local speech recognition with Metal acceleration
- **AVAudioEngine** - low-latency audio capture
- **CGEvent** - global hotkey detection and keyboard simulation

## Troubleshooting

### App doesn't respond to fn key
- Check Accessibility permission in System Settings > Privacy & Security > Accessibility
- Try removing and re-adding AudioType from the list

### No audio captured
- Check Microphone permission in System Settings > Privacy & Security > Microphone
- Ensure your microphone is working in other apps

### Transcription is slow
- Try a smaller model (tiny or base) in Settings
- Ensure you're on Apple Silicon for Metal acceleration

## License

MIT

## Acknowledgments

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) by Georgi Gerganov
- [OpenAI Whisper](https://github.com/openai/whisper) for the original model
