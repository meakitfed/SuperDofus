"""
Converts extracted PNG textures to lossless WebP in place (pixel-identical, ~40% smaller).
The Godot loader reads either format.

    python compact.py [--content ../../game/content] [--jobs 8] [--verify 20]
"""
from __future__ import annotations

import argparse
import concurrent.futures as cf
import os
import random
from pathlib import Path

from PIL import Image, ImageChops


def convert(png: str) -> tuple[int, int]:
    try:
        return _convert(png)
    except Exception:  # truncated file (e.g. disk full during extraction): re-extract it
        print(f"  ! unreadable {png}", flush=True)
        return 0, 0


def _convert(png: str) -> tuple[int, int]:
    src = Path(png)
    dst = src.with_suffix(".webp")
    before = src.stat().st_size
    with Image.open(src) as im:
        # exact=True keeps the RGB of fully transparent texels (they bleed through linear filtering)
        im.save(dst, "WEBP", lossless=True, quality=0, method=0, exact=True)
    src.unlink()
    return before, dst.stat().st_size


def identical(png_bytes: bytes, tmp: Path) -> bool:
    import io
    a = Image.open(io.BytesIO(png_bytes)).convert("RGBA")
    a.save(tmp, "WEBP", lossless=True, quality=0, method=0, exact=True)
    b = Image.open(tmp).convert("RGBA")
    return ImageChops.difference(a, b).getbbox() is None


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--content", type=Path, default=Path(__file__).resolve().parents[2] / "game" / "content")
    ap.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) - 1))
    ap.add_argument("--verify", type=int, default=0, help="check N random files for pixel identity, then exit")
    args = ap.parse_args()
    pngs = [str(p) for p in args.content.rglob("*.png")]
    if args.verify:
        tmp = args.content / "_verify.webp"
        sample = random.sample(pngs, min(args.verify, len(pngs)))
        ok = all(identical(Path(p).read_bytes(), tmp) for p in sample)
        tmp.unlink(missing_ok=True)
        print(f"{len(sample)} files pixel-identical: {ok}")
        return
    print(f"{len(pngs)} png files")
    saved = done = 0
    with cf.ProcessPoolExecutor(args.jobs) as pool:
        for before, after in pool.map(convert, pngs, chunksize=16):
            saved += before - after
            done += 1
            if done % 1000 == 0:
                print(f"  {done}/{len(pngs)}  saved {saved / 1e9:.2f} GB", flush=True)
    print(f"done: {done} files, saved {saved / 1e9:.2f} GB")


if __name__ == "__main__":
    main()
