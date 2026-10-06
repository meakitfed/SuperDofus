"""
Golden comparison against PyDofus/d3-ts-renderer (the reference WebGL renderer).

    python tools/golden/compare.py --ref-repo <path to built d3-ts-renderer> [--cases cases.json]

For every case it renders the same look/animation/frame with the reference (Node, headless-gl)
and with Godot (tools/render_shot.gd, transparent background), crops both to their alpha
bounding box, resizes to a common size and reports the mean absolute RGBA difference.
Writes side-by-side images to tools/golden/out/.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / "game"
OUT = Path(__file__).resolve().parent / "out"
DEFAULT_GODOT = Path.home() / "Documents" / "Godot" / "Godot_v4.7-stable_win64_console.exe"
DEFAULT_CASES = [
    {"look": "{1|110,2172||100}", "anim": "AnimAttaque1100_1", "frames": [12, 16, 24], "bone": "1-11-combat"},
    {"look": "{1|120,2195,3042,3069,3963|1=16777215,2=15335424,3=15335424,4=16777215,5=0,6=15335424|56}",
     "anim": "AnimStatiqueExplo0_1", "frames": [0, 20], "bone": "1-static"},
    {"look": "{1001|||100}", "anim": "AnimMarche_1", "frames": [3]},
    # screen / lighten blends: approximated in Godot (no MAX equation, no ONE_MINUS_SRC_COLOR)
    {"look": "{1033|||100}", "anim": "AnimCourse_6", "frames": [3], "threshold": 30},
    {"look": "{1|10,2012||100}", "anim": "AnimAttaque24_5", "frames": [8], "bone": "1-combat"},
    {"look": "{1|10,2012||100}", "anim": "AnimAttaque24_5", "frames": [20], "bone": "1-combat", "threshold": 30},
    {"look": "{2069|||150}", "anim": "AnimStatique_1", "frames": [0]},
]


BG = (46, 51, 61)  # render_shot.gd default clear colour


def on_bg(img: Image.Image) -> Image.Image:
    bg = Image.new("RGBA", img.size, BG + (255,))
    bg.alpha_composite(img.convert("RGBA"))
    return bg


def crop_content(img: Image.Image) -> Image.Image:
    diff = ImageChops.difference(img.convert("RGB"), Image.new("RGB", img.size, BG)).convert("L")
    box = diff.point(lambda v: 255 if v > 6 else 0).getbbox()
    return img.crop(box) if box else img


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref-repo", required=True, type=Path, help="built d3-ts-renderer checkout (npm install + gl)")
    ap.add_argument("--godot", type=Path, default=Path(os.environ.get("GODOT", DEFAULT_GODOT)))
    ap.add_argument("--cases", type=Path)
    ap.add_argument("--threshold", type=float, default=12.0, help="max mean abs diff (0-255) per case")
    args = ap.parse_args()
    cases = json.loads(args.cases.read_text()) if args.cases else DEFAULT_CASES
    OUT.mkdir(exist_ok=True)
    shutil.copy(Path(__file__).with_name("ref_render.mjs"), args.ref_repo / "ref_render.mjs")
    content = str(GAME / "content").replace("\\", "/")
    failures = 0
    for i, case in enumerate(cases):
        frames = ",".join(map(str, case["frames"]))
        ref_prefix = OUT / f"case{i}_ref"
        subprocess.run(["node", "ref_render.mjs", content, case["look"], case["anim"], frames, str(ref_prefix),
                        case.get("bone", "")], cwd=args.ref_repo, check=True, capture_output=True)
        base, direction = case["anim"].rsplit("_", 1)
        for f in case["frames"]:
            ours = OUT / f"case{i}_ours_{f}.png"
            subprocess.run([str(args.godot), "--path", str(GAME), "-s", "res://tools/render_shot.gd", "--",
                            f"--out={ours}", "--cell=390", "--aspect=0.75", "--foot=100", "--zoom=2", f"--anim={base}", f"--dir={direction}",
                            f"--frames={f}", case["look"]], check=True, capture_output=True)
            # both composited on the same opaque background (Godot clip groups need one)
            ref = crop_content(on_bg(Image.open(f"{ref_prefix}_{f}.png")))
            got = crop_content(Image.open(ours).convert("RGBA"))
            got_r = got.resize(ref.size, Image.BILINEAR)
            diff = ImageChops.difference(ref, got_r)
            stat = sum(sum(h * v for v, h in enumerate(diff.getchannel(c).histogram())) for c in "RGBA")
            mad = stat / (ref.size[0] * ref.size[1] * 4)
            limit = case.get("threshold", args.threshold)
            side = Image.new("RGBA", (ref.size[0] * 2 + 10, ref.size[1]), (40, 44, 52, 255))
            side.alpha_composite(ref, (0, 0))
            side.alpha_composite(got_r, (ref.size[0] + 10, 0))
            side.save(OUT / f"case{i}_{f}_side.png")
            status = "ok " if mad <= limit else "BAD"
            failures += mad > limit
            print(f"{status} case{i} {case['look'][:40]:40} {case['anim']:24} f{f:<3} size ref{ref.size} ours{got.size} mad={mad:.2f}")
    print(f"{failures} case(s) above threshold")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
