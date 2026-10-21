#!/usr/bin/env bash
# Usage: tool/frame_phone_screenshot.sh <input.png> <output.png>
set -euo pipefail
if [ "$#" -ne 2 ]; then
  echo "Usage: tool/frame_phone_screenshot.sh <input.png> <output.png>" >&2
  exit 1
fi
SRC="$1"
OUT="$2"
W=$(magick identify -format '%w' "$SRC")
H=$(magick identify -format '%h' "$SRC")
P=$(awk -v w="$W" 'BEGIN { printf "%d", (7 * w / 146) + 0.5 }')
IR=$(awk -v w="$W" 'BEGIN { printf "%d", (23 * w / 146) + 0.5 }')
OR=$(awk -v w="$W" 'BEGIN { printf "%d", (30 * w / 146) + 0.5 }')
SW=$(awk -v w="$W" 'BEGIN { s = (4 * w / 600) + 0.5; if (s < 1) s = 1; printf "%d", s }')
FW=$((W + 2 * P))
FH=$((H + 2 * P))
I=$((SW / 2))
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
magick "$SRC" \( -size "${W}x${H}" xc:black -fill white -draw "roundrectangle 0,0,$((W - 1)),$((H - 1)),$IR,$IR" \) -alpha off -compose CopyOpacity -composite "$TMP/inner.png"
magick -size "${FW}x${FH}" xc:none \( -size "${FW}x${FH}" gradient:'#23263f'-'#0c0e1c' -distort SRT 20 \) -compose over -composite \( -size "${FW}x${FH}" xc:black -fill white -draw "roundrectangle 0,0,$((FW - 1)),$((FH - 1)),$OR,$OR" \) -alpha off -compose CopyOpacity -composite -fill none -stroke '#2b2f4d' -strokewidth "$SW" -draw "roundrectangle $I,$I,$((FW - 1 - I)),$((FH - 1 - I)),$OR,$OR" "$TMP/bezel.png"
magick "$TMP/bezel.png" "$TMP/inner.png" -gravity center -compose over -composite -depth 8 "$OUT"
