"""
SuperDofus content extractor.

Converts Dofus 3 (Unity) asset bundles into the neutral on-disk layout consumed by
the Godot renderer (same layout as PyDofus/d3-ts-renderer):

    <out>/Content/Characters/Bones/<bone>/bone.json, skin.json, <i>.png, <anim>.dat
    <out>/Content/Characters/Skins/<skin>/skin.json, <i>.png
    <out>/Content/Animations/Props/<prop>/...      (same as bones)
    <out>/Content/Data/<name>.json                 ({"objectsById": {...}})

Textures are written exactly as stored in the bundle (vertically flipped): the mesh
UVs expect that orientation.
"""
from __future__ import annotations

import argparse
import concurrent.futures as cf
import glob
import json
import os
import shutil
import sys
import warnings
from pathlib import Path

import UnityPy
from UnityPy.export.Texture2DConverter import get_image_from_texture2d

warnings.filterwarnings("ignore")

DEFAULT_GAME = Path(os.environ.get("LOCALAPPDATA", "")) / "Ankama" / "Dofus-dofus3"
STREAMING = Path("Dofus_Data") / "StreamingAssets" / "Content"
# renderer rules + catalogs used by the look viewer (heads, items, monsters, mounts)
DATA_TABLES = ("bodiesdataroot", "breedsdataroot", "skinslotsrulesdataroot", "soundbonesdataroot",
               "headsdataroot", "itemsdataroot", "itemtypesdataroot", "monstersdataroot", "mountsdataroot",
               "mountbonesdataroot")
# never fill the disk: stop extracting data tables below this much free space
MIN_FREE_BYTES = 2 * 1024 ** 3


def detect_unity_version(game: Path) -> str:
    """Read the engine version string from globalgamemanagers (bundles strip it)."""
    ggm = game / "Dofus_Data" / "globalgamemanagers"
    try:
        with ggm.open("rb") as f:
            head = f.read(256)
        # serialized file header (v22+): the version string starts at 0x30
        return head[0x30:head.index(b"\x00", 0x30)].decode("ascii")
    except (OSError, ValueError):
        return "6000.3.16f1"


_UNSAFE = '<>:"/\\|?*'


def safe_file_name(name: str) -> str:
    """Animation names may hold characters Windows forbids (e.g. 'AnimMarche_*1'):
    percent-encode them. The Godot loader applies the same rule."""
    return "".join(f"%{ord(c):02X}" if c in _UNSAFE or c == "%" else c for c in name)


def _container_entry(env, key: str):
    items = dict(env.container.items())
    return items[key] if key in items else next(iter(items.values()))


