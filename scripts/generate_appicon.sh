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

# Create a cropped base image so the icon fills.
# (Many source icons include transparent padding; iOS 26 looks best when the
# artwork fills the squircle mask.)
CROPPED_BASE_PNG="$WORK_DIR/base_cropped.png"
python3 - "$BASE_PNG" "$CROPPED_BASE_PNG" <<'PY'
import subprocess
import re
import sys
from pathlib import Path

base = Path(sys.argv[1])
out = Path(sys.argv[2])

info = subprocess.check_output(["/usr/bin/sips", "-g", "pixelWidth", "-g", "pixelHeight", str(base)], text=True)
width = int(re.search(r"pixelWidth:\s*(\d+)", info).group(1))
height = int(re.search(r"pixelHeight:\s*(\d+)", info).group(1))
size = min(width, height)

# Crop to 80% to remove transparent margins.
crop = max(1, int(size * 0.80))
subprocess.check_call(["/usr/bin/sips", "-c", str(crop), str(crop), str(base), "--out", str(out)], stdout=subprocess.DEVNULL)
PY

# Helper to generate resized png
resize() {
  local size=$1
  local out=$2
  /usr/bin/sips -z "$size" "$size" "$CROPPED_BASE_PNG" --out "$out" >/dev/null
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

python3 "$(dirname "$0")/generate_appicon_contents.py" "$APPICONSET_DIR"

rm -rf "$WORK_DIR"
