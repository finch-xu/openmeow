#!/bin/bash
set -euo pipefail

# check_licenses.sh — Validate SPM dependency licenses against an allowlist.
# Runs as an Xcode Build Phase. Exits 1 if a non-permissive license is found.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALLOWLIST="$SCRIPT_DIR/license_allowlist.txt"

# Locate Package.resolved
if [ -n "${PROJECT_DIR:-}" ]; then
    PACKAGE_RESOLVED="$PROJECT_DIR/openmeow.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
else
    PACKAGE_RESOLVED="$SCRIPT_DIR/../openmeow/openmeow.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
fi

# Locate SPM checkouts — Xcode build vs local run
if [ -n "${BUILD_DIR:-}" ]; then
    CHECKOUTS_DIR="$(dirname "$BUILD_DIR")/SourcePackages/checkouts"
else
    # Fallback: search DerivedData
    CHECKOUTS_DIR="$(find ~/Library/Developer/Xcode/DerivedData -path "*/openmeow*/SourcePackages/checkouts" -maxdepth 4 2>/dev/null | head -1)"
fi

if [ ! -f "$PACKAGE_RESOLVED" ]; then
    echo "error: Package.resolved not found at $PACKAGE_RESOLVED"
    exit 1
fi

if [ ! -f "$ALLOWLIST" ]; then
    echo "error: Allowlist not found at $ALLOWLIST"
    exit 1
fi

# Parse allowlist (skip comments and blank lines)
ALLOWED_TYPES=()
EXEMPT_PACKAGES=()
while IFS= read -r line; do
    line="$(echo "$line" | sed 's/#.*//' | xargs)"
    [ -z "$line" ] && continue
    if [[ "$line" == package:* ]]; then
        EXEMPT_PACKAGES+=("${line#package:}")
    else
        ALLOWED_TYPES+=("$line")
    fi
done < "$ALLOWLIST"

# Detect license type from file content
detect_license() {
    local file="$1"
    local content
    content="$(cat "$file")"

    if echo "$content" | grep -qi "MIT License\|Permission is hereby granted, free of charge"; then
        echo "MIT"; return
    fi
    if echo "$content" | grep -qi "Apache License.*Version 2"; then
        echo "Apache-2.0"; return
    fi
    if echo "$content" | grep -qi "Redistribution and use in source and binary forms"; then
        if echo "$content" | grep -qi "3\. Neither the name\|Neither the name of"; then
            echo "BSD-3-Clause"; return
        fi
        echo "BSD-2-Clause"; return
    fi
    if echo "$content" | grep -qi "ISC License\|Permission to use, copy, modify, and/or distribute"; then
        echo "ISC"; return
    fi
    if echo "$content" | grep -qi "zlib License\|zlib/libpng"; then
        echo "Zlib"; return
    fi
    if echo "$content" | grep -qi "Boost Software License"; then
        echo "BSL-1.0"; return
    fi
    if echo "$content" | grep -qi "Unicode License\|UNICODE.*LICENSE"; then
        echo "Unicode-3.0"; return
    fi
    if echo "$content" | grep -qi "GNU Lesser General Public License\|LGPL"; then
        echo "LGPL"; return
    fi
    if echo "$content" | grep -qi "GNU General Public License\|GPL"; then
        echo "GPL"; return
    fi
    echo "UNKNOWN"
}

# Find LICENSE file for a package
find_license_file() {
    local pkg_dir="$1"
    for name in LICENSE LICENSE.md LICENSE.txt LICENCE LICENCE.md LICENCE.txt COPYING; do
        if [ -f "$pkg_dir/$name" ]; then
            echo "$pkg_dir/$name"
            return
        fi
    done
    echo ""
}

is_allowed() {
    local license_type="$1"
    [ ${#ALLOWED_TYPES[@]} -eq 0 ] && return 1
    for allowed in "${ALLOWED_TYPES[@]}"; do
        if [ "$license_type" = "$allowed" ]; then
            return 0
        fi
    done
    return 1
}

is_exempt() {
    local identity="$1"
    [ ${#EXEMPT_PACKAGES[@]} -eq 0 ] && return 1
    for exempt in "${EXEMPT_PACKAGES[@]}"; do
        if [ "$identity" = "$exempt" ]; then
            return 0
        fi
    done
    return 1
}

# Extract package identities from Package.resolved (JSON v3 format)
IDENTITIES=()
while IFS= read -r id; do
    IDENTITIES+=("$id")
done < <(python3 -c "
import json, sys
with open('$PACKAGE_RESOLVED') as f:
    data = json.load(f)
for pin in data.get('pins', []):
    print(pin['identity'])
")

echo "=== OpenMeow License Check ==="
echo "Checking ${#IDENTITIES[@]} SPM dependencies..."
echo ""

FAILED=0
PASS_COUNT=0
SKIP_COUNT=0

for identity in "${IDENTITIES[@]}"; do
    if is_exempt "$identity"; then
        echo "  ⏭  $identity: EXEMPT"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        continue
    fi

    pkg_dir="$CHECKOUTS_DIR/$identity"
    if [ ! -d "$pkg_dir" ]; then
        echo "  ⚠️  $identity: checkout not found (skipped)"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        continue
    fi

    license_file="$(find_license_file "$pkg_dir")"
    if [ -z "$license_file" ]; then
        echo "  ❌ $identity: NO LICENSE FILE FOUND"
        FAILED=$((FAILED + 1))
        continue
    fi

    license_type="$(detect_license "$license_file")"

    if is_allowed "$license_type"; then
        echo "  ✅ $identity: $license_type"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  ❌ $identity: $license_type (NOT in allowlist)"
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "Results: $PASS_COUNT passed, $FAILED failed, $SKIP_COUNT skipped"

if [ "$FAILED" -gt 0 ]; then
    echo ""
    echo "error: $FAILED dependencies have non-compliant or unrecognized licenses."
    echo "Review the packages above and either:"
    echo "  1. Add the license type to Scripts/license_allowlist.txt"
    echo "  2. Add 'package:<identity>' to exempt a specific package"
    echo "  3. Remove the dependency"
    exit 1
fi

echo "All licenses OK."
