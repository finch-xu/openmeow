#!/bin/bash
set -euo pipefail

# Download pre-built sherpa-onnx xcframework for macOS (arm64)
SHERPA_VERSION="v1.12.39"
FRAMEWORK_DIR="$(cd "$(dirname "$0")/.." && pwd)/Frameworks"
mkdir -p "$FRAMEWORK_DIR"

if [ -d "$FRAMEWORK_DIR/sherpa-onnx.xcframework" ]; then
    echo "sherpa-onnx.xcframework already exists at $FRAMEWORK_DIR"
    exit 0
fi

BASE_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/${SHERPA_VERSION}"
XCFW_TAR="sherpa-onnx-${SHERPA_VERSION}-macos-xcframework-static.tar.bz2"
STATIC_TAR="sherpa-onnx-${SHERPA_VERSION}-osx-arm64-static-lib.tar.bz2"

BUILD_DIR=$(mktemp -d)
cd "$BUILD_DIR"

echo "Downloading pre-built sherpa-onnx ${SHERPA_VERSION}..."
curl -sL "${BASE_URL}/${XCFW_TAR}" | tar -xjf -
curl -sL "${BASE_URL}/${STATIC_TAR}" | tar -xjf -

# Copy xcframework to project
XCFW_SRC="sherpa-onnx-${SHERPA_VERSION}-macos-xcframework-static/sherpa-onnx.xcframework"
STATIC_SRC="sherpa-onnx-${SHERPA_VERSION}-osx-arm64-static-lib/lib/libonnxruntime.a"

cp -R "$XCFW_SRC" "$FRAMEWORK_DIR/"
cp "$STATIC_SRC" "$FRAMEWORK_DIR/sherpa-onnx.xcframework/macos-arm64_x86_64/"

echo "Done: $FRAMEWORK_DIR/sherpa-onnx.xcframework"

# Cleanup
rm -rf "$BUILD_DIR"
