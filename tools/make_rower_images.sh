#!/bin/bash
# Regenerates rower_images/ from the characters listed in index.html.
# For each character: grabs the frame halfway through the drive from rower_videos/<name>.mp4
# (the loop starts at the catch; the drive ends ~38% in, so mid-drive is ~19%) as a 500x500 PNG,
# and removes any images in rower_images/ that are no longer characters.
# Usage: tools/make_rower_images.sh   (macOS; needs swift)
set -euo pipefail
cd "$(dirname "$0")/.."
FRACTION=${FRACTION:-0.19}

names=$(grep -o 'src="rower_videos/[^"]*\.mp4"' index.html | sed 's|.*/||; s|\.mp4"||' | sort -u)
mkdir -p rower_images

for f in rower_images/*.png; do
  [ -e "$f" ] || continue
  n=$(basename "$f" .png)
  echo "$names" | grep -qx "$n" || { echo "removing $f"; rm "$f"; }
done

swiftc -O -o /tmp/extract_frame tools/extract_frame.swift 2>/dev/null
for n in $names; do
  [ -f "rower_videos/$n.mp4" ] || { echo "missing video for $n" >&2; exit 1; }
  /tmp/extract_frame "rower_videos/$n.mp4" "$FRACTION" "rower_images/$n.png"
done
echo "$(echo "$names" | wc -l | tr -d ' ') images written"
