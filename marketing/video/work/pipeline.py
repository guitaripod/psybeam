import json, os, subprocess, sys, shlex

WORK = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(WORK)
ASSETS = f"{ROOT}/assets"
FF = "/opt/homebrew/bin/ffmpeg"
FP = "/opt/homebrew/bin/ffprobe"
TEXTCARD = f"{WORK}/textcard/textcard"
ICON = "/Users/marcus/Dev/ios/psybeam/Psybeam/Assets.xcassets/AppIcon.appiconset/icon-1024.png"

W, H, FPS = 1080, 1920, 30
SEG_DIR = f"{WORK}/segments"
os.makedirs(SEG_DIR, exist_ok=True)

FONT_FOR_LANG = {
    "en": "system", "es": "system", "fr": "system", "it": "system",
    "ja": "Hiragino Sans", "ko": "Apple SD Gothic Neo", "th": "Thonburi",
}

DISCLOSURE_TEXT = {
    "en": "Dramatization · AI-generated scenes · Real Psybeam translation audio",
    "ja": "制作には AI 生成シーンを使用 · 翻訳音声は実際の Psybeam",
}

def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print("CMD FAILED:", " ".join(shlex.quote(c) for c in cmd))
        print(r.stderr[-4000:])
        raise SystemExit(1)
    return r

def ffprobe_dur(path):
    r = subprocess.run([FP, "-v", "error", "-show_entries", "format=duration",
                         "-of", "default=noprint_wrappers=1:nokey=1", path],
                        capture_output=True, text=True)
    return float(r.stdout.strip())

def textcard(spec, out_png):
    spec_path = out_png + ".spec.json"
    json.dump(spec, open(spec_path, "w"), ensure_ascii=False)
    run([TEXTCARD, "--spec", spec_path, "--out", out_png])
    return out_png

def caption_layer(text, font, y, size=54, weight="bold"):
    return {
        "text": text, "font": font, "size": size, "weight": weight,
        "color": "#FFFFFF", "x": 0.5, "y": y, "align": "center",
        "maxWidthFrac": 0.86, "bgColor": "#000000B3", "bgPadX": 30, "bgPadY": 18,
        "bgRadius": 20, "lineSpacing": 1.15,
    }

def hook_layer(text, font, y=0.26, size=76):
    return {
        "text": text, "font": font, "size": size, "weight": "black",
        "color": "#FFFFFF", "x": 0.5, "y": y, "align": "center",
        "maxWidthFrac": 0.85, "bgColor": "#000000B3", "bgPadX": 34, "bgPadY": 22,
        "bgRadius": 24, "lineSpacing": 1.12,
    }

def cover_filter(w=W, h=H):
    return f"scale={w}:{h}:force_original_aspect_ratio=increase,crop={w}:{h},fps={FPS},format=yuv420p"

def make_scene_segment(src, start, dur, out_mp4, caption_png=None, audio_src=None,
                        audio_start=0.0, audio_dur=None, audio_pad_before=0.15,
                        extra_dim=False):
    vf = cover_filter()
    if extra_dim:
        vf += ",eq=brightness=-0.03"

    inputs = ["-ss", f"{start:.3f}", "-t", f"{dur:.3f}", "-i", src]
    n_inputs = 1

    if caption_png:
        inputs += ["-i", caption_png]
        cap_idx = n_inputs
        n_inputs += 1
    else:
        cap_idx = None

    if audio_src:
        a_inputs = ["-ss", f"{audio_start:.3f}"]
        if audio_dur:
            a_inputs += ["-t", f"{audio_dur:.3f}"]
        a_inputs += ["-i", audio_src]
        inputs += a_inputs
        audio_idx = n_inputs
        n_inputs += 1
    else:
        inputs += ["-f", "lavfi", "-t", f"{dur:.3f}", "-i", "anullsrc=r=48000:cl=stereo"]
        audio_idx = n_inputs
        n_inputs += 1

    filter_parts = [f"[0:v]{vf}[base]"]
    map_v = "[base]"
    if cap_idx is not None:
        filter_parts.append(f"[base][{cap_idx}:v]overlay=0:0[v]")
        map_v = "[v]"

    if audio_src:
        adelay_ms = int(audio_pad_before * 1000)
        filter_parts.append(
            f"[{audio_idx}:a]aformat=sample_rates=48000:channel_layouts=stereo,"
            f"adelay={adelay_ms}|{adelay_ms},apad=whole_dur={dur:.3f}[a]"
        )
        map_a = "[a]"
    else:
        map_a = f"{audio_idx}:a"

    filter_complex = ";".join(filter_parts)
    cmd = [FF, "-y", "-loglevel", "error"] + inputs + [
        "-filter_complex", filter_complex, "-map", map_v, "-map", map_a,
        "-t", f"{dur:.3f}", "-r", str(FPS),
        "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2",
        out_mp4,
    ]
    run(cmd)
    return out_mp4


