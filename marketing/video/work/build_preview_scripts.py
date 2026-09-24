"""Builds the two App Preview demo scripts from tokyo-ramen's real transcripts:
en-US plays traveler-speaks-English/local-speaks-Japanese as recorded, ja plays
the reversed perspective (traveler speaks Japanese, local speaks English) by
swapping which side of the same real transcript pair is passed as "traveler"
vs "local" to `build`."""
import json, os, sys

WORK = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, WORK)
from build_story_script import build

manifest = json.load(open("/Users/marcus/Dev/ios/psybeam/marketing/video/assets/manifest.json"))
tokyo = next(s for s in manifest["stories"] if s["id"] == "tokyo-ramen")
t_dir = next(t for t in tokyo["translations"] if t["direction"] == "traveler -> local")
l_dir = next(t for t in tokyo["translations"] if t["direction"] == "local -> traveler")

events_en, marks_en = build(
    t_dir["source_transcript"], t_dir["output_transcript"],
    l_dir["source_transcript"], l_dir["output_transcript"],
)

events_ja, marks_ja = build(
    l_dir["source_transcript"], l_dir["output_transcript"],
    t_dir["source_transcript"], t_dir["output_transcript"],
)

out_dir = f"{WORK}/demo-scripts"
json.dump(events_en, open(f"{out_dir}/preview-en.json", "w"), indent=2, ensure_ascii=False)
json.dump(events_ja, open(f"{out_dir}/preview-ja.json", "w"), indent=2, ensure_ascii=False)
json.dump({"en": marks_en, "ja": marks_ja}, open(f"{out_dir}/_preview_marks.json", "w"), indent=2)
print("en marks", json.dumps(marks_en))
print("ja marks", json.dumps(marks_ja))
