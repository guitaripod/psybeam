"""Builds final/kyoto-shop-ja.mp4: the Japanese shop-staff cut of the Kyoto
story. The shopkeeper is the operator (pair ja:en, blue/traveler = his
Japanese, green/local = the customer's English), so the customer's line is
captioned as a Japanese subtitle for the target audience, the shopkeeper's own
line is captioned as spoken, and the two UI cutaways swap which one is
upright: the customer's line translated to Japanese now reads upright (it
faces the shopkeeper, who holds the phone), and the shopkeeper's reply
translated to English is the one that rotates to face the customer. Reuses
the same LTX shots and the same two real gpt-realtime-translate audio pairs as
kyoto-shop.mp4, against a fresh UI screen recording captured with
PSYBEAM_DEMO_PAIR=ja:en under the Japanese locale."""
import json, os, sys

WORK = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, WORK)
from pipeline import (
    ASSETS, FONT_FOR_LANG, FF, ICON, ROOT, SEG_DIR, W, H, FPS,
    caption_layer, concat_segments, ffprobe_dur, finalize, hook_layer,
    make_scene_segment, make_ui_segment, run, textcard,
)

SID = "kyoto-shop"
OUT_NAME = "kyoto-shop-ja.mp4"

HOOK_TEXT = "英語が話せなくても、\n接客できる。"
CTA_LINES = ["Psybeam", "外国人のお客様との会話に", "5分無料・サブスクなし", "App Storeで入手"]
DISCLOSURE_TEXT = "再現映像・AI生成シーン／翻訳音声はPsybeamの実際の出力"

