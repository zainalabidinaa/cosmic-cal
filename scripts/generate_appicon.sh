#!/usr/bin/env bash
set -euo pipefail

INPUT_ICNS=${1:?"Usage: generate_appicon.sh <input.icns> <output_assets_dir>"}
OUTPUT_ASSETS_DIR=${2:?"Usage: generate_appicon.sh <input.icns> <output_assets_dir>"}

WORK_DIR=$(mktemp -d)
ICONSET_DIR="$WORK_DIR/icon.iconset"

mkdir -p "$WORK_DIR"
iconutil --convert iconset "$INPUT_ICNS" --output "$ICONSET_DIR"

BASE_PNG="$ICONSET_DIR/icon_512x512@2x.png"
if [[ ! -f "$BASE_PNG" ]]; then
  BASE_PNG=$(ls -1 "$ICONSET_DIR"/*.png | sort | tail -n 1)
fi

APPICONSET_DIR="$OUTPUT_ASSETS_DIR/AppIcon.appiconset"
rm -rf "$OUTPUT_ASSETS_DIR"
mkdir -p "$APPICONSET_DIR"

# Root Contents.json
cat > "$OUTPUT_ASSETS_DIR/Contents.json" <<'EOF'
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

# Helper to generate resized png
resize() {
  local size=$1
  local out=$2
  /usr/bin/sips -z "$size" "$size" "$BASE_PNG" --out "$out" >/dev/null
}

# Marketing icon (1024)
resize 1024 "$APPICONSET_DIR/icon-1024.png"

# iPhone
resize 60  "$APPICONSET_DIR/icon-20@3x.png"   # 20pt @3x
resize 40  "$APPICONSET_DIR/icon-20@2x.png"   # 20pt @2x
resize 87  "$APPICONSET_DIR/icon-29@3x.png"   # 29pt @3x
resize 58  "$APPICONSET_DIR/icon-29@2x.png"   # 29pt @2x
resize 120 "$APPICONSET_DIR/icon-40@3x.png"   # 40pt @3x
resize 80  "$APPICONSET_DIR/icon-40@2x.png"   # 40pt @2x
resize 180 "$APPICONSET_DIR/icon-60@3x.png"   # 60pt @3x
resize 120 "$APPICONSET_DIR/icon-60@2x.png"   # 60pt @2x

# iPad
resize 20  "$APPICONSET_DIR/icon-ipad-20@1x.png"
resize 40  "$APPICONSET_DIR/icon-ipad-20@2x.png"
resize 29  "$APPICONSET_DIR/icon-ipad-29@1x.png"
resize 58  "$APPICONSET_DIR/icon-ipad-29@2x.png"
resize 40  "$APPICONSET_DIR/icon-ipad-40@1x.png"
resize 80  "$APPICONSET_DIR/icon-ipad-40@2x.png"
resize 76  "$APPICONSET_DIR/icon-ipad-76@1x.png"
resize 152 "$APPICONSET_DIR/icon-ipad-76@2x.png"
resize 167 "$APPICONSET_DIR/icon-ipad-83.5@2x.png"

python3 "$(dirname "$0")/generate_appicon_contents.py" "$APPICONSET_DIR"

rm -rf "$WORK_DIR"
