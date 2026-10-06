"""
Dofus 3 UI assets -> SuperDofus content.

    python ui.py fonts        # Content/Fonts/<name>.ttf (Lexend = the Dofus 3 UI font, Rowdies, Noto...)
    python ui.py textures hud # Content/UI/<theme path>.webp for textures whose path contains "hud"
    python ui.py portraits 540 547   # monster portraits by monster gfxId
    python ui.py classes      # Content/UI/classes: class heads (Head_<breed><sex>, small/big) and symbols
    python ui.py cosmetics    # Content/UI/cosmetics: face (heads.assetId) and body (bodies.assetId) thumbnails

The Dofus 3 UI is made with Unity UI Toolkit (UXML layouts + USS stylesheets in
uielements_assets_all.bundle, textures in uidarkstone/uiassets bundles).
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import UnityPy

sys.path.insert(0, str(Path(__file__).parent))
from extract import DEFAULT_GAME, detect_unity_version  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CONTENT = ROOT / "game" / "content" / "Content"
AA = DEFAULT_GAME / "Dofus_Data" / "StreamingAssets" / "aa" / "StandaloneWindows64"


def fonts() -> None:
    out = CONTENT / "Fonts"
    out.mkdir(parents=True, exist_ok=True)
    env = UnityPy.load(str(AA / "uielements_assets_all.bundle"))
    for o in env.objects:
        if o.type.name == "Font":
            f = o.read()
            data = bytes(f.m_FontData or b"")
            if data:
                ext = "otf" if data[:4] == b"OTTO" else "ttf"
                (out / f"{f.m_Name}.{ext}").write_bytes(data)
                print(f"  font {f.m_Name}.{ext} ({len(data) // 1024} KB)")


def portraits(gfx_ids: set[int]) -> None:
    """Monster portraits (Picto/Monsters, keyed by the monster's gfxId) -> Content/Picto/Monsters/<gfx>.webp."""
    out = CONTENT / "Picto" / "Monsters"
    out.mkdir(parents=True, exist_ok=True)
    env = UnityPy.load(str(DEFAULT_GAME / "Dofus_Data/StreamingAssets/Content/Picto/Monsters/monster_assets_1x.bundle"))
    wanted = {str(g) for g in gfx_ids}
    n = 0
    for path, ptr in env.container.items():
        name = path.rsplit("/", 1)[-1].rsplit(".", 1)[0]
        if name in wanted:
            obj = ptr.deref()
            if obj.type.name in ("Texture2D", "Sprite"):
                obj.read().image.save(out / f"{name}.webp", lossless=True, quality=0, method=0, exact=True)
                n += 1
    print(f"  monster portraits: {n}/{len(wanted)}")


def textures(pattern: str) -> None:
    n = 0
    for bundle in ("uidarkstone_assets_all.bundle", "uiassets_assets_1x.bundle"):
        env = UnityPy.load(str(AA / bundle))
        for path, ptr in env.container.items():
            if pattern.lower() not in path.lower() or not path.endswith((".png", ".jpg")):
                continue
            obj = ptr.deref()
            if obj.type.name not in ("Texture2D", "Sprite"):
                continue
            rel = path.split("/Themes/", 1)[-1].rsplit(".", 1)[0]
            dst = CONTENT / "UI" / f"{rel}.webp"
            dst.parent.mkdir(parents=True, exist_ok=True)
            obj.read().image.save(dst, lossless=True, quality=0, method=0, exact=True)
            n += 1
    print(f"  {n} textures matching '{pattern}' -> {CONTENT / 'UI'}")


def classes() -> None:
    """Class art (Picto/UI/class_assets_*): heads/small/1x/Head_<breed*10+sex>, heads/big/Head_..,
    symbol_<breed> -> Content/UI/classes/<same path>.webp (character selection and creation)."""
    n = 0
    for bundle in ("class_assets_1x.bundle", "class_assets_.bundle"):
        env = UnityPy.load(str(DEFAULT_GAME / "Dofus_Data/StreamingAssets/Content/Picto/UI" / bundle))
        for path, ptr in env.container.items():
            rel = path.split("/classes/", 1)[-1].rsplit(".", 1)[0]
            if not (rel.startswith("heads/") or rel.startswith("symbol_")):
                continue
            obj = ptr.deref()
            if obj.type.name not in ("Texture2D", "Sprite"):
                continue
            dst = CONTENT / "UI" / "classes" / f"{rel}.webp"
            dst.parent.mkdir(parents=True, exist_ok=True)
            obj.read().image.save(dst, lossless=True, quality=0, method=0, exact=True)
            n += 1
    print(f"  {n} class textures -> {CONTENT / 'UI' / 'classes'}")


def cosmetics() -> None:
    """Character creation thumbnails (Picto/UI/cosmetic_assets_*): cosmetics/1x/<heads.assetId>
    (faces) and cosmetics/body/<bodies.assetId> -> Content/UI/cosmetics/{faces,bodies}/<assetId>.webp."""
    n = 0
    for bundle, folder, dst_dir in (("cosmetic_assets_1x.bundle", "/cosmetics/1x/", "faces"),
                                    ("cosmetic_assets_.bundle", "/cosmetics/body/", "bodies")):
        env = UnityPy.load(str(DEFAULT_GAME / "Dofus_Data/StreamingAssets/Content/Picto/UI" / bundle))
        for path, ptr in env.container.items():
            if folder not in path:
                continue
            obj = ptr.deref()
            if obj.type.name not in ("Texture2D", "Sprite"):
                continue
            dst = CONTENT / "UI" / "cosmetics" / dst_dir / (path.rsplit("/", 1)[-1].rsplit(".", 1)[0] + ".webp")
            dst.parent.mkdir(parents=True, exist_ok=True)
            obj.read().image.save(dst, lossless=True, quality=0, method=0, exact=True)
            n += 1
    print(f"  {n} cosmetic thumbnails -> {CONTENT / 'UI' / 'cosmetics'}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("fonts")
    p = sub.add_parser("portraits")
    p.add_argument("gfx", nargs="+", type=int)
    t = sub.add_parser("textures")
    t.add_argument("pattern")
    sub.add_parser("classes")
    sub.add_parser("cosmetics")
    args = ap.parse_args()
    UnityPy.config.FALLBACK_UNITY_VERSION = detect_unity_version(DEFAULT_GAME)
    if args.cmd == "fonts":
        fonts()
    elif args.cmd == "cosmetics":
        cosmetics()
    elif args.cmd == "classes":
        classes()
    elif args.cmd == "portraits":
        portraits(set(args.gfx))
    else:
        textures(args.pattern)


if __name__ == "__main__":
    main()
