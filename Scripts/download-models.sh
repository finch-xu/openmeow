#!/bin/bash
set -euo pipefail

# Download default models for OpenMeow
# Models are stored in ~/Library/Application Support/OpenMeow/models/

MODELS_DIR="$HOME/Library/Application Support/OpenMeow/models"
mkdir -p "$MODELS_DIR"

# Kokoro Multi-lang TTS (int8, ~200MB, 103 speakers, zh+en)
KOKORO_DIR="$MODELS_DIR/kokoro-int8-multi-lang-v1_1"
if [ ! -d "$KOKORO_DIR" ]; then
    echo "Downloading Kokoro multi-lang v1.1 (int8)..."
    curl -SL -o "$MODELS_DIR/kokoro-int8-multi-lang-v1_1.tar.bz2" \
        "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-int8-multi-lang-v1_1.tar.bz2"
    cd "$MODELS_DIR"
    tar xjf kokoro-int8-multi-lang-v1_1.tar.bz2
    rm -f kokoro-int8-multi-lang-v1_1.tar.bz2
    echo "Done: $KOKORO_DIR"
else
    echo "Kokoro model already exists, skipping."
fi

# SenseVoice ASR (int8, zh/en/ja/ko/yue)
SENSEVOICE_DIR="$MODELS_DIR/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09"
if [ ! -d "$SENSEVOICE_DIR" ]; then
    echo "Downloading SenseVoice ASR (int8)..."
    curl -SL -o "$MODELS_DIR/sensevoice.tar.bz2" \
        "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09.tar.bz2"
    cd "$MODELS_DIR"
    tar xjf sensevoice.tar.bz2
    rm -f sensevoice.tar.bz2
    echo "Done: $SENSEVOICE_DIR"
else
    echo "SenseVoice model already exists, skipping."
fi

echo ""
echo "All models downloaded to: $MODELS_DIR"
ls -la "$MODELS_DIR"