def make_ui_segment(src, start, dur, out_mp4, audio_src, audio_start, audio_dur, audio_pad_before=0.1):
    fg_w = round(W * (H / 2868 * 1320) / (H))
    fg_scale = f"scale={W}:{H}:force_original_aspect_ratio=decrease"
    bg_vf = f"scale={W}:{H}:force_original_aspect_ratio=increase,crop={W}:{H},boxblur=24:3,eq=brightness=-0.12:saturation=1.05,fps={FPS},format=yuv420p"
    fg_vf = f"{fg_scale},fps={FPS},format=yuv420p"
    filter_complex = (
        f"[0:v]trim=start={start:.3f}:duration={dur:.3f},setpts=PTS-STARTPTS,{bg_vf}[bg];"
        f"[0:v]trim=start={start:.3f}:duration={dur:.3f},setpts=PTS-STARTPTS,{fg_vf}[fg];"
        f"[bg][fg]overlay=(W-w)/2:(H-h)/2[v];"
        f"[1:a]atrim=start={audio_start:.3f}:duration={audio_dur:.3f},asetpts=PTS-STARTPTS,"
        f"aformat=sample_rates=48000:channel_layouts=stereo,adelay={int(audio_pad_before*1000)}|{int(audio_pad_before*1000)},"
        f"apad=whole_dur={dur:.3f}[a]"
    )
    cmd = [FF, "-y", "-loglevel", "error", "-i", src, "-i", audio_src,
           "-filter_complex", filter_complex, "-map", "[v]", "-map", "[a]",
           "-t", f"{dur:.3f}", "-r", str(FPS),
           "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p",
           "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2",
           out_mp4]
    run(cmd)
    return out_mp4


def concat_segments(seg_paths, out_mp4):
    list_path = out_mp4 + ".list.txt"
    with open(list_path, "w") as f:
        for p in seg_paths:
            f.write(f"file '{p}'\n")
    cmd = [FF, "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", list_path,
           "-c", "copy", out_mp4]
    run(cmd)
    return out_mp4


def finalize(in_mp4, out_mp4, disclosure_png, end_card_start):
    filter_complex = (
        f"[0:v][1:v]overlay=0:0:enable='lt(t,3)'[v1];"
        f"[v1][1:v]overlay=0:0:enable='gte(t,{end_card_start:.3f})'[v]"
    )
    cmd = [FF, "-y", "-loglevel", "error", "-i", in_mp4, "-i", disclosure_png,
           "-filter_complex", filter_complex, "-map", "[v]", "-map", "0:a",
           "-c:v", "libx264", "-preset", "medium", "-crf", "17", "-pix_fmt", "yuv420p",
           "-af", "loudnorm=I=-14:TP=-1.5:LRA=11",
           "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2",
           "-movflags", "+faststart",
           out_mp4]
    run(cmd)
    return out_mp4
