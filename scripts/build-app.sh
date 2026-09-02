#!/bin/bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-debug}"

swift build --package-path "$PROJECT_DIR" -c "$CONFIGURATION"
BIN_DIR="$(swift build --package-path "$PROJECT_DIR" -c "$CONFIGURATION" --show-bin-path)"
APP_DIR="$PROJECT_DIR/build/EdgePulse.app"
CONTENTS_DIR="$APP_DIR/Contents"
SIGNING_IDENTITY="${EDGEPULSE_SIGNING_IDENTITY:--}"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$PROJECT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$BIN_DIR/EdgePulse" "$CONTENTS_DIR/MacOS/EdgePulse"
chmod +x "$CONTENTS_DIR/MacOS/EdgePulse"

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    codesign \
        --force \
        --sign - \
        --identifier com.cf3i.edgepulse \
        --requirements "$PROJECT_DIR/Config/EdgePulse.requirements" \
        "$APP_DIR"
else
    codesign \
        --force \
        --sign "$SIGNING_IDENTITY" \
        --identifier com.cf3i.edgepulse \
        "$APP_DIR"
fi

echo "$APP_DIR"
