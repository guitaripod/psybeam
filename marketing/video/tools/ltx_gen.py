#!/usr/bin/env python3
"""Queue LTX-2.5 shots against a running ComfyUI server and report the results.

Reads a JSON shot list and, for each shot, loads the matching UI-format LTX-2.5
workflow template (text-to-video, image-to-video, or first/last-frame-to-video),
overwrites its exposed widgets (prompt, duration, resolution, seed, fps, model),
uploads any conditioning image(s), flattens the graph to ComfyUI's /prompt API
format with wf2api.py, queues it, waits for completion, and prints one JSON
report line per shot with its wall-clock time and output file path(s).

Shot list schema (a JSON array of objects):

    {
      "name": "ramen_counter",            required, used as the output filename
      "mode": "t2v" | "i2v" | "flf2v",     optional, defaults to "t2v"
      "prompt": "...",                    required
      "seconds": 5,                       optional, defaults to 5
      "width": 704, "height": 1280,       optional, default to the template's
      "fps": 24,                          optional, defaults to 24
      "seed": 12345,                      optional, defaults to a random seed
      "model": "distilled" | "dev",       optional, defaults to "distilled".
                                           This only swaps the checkpoint; the
                                           template's ManualSigmas/CFG nodes are
                                           tuned for the distilled model's fixed
                                           few-step schedule, so "dev" will be
                                           undersampled without also hand-editing
                                           those nodes to ~20-50 steps at CFG 2-5.
      "prompt_enhance": false,            optional, defaults to false
      "image": "/path/to/frame.png",      required for mode "i2v"
      "first_image": "/path/to/a.png",    required for mode "flf2v"
      "last_image": "/path/to/b.png"      required for mode "flf2v"
    }

Usage:

    ltx_gen.py shots.json [--server URL] [--workflow-dir DIR] [--wf2api PATH]
                          [--out report.jsonl]
"""
import argparse
import json
import mimetypes
import os
import random
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid

DEFAULT_SERVER = os.environ.get("LTX_GEN_SERVER", "http://127.0.0.1:8188")
DEFAULT_WORKFLOW_DIR = os.environ.get(
    "LTX_GEN_WORKFLOW_DIR",
    os.path.expanduser("~/AI/comfyui/ComfyUI/user/default/workflows"),
)
DEFAULT_WF2API = os.environ.get(
    "LTX_GEN_WF2API", os.path.expanduser("~/AI/comfyui/wf2api.py")
)
DEFAULT_OUTPUT_DIR = os.environ.get(
    "LTX_GEN_OUTPUT_DIR", "/mnt/nvme8tb/comfyui-output"
)

WORKFLOW_FILES = {
    "t2v": "ltx2_5_t2v_bf16.json",
    "i2v": "ltx2_5_i2v_bf16.json",
    "flf2v": "ltx2_5_flf2v_bf16.json",
}

MODEL_FILES = {
    "distilled": "ltx-2.5-22b-distilled-transformer-bf16.safetensors",
    "dev": "ltx-2.5-22b-dev-transformer-bf16.safetensors",
}


