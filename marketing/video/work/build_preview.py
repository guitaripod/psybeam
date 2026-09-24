import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pipeline import FF, FP, WORK, ROOT, ASSETS, TEXTCARD, textcard, run, ffprobe_dur, concat_segments

PW, PH, FPS = 886, 1920, 30
OFFSET = 2.2

MANIFEST = json.load(open(f"{ASSETS}/manifest.json"))
tokyo = next(s for s in MANIFEST["stories"] if s["id"] == "tokyo-ramen")
t_dir = next(t for t in tokyo["translations"] if t["direction"] == "traveler -> local")
l_dir = next(t for t in tokyo["translations"] if t["direction"] == "local -> traveler")
AUDIO_DIR = f"{ASSETS}/tokyo-ramen/audio"

AUDIO_WINDOWS = json.load(open(f"{WORK}/audio_windows.json"))["tokyo-ramen"]

def aw(fname):
    return AUDIO_WINDOWS[fname]

def cover(w, h):
    return f"scale={w}:{h}:force_original_aspect_ratio=increase,crop={w}:{h},fps={FPS},format=yuv420p"

def seg_from_raw(raw, start, dur, out_mp4, audio_src=None, audio_start=0.0, audio_dur=None, caption_png=None):
    inputs = ["-ss", f"{start:.3f}", "-t", f"{dur:.3f}", "-i", raw]
    n = 1
    cap_idx = None
    if caption_png:
        inputs += ["-i", caption_png]
        cap_idx = n
        n += 1
    if audio_src:
        inputs += ["-ss", f"{audio_start:.3f}", "-t", f"{audio_dur:.3f}", "-i", audio_src]
        a_idx = n
        n += 1
    else:
        inputs += ["-f", "lavfi", "-t", f"{dur:.3f}", "-i", "anullsrc=r=48000:cl=stereo"]
        a_idx = n
        n += 1

    parts = [f"[0:v]{cover(PW, PH)}[base]"]
    mapv = "[base]"
    if cap_idx is not None:
        parts.append(f"[base][{cap_idx}:v]overlay=0:0[v]")
        mapv = "[v]"
    if audio_src:
        parts.append(f"[{a_idx}:a]aformat=sample_rates=48000:channel_layouts=stereo,apad=whole_dur={dur:.3f}[a]")
        mapa = "[a]"
    else:
        mapa = f"{a_idx}:a"

    cmd = [FF, "-y", "-loglevel", "error"] + inputs + [
        "-filter_complex", ";".join(parts), "-map", mapv, "-map", mapa,
        "-t", f"{dur:.3f}", "-r", str(FPS),
        "-c:v", "libx264", "-preset", "medium", "-crf", "17", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2",
        out_mp4,
    ]
    run(cmd)
    return out_mp4


def still_seg(png, dur, out_mp4):
    cmd = [FF, "-y", "-loglevel", "error", "-loop", "1", "-t", f"{dur:.3f}", "-i", png,
           "-f", "lavfi", "-t", f"{dur:.3f}", "-i", "anullsrc=r=48000:cl=stereo",
           "-vf", f"scale={PW}:{PH},format=yuv420p", "-r", str(FPS),
           "-c:v", "libx264", "-preset", "medium", "-crf", "17", "-pix_fmt", "yuv420p",
           "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2",
           out_mp4]
    run(cmd)
    return out_mp4


