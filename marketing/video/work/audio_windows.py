import json, subprocess, sys, re, os

FF = "/opt/homebrew/bin/ffmpeg"
ASSETS = "/Users/marcus/Dev/ios/psybeam/marketing/video/assets"

def active_window(path, noise="-35dB", d=0.15):
    cmd = [FF, "-i", path, "-af", f"silencedetect=noise={noise}:d={d}", "-f", "null", "-"]
    out = subprocess.run(cmd, capture_output=True, text=True).stderr
    starts = [float(x) for x in re.findall(r"silence_start:\s*([\-0-9.]+)", out)]
    ends = [float(x) for x in re.findall(r"silence_end:\s*([0-9.]+)", out)]
    dur_cmd = ["/opt/homebrew/bin/ffprobe", "-v", "error", "-show_entries", "format=duration",
               "-of", "default=noprint_wrappers=1:nokey=1", path]
    total = float(subprocess.run(dur_cmd, capture_output=True, text=True).stdout.strip())
    silences = list(zip(starts, ends))
    active_start = 0.0
    active_end = total
    if silences and silences[0][0] <= 0.05:
        active_start = silences[0][1]
        silences = silences[1:]
    if silences and abs(silences[-1][1] - total) < 0.05:
        active_end = silences[-1][0]
    return {"total": round(total, 3), "active_start": round(active_start, 3),
            "active_end": round(active_end, 3), "active_dur": round(active_end - active_start, 3)}

def main():
    result = {}
    for story in sorted(os.listdir(ASSETS)):
        d = os.path.join(ASSETS, story)
        if not os.path.isdir(d):
            continue
        audio_dir = os.path.join(d, "audio")
        if not os.path.isdir(audio_dir):
            continue
        result[story] = {}
        for f in sorted(os.listdir(audio_dir)):
            if f.endswith(".wav"):
                result[story][f] = active_window(os.path.join(audio_dir, f))
    print(json.dumps(result, indent=2))

if __name__ == "__main__":
    main()
