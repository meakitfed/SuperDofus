"""
Dofus 3 maps -> SuperDofus content + worlds.

    python maps.py index                      # Content/Maps/index.json : map id -> data bundle
    python maps.py extract 154010883 ...      # map visuals: Content/Maps/<id>.json + Gfx/<gfxId>.webp (+ animated props)
    python maps.py world incarnam --center 154010883 --radius 1
                                              # a playable world (game/worlds/<name>/) built from real maps:
                                              # cells, exits, fight placement, monster groups of the subarea
    python maps.py world incarnam --center 154010373 --area 45
                                              # every outdoor map of an area (areas.id) linked to the centre
                                              # + the interiors and door triggers of game/worlds/<name>/links.json
    python maps.py full dofus                 # every map of the client as one world (resumable, ~1-2 h, a few GB)
    python maps.py i18n                       # Content/I18n/<lang>.bin (names of monsters, areas, spells...)
    python maps.py worldmap 2 [--zoom 1]      # world map tiles: Content/Worldmaps/<id>/<zoom>/<n>.webp
                                              # (n = 1.. row-major, 1024 px; worldmaps table for the layout)

Map visual format (Content/Maps/<id>.json), positions already converted to the
renderer's screen space (cell 0 centre = (0, 0), y down):
    {"id", "bg": 0xAARRGGBB, "neighbors": {"top", "bottom", "left", "right"},
     "cells": [[flags...] x 560], "layers": {"background": [el], "sortable": [el], "foreground": [el]},
     "animated": [el + {"anim": prop name}]}
    el = {"g": gfxId, "c": 0xAARRGGBB tint (0x80 = neutral), "t": [a, b, c, d, x, y] screen affine,
          "cell": cellId (sortable only), "o": inner cell order, "m": blend ("add"...)}
The Unity map space has its origin at the centre of the cell grid, y up:
    screen = (unity_x + ORIGIN_X, ORIGIN_Y - unity_y)
"""
from __future__ import annotations

import argparse
import collections
import json
import os
import random
import shutil
import sys
from pathlib import Path

import UnityPy

sys.path.insert(0, str(Path(__file__).parent))
from extract import DEFAULT_GAME, Extractor, detect_unity_version  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CONTENT = ROOT / "game" / "content" / "Content"
WORLDS = ROOT / "game" / "worlds"
# centre of the grid of cell centres (cells 0..559: x 0..1161, y 0..838.5)
ORIGIN_X = 580.5
ORIGIN_Y = 419.25
LAYERS = (("background", "backgroundElements"), ("sortable", "sortableElements"), ("foreground", "foregroundElements"))
CELL_FLAGS = ("mov", "los", "nonWalkableDuringFight", "nonWalkableDuringRP", "red", "blue", "visible", "floor",
              "mapChangeData", "farmCell", "havenbagCell")
# Unity BlendMode factors -> Godot-ish modes (ShaderBlendingParameters)
BLEND_ONE, BLEND_SRC_ALPHA, BLEND_DST_COLOR = 1, 5, 2


