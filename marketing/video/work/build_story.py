import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pipeline import *

MANIFEST = json.load(open(f"{ASSETS}/manifest.json"))
AUDIO_WINDOWS = json.load(open(f"{WORK}/audio_windows.json"))
MARKS = json.load(open(f"{WORK}/demo-scripts/_marks.json"))

HOOK_TEXT = {
    "tokyo-ramen": ("I don't speak a word of Japanese.", "en"),
    "cdmx-tacos": ("I don't speak a word of Spanish.", "en"),
    "paris-bakery": ("I don't speak a word of French.", "en"),
    "rome-trattoria": ("I don't speak a word of Italian.", "en"),
    "bangkok-market": ("I don't speak a word of Thai.", "en"),
    "seoul-pharmacy": ("I don't speak a word of Korean.", "en"),
    "kyoto-shop": ("I don't speak a word of Japanese.", "en"),
}

HOOK_TEXT_B = {
    "tokyo-ramen": ("Order ramen in Tokyo. Speak zero Japanese.", "en"),
    "cdmx-tacos": ("Order tacos in Mexico City. Speak zero Spanish.", "en"),
}

CTA_LINES = ["Psybeam", "Voice translator for travel",
             "5 free minutes · No subscription", "Download on the App Store"]

OFFSET = 2.2
PAD_HEAD = 0.15
PAD_TAIL = 0.30
MIN_DIALOGUE = 3.0
MAX_DIALOGUE = 3.8
MIN_UI = 3.0
MAX_UI = 4.4

TRANSCRIPT_FIXUPS = {
    "네.이 목��디랑 이 약을 추천해요.":
        "네, 이 목캔디랑 이 약을 추천해요.",
}

def fix_transcript(text):
    """Repairs the two literal U+FFFD replacement characters in the manifest's
    Korean STT transcript (upstream encoding corruption in the mako transcript,
    not a Psybeam bug): "목캔디" (mok-kaen-di) is Korea's well-known
    throat-lozenge brand name, confirmed by the paired real English translation
    "this throat candy and this medicine"."""
    return TRANSCRIPT_FIXUPS.get(text, text)

def get_story(sid):
    return next(s for s in MANIFEST["stories"] if s["id"] == sid)

def get_dir(story, direction):
    return next(t for t in story["translations"] if t["direction"] == direction)

def aw(sid, fname):
    return AUDIO_WINDOWS[sid][fname]

def clamp(v, lo, hi):
    return max(lo, min(hi, v))