class Extractor:
    def __init__(self, game: Path, out: Path, image_ext: str = "png", overwrite: bool = False):
        self.src = game / STREAMING
        self.out = out / "Content"
        self.image_ext = image_ext
        self.overwrite = overwrite
        if not self.src.exists():
            raise SystemExit(f"Dofus content not found: {self.src}")

    # ── skins / bones ─────────────────────────────────────────────────────────────

    def _write_skin(self, obj, output: Path) -> None:
        skin = obj.parse_as_dict()
        for nb, ref in enumerate(skin["textures"]):
            path_id = ref["m_PathID"]
            if path_id in obj.assets_file.files:
                texture = obj.assets_file.files[path_id].read()
                image = get_image_from_texture2d(texture, False)
                if self.image_ext == "webp":
                    # lossless, fast; exact keeps transparent texels' RGB (linear filtering reads them)
                    image.save(output / f"{nb}.webp", lossless=True, quality=0, method=0, exact=True)
                else:
                    image.save(output / f"{nb}.png", optimize=False)
        for key in ("m_GameObject", "m_Script"):
            skin.pop(key, None)
        skin["textures"] = [{} for _ in skin["textures"]]
        (output / "skin.json").write_text(json.dumps(skin, separators=(",", ":")), encoding="utf-8")

    def bone(self, name: str, is_prop: bool = False) -> bool:
        name = name.lower()
        if is_prop:
            bundle = self.src / "Animations" / "Props" / f"props_assets_prop_{name}.bundle"
            output = self.out / "Animations" / "Props" / name
        else:
            bundle = self.src / "Characters" / "Bones" / f"bones_assets_bone_{name}.bundle"
            output = self.out / "Characters" / "Bones" / name
        if (output / "bone.json").exists() and not self.overwrite:
            return True
        if not bundle.exists():
            print(f"  ! missing bundle {bundle.name}", file=sys.stderr)
            return False
        env = UnityPy.load(str(bundle))
        pointer = _container_entry(env, f"{name}.asset")
        bone = pointer.deref_parse_as_dict()
        output.mkdir(parents=True, exist_ok=True)
        skin_obj = env.assets[0].files[bone["boneAsset"]["m_PathID"]]
        self._write_skin(skin_obj, output)
        for anim in bone["animations"]:
            (output / f'{safe_file_name(anim["name"])}.dat').write_bytes(bytes(anim["dataBytes"]))
            del anim["dataBytes"]
            anim.pop("data", None)
            # NaN bounds are not valid JSON: normalise to null
            b = anim.get("bounds") or {}
            if any(v != v for v in b.values()):
                anim["bounds"] = None
        for key in ("m_GameObject", "m_Script", "boneAsset"):
            bone.pop(key, None)
        for g in bone["graphics"]:
            g.pop("asset", None)
        (output / "bone.json").write_text(json.dumps(bone, separators=(",", ":")), encoding="utf-8")
        return True

    def skin(self, skin_id: str) -> bool:
        bundle = self.src / "Characters" / "Skins" / f"skins_assets_skin_{skin_id}.bundle"
        output = self.out / "Characters" / "Skins" / str(skin_id)
        if (output / "skin.json").exists() and not self.overwrite:
            return True
        if not bundle.exists():
            print(f"  ! missing bundle {bundle.name}", file=sys.stderr)
            return False
        env = UnityPy.load(str(bundle))
        pointer = _container_entry(env, f"{skin_id}.asset")
        output.mkdir(parents=True, exist_ok=True)
        self._write_skin(pointer.deref(), output)
        return True

    # ── datacenter ────────────────────────────────────────────────────────────────

    def list_tables(self) -> list[str]:
        prefix, suffix = "data_assets_", ".asset.bundle"
        return sorted(p.name[len(prefix):-len(suffix)] for p in (self.src / "Data").glob(f"{prefix}*{suffix}"))

    def data(self, table: str) -> bool | None:
        """Exports one table. Incremental: None (skipped) when the JSON is newer
        than its bundle, unless --overwrite."""
        folder = self.src / "Data"
        bundle = folder / f"data_assets_{table}.asset.bundle"
        if not bundle.exists():
            print(f"  ! missing bundle {bundle.name}", file=sys.stderr)
            return False
        output = self.out / "Data" / f"{table}.json"
        if not self.overwrite and output.exists() and output.stat().st_mtime >= bundle.stat().st_mtime:
            return None
        free = shutil.disk_usage(self.out.parent if self.out.parent.exists() else Path.cwd()).free
        if free < MIN_FREE_BYTES:
            raise SystemExit(f"Not enough free disk space ({free // 1024 ** 2} MB): stopped before {table}")
        files = [str(bundle)] + glob.glob(str(folder / "*monoscripts*.bundle"))
        env = UnityPy.load(*files)
        root = next(iter(env.container.values())).deref().parse_as_dict()
        refs = {r["rid"]: r["data"] for r in root.get("references", {}).get("RefIds", [])}

        def resolve(value):
            if isinstance(value, dict):
                if set(value.keys()) == {"rid"}:
                    return resolve(refs.get(value["rid"]))
                return {k: resolve(v) for k, v in value.items()}
            if isinstance(value, list):
                return [resolve(v) for v in value]
            return value

        by_id = root["objectsById"]
        objects = {str(k): resolve(v) for k, v in zip(by_id["m_keys"], by_id["m_values"])}
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps({"objectsById": objects}, separators=(",", ":")), encoding="utf-8")
        return True

    def write_family_index(self) -> None:
        """Bones split over several bundles (player bone 1: 1-static, 1-movement, 1-<breed>-combat...)
        are indexed in Bones/families.json: {family: {bundle: [anim names]}} so the renderer can
        find which bundle holds an animation without opening every bone.json."""
        root = self.out / "Characters" / "Bones"
        families: dict[str, dict[str, list[str]]] = {}
        for folder in sorted(root.glob("*-*")):
            bone_json = folder / "bone.json"
            if not bone_json.exists():
                continue
            anims = [a["name"] for a in json.loads(bone_json.read_text(encoding="utf-8"))["animations"]]
            families.setdefault(folder.name.split("-")[0], {})[folder.name] = anims
        (root / "families.json").write_text(json.dumps(families, separators=(",", ":")), encoding="utf-8")

    # ── listing ───────────────────────────────────────────────────────────────────

    def list_bones(self) -> list[str]:
        prefix = "bones_assets_bone_"
        return sorted(p.name[len(prefix):-len(".bundle")] for p in (self.src / "Characters" / "Bones").glob(f"{prefix}*.bundle"))

    def list_skins(self) -> list[str]:
        prefix = "skins_assets_skin_"
        return sorted(p.name[len(prefix):-len(".bundle")] for p in (self.src / "Characters" / "Skins").glob(f"{prefix}*.bundle"))

    def list_props(self) -> list[str]:
        prefix = "props_assets_prop_"
        return sorted(p.name[len(prefix):-len(".bundle")] for p in (self.src / "Animations" / "Props").glob(f"{prefix}*.bundle"))


# Worker entry point (process pool): one Extractor per process.
_worker: Extractor | None = None


def _init_worker(game: str, out: str, ext: str, overwrite: bool, version: str) -> None:
    global _worker
    UnityPy.config.FALLBACK_UNITY_VERSION = version
    _worker = Extractor(Path(game), Path(out), ext, overwrite)