class MapExtractor:
    def __init__(self, game: Path = DEFAULT_GAME):
        UnityPy.config.FALLBACK_UNITY_VERSION = detect_unity_version(game)
        self.game = game
        self.src = game / "Dofus_Data" / "StreamingAssets" / "Content"
        self.gfx_bundles = sorted(int(p.name.split("_")[2]) for p in (self.src / "Map" / "Textures" / "1x").glob("mapgfx_1x_*_assets_all.bundle"))
        self._index: dict[str, str] | None = None

    # ── index ───────────────────────────────────────────────────────────────────

    def build_index(self) -> dict[str, str]:
        index = {}
        bundles = sorted((self.src / "Map" / "Data").glob("mapdata_assets_*.bundle"))
        for i, bundle in enumerate(bundles, 1):
            env = UnityPy.load(str(bundle))
            for key in env.container.keys():
                name = key.rsplit("/", 1)[-1]
                if name.startswith("map_") and name.endswith(".asset"):
                    index[name[4:-6]] = bundle.name
            if i % 50 == 0:
                print(f"  {i}/{len(bundles)} bundles, {len(index)} maps")
        out = CONTENT / "Maps" / "index.json"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(index, separators=(",", ":")), encoding="utf-8")
        self._index = index
        print(f"{len(index)} maps indexed -> {out}")
        return index

    def index(self) -> dict[str, str]:
        if self._index is None:
            path = CONTENT / "Maps" / "index.json"
            self._index = json.loads(path.read_text(encoding="utf-8")) if path.exists() else self.build_index()
        return self._index

    # ── raw map ─────────────────────────────────────────────────────────────────

    def raw_maps(self, ids: list[int]) -> dict[int, dict]:
        """Parsed map MonoBehaviours, grouped by bundle to open each bundle once."""
        by_bundle = collections.defaultdict(set)
        for i in ids:
            b = self.index().get(str(i))
            if b is None:
                print(f"  ! map {i} not found", file=sys.stderr)
            else:
                by_bundle[b].add(i)
        out = {}
        for bundle, wanted in by_bundle.items():
            env = UnityPy.load(str(self.src / "Map" / "Data" / bundle))
            for key, ptr in env.container.items():
                name = key.rsplit("/", 1)[-1]
                if name.startswith("map_") and int(name[4:-6]) in wanted:
                    out[int(name[4:-6])] = ptr.deref_parse_as_dict()
        return out

    # ── conversion ──────────────────────────────────────────────────────────────

    @staticmethod
    def _refs(raw: dict) -> dict:
        return {r["rid"]: r for r in raw.get("references", {}).get("RefIds", [])}

    @staticmethod
    def _affine(t: dict) -> list[float]:
        # Unity row-vector matrix [[m11, m12], [m21, m22]] + (m31, m32), y up -> screen (y down):
        # x axis image = (m11, -m12), y axis image = (-m21, m22)
        return [t["m11"], -t["m12"], -t["m21"], t["m22"], t["m31"] + ORIGIN_X, ORIGIN_Y - t["m32"]]

    def _blend(self, material_data: dict, index: int, refs: dict) -> str:
        shaders = material_data.get("shaderData", [])
        if index >= len(shaders):
            return ""
        shader = refs.get(shaders[index]["rid"], {}).get("data") or {}
        for p in shader.get("shaderParameters", []):
            ref = refs.get(p["rid"], {})
            if ref.get("type", {}).get("class") == "ShaderBlendingParameters":
                d = ref["data"]
                src, dst = d["sourceFactor"], d["destinationFactor"]
                if dst == BLEND_ONE:
                    return "add"
                if src == BLEND_DST_COLOR:
                    return "mul"
                return f"blend_{src}_{d['blendOperation']}_{dst}"
        return ""

    def convert(self, map_id: int, raw: dict) -> dict:
        md = raw["mapData"]
        refs = self._refs(raw)
        layers = {}
        for name, key in LAYERS:
            material = md.get(f"{name}MaterialData", {})
            els = []
            for e in md[key]:
                el = {"g": e["gfxId"], "c": e["color"]["value"], "t": self._affine(e["transform"])}
                if "cellId" in e:
                    el["cell"] = e["cellId"]
                    el["o"] = e.get("innerCellRenderOrder", 0)
                blend = self._blend(material, e["materialIndex"], refs)
                if blend:
                    el["m"] = blend
                els.append(el)
            if name == "sortable":
                # interactive elements (doors, harvestables...) are sortable elements too
                for r in md.get("interactiveElements", []):
                    e = refs.get(r["rid"], {}).get("data")
                    if e and "gfxId" in e and "transform" in e and e.get("type") is None:
                        els.append({"g": e["gfxId"], "c": e["color"]["value"], "t": self._affine(e["transform"]),
                                    "cell": e.get("cellId", 0), "o": e.get("innerCellRenderOrder", 0)})
                els.sort(key=lambda el: (el["cell"], el["o"]))
            layers[name] = els
        animated = []
        for e in md.get("animatedElements", []):
            animated.append({"g": e["gfxId"], "c": e["color"]["value"], "t": self._affine(e["transform"]),
                             "cell": e["cellId"], "o": e.get("innerCellRenderOrder", 0),
                             "play": e.get("playAnimation", 0), "min": e.get("minDelay", 0), "max": e.get("maxDelay", 0)})
        for r in md.get("interactiveElements", []):
            e = refs.get(r["rid"], {}).get("data")
            if e and "playAnimation" in e:
                animated.append({"g": e["gfxId"], "c": e["color"]["value"], "t": self._affine(e["transform"]),
                                 "cell": e["cellId"], "o": e.get("innerCellRenderOrder", 0),
                                 "play": e.get("playAnimation", 0), "min": e.get("minDelay", 0), "max": e.get("maxDelay", 0)})
        cells = [[int(c.get(f, 0)) for f in CELL_FLAGS] for c in sorted(md["cellsData"], key=lambda c: c["cellNumber"])]
        return {
            "id": map_id,
            "bg": md["backgroundColor"]["value"],
            "neighbors": {"top": md["topNeighbourId"], "bottom": md["bottomNeighbourId"],
                          "left": md["leftNeighbourId"], "right": md["rightNeighbourId"]},
            "cell_flags": list(CELL_FLAGS),
            "cells": cells,
            "layers": layers,
            "animated": animated,
        }

    # ── graphics ────────────────────────────────────────────────────────────────

    def extract_gfx(self, gfx_ids: set[int], overwrite: bool = False) -> None:
        out = CONTENT / "Maps" / "Gfx"
        out.mkdir(parents=True, exist_ok=True)
        todo = {g for g in gfx_ids if overwrite or not (out / f"{g}.webp").exists()}
        by_bundle = collections.defaultdict(set)
        for g in todo:
            base = max((b for b in self.gfx_bundles if b <= g), default=None)
            if base is not None:
                by_bundle[base].add(g)
        written = 0
        for base, wanted in sorted(by_bundle.items()):
            env = UnityPy.load(str(self.src / "Map" / "Textures" / "1x" / f"mapgfx_1x_{base}_assets_all.bundle"))
            textures, sprites = {}, {}
            for o in env.objects:
                if o.type.name not in ("Texture2D", "Sprite"):
                    continue
                name = o.peek_name()
                if not name.isdigit() or int(name) not in wanted:
                    continue
                (textures if o.type.name == "Texture2D" else sprites)[int(name)] = o
            for g, tex_obj in textures.items():
                tex = tex_obj.read()
                image = tex.image
                if g in sprites:
                    # crop to the sprite rect (textures may be padded); Unity rects start bottom-left
                    r = sprites[g].read().m_Rect
                    h = image.height
                    image = image.crop((int(r.x), int(h - r.y - r.height), int(r.x + r.width), int(h - r.y)))
                image.save(out / f"{g}.webp", lossless=True, quality=0, method=0, exact=True)
                written += 1
            missing = wanted - set(textures)
            if missing:
                print(f"  ! {len(missing)} gfx not in bundle {base}: {sorted(missing)[:5]}", file=sys.stderr)
        print(f"  gfx: {written} written, {len(gfx_ids) - len(todo)} already there")

    def extract(self, ids: list[int], overwrite: bool = False) -> dict[int, dict]:
        raws = self.raw_maps(ids)
        out = CONTENT / "Maps"
        out.mkdir(parents=True, exist_ok=True)
        gfx: set[int] = set()
        props: set[int] = set()
        maps = {}
        for map_id, raw in raws.items():
            m = self.convert(map_id, raw)
            maps[map_id] = m
            (out / f"{map_id}.json").write_text(json.dumps(m, separators=(",", ":")), encoding="utf-8")
            for layer in m["layers"].values():
                gfx.update(el["g"] for el in layer)
            props.update(el["g"] for el in m["animated"])
        self.extract_gfx(gfx, overwrite)
        if props:
            ex = Extractor(self.game, CONTENT.parent, "webp", overwrite)
            ok = [p for p in sorted(props) if ex.bone(str(p), is_prop=True)]
            print(f"  animated props: {len(ok)}/{len(props)}")
        print(f"{len(maps)} maps -> {out}")
        return maps

    # ── i18n ────────────────────────────────────────────────────────────────────

    def i18n(self, langs=("fr",)) -> None:
        out = CONTENT / "I18n"
        out.mkdir(parents=True, exist_ok=True)
        for lang in langs:
            shutil.copyfile(self.src / "I18n" / f"{lang}.bin", out / f"{lang}.bin")
            print(f"  i18n {lang} -> {out}")


