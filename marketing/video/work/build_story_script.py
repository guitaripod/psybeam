import json, sys, os

TRANSCRIPT_FIXUPS = {
    "네.이 목��디랑 이 약을 추천해요.":
        "네, 이 목캔디랑 이 약을 추천해요.",
}

def fix_transcript(text):
    return TRANSCRIPT_FIXUPS.get(text, text)

def dur_for(text, lo=1.2, hi=3.0, per_char=0.09):
    return max(lo, min(hi, len(text) * per_char))

def build(traveler_source, traveler_out, local_source, local_out):
    events = []
    t = 0.5
    events.append({"at": t, "speaker": "traveler", "event": "hold"})
    d_src1 = round(dur_for(traveler_source), 2)
    events.append({"at": t + 0.1, "speaker": "traveler", "event": "stream_source", "text": traveler_source, "duration": d_src1})
    d_out1 = round(dur_for(traveler_out, per_char=0.14), 2)
    events.append({"at": t + 0.35, "speaker": "traveler", "event": "stream", "text": traveler_out, "duration": d_out1})
    release1 = t + 0.35 + d_out1 + 0.35
    events.append({"at": round(release1, 2), "speaker": "traveler", "event": "release"})
    cutaway1_start = round(release1, 2)
    settle1 = round(release1 + 1.6, 2)

    t2 = settle1 + 1.3
    events.append({"at": t2, "speaker": "local", "event": "hold"})
    d_src2 = round(dur_for(local_source), 2)
    events.append({"at": t2 + 0.1, "speaker": "local", "event": "stream_source", "text": local_source, "duration": d_src2})
    d_out2 = round(dur_for(local_out), 2)
    events.append({"at": t2 + 0.35, "speaker": "local", "event": "stream", "text": local_out, "duration": d_out2})
    release2 = t2 + 0.35 + d_out2 + 0.35
    events.append({"at": round(release2, 2), "speaker": "local", "event": "release"})
    settle2 = round(release2 + 1.6, 2)
    total = settle2 + 1.6

    marks = {
        "hold1": t,
        "cutaway1_start": cutaway1_start,
        "settle1": settle1,
        "hold2": t2,
        "cutaway2_start": round(release2, 2),
        "settle2": settle2,
        "total": round(total, 2),
    }
    return events, marks

if __name__ == "__main__":
    manifest = json.load(open("/Users/marcus/Dev/ios/psybeam/marketing/video/assets/manifest.json"))
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)
    all_marks = {}
    for s in manifest["stories"]:
        sid = s["id"]
        t_dir = next(t for t in s["translations"] if t["direction"] == "traveler -> local")
        l_dir = next(t for t in s["translations"] if t["direction"] == "local -> traveler")
        events, marks = build(
            fix_transcript(t_dir["source_transcript"]), fix_transcript(t_dir["output_transcript"]),
            fix_transcript(l_dir["source_transcript"]), fix_transcript(l_dir["output_transcript"]),
        )
        pair = f"en:{s['local_language']}"
        script_path = os.path.join(out_dir, f"{sid}.json")
        json.dump(events, open(script_path, "w"), indent=2, ensure_ascii=False)
        all_marks[sid] = {"marks": marks, "pair": pair, "script": script_path}
    json.dump(all_marks, open(os.path.join(out_dir, "_marks.json"), "w"), indent=2, ensure_ascii=False)
    print(json.dumps(all_marks, indent=2, ensure_ascii=False))