def build_story(sid, hook_variant="a", out_name=None):
    """Assembles the seven-beat vertical cut for one story: S1 hook card, S2
    the traveler's dialogue shot (upright caption in their own language), S3
    a UI cutaway of the traveler's line translated for the local (rotated to
    face them), S4 the local's dialogue shot (upright caption in their own
    language), S5 a UI cutaway of the local's reply translated for the
    traveler (upright), S6 the payoff shot, S7 the end card."""
    story = get_story(sid)
    lang = story["local_language"]
    font = FONT_FOR_LANG[lang]
    marks = MARKS[sid]["marks"]
    shots_dir = f"{ASSETS}/{sid}/shots"
    audio_dir = f"{ASSETS}/{sid}/audio"
    raw_ui = f"{WORK}/raw/{sid}.mov"

    seg_prefix = f"{SEG_DIR}/{sid}_{hook_variant}"
    os.makedirs(SEG_DIR, exist_ok=True)
    segs = []

    t_dir = get_dir(story, "traveler -> local")
    l_dir = get_dir(story, "local -> traveler")

    hook_text, hook_lang = (HOOK_TEXT_B[sid] if hook_variant == "b" else HOOK_TEXT[sid])
    hook_png = textcard(
        {"width": W, "height": H, "layers": [hook_layer(hook_text, "system")]},
        f"{seg_prefix}_hook.png",
    )
    s1 = make_scene_segment(
        f"{shots_dir}/{sid}_1_establish.mp4", 0.0, 2.0,
        f"{seg_prefix}_s1.mp4", caption_png=hook_png, extra_dim=True,
    )
    segs.append(s1)

    src_w = aw(sid, f"{sid}_2_traveler_source.wav")
    src_active = clamp(src_w["active_dur"] + PAD_HEAD + PAD_TAIL, MIN_DIALOGUE, MAX_DIALOGUE)
    src_astart = max(0.0, src_w["active_start"] - PAD_HEAD)
    cap2 = textcard(
        {"width": W, "height": H, "layers": [caption_layer(t_dir["source_transcript"], "system", 0.42)]},
        f"{seg_prefix}_s2.png",
    )
    s2 = make_scene_segment(
        f"{shots_dir}/{sid}_2_traveler.mp4", 0.0, src_active,
        f"{seg_prefix}_s2.mp4", caption_png=cap2,
        audio_src=f"{audio_dir}/{sid}_2_traveler_source.wav",
        audio_start=src_astart, audio_dur=min(src_w["total"] - src_astart, src_active),
        audio_pad_before=0.12,
    )
    segs.append(s2)

    tr_w = aw(sid, f"{sid}_2_traveler_translated_{lang}.wav")
    tr_active = clamp(tr_w["active_dur"] + PAD_HEAD + PAD_TAIL, MIN_UI, MAX_UI)
    tr_astart = max(0.0, tr_w["active_start"] - PAD_HEAD)
    tr_adur = min(tr_w["total"] - tr_astart, tr_active)
    settle1_wall = OFFSET + marks["settle1"]
    ui1_end = settle1_wall + 0.35
    ui1_start = ui1_end - tr_active
    s3 = make_ui_segment(
        raw_ui, ui1_start, tr_active, f"{seg_prefix}_s3.mp4",
        audio_src=f"{audio_dir}/{sid}_2_traveler_translated_{lang}.wav",
        audio_start=tr_astart, audio_dur=tr_adur, audio_pad_before=0.15,
    )
    segs.append(s3)

    lsrc_w = aw(sid, f"{sid}_3_local_source.wav")
    lsrc_active = clamp(lsrc_w["active_dur"] + PAD_HEAD + PAD_TAIL, MIN_DIALOGUE, MAX_DIALOGUE)
    lsrc_astart = max(0.0, lsrc_w["active_start"] - PAD_HEAD)
    cap4 = textcard(
        {"width": W, "height": H, "layers": [caption_layer(fix_transcript(l_dir["source_transcript"]), font, 0.42, size=52)]},
        f"{seg_prefix}_s4.png",
    )
    s4 = make_scene_segment(
        f"{shots_dir}/{sid}_3_local.mp4", 0.0, lsrc_active,
        f"{seg_prefix}_s4.mp4", caption_png=cap4,
        audio_src=f"{audio_dir}/{sid}_3_local_source.wav",
        audio_start=lsrc_astart, audio_dur=min(lsrc_w["total"] - lsrc_astart, lsrc_active),
        audio_pad_before=0.12,
    )
    segs.append(s4)

    lt_w = aw(sid, f"{sid}_3_local_translated_en.wav")
    lt_active = clamp(lt_w["active_dur"] + PAD_HEAD + PAD_TAIL, MIN_UI, MAX_UI)
    lt_astart = max(0.0, lt_w["active_start"] - PAD_HEAD)
    lt_adur = min(lt_w["total"] - lt_astart, lt_active)
    settle2_wall = OFFSET + marks["settle2"]
    ui2_end = settle2_wall + 0.35
    ui2_start = ui2_end - lt_active
    s5 = make_ui_segment(
        raw_ui, ui2_start, lt_active, f"{seg_prefix}_s5.mp4",
        audio_src=f"{audio_dir}/{sid}_3_local_translated_en.wav",
        audio_start=lt_astart, audio_dur=lt_adur, audio_pad_before=0.15,
    )
    segs.append(s5)

    s6 = make_scene_segment(
        f"{shots_dir}/{sid}_4_payoff.mp4", 0.0, 2.0,
        f"{seg_prefix}_s6.mp4",
    )
    segs.append(s6)

    end_card_png = textcard({
        "width": W, "height": H,
        "layers": [
            {"text": CTA_LINES[0], "font": "system", "size": 84, "weight": "heavy",
             "color": "#FFFFFF", "x": 0.5, "y": 0.565, "align": "center", "maxWidthFrac": 0.9},
            {"text": CTA_LINES[1], "font": "system", "size": 42, "weight": "medium",
             "color": "#DCE8FF", "x": 0.5, "y": 0.625, "align": "center", "maxWidthFrac": 0.85},
            {"text": CTA_LINES[2], "font": "system", "size": 38, "weight": "semibold",
             "color": "#FFFFFF", "x": 0.5, "y": 0.70, "align": "center", "maxWidthFrac": 0.85},
            {"text": CTA_LINES[3], "font": "system", "size": 34, "weight": "bold",
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

    disclosure_text, dlang = (DISCLOSURE_TEXT["ja"], "ja") if lang == "ja" and sid == "__never__" else (DISCLOSURE_TEXT["en"], "en")
    disc_png = textcard({
        "width": W, "height": H,
        "layers": [{
            "text": disclosure_text, "font": "system", "weight": "semibold", "size": 25,
            "color": "#FFFFFFF0", "x": 0.5, "y": 0.955, "align": "center",
            "maxWidthFrac": 0.92, "bgColor": "#000000A0", "bgPadX": 20, "bgPadY": 10, "bgRadius": 10,
        }],
    }, f"{seg_prefix}_disclosure.png")

    final_name = out_name or f"{sid}.mp4" if hook_variant == "a" else f"{sid}-b.mp4"
    final_out = f"{ROOT}/final/{final_name}"
    os.makedirs(f"{ROOT}/final", exist_ok=True)
    finalize(concat_out, final_out, disc_png, end_card_start)
    print(f"OK {sid} variant={hook_variant} total={total_dur:.2f}s end_card_start={end_card_start:.2f}s -> {final_out}")
    return final_out, total_dur

if __name__ == "__main__":
    sid = sys.argv[1]
    variant = sys.argv[2] if len(sys.argv) > 2 else "a"
    build_story(sid, variant)
