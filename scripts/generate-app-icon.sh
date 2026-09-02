#!/bin/bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ASSET_DIR="$PROJECT_DIR/Assets"
SOURCE_SVG="$ASSET_DIR/AppIcon.svg"
OUTPUT_ICNS="$ASSET_DIR/AppIcon.icns"
TEMP_DIR="$(mktemp -d)"
ICONSET_DIR="$TEMP_DIR/AppIcon.iconset"

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

mkdir -p "$ICONSET_DIR"
qlmanage -t -s 1024 -o "$TEMP_DIR" "$SOURCE_SVG" >/dev/null 2>&1
SOURCE_PNG="$TEMP_DIR/AppIcon.svg.png"

make_icon() {
    local size="$1"
    local name="$2"
    sips -z "$size" "$size" "$SOURCE_PNG" --out "$ICONSET_DIR/$name" >/dev/null
}

make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
make_icon 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"
echo "$OUTPUT_ICNS"
