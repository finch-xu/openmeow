<p align="center">
  <img src="assets/icon_readme.png" width="128" height="128" alt="OpenMeow">
</p>

<h1 align="center">OpenMeow</h1>

<p align="center">
  A native macOS menu bar app that serves as a local, OpenAI-compatible voice API gateway.
</p>

<p align="center">
  <a href="#features">Features</a> &bull;
  <a href="#installation">Installation</a> &bull;
  <a href="#api">API</a> &bull;
  <a href="#models">Models</a> &bull;
  <a href="#building">Building</a> &bull;
  <a href="README_CN.md">中文</a>
</p>

---

## Features

- **Menu bar app** — runs quietly in the background on macOS (Apple Silicon)
- **OpenAI-compatible API** — drop-in replacement for `/v1/audio/speech` and `/v1/audio/transcriptions`
- **Multiple engines** — sherpa-onnx, WhisperKit, speech-swift (Qwen3-TTS/ASR)
- **Audio format support** — WAV, MP3, Opus (OGG/WebM), PCM, FLAC, AAC
- **Model store** — download and manage models from the built-in registry
- **Privacy first** — everything runs locally, no data leaves your machine

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

## Models

### TTS

| Model | Size | Languages |
|-------|------|-----------|
| Kokoro Multi-lang v1.0 | 360 MB | Chinese, English |
| Kitten Nano v0.1 | 26 MB | English |
| Kitten Mini v0.1 | 18 MB | English |
| Qwen3-TTS 0.6B (MLX) | 1.7 GB | Multilingual |
| Qwen3-TTS 1.7B (MLX) | 3.2 GB | Multilingual |

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

LAME MP3 encoder is dynamically linked under [LGPL-2.0](THIRD-PARTY-LICENSES). You may replace `libmp3lame.dylib` with your own build.
