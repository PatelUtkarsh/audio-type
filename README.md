# AudioType

A native macOS menu bar app for voice-to-text. Hold **fn** to record, release to transcribe and type.

## Features

- **Hold fn key** to record voice, release to transcribe and insert text
- **Cloud-powered transcription** via [Groq](https://groq.com/) — uses Whisper Large V3 for high accuracy
- **Works in any app** — types transcribed text into the focused application
- **Self-serve** — bring your own free Groq API key
- **Lightweight** — runs in menu bar, no dock icon

## Privacy & Data

> **Important:** AudioType previously ran transcription 100% locally using whisper.cpp. We found the local model quality insufficient for reliable daily use, so we switched to Groq's cloud-based Whisper API which provides significantly better accuracy and speed.

**What this means:**

- Audio recordings **are sent to Groq's servers** for transcription
- An internet connection **is required** for transcription
- Your Groq API key is stored locally in Application Support with restricted file permissions
- No audio is saved to disk locally — it is recorded in memory, sent to Groq, and discarded
- See [Groq's data policy](https://groq.com/privacy-policy/) for how they handle your data

### Looking for the privacy-focused local version?

If you prefer **100% offline transcription** with no data leaving your machine, you can use [AudioType v1.1.1](https://github.com/PatelUtkarsh/audio-type/releases/tag/v1.1.1) — the last release that runs transcription entirely on-device using a local OpenAI Whisper model via [whisper.cpp](https://github.com/ggerganov/whisper.cpp). No internet or API key required. Note that local transcription accuracy is lower than the cloud version.

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon or Intel Mac
- Internet connection
- Free [Groq API key](https://console.groq.com/keys)

## Setup

### 1. Get a Groq API Key (free)

1. Go to [console.groq.com/keys](https://console.groq.com/keys)
2. Create an account or sign in
3. Generate a new API key
4. Copy the key — you'll paste it into AudioType on first launch

Groq's free tier is generous enough for typical dictation use. See [Groq's rate limits](https://console.groq.com/docs/rate-limits) for current details.

### 2. Install AudioType

#### Download Release

1. Download the latest `.dmg` from [Releases](https://github.com/PatelUtkarsh/audio-type/releases)
2. Open the DMG and drag AudioType to Applications
3. **First launch** — Right-click the app and select "Open" (required for unsigned apps)
4. Click "Open" in the dialog to confirm

> **Note:** Since this app is not notarized, macOS will block it on first launch. You can also bypass this via Terminal:
> ```bash
> xattr -cr /Applications/AudioType.app
> ```

#### Build from Source

```bash
# Clone the repository
git clone https://github.com/PatelUtkarsh/audio-type.git
cd audio-type

# Build and create app bundle
make app

# Run the app
open AudioType.app
```

### 3. First Launch

On first launch, AudioType will ask you to:

1. **Grant Microphone access** — to record your voice
2. **Grant Accessibility access** — to type text into other apps
3. **Enter your Groq API key** — for cloud transcription

## Permissions

| Permission | Purpose |
|------------|---------|
| **Microphone** | Record voice for transcription |
| **Accessibility** | Detect fn key and type text into apps |
| **Internet** | Send audio to Groq for transcription |

## Usage

1. **Launch AudioType** — appears in menu bar with a waveform icon
2. **Hold fn key** — starts recording (overlay shows "Recording...")
3. **Release fn key** — sends audio to Groq and types the result
4. **Click menu bar icon** — access Settings or Quit

### Settings

- **Groq API Key** — add or update your key
- **Model Selection**:
  - `Whisper Large V3 Turbo` — faster, slightly lower accuracy (default)
  - `Whisper Large V3` — highest accuracy, slightly slower

## How It Works

```
fn key held -> Record audio -> Release fn key
                                    |
                                    v
                            Encode audio as WAV
                                    |
                                    v
                            Send to Groq API
                            (Whisper Large V3)
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

- **Swift** — native macOS app
- **Groq API** — cloud speech-to-text (Whisper Large V3)
- **AVAudioEngine** — low-latency audio capture
- **CGEvent** — global hotkey detection and keyboard simulation
- **Local secure storage** — API key stored with restricted file permissions

## Troubleshooting

### App doesn't respond to fn key
- Check Accessibility permission in System Settings > Privacy & Security > Accessibility
- Try removing and re-adding AudioType from the list

### No audio captured
- Check Microphone permission in System Settings > Privacy & Security > Microphone
- Ensure your microphone is working in other apps

### Transcription fails
- Check your internet connection
- Verify your Groq API key is valid in Settings
- If you see "Rate limited", wait a moment and try again
- Check [Groq status](https://status.groq.com/) for service issues

### "API key required" error
- Open Settings from the menu bar icon and enter your Groq API key
- Get a free key at [console.groq.com/keys](https://console.groq.com/keys)

## Rate Limits

Groq offers a free tier that is generous enough for typical dictation use. For current limits and pricing, see [Groq's rate limits](https://console.groq.com/docs/rate-limits) and [pricing](https://groq.com/pricing/).

## License

MIT

## Acknowledgments

- [Groq](https://groq.com/) for fast cloud inference
- [OpenAI Whisper](https://github.com/openai/whisper) for the speech-to-text model
- This project is entirely vibe coded with AI assistance