OFFSET = 2.2
PAD_HEAD = 0.15
PAD_TAIL = 0.30
MIN_UI = 3.0
MAX_UI = 4.4


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def main():
    manifest = json.load(open(f"{ASSETS}/manifest.json"))
    story = next(s for s in manifest["stories"] if s["id"] == SID)
    lang = story["local_language"]
    font = FONT_FOR_LANG[lang]
    audio_windows = json.load(open(f"{WORK}/audio_windows.json"))[SID]
    marks = json.load(open(f"{WORK}/demo-scripts/_marks.json"))["kyoto-shop-ja"]["marks"]

    shots_dir = f"{ASSETS}/{SID}/shots"
    audio_dir = f"{ASSETS}/{SID}/audio"
    raw_ui = f"{WORK}/raw/kyoto-shop-ja.mov"

    t_dir = next(t for t in story["translations"] if t["direction"] == "traveler -> local")
    l_dir = next(t for t in story["translations"] if t["direction"] == "local -> traveler")

    def aw(fname):
        return audio_windows[fname]

    seg_prefix = f"{SEG_DIR}/kyoto-shop-ja"
    os.makedirs(SEG_DIR, exist_ok=True)
    segs = []

    hook_png = textcard(
        {"width": W, "height": H, "layers": [hook_layer(HOOK_TEXT, font)]},
        f"{seg_prefix}_hook.png",
    )
    s1 = make_scene_segment(
        f"{shots_dir}/{SID}_1_establish.mp4", 0.0, 2.0,
        f"{seg_prefix}_s1.mp4", caption_png=hook_png, extra_dim=True,
    )
    segs.append(s1)

    src_w = aw(f"{SID}_2_traveler_source.wav")
    src_active = clamp(src_w["active_dur"] + PAD_HEAD + PAD_TAIL, 3.0, 3.8)
    src_astart = max(0.0, src_w["active_start"] - PAD_HEAD)
    cap2 = textcard(
        {"width": W, "height": H, "layers": [caption_layer(t_dir["output_transcript"], font, 0.42, size=52)]},
        f"{seg_prefix}_s2.png",
    )
    s2 = make_scene_segment(
        f"{shots_dir}/{SID}_2_traveler.mp4", 0.0, src_active,
        f"{seg_prefix}_s2.mp4", caption_png=cap2,
        audio_src=f"{audio_dir}/{SID}_2_traveler_source.wav",
        audio_start=src_astart, audio_dur=min(src_w["total"] - src_astart, src_active),
        audio_pad_before=0.12,
    )
    segs.append(s2)

    tr_w = aw(f"{SID}_2_traveler_translated_{lang}.wav")
    tr_active = clamp(tr_w["active_dur"] + PAD_HEAD + PAD_TAIL, MIN_UI, MAX_UI)
    tr_astart = max(0.0, tr_w["active_start"] - PAD_HEAD)
    tr_adur = min(tr_w["total"] - tr_astart, tr_active)
    settle1_wall = OFFSET + marks["settle1"]
    ui1_end = settle1_wall + 0.35
    ui1_start = ui1_end - tr_active
    s3 = make_ui_segment(
        raw_ui, ui1_start, tr_active, f"{seg_prefix}_s3.mp4",
        audio_src=f"{audio_dir}/{SID}_2_traveler_translated_{lang}.wav",
        audio_start=tr_astart, audio_dur=tr_adur, audio_pad_before=0.15,
    )
    segs.append(s3)

    lsrc_w = aw(f"{SID}_3_local_source.wav")
    lsrc_active = clamp(lsrc_w["active_dur"] + PAD_HEAD + PAD_TAIL, 3.0, 3.8)
    lsrc_astart = max(0.0, lsrc_w["active_start"] - PAD_HEAD)
    cap4 = textcard(
        {"width": W, "height": H, "layers": [caption_layer(l_dir["source_transcript"], font, 0.42, size=52)]},
        f"{seg_prefix}_s4.png",
    )
    s4 = make_scene_segment(
        f"{shots_dir}/{SID}_3_local.mp4", 0.0, lsrc_active,
        f"{seg_prefix}_s4.mp4", caption_png=cap4,
        audio_src=f"{audio_dir}/{SID}_3_local_source.wav",
        audio_start=lsrc_astart, audio_dur=min(lsrc_w["total"] - lsrc_astart, lsrc_active),
        audio_pad_before=0.12,
    )
    segs.append(s4)

    lt_w = aw(f"{SID}_3_local_translated_en.wav")
    lt_active = clamp(lt_w["active_dur"] + PAD_HEAD + PAD_TAIL, MIN_UI, MAX_UI)
    lt_astart = max(0.0, lt_w["active_start"] - PAD_HEAD)
    lt_adur = min(lt_w["total"] - lt_astart, lt_active)
    settle2_wall = OFFSET + marks["settle2"]
    ui2_end = settle2_wall + 0.35
    ui2_start = ui2_end - lt_active
    s5 = make_ui_segment(
        raw_ui, ui2_start, lt_active, f"{seg_prefix}_s5.mp4",
        audio_src=f"{audio_dir}/{SID}_3_local_translated_en.wav",
        audio_start=lt_astart, audio_dur=lt_adur, audio_pad_before=0.15,
    )
    segs.append(s5)

    s6 = make_scene_segment(
        f"{shots_dir}/{SID}_4_payoff.mp4", 0.0, 2.0,
        f"{seg_prefix}_s6.mp4",
    )
    segs.append(s6)

    end_card_png = textcard({
        "width": W, "height": H,
        "layers": [
            {"text": CTA_LINES[0], "font": "system", "size": 84, "weight": "heavy",
             "color": "#FFFFFF", "x": 0.5, "y": 0.565, "align": "center", "maxWidthFrac": 0.9},
            {"text": CTA_LINES[1], "font": font, "size": 40, "weight": "medium",
             "color": "#DCE8FF", "x": 0.5, "y": 0.625, "align": "center", "maxWidthFrac": 0.85},
            {"text": CTA_LINES[2], "font": font, "size": 38, "weight": "semibold",
             "color": "#FFFFFF", "x": 0.5, "y": 0.70, "align": "center", "maxWidthFrac": 0.85},
            {"text": CTA_LINES[3], "font": font, "size": 34, "weight": "bold",
             "color": "#9FD8FF", "x": 0.5, "y": 0.775, "align": "center", "maxWidthFrac": 0.85},
        ],
    }, f"{seg_prefix}_endcard_text.png")

    s7 = f"{seg_prefix}_s7.mp4"
    run([FF, "-y", "-loglevel", "error",
         "-f", "lavfi", "-i", f"gradients=s={W}x{H}:c0=0x0A1830:c1=0x1E63C8:x0=540:y0=0:x1=540:y1=1920:d=2.5:rate={FPS}",
         "-i", ICON, "-i", end_card_png,
         "-f", "lavfi", "-t", "2.5", "-i", "anullsrc=r=48000:cl=stereo",
         "-filter_complex",
         f"[1:v]scale=340:340[icon];[0:v][icon]overlay=(W-w)/2:520[bg2];[bg2][2:v]overlay=0:0[v]",
         "-map", "[v]", "-map", "3:a",
         "-t", "2.5", "-r", str(FPS),
         "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p",
         "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2",
         s7])
    segs.append(s7)

    concat_out = f"{seg_prefix}_concat.mp4"
    concat_segments(segs, concat_out)

    durations = [ffprobe_dur(p) for p in segs]
    end_card_start = sum(durations[:-1])
    total_dur = sum(durations)

    disc_png = textcard({
        "width": W, "height": H,
        "layers": [{
            "text": DISCLOSURE_TEXT, "font": font, "weight": "semibold", "size": 23,
            "color": "#FFFFFFF0", "x": 0.5, "y": 0.955, "align": "center",
            "maxWidthFrac": 0.92, "bgColor": "#000000A0", "bgPadX": 20, "bgPadY": 10, "bgRadius": 10,
        }],
    }, f"{seg_prefix}_disclosure.png")

    final_out = f"{ROOT}/final/{OUT_NAME}"
    os.makedirs(f"{ROOT}/final", exist_ok=True)
    finalize(concat_out, final_out, disc_png, end_card_start)
    print(f"OK {SID}-ja total={total_dur:.2f}s end_card_start={end_card_start:.2f}s -> {final_out}")
    return final_out, total_dur


if __name__ == "__main__":
    main()