class ComfyClient:
    """A minimal stdlib HTTP client for a running ComfyUI server."""

    def __init__(self, server):
        self.server = server.rstrip("/")

    def get_json(self, path, timeout=600):
        with urllib.request.urlopen(f"{self.server}{path}", timeout=timeout) as r:
            return json.load(r)

    def post_json(self, path, payload, timeout=600):
        body = json.dumps(payload).encode()
        req = urllib.request.Request(
            f"{self.server}{path}",
            data=body,
            headers={"Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            raise SystemExit(f"POST {path} failed: {e.read().decode()[:4000]}")

    def upload_image(self, path, overwrite=True):
        """Upload a local image to ComfyUI's input store; return its stored name.

        The returned value is what a LoadImage node's filename widget expects:
        "name" alone, or "subfolder/name" when the server places it in one.
        """
        boundary = uuid.uuid4().hex
        filename = os.path.basename(path)
        content_type = mimetypes.guess_type(filename)[0] or "application/octet-stream"
        with open(path, "rb") as f:
            data = f.read()
        crlf = b"\r\n"
        chunks = [
            f"--{boundary}".encode(),
            (
                f'Content-Disposition: form-data; name="image"; '
                f'filename="{filename}"'
            ).encode(),
            f"Content-Type: {content_type}".encode(),
            b"",
            data,
            f"--{boundary}".encode(),
            b'Content-Disposition: form-data; name="overwrite"',
            b"",
            str(overwrite).lower().encode(),
            f"--{boundary}--".encode(),
            b"",
        ]
        body = crlf.join(chunks)
        req = urllib.request.Request(
            f"{self.server}/upload/image",
            data=body,
            headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        )
        with urllib.request.urlopen(req, timeout=120) as r:
            info = json.load(r)
        subfolder = info.get("subfolder") or ""
        return f"{subfolder}/{info['name']}" if subfolder else info["name"]

    def wait_for_prompt(self, prompt_id, poll_seconds=2.0):
        """Block until a queued prompt finishes; return its outputs or raise."""
        while True:
            history = self.get_json(f"/history/{prompt_id}")
            if prompt_id in history:
                status = history[prompt_id]["status"]
                if status.get("completed"):
                    return history[prompt_id]["outputs"]
                if status.get("status_str") == "error":
                    raise SystemExit(json.dumps(status, indent=1)[:4000])
            time.sleep(poll_seconds)


def gpu_memory_used_mib():
    """Return current GPU memory usage in MiB, or None if nvidia-smi is unavailable."""
    try:
        out = subprocess.run(
            ["nvidia-smi", "--query-gpu=memory.used", "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=10, check=True,
        )
        return int(out.stdout.strip().splitlines()[0])
    except Exception:
        return None


def load_template(workflow_dir, mode):
    path = os.path.join(workflow_dir, WORKFLOW_FILES[mode])
    with open(path) as f:
        return json.load(f)


def find_nodes(doc, predicate):
    return [n for n in doc["nodes"] if predicate(n)]


def find_one_node(doc, predicate, description):
    matches = find_nodes(doc, predicate)
    if len(matches) != 1:
        raise SystemExit(
            f"expected exactly one {description} node, found {len(matches)}"
        )
    return matches[0]


def subgraph_type_ids(doc):
    return {sg["id"] for sg in doc.get("definitions", {}).get("subgraphs", [])}


def shot_subgraph_definition(doc, node):
    return next(
        sg for sg in doc["definitions"]["subgraphs"] if sg["id"] == node["type"]
    )


def find_internal(sg, class_type, title_contains=None):
    matches = find_internal_all(sg, class_type, title_contains)
    if len(matches) != 1:
        raise SystemExit(
            f"expected exactly one {class_type} node matching "
            f"{title_contains!r} inside the shot subgraph, found {len(matches)}"
        )
    return matches[0]


def find_internal_all(sg, class_type, title_contains=None):
    return [
        n for n in sg["nodes"]
        if n["type"] == class_type
        and (title_contains is None or title_contains in (n.get("title") or "").lower())
    ]


def detach_boundary_link(node):
    """Clear a subgraph-internal node's inbound link so it falls back to its own widget.

    Every pin the shot subgraph exposes is wired straight through to one
    internal node via a link from the subgraph's own boundary pseudo-node.
    wf2api.py's flattener keys that boundary purely by each pin's position in
    the *outer* instance's own connector row, which every i2v/flf2v template
    desyncs from the pins' true definition order (an added image pin, an
    omitted seed pin, a dropped upscaler pin) -- misrouting values to the
    wrong consumer, sometimes past a COMBO's valid options entirely. Editing
    the widget directly on the true consumer and cutting its one inbound
    link sidesteps that boundary arithmetic altogether.
    """
    inputs = node.get("inputs") or []
    if inputs:
        inputs[0]["link"] = None


def apply_shot_widgets(doc, shot):
    """Overwrite the LTX-2.5 shot subgraph's internal widgets directly."""
    ids = subgraph_type_ids(doc)
    node = find_one_node(doc, lambda n: n["type"] in ids, "shot subgraph")
    sg = shot_subgraph_definition(doc, node)

    prompt_node = find_internal(sg, "PrimitiveStringMultiline")
    enhance_node = find_internal(sg, "PrimitiveBoolean", "prompt enhance")
    duration_node = find_internal(sg, "PrimitiveInt", "duration")
    width_node = find_internal(sg, "PrimitiveInt", "width")
    height_node = find_internal(sg, "PrimitiveInt", "height")
    fps_node = find_internal(sg, "PrimitiveInt", "frame rate")
    unet_node = find_internal(sg, "UNETLoader")

    for target in (prompt_node, enhance_node, duration_node, width_node, height_node, fps_node, unet_node):
        detach_boundary_link(target)
    for loader in (
        find_internal_all(sg, "VAELoader")
        + find_internal_all(sg, "CLIPLoader")
        + find_internal_all(sg, "LatentUpscaleModelLoader")
    ):
        detach_boundary_link(loader)

    prompt_node["widgets_values"][0] = shot["prompt"]
    enhance_node["widgets_values"][0] = bool(shot.get("prompt_enhance", False))
    duration_node["widgets_values"][0] = int(shot.get("seconds", 5))
    width_node["widgets_values"][0] = int(shot.get("width", width_node["widgets_values"][0]))
    height_node["widgets_values"][0] = int(shot.get("height", height_node["widgets_values"][0]))
    fps_node["widgets_values"][0] = int(shot.get("fps", 24))
    unet_node["widgets_values"][0] = MODEL_FILES[shot.get("model", "distilled")]

    seed = int(shot.get("seed", random.randrange(2**48)))
    for noise_node in find_internal_all(sg, "RandomNoise"):
        detach_boundary_link(noise_node)
        noise_node["widgets_values"][0] = seed
        noise_node["widgets_values"][1] = "fixed"
    return seed


def apply_image_nodes(doc, shot, client):
    """Upload the shot's conditioning image(s) and point the LoadImage node(s) at them."""
    load_images = find_nodes(doc, lambda n: n["type"] == "LoadImage")
    if len(load_images) == 1:
        load_images[0]["widgets_values"][0] = client.upload_image(shot["image"])
    elif len(load_images) == 2:
        by_title = {(n.get("title") or "").lower(): n for n in load_images}
        first = next(n for t, n in by_title.items() if "first" in t)
        last = next(n for t, n in by_title.items() if "last" in t)
        first["widgets_values"][0] = client.upload_image(shot["first_image"])
        last["widgets_values"][0] = client.upload_image(shot["last_image"])
    else:
        raise SystemExit(f"unexpected LoadImage node count: {len(load_images)}")


def apply_output_prefix(doc, shot):
    node = find_one_node(doc, lambda n: n["type"] == "SaveVideo", "SaveVideo")
    node["widgets_values"][0] = f"video/{shot['name']}"


def build_api_graph(doc, wf2api_path, tmp_dir, name):
    """Flatten a UI-format workflow (subgraphs included) to /prompt API format."""
    ui_path = os.path.join(tmp_dir, f"ui_{name}.json")
    api_path = os.path.join(tmp_dir, f"api_{name}.json")
    with open(ui_path, "w") as f:
        json.dump(doc, f)
    subprocess.run(
        [sys.executable, wf2api_path, ui_path, api_path],
        check=True, stdout=subprocess.DEVNULL,
    )
    with open(api_path) as f:
        return json.load(f)


def fill_defaults(client, api):
    """Supply defaults for widgets a newer ComfyUI added since the template was saved."""
    spec = client.get_json("/object_info")
    for node in api.values():
        sig = spec.get(node["class_type"], {}).get("input", {})
        fields = {**(sig.get("required") or {}), **(sig.get("optional") or {})}
        for name, definition in fields.items():
            if node["inputs"].get(name) is not None:
                continue
            opts = definition[1] if len(definition) > 1 and isinstance(definition[1], dict) else {}
            if "default" in opts:
                node["inputs"][name] = opts["default"]
            elif isinstance(definition[0], str) and definition[0] == "COMBO" and opts.get("options"):
                node["inputs"][name] = opts["options"][0]
    return api


def output_paths(outputs, output_dir):
    files = []
    for out in outputs.values():
        for v in out.get("images", []) + out.get("videos", []) + out.get("gifs", []):
            subfolder = v.get("subfolder") or ""
            files.append(os.path.join(output_dir, subfolder, v["filename"]))
    return files


def run_shot(client, shot, workflow_dir, wf2api_path, tmp_dir, output_dir, client_id):
    mode = shot.get("mode", "t2v")
    doc = load_template(workflow_dir, mode)
    seed = apply_shot_widgets(doc, shot)
    if mode != "t2v":
        apply_image_nodes(doc, shot, client)
    apply_output_prefix(doc, shot)
    api = fill_defaults(client, build_api_graph(doc, wf2api_path, tmp_dir, shot["name"]))
    vram_before = gpu_memory_used_mib()
    t0 = time.time()
    prompt_id = client.post_json("/prompt", {"prompt": api, "client_id": client_id})["prompt_id"]
    outputs = client.wait_for_prompt(prompt_id)
    elapsed = time.time() - t0
    vram_after = gpu_memory_used_mib()
    return {
        "name": shot["name"],
        "mode": mode,
        "seed": seed,
        "seconds": elapsed,
        "files": output_paths(outputs, output_dir),
        "vram_before_mib": vram_before,
        "vram_after_mib": vram_after,
    }


def parse_args(argv):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("shots", help="path to a JSON shot-list file")
    p.add_argument("--server", default=DEFAULT_SERVER)
    p.add_argument("--workflow-dir", default=DEFAULT_WORKFLOW_DIR)
    p.add_argument("--wf2api", default=DEFAULT_WF2API)
    p.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR)
    p.add_argument("--out", help="also write the JSON report array to this path")
    return p.parse_args(argv)


def main(argv=None):
    args = parse_args(argv if argv is not None else sys.argv[1:])
    with open(args.shots) as f:
        shots = json.load(f)
    client = ComfyClient(args.server)
    client_id = str(uuid.uuid4())
    reports = []
    with tempfile.TemporaryDirectory(prefix="ltx_gen_") as tmp_dir:
        for shot in shots:
            report = run_shot(
                client, shot, args.workflow_dir, args.wf2api, tmp_dir,
                args.output_dir, client_id,
            )
            print(json.dumps(report), flush=True)
            reports.append(report)
    if args.out:
        with open(args.out, "w") as f:
            json.dump(reports, f, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