# ── worlds ──────────────────────────────────────────────────────────────────────

def _load_table(name: str) -> dict:
    return json.loads((CONTENT / "Data" / f"{name}.json").read_text(encoding="utf-8"))["objectsById"]


_TABLES: dict = {}


def _cached_table(name: str) -> dict:
    if name not in _TABLES:
        _TABLES[name] = _load_table(name)
    return _TABLES[name]


MONSTER_SPELL = 1_000_000  # same as spells.py: monster spell id = MONSTER_SPELL + spell level id
# monsters.m_flags: bit 2 = boss, bit 3 = mini-boss (all 306 monsters named by a
# correspondingMiniBossId have bit 3; Bouftou Royal, the Incarnam crypt chief have bit 2)
MONSTER_BOSS = 1 << 2
MONSTER_MINI_BOSS = 1 << 3
# bits 9 / 10: canSwitchPos / canSwitchPosOnTarget (client code MonsterData getters, P1.13n)
MONSTER_CAN_SWITCH = 1 << 9
MONSTER_CAN_SWITCH_ON_TARGET = 1 << 10
# mapsinformation.m_flags = the Dofus 2 map capabilities (MapPosition.capabilities):
# bit 9 ALLOW_TAVERN_REGEN (only the Tavern in Incarnam), bit 13 ALLOW_MONSTER_RESPAWN
# (off on zaap maps and in the Tavern), bit 20 ALLOW_MONSTER_AGRESSION
MAP_TAVERN_REGEN = 1 << 9
MAP_MONSTER_RESPAWN = 1 << 13
MAP_MONSTER_AGGRESSION = 1 << 20
# bit 23: hasPriorityOnWorldmap (set on 421 of the 545 outdoor coordinates shared by several maps)
MAP_PRIORITY_BIT = 23
RES = {"earth": "earthResistance", "fire": "fireResistance", "water": "waterResistance",
       "air": "airResistance", "neutral": "neutralResistance"}


