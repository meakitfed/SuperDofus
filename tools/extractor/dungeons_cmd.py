"""P4.01: dungeons (dungeonsdataroot) -> game/worlds/<world>/dungeons.json, and the dungeon bosses
-> the "bosses" key of worlds/<world>/monsters.json (kept out of the spawn pools of the subareas).
Called by `gamedata.py dungeons <world>`. Worlds other than `dofus` get an empty file."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTENT = ROOT / "game" / "content" / "Content"
sys.path.insert(0, str(Path(__file__).parent))


def run(world: str) -> None:
    from spells import i18n_reader
    import maps
    folder = ROOT / "game" / "worlds" / world
    out = {}
    bosses = {}
    if world == "dofus":
        text = i18n_reader(CONTENT / "I18n" / "fr.bin")
        rows = json.loads((CONTENT / "Data" / "dungeonsdataroot.json").read_text(encoding="utf-8"))["objectsById"]
        monsters = maps._cached_table("monstersdataroot")
        for k, d in sorted(rows.items(), key=lambda kv: int(kv[0])):
            ids = [int(b) for b in d.get("bosses", [])]
            out[str(d["id"])] = {
                "id": int(d["id"]), "name": text(d["nameId"]), "level": int(d["optimalPlayerLevel"]),
                "min_level": int(d["minLevel"]), "difficulty": int(d["difficulty"]),
                "maps": [int(m) for m in d["mapIds"]], "entrance_map": int(d["entranceMapId"]),
                "exit_map": int(d["exitMapId"]),
                "keys": [{"item": int(o["id"]), "qty": int(o["quantity"])} for o in d.get("requiredObjects", [])],
                "bosses": ids}
            for b in ids:
                mo = monsters.get(str(b))
                if mo and mo.get("grades") and str(b) not in bosses:
                    bosses[str(b)] = {"name_id": int(mo["nameId"]), "race": int(mo.get("race", 0)),
                                      "grades": [maps.monster_member(mo, g["grade"]) for g in mo["grades"]]}
    (folder / "dungeons.json").write_text(json.dumps({"dungeons": out}, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
    print(f"  dungeons: {len(out)} -> {folder / 'dungeons.json'}")
    mpath = folder / "monsters.json"
    if bosses and mpath.exists():
        data = json.loads(mpath.read_text(encoding="utf-8"))
        data["bosses"] = bosses
        mpath.write_text(json.dumps(data, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
        print(f"  bosses: {len(bosses)} -> {mpath} (key `bosses`)")
