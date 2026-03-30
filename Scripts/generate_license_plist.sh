#!/bin/bash
set -euo pipefail

# generate_license_plist.sh — Generate license acknowledgment plist via LicensePlist.
# Runs as an Xcode Build Phase. Warns (but doesn't fail) if LicensePlist is not installed.

# Find license-plist binary
LICENSE_PLIST=""
for path in /opt/homebrew/bin/license-plist /usr/local/bin/license-plist; do
    if [ -x "$path" ]; then
        LICENSE_PLIST="$path"
        break
    fi
done

if [ -z "$LICENSE_PLIST" ]; then
    echo "warning: LicensePlist not installed. Run 'brew install licenseplist' to enable license acknowledgment generation."
    exit 0
fi

# Determine paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -n "${PROJECT_DIR:-}" ]; then
    # Running inside Xcode Build Phase
    XCWORKSPACE="$PROJECT_DIR/openmeow.xcodeproj/project.xcworkspace"
    SPM_SOURCES="$(dirname "$(dirname "$BUILD_DIR")")/SourcePackages"
    OUTPUT_DIR="$BUILT_PRODUCTS_DIR"
else
    # Running manually from command line
    XCWORKSPACE="$SCRIPT_DIR/../openmeow/openmeow.xcodeproj/project.xcworkspace"
    SPM_SOURCES="$(find ~/Library/Developer/Xcode/DerivedData -path "*/openmeow*/SourcePackages" -maxdepth 4 -type d 2>/dev/null | head -1)"
    OUTPUT_DIR="$SCRIPT_DIR/../openmeow/licenses-output"
fi

if [ ! -d "$XCWORKSPACE" ]; then
    echo "warning: Xcode workspace not found at $XCWORKSPACE"
    exit 0
fi

ARGS=(
    --xcworkspace-path "$XCWORKSPACE"
    --output-path "$OUTPUT_DIR/licenses"
    --suppress-opening-directory
    --force
)

if [ -n "${SPM_SOURCES:-}" ] && [ -d "${SPM_SOURCES:-}" ]; then
    ARGS+=(--package-sources-path "$SPM_SOURCES")
fi

echo "Generating license plist with LicensePlist..."
"$LICENSE_PLIST" "${ARGS[@]}" 2>&1 | grep -E '\[(INFO|WARNING)\]' | grep -v 'Not found:.*Pods\|Cartfile\|Mintfile\|nestfile\|Package.swift\|Package.resolved\|license_plist.yml\|latest_result' || true

echo "License plist generated at: $OUTPUT_DIR/licenses"
