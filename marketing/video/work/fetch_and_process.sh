#!/bin/bash
set -euo pipefail
FF=/opt/homebrew/bin/ffmpeg
ROOT=/Users/marcus/Dev/ios/psybeam/marketing/video
ASSETS="$ROOT/assets"
WORK="$ROOT/work"

ssh arch 'cat ~/AI/comfyui/psybeam/report_stories.json' > "$WORK/report_stories.json"

python3 - "$WORK/report_stories.json" <<'PYEOF'
import json, sys, os
reports = json.load(open(sys.argv[1]))
stories = {}
for r in reports:
    stories.setdefault(r["story"], []).append(r)
os.makedirs("/Users/marcus/Dev/ios/psybeam/marketing/video/work/download_list.txt", exist_ok=True) if False else None
with open("/Users/marcus/Dev/ios/psybeam/marketing/video/work/download_list.txt", "w") as out:
    for story, shots in stories.items():
        for s in shots:
            for f in s["files"]:
                out.write(f"{story}\t{f}\t{s['name']}\n")
print(f"{sum(len(v) for v in stories.values())} shots across {len(stories)} stories")
PYEOF

mkdir -p "$ASSETS"/*/shots 2>/dev/null || true
while IFS=$'\t' read -r story remote name; do
  mkdir -p "$ASSETS/$story/shots"
  scp -q "arch:$remote" "$ASSETS/$story/shots/${name}.mp4"
done < "$WORK/download_list.txt"

echo "download complete"
find "$ASSETS" -name '*.mp4' | wc -l
