<p align="center">
  <img src="assets/icon_readme.png" width="128" height="128" alt="OpenMeow">
</p>

<h1 align="center">OpenMeow</h1>

<p align="center">
  A native macOS menu bar app providing local & cloud TTS/ASR services via an OpenAI-compatible API.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License"></a>
  <img src="https://img.shields.io/badge/platform-macOS-lightgrey.svg" alt="Platform">
  <img src="https://img.shields.io/badge/Apple_Silicon-M1%2B-black.svg?logo=apple" alt="Apple Silicon">
  <img src="https://img.shields.io/badge/Swift-6.3-F05138.svg?logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/API-OpenAI_Compatible-10a37f.svg" alt="OpenAI Compatible">
</p>

<p align="center">
  <a href="#features">Features</a> &bull;
  <a href="#installation">Installation</a> &bull;
  <a href="#api">API</a> &bull;
  <a href="#use-with-openclaw">OpenClaw</a> &bull;
  <a href="#models">Models</a> &bull;
  <a href="#building">Building</a> &bull;
  <a href="README_CN.md">中文</a>
</p>

---

<p align="center">
  <img src="assets/screenshot_models.png" width="720" alt="OpenMeow Models">
</p>

## Features

- **Supported models** — Kokoro TTS, Kitten TTS, Qwen3 TTS, MiMo v2 TTS, FireRedASR v2, Qwen3 ASR, and more (local or cloud)
- **Menu bar app** — runs quietly in the background on macOS (Apple Silicon)
- **OpenAI-compatible API** — drop-in replacement for `/v1/audio/speech` and `/v1/audio/transcriptions`
- **Multiple engines** — sherpa-onnx, speech-swift (Qwen3-TTS/ASR)
- **Cloud TTS** — cloud-model API access including OpenAI-compatible services, Xiaomi MiMo, and Alibaba Qwen3
- **Audio format support** — WAV, MP3, Opus (OGG/WebM), PCM, FLAC, AAC
- **Model store** — download and manage models from the built-in registry
- **Works with OpenClaw** — give [OpenClaw](https://github.com/openclaw/openclaw) local voice capabilities in one line of config
- **Privacy first** — local models keep data on your machine; cloud models are opt-in

## Requirements

- macOS 15.0+
- Apple Silicon (M1/M2/M3/M4/M5)

## Installation

Download the latest `.dmg` or `.zip` from [Releases](../../releases), drag to Applications, and launch. No additional tools required.

## API

OpenMeow listens on `http://127.0.0.1:23333` by default.

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/v1/audio/speech` | POST | Text-to-Speech |
| `/v1/audio/transcriptions` | POST | Speech-to-Text |
| `/v1/models` | GET | List available models |
| `/v1/voices` | GET | List available voices |
| `/health` | GET | Health check |

### TTS Example

```bash
curl -X POST http://127.0.0.1:23333/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{"model": "kokoro-multi-lang-v1_0", "input": "Hello from OpenMeow!", "voice": "af_heart"}' \
  --output speech.mp3
```

### ASR Example

```bash
curl -X POST http://127.0.0.1:23333/v1/audio/transcriptions \
  -F "file=@audio.wav" \
  -F "model=whisper-large-v3-turbo"
```

## Use with OpenClaw

OpenMeow speaks the same API as OpenAI, so [OpenClaw](https://github.com/openclaw/openclaw) can use it as a local voice backend with zero cloud dependency.

**TTS** — add to your OpenClaw config:

```jsonc
"messages": {
  "tts": {
    "auto": "always",
    "provider": "openai",
    "providers": {
      "openai": {
        "apiKey": "dummy-key",
        "baseUrl": "http://127.0.0.1:23333/v1",
        "model": "qwen3-tts-1.7b-mlx",
        "voice": "Vivian"
      }
    },
    "timeoutMs": 60000
  }
}
```

**ASR** — add to `tools.media.audio`:

```jsonc
"tools": {
  "media": {
    "audio": {
      "enabled": true,
      "models": [
        {
          "type": "cli",
          "command": "/bin/sh",
          "args": [
            "-c",
            "curl -s http://127.0.0.1:23333/v1/audio/transcriptions -F file=@{{MediaPath}} -F model=qwen3-asr-0.6b-mlx | jq -r .text"
          ],
          "timeoutSeconds": 60
        }
      ]
    }
  }
}
```

## Models

### TTS — Local

| Model | Size | Languages |
|-------|------|-----------|
| Kokoro Multi-lang v1.0 | 360 MB | Chinese, English |
| Kitten Nano v0.1 | 26 MB | English |
| Kitten Mini v0.1 | 18 MB | English |
| Qwen3-TTS 0.6B (MLX) | 1.7 GB | Multilingual |
| Qwen3-TTS 1.7B (MLX) | 3.2 GB | Multilingual |

### TTS — Cloud

| Model | Provider | Voices | Languages |
|-------|----------|--------|-----------|
| OpenAI TTS (Cloud) | OpenAI / compatible | 6 | 14 languages |
| MiMo TTS v2 (Cloud) | Xiaomi MiMo | 3 | Chinese, English |
| Qwen3 TTS Flash (Cloud) | Alibaba DashScope | 44 | 10 languages (incl. Chinese dialects) |

### ASR

| Model | Size | Languages |
|-------|------|-----------|
| FireRedASR v2 | 200 MB | Chinese + 20 dialects |
| Qwen3-ASR 0.6B (MLX) | 680 MB | 30+ languages |
| Whisper Large v3 Turbo | 600 MB | 92+ languages |
| Whisper Base | 150 MB | 99 languages |

## Building

```bash
# 1. Clone
git clone https://github.com/user/openmeow.git
cd openmeow

# 2. Download frameworks
Scripts/download-sherpa-onnx.sh
Scripts/download-opus.sh
Scripts/download-lame.sh

# 3. Open in Xcode and build
open openmeow/openmeow.xcodeproj
```

> Frameworks (sherpa-onnx, opus, lame) are not included in the repo due to size. Build scripts download and compile them locally.

## License

[MIT](LICENSE)

### Third-Party Components

| Component | License | Link |
|-----------|---------|------|
| [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) | Apache-2.0 | On-device speech (TTS/ASR) |
| [speech-swift](https://github.com/soniqo/speech-swift) | Apache-2.0 | Qwen3-TTS/ASR via MLX |
| [LAME](https://lame.sourceforge.io/) | LGPL-2.0 | MP3 encoder (dynamically linked) |

LAME is the only LGPL component and is dynamically linked as `libmp3lame.dylib`. You may replace it with your own build. See [THIRD-PARTY-LICENSES](THIRD-PARTY-LICENSES) for details.
