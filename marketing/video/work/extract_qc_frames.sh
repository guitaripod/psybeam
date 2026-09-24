#!/bin/bash
set -euo pipefail
FF=/opt/homebrew/bin/ffmpeg
ASSETS=/Users/marcus/Dev/ios/psybeam/marketing/video/assets
for mp4 in "$ASSETS"/*/shots/*.mp4; do
  story=$(basename "$(dirname "$(dirname "$mp4")")")
  name=$(basename "$mp4" .mp4)
  outdir="$ASSETS/$story/qc"
  mkdir -p "$outdir"
  dur=$($FF -i "$mp4" 2>&1 | grep Duration | sed -E 's/.*Duration: ([0-9:.]+).*/\1/')
  "$FF" -y -loglevel error -i "$mp4" -vf "select=eq(n\,20)" -vframes 1 "$outdir/${name}_frame.jpg"
done
echo "QC frames extracted"