def build_preview(locale, pair, marks, idle_caption_text, idle_font):
    raw = f"{WORK}/raw/preview-{locale}.mov"
    dest_raw = f"{WORK}/raw/destination-{locale}.mov"
    seg_dir = f"{WORK}/segments/preview_{locale}"
    os.makedirs(seg_dir, exist_ok=True)
    segs = []

    idle_wall = 1.0 if locale == "en" else 2.4
    idle_png_src = f"{seg_dir}/idle_frame.png"
    run([FF, "-y", "-loglevel", "error", "-ss", f"{idle_wall:.3f}", "-i", raw, "-frames:v", "1",
         "-vf", cover(PW, PH), idle_png_src])

    cap_png = textcard({
        "width": PW, "height": PH,
        "layers": [{
            "text": idle_caption_text, "font": idle_font, "weight": "bold", "size": 46,
            "color": "#FFFFFF", "x": 0.5, "y": 0.20, "align": "center", "maxWidthFrac": 0.85,
            "bgColor": "#000000B3", "bgPadX": 26, "bgPadY": 16, "bgRadius": 18, "lineSpacing": 1.15,
        }],
    }, f"{seg_dir}/idle_caption.png")

    s1 = f"{seg_dir}/s1.mp4"
    cmd = [FF, "-y", "-loglevel", "error", "-loop", "1", "-t", "3.0", "-i", idle_png_src,
           "-i", cap_png, "-f", "lavfi", "-t", "3.0", "-i", "anullsrc=r=48000:cl=stereo",
           "-filter_complex", "[0:v][1:v]overlay=0:0[v]",
           "-map", "[v]", "-map", "2:a", "-t", "3.0", "-r", str(FPS),
           "-c:v", "libx264", "-preset", "medium", "-crf", "17", "-pix_fmt", "yuv420p",
           "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2", s1]
    run(cmd)
    segs.append(s1)

    tr_active = aw(f"tokyo-ramen_2_traveler_translated_ja.wav")
    lt_active = aw(f"tokyo-ramen_3_local_translated_en.wav")

    if locale == "en":
        first_audio = f"{AUDIO_DIR}/tokyo-ramen_2_traveler_translated_ja.wav"
        first_w = tr_active
        second_audio = f"{AUDIO_DIR}/tokyo-ramen_3_local_translated_en.wav"
        second_w = lt_active
    else:
        first_audio = f"{AUDIO_DIR}/tokyo-ramen_3_local_translated_en.wav"
        first_w = lt_active
        second_audio = f"{AUDIO_DIR}/tokyo-ramen_2_traveler_translated_ja.wav"
        second_w = tr_active

    pad_head, pad_tail = 0.15, 0.3
    dur1 = max(4.0, first_w["active_dur"] + pad_head + pad_tail)
    a1start = max(0.0, first_w["active_start"] - pad_head)
    a1dur = min(first_w["total"] - a1start, dur1)
    settle1_wall = OFFSET + marks["settle1"]
    end1 = settle1_wall + 0.35
    start1 = end1 - dur1
    s2 = seg_from_raw(raw, start1, dur1, f"{seg_dir}/s2.mp4",
                       audio_src=first_audio, audio_start=a1start, audio_dur=a1dur)
    segs.append(s2)

    dur2 = max(4.0, second_w["active_dur"] + pad_head + pad_tail)
    a2start = max(0.0, second_w["active_start"] - pad_head)
    a2dur = min(second_w["total"] - a2start, dur2)
    settle2_wall = OFFSET + marks["settle2"]
    end2 = settle2_wall + 0.35
    start2 = end2 - dur2
    s3 = seg_from_raw(raw, start2, dur2, f"{seg_dir}/s3.mp4",
                       audio_src=second_audio, audio_start=a2start, audio_dur=a2dur)
    segs.append(s3)

    s4 = seg_from_raw(dest_raw, 3.0, 3.6, f"{seg_dir}/s4.mp4")
    segs.append(s4)

    concat_out = f"{seg_dir}/concat.mp4"
    concat_segments(segs, concat_out)

    final_dir = f"{ROOT}/final"
    os.makedirs(final_dir, exist_ok=True)
    name = "app-preview-en-US.mp4" if locale == "en" else "app-preview-ja.mp4"
    final_out = f"{final_dir}/{name}"
    cmd = [FF, "-y", "-loglevel", "error", "-i", concat_out,
           "-af", "loudnorm=I=-14:TP=-1.5:LRA=11",
           "-c:v", "libx264", "-preset", "medium", "-crf", "16", "-pix_fmt", "yuv420p",
           "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2",
           "-movflags", "+faststart", final_out]
    run(cmd)
    total = sum(ffprobe_dur(p) for p in segs)
    print(f"OK preview {locale} total={total:.2f}s -> {final_out}")
    return final_out


if __name__ == "__main__":
    pm = json.load(open(f"{WORK}/demo-scripts/_preview_marks.json"))
    build_preview("en", "en:ja", pm["en"],
                   "Speak English. They hear Japanese.", "system")
    build_preview("ja", "ja:en", pm["ja"],
                   "日本語で話してください。相手には英語で聞こえます。",
                   "Hiragino Sans")
