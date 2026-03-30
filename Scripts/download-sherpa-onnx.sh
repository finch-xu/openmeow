#!/bin/bash
set -euo pipefail

# Build or download sherpa-onnx xcframework for macOS
FRAMEWORK_DIR="$(cd "$(dirname "$0")/.." && pwd)/Frameworks"
mkdir -p "$FRAMEWORK_DIR"

if [ -d "$FRAMEWORK_DIR/sherpa-onnx.xcframework" ]; then
    echo "sherpa-onnx.xcframework already exists at $FRAMEWORK_DIR"
    exit 0
fi

echo "Building sherpa-onnx from source..."
BUILD_DIR=$(mktemp -d)
cd "$BUILD_DIR"

git clone --depth 1 https://github.com/k2-fsa/sherpa-onnx.git
cd sherpa-onnx

bash build-swift-macos.sh

# Copy xcframework to project
if [ -d "build-swift-macos/sherpa-onnx.xcframework" ]; then
    cp -R build-swift-macos/sherpa-onnx.xcframework "$FRAMEWORK_DIR/"
    echo "Done: $FRAMEWORK_DIR/sherpa-onnx.xcframework"
else
    echo "ERROR: xcframework not found after build"
    exit 1
fi

# Cleanup
rm -rf "$BUILD_DIR"
