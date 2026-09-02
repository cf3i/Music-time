#!/bin/bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-debug}"

swift build --package-path "$PROJECT_DIR" -c "$CONFIGURATION"
BIN_DIR="$(swift build --package-path "$PROJECT_DIR" -c "$CONFIGURATION" --show-bin-path)"
APP_DIR="$PROJECT_DIR/build/EdgePulse.app"
CONTENTS_DIR="$APP_DIR/Contents"
LOCAL_SIGNING_DIR="$PROJECT_DIR/.local-signing"
LOCAL_KEYCHAIN="$LOCAL_SIGNING_DIR/EdgePulseLocal.keychain-db"
LOCAL_PASSWORD_FILE="$LOCAL_SIGNING_DIR/keychain-password"
SIGNING_IDENTITY="${EDGEPULSE_SIGNING_IDENTITY:-}"
SIGNING_KEYCHAIN="${EDGEPULSE_SIGNING_KEYCHAIN:-}"

if [[ -z "$SIGNING_IDENTITY" ]]; then
    if [[ ! -f "$LOCAL_KEYCHAIN" || ! -f "$LOCAL_PASSWORD_FILE" ]]; then
        echo "A stable signing identity is required for persistent audio permission." >&2
        echo "Run ./scripts/setup-local-signing.sh once, then build again." >&2
        exit 1
    fi

    SIGNING_IDENTITY="EdgePulse Local Development"
    SIGNING_KEYCHAIN="$LOCAL_KEYCHAIN"
    security unlock-keychain -p "$(<"$LOCAL_PASSWORD_FILE")" "$LOCAL_KEYCHAIN"
    if ! security find-identity -v -p codesigning "$LOCAL_KEYCHAIN" \
        | grep -Fq "\"$SIGNING_IDENTITY\""; then
        echo "The local signing identity is not trusted for code signing yet." >&2
        echo "Run ./scripts/setup-local-signing.sh and approve its one-time system confirmation." >&2
        exit 1
    fi
fi

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$PROJECT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$BIN_DIR/EdgePulse" "$CONTENTS_DIR/MacOS/EdgePulse"
if [[ -f "$PROJECT_DIR/Assets/AppIcon.icns" ]]; then
    cp "$PROJECT_DIR/Assets/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
fi
chmod +x "$CONTENTS_DIR/MacOS/EdgePulse"

if [[ -n "$SIGNING_KEYCHAIN" ]]; then
    codesign \
        --force \
        --sign "$SIGNING_IDENTITY" \
        --keychain "$SIGNING_KEYCHAIN" \
        --identifier com.cf3i.edgepulse \
        "$APP_DIR"
else
    codesign \
        --force \
        --sign "$SIGNING_IDENTITY" \
        --identifier com.cf3i.edgepulse \
        "$APP_DIR"
fi

echo "$APP_DIR"
