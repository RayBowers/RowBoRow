#!/bin/bash
# Regenerates rower_videos/ from the characters in the RowBoRow app, then updates index.html and rower_images/.
#   1. Renders one 500x500 (black bg, cyan ink) one-stroke loop per `Figure` case, named after the
#      character (tools/render_rower_videos.swift, built with the app's own drawing code).
#   2. Deletes videos for anything that is no longer a character.
#   3. Moves moov to the front of each mp4 if needed (tools/faststart.py, pure Python).
#   4. Rewrites the character section of index.html (tools/update_index.py).
#   5. Regenerates rower_images/ posters (tools/make_rower_images.sh).
# Usage: tools/make_rower_videos.sh   (macOS; needs swift and python3)
# APP_DIR overrides the app source location (default: ../RowBoRow_Apple/RowBoRow).
set -euo pipefail
cd "$(dirname "$0")/.."
APP_DIR=${APP_DIR:-../RowBoRow_Apple/RowBoRow}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Everything that draws a figure; ContentView, purchases and Siri code are not needed.
SRC=$(find "$APP_DIR" -name '*.swift' ! -name 'ContentView.swift' ! -name 'PurchaseManager.swift' \
      ! -name 'StrokeRateIntent.swift' ! -name 'RowBoRowApp.swift')
swiftc -O -parse-as-library -o "$WORK/render" $SRC tools/render_rower_videos.swift
"$WORK/render" "$WORK/videos"

mkdir -p rower_videos
for f in rower_videos/*.mp4; do
  [ -e "$f" ] || continue
  [ -e "$WORK/videos/$(basename "$f")" ] || { echo "removing $f"; rm "$f"; }
done
cp "$WORK"/videos/*.mp4 rower_videos/
python3 tools/faststart.py rower_videos/*.mp4 | grep -v '^already' || true

python3 tools/update_index.py "$WORK/videos/manifest.json"
tools/make_rower_images.sh