def _run(job: tuple[str, str]) -> tuple[str, str, bool, str]:
    kind, name = job
    try:
        if kind == "bone":
            ok = _worker.bone(name)
        elif kind == "prop":
            ok = _worker.bone(name, is_prop=True)
        else:
            ok = _worker.skin(name)
        return kind, name, ok, ""
    except Exception as exc:  # keep going on corrupted/unsupported bundles
        return kind, name, False, repr(exc)


def split_list(values: list[str] | None) -> list[str]:
    out: list[str] = []
    for v in values or []:
        out.extend(x.strip() for x in v.split(",") if x.strip())
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description="Extract Dofus 3 bones/skins/data for the SuperDofus Godot renderer.")
    ap.add_argument("--game", type=Path, default=DEFAULT_GAME, help="Dofus 3 install folder")
    ap.add_argument("--out", type=Path, default=Path(__file__).resolve().parents[2] / "game" / "content")
    ap.add_argument("--bones", nargs="*", help="bone names (e.g. 1-static 1-movement 151); comma or space separated")
    ap.add_argument("--skins", nargs="*", help="skin ids")
    ap.add_argument("--props", nargs="*", help="map prop animation names")
    ap.add_argument("--data", action="store_true", help="extract datacenter tables (bodies, breeds, skin slots...)")
    ap.add_argument("--tables", nargs="*", help="datacenter tables to export (e.g. questsdataroot npcsdataroot), "
                    "or 'all'; incremental (skips up-to-date tables unless --overwrite)")
    ap.add_argument("--player", action="store_true", help="all player bones (1-*)")
    ap.add_argument("--all", action="store_true", help="every bone, skin, prop and data table")
    ap.add_argument("--all-bones", action="store_true")
    ap.add_argument("--all-skins", action="store_true")
    ap.add_argument("--all-props", action="store_true")
    ap.add_argument("--webp", action="store_true", help="write lossless WebP instead of PNG (~40%% smaller, recommended)")
    ap.add_argument("--overwrite", action="store_true")
    ap.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) - 1))
    ap.add_argument("--list", choices=["bones", "skins", "props", "tables"], help="print available names and exit")
    args = ap.parse_args()

    version = detect_unity_version(args.game)
    UnityPy.config.FALLBACK_UNITY_VERSION = version
    ext = "webp" if args.webp else "png"
    ex = Extractor(args.game, args.out, ext, args.overwrite)

    if args.list == "tables":
        print("\n".join(ex.list_tables()))
        return
    if args.list:
        print("\n".join(getattr(ex, f"list_{args.list}")()))
        return

    bones = split_list(args.bones)
    skins = split_list(args.skins)
    props = split_list(args.props)
    if args.player:
        bones += [b for b in ex.list_bones() if b.startswith("1-")]
    if args.all:
        args.all_bones = args.all_skins = args.all_props = args.data = True
    if args.all_bones:
        bones = ex.list_bones()
    if args.all_skins:
        skins = ex.list_skins()
    if args.all_props:
        props = ex.list_props()
    tables = list(DATA_TABLES) if args.data else []
    wanted = split_list(args.tables)
    tables += ex.list_tables() if "all" in wanted else [t if t.endswith("dataroot") else t + "dataroot" for t in wanted]
    tables = list(dict.fromkeys(tables))
    if not (bones or skins or props or tables):
        ap.print_help()
        return

    print(f"Unity {version} | {len(bones)} bones, {len(skins)} skins, {len(props)} props -> {args.out}")
    for table in tables:
        try:
            result = ex.data(table)
        except SystemExit:
            raise
        except Exception as e:  # one broken table must not stop the others
            print(f"  ! data {table} failed: {e}", file=sys.stderr)
            continue
        print(f"  data {table}: {'up to date' if result is None else 'ok' if result else 'FAILED'}")

    # the reference renderer falls back to bone 666 when a bone is missing
    if bones and "666" not in bones:
        bones.append("666")

    jobs = [("bone", b) for b in dict.fromkeys(bones)] + [("skin", s) for s in dict.fromkeys(skins)] + \
           [("prop", p) for p in dict.fromkeys(props)]
    failed = 0
    if len(jobs) <= 4 or args.jobs <= 1:
        _init_worker(str(args.game), str(args.out), ext, args.overwrite, version)
        results = map(_run, jobs)
    else:
        pool = cf.ProcessPoolExecutor(args.jobs, initializer=_init_worker,
                                      initargs=(str(args.game), str(args.out), ext, args.overwrite, version))
        results = pool.map(_run, jobs, chunksize=8)
    for i, (kind, name, ok, err) in enumerate(results, 1):
        if not ok:
            failed += 1
            print(f"  ! {kind} {name} failed {err}", file=sys.stderr)
        if i % 200 == 0 or i == len(jobs):
            print(f"  {i}/{len(jobs)}")
    if bones:
        ex.write_family_index()
    print(f"done ({failed} failed)")


if __name__ == "__main__":
    main()