def monster_member(mo: dict, grade: int) -> dict:
    """One monster of a group at `grade` (1..5): its real stats, spells and drops.
    Kamas are not in the Dofus 3 data: [2 x level, 4 x level + 6] (approximation)."""
    grades = mo["grades"]
    g = grades[min(grade, len(grades)) - 1]
    spells_table = _cached_table("spellsdataroot")
    spells = []
    grade_specs = mo.get("spellGrades", [])
    for i, sid in enumerate(mo.get("spells", [])):
        sp = spells_table.get(str(sid))
        if not sp or not sp["spellLevels"]:
            continue
        # spellGrades[i] = "level,monsterGrade;..." per monster grade
        lvl = 1
        if i < len(grade_specs):
            parts = [p.split(",") for p in grade_specs[i].split(";") if "," in p and "null" not in p]
            for p in parts:
                if int(p[1]) == g["grade"]:
                    lvl = int(p[0])
        levels = sp["spellLevels"]
        spells.append(MONSTER_SPELL + int(levels[min(lvl, len(levels)) - 1]))
    drops = [{"item": int(d["objectId"]), "pct": round(float(d.get(f"percentDropForGrade{g['grade']}", 0)), 3)}
             for d in mo.get("drops", []) if not d.get("hasCriterions") and float(d.get(f"percentDropForGrade{g['grade']}", 0)) > 0]
    level = int(g["level"])
    flags = int(mo.get("m_flags", 0))
    # P1.13n: only written when false (FightEffects.can_swap), the default being true
    switch = {k: False for k, bit in (("switch", MONSTER_CAN_SWITCH), ("switch_on_target", MONSTER_CAN_SWITCH_ON_TARGET))
              if not flags & bit}
    return {**switch, "monster": int(mo["id"]), "name_id": int(mo["nameId"]), "look": mo["look"], "portrait": int(mo.get("gfxId", 0)),
            "grade": int(g["grade"]), "level": level, "hp": int(g["lifePoints"]),
            "ap": int(g["actionPoints"]), "mp": max(0, int(g["movementPoints"])), "xp": int(g.get("gradeXp", 0)),
            "stats": {"strength": g["strength"], "intelligence": g["intelligence"], "chance": g["chance"],
                      "agility": g["agility"], "wisdom": g["wisdom"], "ap_dodge": g["paDodge"], "mp_dodge": g["pmDodge"]},
            "res": {k: int(g[v]) for k, v in RES.items()},
            "spells": spells, "drops": drops,
            # APPROX(P1.09): monster kamas are server-side data, absent from the client
            "kamas": [2 * level, 4 * level + 6],
            # monsters.aggressive*: vision (cells), level gap, immunity criteria, delay (ms)
            "aggro": {"zone": int(mo.get("aggressiveZoneSize", 0)), "level_diff": int(mo.get("aggressiveLevelDiff", 0)),
                      "immunity": mo.get("aggressiveImmunityCriterion", ""), "delay": int(mo.get("aggressiveAttackDelay", 0))}}


def world_monsters(subarea_ids: set) -> dict:
    """monsters.json of a world: the monsters of its subareas (subareas.monsters)
    with their 5 grades; the sim composes the groups (MonsterSpawner).
    Bosses and mini-bosses are left out: they are not roaming groups."""
    subareas = _cached_table("subareasdataroot")
    monsters = _cached_table("monstersdataroot")
    out = {"subareas": {}, "monsters": {}}
    for sid in sorted(subarea_ids):
        sub = subareas.get(str(sid))
        if not sub:
            continue
        pool = []
        for mid in sub.get("monsters", []):
            mo = monsters.get(str(mid))
            if not mo or not mo.get("grades") or int(mo.get("m_flags", 0)) & (MONSTER_BOSS | MONSTER_MINI_BOSS):
                continue
            g = mo["grades"][0]
            if int(g.get("actionPoints", 0)) <= 0 or int(g.get("lifePoints", 0)) <= 0:
                continue
            pool.append(int(mid))
            if str(mid) not in out["monsters"]:
                out["monsters"][str(mid)] = {"name_id": int(mo["nameId"]), "race": int(mo.get("race", 0)),
                                             "grades": [monster_member(mo, gr["grade"]) for gr in mo["grades"]]}
        out["subareas"][str(sid)] = {"level": int(sub.get("level", 0)), "area": int(sub.get("areaId", 0)), "monsters": pool}
    return out


