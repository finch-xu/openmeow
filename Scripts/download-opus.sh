#!/bin/bash
set -euo pipefail

# Build libopus + libogg xcframework for macOS (arm64 + x86_64)
# Both libraries are BSD-3-Clause licensed.

FRAMEWORK_DIR="$(cd "$(dirname "$0")/.." && pwd)/Frameworks"
XCFW_DIR="$FRAMEWORK_DIR/opus.xcframework"
mkdir -p "$FRAMEWORK_DIR"

if [ -d "$XCFW_DIR" ]; then
    echo "opus.xcframework already exists at $FRAMEWORK_DIR"
    exit 0
fi

echo "Building libopus + libogg from source..."
BUILD_DIR=$(mktemp -d)
INSTALL_DIR="$BUILD_DIR/install"
mkdir -p "$INSTALL_DIR"

cleanup() { rm -rf "$BUILD_DIR"; }
trap cleanup EXIT

CMAKE_COMMON=(
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"
    -DCMAKE_OSX_DEPLOYMENT_TARGET="14.0"
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR"
    -DBUILD_SHARED_LIBS=OFF
    -DBUILD_TESTING=OFF
    -DCMAKE_BUILD_TYPE=Release
)

# --- Build libogg ---
echo "==> Cloning libogg..."
git clone --depth 1 https://github.com/xiph/ogg.git "$BUILD_DIR/ogg"

echo "==> Building libogg..."
cmake -S "$BUILD_DIR/ogg" -B "$BUILD_DIR/ogg-build" \
    "${CMAKE_COMMON[@]}" \
    -DINSTALL_DOCS=OFF
cmake --build "$BUILD_DIR/ogg-build" --config Release -j "$(sysctl -n hw.ncpu)"
cmake --install "$BUILD_DIR/ogg-build"

# --- Build libopus ---
echo "==> Cloning libopus..."
git clone --depth 1 https://github.com/xiph/opus.git "$BUILD_DIR/opus"

echo "==> Building libopus..."
cmake -S "$BUILD_DIR/opus" -B "$BUILD_DIR/opus-build" \
    "${CMAKE_COMMON[@]}" \
    -DOPUS_BUILD_SHARED_LIBRARY=OFF \
    -DOPUS_BUILD_TESTING=OFF \
    -DOPUS_BUILD_PROGRAMS=OFF \
    -DCMAKE_PREFIX_PATH="$INSTALL_DIR"
cmake --build "$BUILD_DIR/opus-build" --config Release -j "$(sysctl -n hw.ncpu)"
cmake --install "$BUILD_DIR/opus-build"

# --- Assemble xcframework ---
echo "==> Assembling xcframework..."
SLICE_DIR="$XCFW_DIR/macos-arm64_x86_64"
HEADER_DIR="$SLICE_DIR/Headers"
mkdir -p "$HEADER_DIR"

# Copy static libraries
cp "$INSTALL_DIR/lib/libopus.a" "$SLICE_DIR/"
cp "$INSTALL_DIR/lib/libogg.a" "$SLICE_DIR/"

# Copy headers preserving directory structure
cp -R "$INSTALL_DIR/include/opus" "$HEADER_DIR/"
cp -R "$INSTALL_DIR/include/ogg" "$HEADER_DIR/"

# Copy licenses
cp "$BUILD_DIR/opus/COPYING" "$XCFW_DIR/LICENSE-opus"
cp "$BUILD_DIR/ogg/COPYING" "$XCFW_DIR/LICENSE-ogg"

# Create Info.plist
cat > "$XCFW_DIR/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>AvailableLibraries</key>
    <array>
        <dict>
            <key>HeadersPath</key>
            <string>Headers</string>
            <key>LibraryIdentifier</key>
            <string>macos-arm64_x86_64</string>
            <key>LibraryPath</key>
            <string>libopus.a</string>
            <key>SupportedArchitectures</key>
            <array>
                <string>arm64</string>
                <string>x86_64</string>
            </array>
            <key>SupportedPlatform</key>
            <string>macos</string>
        </dict>
    </array>
    <key>CFBundlePackageType</key>
    <string>XFWK</string>
    <key>XCFrameworkFormatVersion</key>
    <string>1.0</string>
</dict>
</plist>
PLIST

echo "Done: $XCFW_DIR"
echo "  libopus.a: $(du -h "$SLICE_DIR/libopus.a" | cut -f1)"
echo "  libogg.a:  $(du -h "$SLICE_DIR/libogg.a" | cut -f1)"
