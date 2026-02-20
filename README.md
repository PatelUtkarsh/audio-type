# AudioType

A native macOS menu bar app for voice-to-text. Hold **fn** to record, release to transcribe and type.

## Features

- **Hold fn key** to record voice, release to transcribe and insert text
- **Multiple cloud providers** — [Groq](https://groq.com/) and [OpenAI](https://openai.com/) Whisper APIs for high accuracy
- **On-device fallback** — Apple Speech (no API key or internet needed)
- **Works in any app** — types transcribed text into the focused application
- **Self-serve** — bring your own API key (Groq free tier, or OpenAI)
- **Lightweight** — runs in menu bar, no dock icon

## Privacy & Data

> **Important:** AudioType previously ran transcription 100% locally using whisper.cpp. We found the local model quality insufficient for reliable daily use, so we switched to cloud-based Whisper APIs which provide significantly better accuracy and speed. An on-device Apple Speech fallback is available if you prefer no cloud usage.

**What this means:**

- When using a cloud engine, audio recordings **are sent to the provider's servers** for transcription
- An internet connection **is required** for cloud transcription (not needed for Apple Speech)
- Your API keys are stored locally in the macOS Keychain
- No audio is saved to disk locally — it is recorded in memory, sent to the cloud provider, and discarded
- See [Groq's data policy](https://groq.com/privacy-policy/) or [OpenAI's data policy](https://openai.com/policies/privacy-policy) for how they handle your data

### Looking for the privacy-focused local version?

If you prefer **100% offline transcription** with no data leaving your machine, you can use [AudioType v1.1.1](https://github.com/PatelUtkarsh/audio-type/releases/tag/v1.1.1) — the last release that runs transcription entirely on-device using a local OpenAI Whisper model via [whisper.cpp](https://github.com/ggerganov/whisper.cpp). No internet or API key required. Note that local transcription accuracy is lower than the cloud version.

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon or Intel Mac
- Internet connection (for cloud engines; not needed for Apple Speech)
- A cloud API key (optional — app works without one using Apple Speech):
  - Free [Groq API key](https://console.groq.com/keys), or
  - [OpenAI API key](https://platform.openai.com/api-keys)

## Setup

### 1. Get an API Key (optional)

AudioType works out of the box using Apple's on-device speech recognition. For higher accuracy, configure a cloud provider:

#### Option A: Groq (free tier)

1. Go to [console.groq.com/keys](https://console.groq.com/keys)
2. Create an account or sign in
3. Generate a new API key
4. Copy the key — you'll paste it into AudioType on first launch

Groq's free tier is generous enough for typical dictation use. See [Groq's rate limits](https://console.groq.com/docs/rate-limits) for current details.

#### Option B: OpenAI

1. Go to [platform.openai.com/api-keys](https://platform.openai.com/api-keys)
2. Create an account or sign in
3. Generate a new API key
4. Copy the key — you'll paste it into AudioType Settings

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
3. **Grant Speech Recognition** — for on-device Apple Speech
4. **Enter a Groq API key** (optional) — for cloud transcription

You can skip the API key step to use Apple Speech. Additional cloud providers (OpenAI) can be configured later in Settings.

## Permissions

| Permission | Purpose |
|------------|---------|
| **Microphone** | Record voice for transcription |
| **Accessibility** | Detect fn key and type text into apps |
| **Speech Recognition** | On-device Apple Speech transcription |
| **Internet** | Send audio to cloud provider (Groq or OpenAI) |

## Usage

1. **Launch AudioType** — appears in menu bar with a waveform icon
2. **Hold fn key** — starts recording (overlay shows waveform)
3. **Release fn key** — sends audio to the active engine and types the result
4. **Click menu bar icon** — access Settings or Quit

### Settings

- **Engine Selection**:
  - `Auto` (default) — uses Groq if configured, then OpenAI, then Apple Speech
  - `Groq Whisper` — always use Groq (requires API key)
  - `OpenAI Whisper` — always use OpenAI (requires API key)
  - `Apple Speech` — always use on-device recognition
- **Groq API Key** — add or update your Groq key
- **OpenAI API Key** — add or update your OpenAI key
- **Model Selection**:
  - Groq: `Whisper Large V3 Turbo` (default, faster) or `Whisper Large V3` (most accurate)
  - OpenAI: `GPT-4o Mini Transcribe` (default, balanced), `GPT-4o Transcribe` (best), or `Whisper V2` (cheapest)
- **Language** — auto-detect or choose from 25+ languages

## How It Works

```
fn key held -> Record audio -> Release fn key
                                    |
                                    v
                            Encode audio as WAV
                                    |
                                    v
                            EngineResolver picks engine
                            (Groq / OpenAI / Apple Speech)
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
- **OpenAI API** — cloud speech-to-text (GPT-4o Transcribe / Whisper)
- **Apple Speech** — on-device speech-to-text (SFSpeechRecognizer)
- **AVAudioEngine** — low-latency audio capture
- **CGEvent** — global hotkey detection and keyboard simulation
- **macOS Keychain** — secure API key storage

## Troubleshooting

### App doesn't respond to fn key
- Check Accessibility permission in System Settings > Privacy & Security > Accessibility
- Try removing and re-adding AudioType from the list

### No audio captured
- Check Microphone permission in System Settings > Privacy & Security > Microphone
- Ensure your microphone is working in other apps

### Transcription fails
- Check your internet connection (for cloud engines)
- Verify your API key is valid in Settings
- If you see "Rate limited", wait a moment and try again
- Check [Groq status](https://status.groq.com/) or [OpenAI status](https://status.openai.com/) for service issues

### "API key required" error
- Open Settings from the menu bar icon and enter your API key
- Get a free Groq key at [console.groq.com/keys](https://console.groq.com/keys)
- Or use Apple Speech (no key required) by setting engine to Auto or Apple Speech

## Rate Limits

Groq offers a free tier that is generous enough for typical dictation use. For current limits and pricing, see [Groq's rate limits](https://console.groq.com/docs/rate-limits) and [pricing](https://groq.com/pricing/).

OpenAI uses pay-as-you-go pricing. See [OpenAI's pricing](https://openai.com/api/pricing/) for current rates.

## License

MIT

## Acknowledgments

- [Groq](https://groq.com/) for fast cloud inference
- [OpenAI](https://openai.com/) for Whisper and GPT-4o transcription models
- This project is entirely vibe coded with AI assistance