def build_world(mx: MapExtractor, name: str, center: int, radius: int, seed: int, max_groups: int, area: int = 0) -> None:
    """Walk the real neighbour links around `center` and turn those maps into a
    playable SuperDofus world: our MapData format + monsters.json (the monsters
    of its subareas: the sim spawns the groups, MonsterSpawner).
    area > 0: no radius, every map of that area reachable through the neighbour links
    (mapscrollactions overrides the map's own links when it has a row).
    Doors: world_doors (JondoEmu door destinations, element cells from the client maps)
    pull in the interiors of the area and give the triggers.
    links.json (hand written, server data with no other source; its triggers win over JondoEmu):
      {"interiors": [map ids], "triggers": [{"map", "cell", "to_map", "to_cell"}],
       "zaaps": {"<map id>": cell of the zaap}}   (waypoints.mapId says which maps have one)
       "phoenixes": {"<map id>": cell of the resurrection phoenix}}   (server data: no source)"""
    rng = random.Random(seed)
    folder = WORLDS / name
    links_path = folder / "links.json"
    links = json.loads(links_path.read_text(encoding="utf-8")) if links_path.exists() else {"interiors": [], "triggers": []}
    in_area: set[int] = set()
    if area:
        radius = 10 ** 6
        for s in _load_table("subareasdataroot").values():
            if s["areaId"] == area:
                in_area.update(s["mapIds"])
    scroll = _load_table("mapscrollactionsdataroot")
    seen = {center: (0, 0)}
    frontier = [center]
    raws = {}
    while frontier:
        batch = [m for m in frontier if m not in raws]
        raws.update(mx.raw_maps(batch))
        nxt = []
        for m in frontier:
            if m not in raws:
                continue
            x, y = seen[m]
            for dx, dy, d in ((0, -1, "top"), (0, 1, "bottom"), (-1, 0, "left"), (1, 0, "right")):
                n = _neighbour(raws[m], scroll.get(str(m)), d)
                p = (x + dx, y + dy)
                if area and n not in in_area:
                    continue
                if n > 0 and n not in seen and max(abs(p[0]), abs(p[1])) <= radius and str(n) in mx.index():
                    seen[n] = p
                    nxt.append(n)
        frontier = nxt
    doors = world_doors(mx, set(seen), in_area or set(seen))
    for m in doors:
        seen.setdefault(m, (0, 0))
    for m in links.get("interiors", []):
        seen.setdefault(int(m), (0, 0))
    ids = sorted(seen)
    print(f"world {name}: {len(ids)} maps {ids}")
    visuals = mx.extract(ids)
    raws = {**raws, **{m: r for m, r in mx.raw_maps([m for m in ids if m not in raws]).items()}}

    info = _cached_table("mapsinformationdataroot")
    waypoint_maps = {int(w["mapId"]) for w in _load_table("waypointsdataroot").values() if w.get("activated", 1)}
    zaap_cells = {int(k): int(v) for k, v in links.get("zaaps", {}).items()}
    phoenix_cells = {int(k): int(v) for k, v in links.get("phoenixes", {}).items() if int(k) in seen}
    for m in sorted(waypoint_maps & set(ids) - set(zaap_cells)):
        print(f"  ! map {m} has a zaap (waypoints) but no cell in links.json", file=sys.stderr)
    (folder / "maps").mkdir(parents=True, exist_ok=True)
    for old in (folder / "maps").glob("*.json"):
        old.unlink()
    triggers = collections.defaultdict(dict)
    for m, ds in doors.items():
        for d in ds:
            if d["to_map"] in seen:
                triggers[m][d["cell"]] = {"cell": d["cell"], "to_map": d["to_map"], "to_cell": d["to_cell"]}
    for t in links.get("triggers", []):
        triggers[int(t["map"])][int(t["cell"])] = {"cell": int(t["cell"]), "to_map": int(t["to_map"]), "to_cell": int(t["to_cell"])}
    triggers = {m: [ts[c] for c in sorted(ts)] for m, ts in triggers.items()}
    flags = {f: i for i, f in enumerate(CELL_FLAGS)}
    for m in ids:
        v = visuals[m]
        neighbors = {d: n for d in ("top", "bottom", "left", "right")
                     if (n := _neighbour(raws[m], scroll.get(str(m)), d)) in seen and n != m}
        data = sim_map(m, v["cells"], neighbors, _map_change(raws[m]), triggers.get(m, []),
                       zaap_cells.get(m, -1) if m in waypoint_maps else -1, phoenix_cells.get(m, -1), seen[m])
        (folder / "maps" / f"{m}.json").write_text(json.dumps(data, indent="\t"), encoding="utf-8")
    mons = world_monsters({int(info.get(str(m), {}).get("subAreaId", -1)) for m in ids})
    (folder / "monsters.json").write_text(json.dumps(mons, indent="\t"), encoding="utf-8")
    import ui
    ui.portraits({g["portrait"] for mo in mons["monsters"].values() for g in mo["grades"]})
    start_flags = visuals[center]["cells"]
    walkable = [i for i, c in enumerate(start_flags) if c[flags["mov"]] and not c[flags["nonWalkableDuringRP"]]]
    start_cell = min(walkable, key=lambda c: abs(c // 14 - 20) + abs(c % 14 - 7)) if walkable else 300
    (folder / "world.json").write_text(json.dumps({
        "id": name, "name": name.capitalize(), "start_map": center, "start_cell": start_cell,
        "wander_ms": [8000, 20000], "max_groups": max_groups, "maps": ids, "phoenixes": sorted(phoenix_cells),
    }, indent="\t"), encoding="utf-8")
    print(f"world written -> {folder}")
    import gamedata
    gamedata.experience()
    gamedata.items(name)


def _map_change(raw: dict) -> dict[str, int]:
    """cellsData.mapChangeData: bit i = the cell leads out in Dofus direction i (0 = east, clockwise)."""
    return {str(c["cellNumber"]): int(c["mapChangeData"]) for c in raw["mapData"]["cellsData"]
            if int(c.get("mapChangeData", 0))}


def sim_map(m: int, cells: list, neighbors: dict, map_change: dict, triggers: list, zaap: int, phoenix: int,
            coords: tuple[int, int] = (0, 0)) -> dict:
    """The sim's MapData dict of a map (game/worlds/<name>/maps/<id>.json) from its cell flags."""
    flags = {f: i for i, f in enumerate(CELL_FLAGS)}
    info = _cached_table("mapsinformationdataroot")
    subareas = _cached_table("subareasdataroot")
    areas = _cached_table("areasdataroot")
    mi = info.get(str(m), {})
    sub = subareas.get(str(mi.get("subAreaId", -1)), {})
    caps = int(mi.get("m_flags", 0))
    return {
        "id": m, "name": "", "subarea": int(mi.get("subAreaId", 0)), "subarea_name_id": int(sub.get("nameId", 0)),
        "area": int(sub.get("areaId", 0)), "outdoor": int(mi.get("worldMap", -1)) != -1,
        "area_name_id": int(areas.get(str(sub.get("areaId", -1)), {}).get("nameId", 0)),
        "map_change": map_change, "triggers": triggers,
        "zaap": zaap, "world_map": int(mi.get("worldMap", -1)),
        "coords": [int(mi.get("posX", coords[0])), int(mi.get("posY", coords[1]))],
        "visual": m, "neighbors": neighbors,
        "blocked": [i for i, c in enumerate(cells) if not c[flags["mov"]] or c[flags["nonWalkableDuringRP"]]],
        "fight_blocked": [i for i, c in enumerate(cells) if not c[flags["mov"]] or c[flags["nonWalkableDuringFight"]]],
        "los_blocked": [i for i, c in enumerate(cells) if not c[flags["los"]]],
        "placement": {"red": [i for i, c in enumerate(cells) if c[flags["red"]]],
                      "blue": [i for i, c in enumerate(cells) if c[flags["blue"]]]},
        "monster_spawn": bool(caps & MAP_MONSTER_RESPAWN), "monster_aggression": bool(caps & MAP_MONSTER_AGGRESSION),
        "tavern": bool(caps & MAP_TAVERN_REGEN), "phoenix": phoenix,
    }


def build_full_world(mx: MapExtractor, name: str, start_map: int, start_cell: int, max_groups: int,
                     links_from: str = "") -> None:
    """Every map of the client (Content/Maps/index.json) as one world: the visuals, the
    sim maps, the doors (world_doors' rules) and the monsters of every subarea.
    Streams bundle by bundle (a raw map is ~1 MB of Python objects) and is resumable:
    game/worlds/<name>/_build.jsonl records the finished bundles (delete it to start over).
    links.json of the world (or of `links_from`) gives zaap and phoenix cells, extra triggers."""
    folder = WORLDS / name
    (folder / "maps").mkdir(parents=True, exist_ok=True)
    links_path = folder / "links.json"
    if not links_path.exists() and links_from:
        shutil.copyfile(WORLDS / links_from / "links.json", links_path)
    links = json.loads(links_path.read_text(encoding="utf-8")) if links_path.exists() else {}
    scroll = _cached_table("mapscrollactionsdataroot")
    index = mx.index()
    waypoint_maps = {int(w["mapId"]) for w in _cached_table("waypointsdataroot").values() if w.get("activated", 1)}
    zaap_cells = {int(k): int(v) for k, v in links.get("zaaps", {}).items()}
    phoenix_cells = {int(k): int(v) for k, v in links.get("phoenixes", {}).items()}
    import jondo
    routes = {k: v for k, v in jondo.door_routes().items() if not v["criterion"]}
    door_maps = {m for m, _c in routes}
    progress = folder / "_build.jsonl"
    done: dict[str, dict] = {}
    if progress.exists():
        for line in progress.read_text(encoding="utf-8").splitlines():
            if line.strip():
                row = json.loads(line)
                done[row["bundle"]] = row
    by_bundle = collections.defaultdict(set)
    for k, b in index.items():
        by_bundle[b].add(int(k))
    bundles = sorted(by_bundle)
    visual_dir = CONTENT / "Maps"
    for i, bundle in enumerate(bundles, 1):
        if bundle in done:
            continue
        env = UnityPy.load(str(mx.src / "Map" / "Data" / bundle))
        gfx, props, inter, maps = set(), set(), {}, []
        for key, ptr in env.container.items():
            nm = key.rsplit("/", 1)[-1]
            if not (nm.startswith("map_") and nm.endswith(".asset")):
                continue
            m = int(nm[4:-6])
            try:
                raw = ptr.deref_parse_as_dict()
                v = mx.convert(m, raw)
            except Exception as ex:  # noqa: BLE001 - a broken map must not stop the whole world
                print(f"  ! map {m}: {ex}", file=sys.stderr)
                continue
            (visual_dir / f"{m}.json").write_text(json.dumps(v, separators=(",", ":")), encoding="utf-8")
            for layer in v["layers"].values():
                gfx.update(el["g"] for el in layer)
            props.update(el["g"] for el in v["animated"])
            if m in door_maps:
                inter[str(m)] = {str(k): c for k, c in _interactive_cells(raw).items()}
            neighbors = {d: n for d in ("top", "bottom", "left", "right")
                         if (n := _neighbour(raw, scroll.get(str(m)), d)) > 0 and n != m and str(n) in index}
            data = sim_map(m, v["cells"], neighbors, _map_change(raw), [],
                           zaap_cells.get(m, -1) if m in waypoint_maps else -1, phoenix_cells.get(m, -1))
            (folder / "maps" / f"{m}.json").write_text(json.dumps(data, separators=(",", ":")), encoding="utf-8")
            maps.append(m)
        row = {"bundle": bundle, "maps": maps, "gfx": sorted(gfx), "props": sorted(props), "inter": inter}
        with progress.open("a", encoding="utf-8") as f:
            f.write(json.dumps(row, separators=(",", ":")) + "\n")
        done[bundle] = row
        print(f"  {i}/{len(bundles)} {bundle}: {len(maps)} maps")
    ids = sorted(m for row in done.values() for m in row["maps"])
    print(f"world {name}: {len(ids)} maps")

    # doors: a JondoEmu route is kept when its element really stands on that cell (world_doors)
    inter = {int(m): {int(k): c for k, c in d.items()} for row in done.values() for m, d in row["inter"].items()}
    world = set(ids)
    triggers = collections.defaultdict(dict)
    for (m, c), r in routes.items():
        if m in world and r["to_map"] in world and inter.get(m, {}).get(r["element"]) == c:
            triggers[m][c] = {"cell": c, "to_map": r["to_map"], "to_cell": r["to_cell"]}
    for t in links.get("triggers", []):
        triggers[int(t["map"])][int(t["cell"])] = {"cell": int(t["cell"]), "to_map": int(t["to_map"]), "to_cell": int(t["to_cell"])}
    for m, ts in triggers.items():
        path = folder / "maps" / f"{m}.json"
        if path.exists():
            data = json.loads(path.read_text(encoding="utf-8"))
            data["triggers"] = [ts[c] for c in sorted(ts)]
            path.write_text(json.dumps(data, separators=(",", ":")), encoding="utf-8")
    print(f"  doors: {sum(len(ts) for ts in triggers.values())} on {len(triggers)} maps")

    mx.extract_gfx({g for row in done.values() for g in row["gfx"]})
    props = sorted({p for row in done.values() for p in row["props"]})
    if props:
        ex = Extractor(mx.game, CONTENT.parent, "webp", False)
        ok = [p for p in props if (CONTENT / "Animations" / "Props" / str(p)).exists() or ex.bone(str(p), is_prop=True)]
        print(f"  animated props: {len(ok)}/{len(props)}")

    info = _cached_table("mapsinformationdataroot")
    mons = world_monsters({int(info.get(str(m), {}).get("subAreaId", -1)) for m in ids})
    (folder / "monsters.json").write_text(json.dumps(mons, separators=(",", ":")), encoding="utf-8")
    import ui
    ui.portraits({g["portrait"] for mo in mons["monsters"].values() for g in mo["grades"]})
    (folder / "world.json").write_text(json.dumps({
        "id": name, "name": name.capitalize(), "start_map": start_map, "start_cell": start_cell,
        "wander_ms": [8000, 20000], "max_groups": max_groups, "maps": ids,
        "phoenixes": sorted(m for m in phoenix_cells if m in world),
    }, indent="\t"), encoding="utf-8")
    write_coords(name)
    print(f"world written -> {folder}")
    import gamedata
    gamedata.experience()
    gamedata.items(name)


def write_coords(name: str) -> None:
    """game/worlds/<name>/coords.json: "x,y" -> [[map id, world_map, outdoor, priority]] for the
    admin tp by coordinates (WorldSource.find_maps) without reading every map.
    priority = mapsinformation.m_flags bit 23 (hasPriorityOnWorldmap, as in Dofus 2 MapPosition):
    the map shown for these coordinates when several share them (old or transition maps)."""
    info = _cached_table("mapsinformationdataroot")
    out: dict[str, list] = {}
    for f in (WORLDS / name / "maps").glob("*.json"):
        d = json.loads(f.read_text(encoding="utf-8"))
        priority = bool(int(info.get(str(d["id"]), {}).get("m_flags", 0)) >> MAP_PRIORITY_BIT & 1)
        out.setdefault("%d,%d" % tuple(d["coords"]), []).append([d["id"], d["world_map"], d["outdoor"], priority])
    (WORLDS / name / "coords.json").write_text(json.dumps(out, separators=(",", ":")), encoding="utf-8")
    print(f"  coords: {len(out)} positions")


def _interactive_cells(node, out: dict | None = None) -> dict[int, int]:
    """Interactive elements of a raw map (client data): m_interactionId -> cellId."""
    out = {} if out is None else out
    if isinstance(node, dict):
        if "m_interactionId" in node and "cellId" in node and int(node["m_interactionId"]) > 0:
            out.setdefault(int(node["m_interactionId"]), int(node["cellId"]))
        for v in node.values():
            _interactive_cells(v, out)
    elif isinstance(node, list):
        for v in node:
            _interactive_cells(v, out)
    return out


def world_doors(mx: MapExtractor, maps: set[int], area_maps: set[int]) -> dict[int, list[dict]]:
    """Doors of a world (roadmap P1.07b): map -> [{cell, to_map, to_cell, src}].
    Destinations are server data: JondoEmu (jondo.door_routes), doors with a criterion
    (quests...) left out. A door is kept when its element really stands on that cell in
    the client map. Interiors of the area reached through doors join the world; one
    with no door leading back into the world is left out (repeated until stable)."""
    import jondo
    routes = {k: v for k, v in jondo.door_routes().items() if not v["criterion"]}
    if not routes:
        print("  ! no JondoEmu dumps: doors only from links.json", file=sys.stderr)
        return {}
    world = set(maps)
    changed = True
    while changed:
        changed = False
        for (m, _c), r in routes.items():
            to = r["to_map"]
            if m in world and to not in world and to in area_maps and str(to) in mx.index():
                world.add(to)
                changed = True
    cells = {m: _interactive_cells(raw) for m, raw in mx.raw_maps(sorted(world)).items()}
    doors: dict[int, list[dict]] = {}
    wrong = []
    for (m, c), r in sorted(routes.items()):
        if m not in world or r["to_map"] not in world:
            continue
        if cells.get(m, {}).get(r["element"]) != c:
            wrong.append((m, c, r["element"], cells.get(m, {}).get(r["element"])))
            continue
        doors.setdefault(m, []).append({"cell": c, "to_map": r["to_map"], "to_cell": r["to_cell"], "src": r["src"]})
    for w in wrong:
        print(f"  ! door map {w[0]} cell {w[1]}: element {w[2]} is on cell {w[3]} in the client map, left out", file=sys.stderr)
    while True:
        dead = {m for m in world - maps if not any(d["to_map"] in world for d in doors.get(m, []))}
        if not dead:
            break
        print(f"  ! interiors with no way out left out: {sorted(dead)}", file=sys.stderr)
        world -= dead
    out = {m: [d for d in ds if d["to_map"] in world] for m, ds in doors.items() if m in world}
    print(f"  doors: {sum(len(ds) for ds in out.values())} on {len(out)} maps, {len(world - maps)} interiors "
          f"({collections.Counter(d['src'] for ds in out.values() for d in ds)})")
    return out


def worldmap_catalog(game: Path) -> dict[str, str]:
    """Addressables catalog of the world map bundle: asset guid -> key ("worldmaps/2/1/5.jpg").
    Binary catalog: strings are [u32 length][bytes]; a key is a chain of nodes
    [u32 string offset][u32 prefix node offset or -1], joined with "/"; the guid
    string of an entry follows its key node."""
    import re
    import struct
    d = (game / "Dofus_Data" / "StreamingAssets" / "Content" / "Picto" / "Worldmaps" / "catalog_1.0.bin").read_bytes()
    u = lambda o: struct.unpack_from("<I", d, o)[0]

    def full(n: int, depth: int = 0) -> str:
        a, b = u(n), u(n + 4)
        pre = "" if b == 0xFFFFFFFF or depth > 8 else full(b, depth + 1) + "/"
        return pre + d[a:a + u(a - 4)].decode("latin1")

    out = {}
    for m in re.finditer(rb"[0-9a-f]{32}", d):
        g = m.start()
        if u(g - 4) == 32:
            try:
                out[m.group().decode()] = full(g - 12)
            except (struct.error, UnicodeDecodeError, RecursionError):
                pass
    return out


def extract_worldmap(game: Path, world_map: int, zoom: str = "1") -> None:
    """Tiles of one world map at one zoom -> Content/Worldmaps/<id>/<zoom>/<n>.webp."""
    UnityPy.config.FALLBACK_UNITY_VERSION = detect_unity_version(game)
    keys = worldmap_catalog(game)
    prefix = f"worldmaps/{world_map}/{zoom}/"
    wanted = {g: k[len(prefix):-4] for g, k in keys.items() if k.startswith(prefix)}
    env = UnityPy.load(str(game / "Dofus_Data" / "StreamingAssets" / "Content" / "Picto" / "Worldmaps" / "worldmap_assets_.bundle"))
    out = CONTENT / "Worldmaps" / str(world_map) / zoom
    out.mkdir(parents=True, exist_ok=True)
    n = 0
    for g, ptr in env.container.items():
        if g in wanted and (ptr.deref() if hasattr(ptr, "deref") else ptr).type.name == "Texture2D":
            (ptr.deref() if hasattr(ptr, "deref") else ptr).read().image.convert("RGB").save(out / f"{wanted[g]}.webp", quality=88, method=4)
            n += 1
    print(f"world map {world_map} zoom {zoom}: {n}/{len(wanted)} tiles -> {out}")


def _neighbour(raw: dict, scroll: dict | None, d: str) -> int:
    """Map reached through side `d`: mapscrollactions when the map has a row there, else mapData."""
    if scroll is not None:
        return int(scroll[f"{d}MapId"]) if scroll[f"{d}Exists"] else 0
    return int(raw["mapData"][f"{d}NeighbourId"])


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("index")
    e = sub.add_parser("extract")
    e.add_argument("ids", nargs="+", type=int)
    e.add_argument("--overwrite", action="store_true")
    w = sub.add_parser("world")
    w.add_argument("name")
    w.add_argument("--center", type=int, required=True, help="map id at the centre of the world")
    w.add_argument("--radius", type=int, default=1, help="1 -> 3x3 maps")
    w.add_argument("--seed", type=int, default=7)
    w.add_argument("--max-groups", type=int, default=3)
    w.add_argument("--area", type=int, default=0, help="areas.id: every map of the area linked to the centre")
    f = sub.add_parser("full")
    f.add_argument("name")
    f.add_argument("--start", type=int, default=154010373, help="start map (default: Incarnam)")
    f.add_argument("--start-cell", type=int, default=287)
    f.add_argument("--max-groups", type=int, default=3)
    f.add_argument("--links-from", default="incarnam", help="world whose links.json seeds this one")
    c = sub.add_parser("coords")
    c.add_argument("name")
    wm = sub.add_parser("worldmap")
    wm.add_argument("id", type=int)
    wm.add_argument("--zoom", default="1")
    i = sub.add_parser("i18n")
    i.add_argument("--langs", nargs="*", default=["fr"])
    args = ap.parse_args()
    mx = MapExtractor()
    if args.cmd == "index":
        mx.build_index()
    elif args.cmd == "extract":
        mx.extract(args.ids, args.overwrite)
    elif args.cmd == "world":
        build_world(mx, args.name, args.center, args.radius, args.seed, args.max_groups, args.area)
    elif args.cmd == "full":
        build_full_world(mx, args.name, args.start, args.start_cell, args.max_groups, args.links_from)
    elif args.cmd == "coords":
        write_coords(args.name)
    elif args.cmd == "worldmap":
        extract_worldmap(DEFAULT_GAME, args.id, args.zoom)
    elif args.cmd == "i18n":
        mx.i18n(args.langs)


if __name__ == "__main__":
    main()
