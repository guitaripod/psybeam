"""Runs a dependency-chained LTX-2.5 shot list against the local ComfyUI server.

Reads a shot list (as produced by build_shots.py, each shot optionally naming a
prior shot in "depends_on") and runs them in list order, extracting the last
frame of a completed shot via ffmpeg and feeding it as the "image" input of any
later shot that depends on it. Prints one JSON report line per shot as it
completes and writes the full report array at the end.
"""
import json
import os
import subprocess
import sys
import tempfile
import uuid

sys.path.insert(0, os.path.expanduser("~/AI/comfyui/psybeam"))
import ltx_gen as lg

FRAME_DIR = os.path.expanduser("~/AI/comfyui/psybeam/frames")
os.makedirs(FRAME_DIR, exist_ok=True)


def extract_last_frame(video_path, out_path):
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-sseof", "-0.2", "-i", video_path,
         "-update", "1", "-frames:v", "1", out_path],
        check=True,
    )


def main():
    shots_path, out_path = sys.argv[1], sys.argv[2]
    with open(shots_path) as f:
        shots = json.load(f)

    client = lg.ComfyClient(lg.DEFAULT_SERVER)
    client_id = str(uuid.uuid4())
    last_frame_by_name = {}
    reports = []

    with tempfile.TemporaryDirectory(prefix="story_gen_") as tmp_dir:
        for shot in shots:
            dep = shot.get("depends_on")
            if dep:
                shot["image"] = last_frame_by_name[dep]
            report = lg.run_shot(
                client, shot, lg.DEFAULT_WORKFLOW_DIR, lg.DEFAULT_WF2API,
                tmp_dir, lg.DEFAULT_OUTPUT_DIR, client_id,
            )
            video_file = report["files"][0]
            frame_path = os.path.join(FRAME_DIR, f"{shot['name']}_last.png")
            extract_last_frame(video_file, frame_path)
            last_frame_by_name[shot["name"]] = frame_path
            report["last_frame"] = frame_path
            report["story"] = shot.get("story")
            report["role"] = shot.get("role")
            report["has_dialogue"] = shot.get("has_dialogue")
            report["speaker"] = shot.get("speaker")
            print(json.dumps(report), flush=True)
            reports.append(report)

    with open(out_path, "w") as f:
        json.dump(reports, f, indent=1)


if __name__ == "__main__":
    main()
