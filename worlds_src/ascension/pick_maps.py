"""Choose the maps of one floor of L'Ascension: a connected group of real Dofus outdoor maps.

    python worlds_src/ascension/pick_maps.py <start map> <subarea>[,<subarea>...] [--max 15]
    python worlds_src/ascension/pick_maps.py --subarea 444      # the outdoor maps of a subarea, with coordinates

It walks the real neighbour links (game/worlds/dofus/maps) from the start map, staying inside the given subareas and
outdoors, nearest first, and stops at --max maps. It prints the ids (to paste into recipe.json) and an ASCII grid of
their coordinates. Only a helper for writing the recipe: the build never runs it.
"""
import argparse
import json
import sys
from collections import deque
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MAPS = ROOT / "game" / "worlds" / "dofus" / "maps"
SUBAREAS = ROOT / "game" / "content" / "Content" / "Data" / "subareasdataroot.json"
SIDES = ("top", "bottom", "left", "right")


def load(mid: int) -> dict | None:
    f = MAPS / f"{mid}.json"
    return json.loads(f.read_text(encoding="utf-8")) if f.exists() else None


def subarea_maps(sub: int) -> list[int]:
    rows = json.loads(SUBAREAS.read_text(encoding="utf-8"))["objectsById"]
    return [int(m) for m in rows[str(sub)]["mapIds"]]


def outdoor(m: dict | None) -> bool:
    """An outdoor map linked to at least one other (isolated ones carry placeholder coordinates)."""
    return m is not None and m.get("world_map", -1) != -1 and any(m.get("neighbors", {}).values())


def walk(start: int, subs: set[int], cap: int) -> list[dict]:
    seen, out, todo = {start}, [], deque([start])
    while todo and len(out) < cap:
        m = load(todo.popleft())
        if not outdoor(m) or m["subarea"] not in subs:
            continue
        out.append(m)
        for s in SIDES:
            n = int(m.get("neighbors", {}).get(s, 0) or 0)
            if n and n not in seen:
                seen.add(n)
                todo.append(n)
    return out


def grid(maps: list[dict]) -> str:
    at = {tuple(m["coords"]): m for m in maps}
    xs = [c[0] for c in at]
    ys = [c[1] for c in at]
    lines = []
    for y in range(min(ys), max(ys) + 1):
        lines.append(" ".join(("#" if (x, y) in at else ".") for x in range(min(xs), max(xs) + 1)) + f"   y={y}")
    lines.append(f"x = {min(xs)}..{max(xs)}")
    return "\n".join(lines)


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser()
    ap.add_argument("start", nargs="?", type=int)
    ap.add_argument("subareas", nargs="?")
    ap.add_argument("--max", type=int, default=15)
    ap.add_argument("--subarea", type=int, help="list the outdoor maps of one subarea")
    a = ap.parse_args()
    if a.subarea is not None:
        maps = [m for m in map(load, subarea_maps(a.subarea)) if outdoor(m)]
        for m in sorted(maps, key=lambda m: (m["coords"][1], m["coords"][0])):
            ns = {s: n for s, n in m.get("neighbors", {}).items() if n}
            print(m["id"], m["coords"], "zaap" if m.get("zaap", -1) >= 0 else "", ns)
        print(grid(maps) if maps else "aucune map d'extérieur")
        return
    maps = walk(a.start, {int(s) for s in a.subareas.split(",")}, a.max)
    print(json.dumps([m["id"] for m in maps]))
    print(grid(maps))


if __name__ == "__main__":
    main()
