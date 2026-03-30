#!/bin/bash
set -euo pipefail

# Build libmp3lame dynamic library for macOS (arm64 only)
# LAME is licensed under LGPL-2.0 — distributed as a dynamic library
# to preserve the MIT license of the host application.

FRAMEWORK_DIR="$(cd "$(dirname "$0")/.." && pwd)/Frameworks"
XCFW_DIR="$FRAMEWORK_DIR/lame.xcframework"
mkdir -p "$FRAMEWORK_DIR"

if [ -d "$XCFW_DIR" ]; then
    echo "lame.xcframework already exists at $FRAMEWORK_DIR"
    exit 0
fi

echo "Building libmp3lame from source (arm64)..."
BUILD_DIR=$(mktemp -d)
INSTALL_DIR="$BUILD_DIR/install"
mkdir -p "$INSTALL_DIR"

cleanup() { rm -rf "$BUILD_DIR"; }
trap cleanup EXIT

# Download LAME 3.100 source
LAME_VERSION="3.100"
LAME_TARBALL="$BUILD_DIR/lame-${LAME_VERSION}.tar.gz"

echo "==> Downloading LAME ${LAME_VERSION}..."
curl -L -o "$LAME_TARBALL" \
    "https://downloads.sourceforge.net/project/lame/lame/${LAME_VERSION}/lame-${LAME_VERSION}.tar.gz"

echo "==> Extracting..."
tar xzf "$LAME_TARBALL" -C "$BUILD_DIR"
LAME_SRC="$BUILD_DIR/lame-${LAME_VERSION}"

# Build for arm64 (Apple Silicon)
echo "==> Building libmp3lame (arm64)..."
cd "$LAME_SRC"

# Remove deprecated symbol that exists in export list but not in source
sed -i.bak '/lame_init_old/d' include/libmp3lame.sym

./configure \
    --host=aarch64-apple-darwin \
    --prefix="$INSTALL_DIR" \
    --disable-static \
    --enable-shared \
    --disable-frontend \
    --disable-gtktest \
    CFLAGS="-arch arm64 -mmacosx-version-min=14.0 -O2" \
    LDFLAGS="-arch arm64 -mmacosx-version-min=14.0"

make -j"$(sysctl -n hw.ncpu)"
make install

# Fix install name for @rpath loading
DYLIB_PATH="$INSTALL_DIR/lib/libmp3lame.dylib"
# Resolve symlinks (libmp3lame.dylib -> libmp3lame.0.dylib)
REAL_DYLIB=$(readlink -f "$DYLIB_PATH" 2>/dev/null || python3 -c "import os; print(os.path.realpath('$DYLIB_PATH'))")

install_name_tool -id @rpath/libmp3lame.dylib "$REAL_DYLIB"

# Assemble xcframework
echo "==> Assembling xcframework..."
SLICE_DIR="$XCFW_DIR/macos-arm64"
HEADER_DIR="$SLICE_DIR/Headers"
mkdir -p "$HEADER_DIR/lame"

# Copy dylib (dereference symlinks)
cp -L "$DYLIB_PATH" "$SLICE_DIR/libmp3lame.dylib"

# Copy public header
cp "$INSTALL_DIR/include/lame/lame.h" "$HEADER_DIR/lame/"

# Copy LGPL license
cp "$LAME_SRC/COPYING" "$XCFW_DIR/LICENSE-lame"

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
            <string>macos-arm64</string>
            <key>LibraryPath</key>
            <string>libmp3lame.dylib</string>
            <key>SupportedArchitectures</key>
            <array>
                <string>arm64</string>
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
echo "  libmp3lame.dylib: $(du -h "$SLICE_DIR/libmp3lame.dylib" | cut -f1)"
echo "  Install name: $(otool -D "$SLICE_DIR/libmp3lame.dylib" | tail -1)"
