"""Gives the Vertebre the look of real Dofus creatures (spec/dofus_map.py).

apply() runs after world.build(): it swaps the generated looks/portraits of monsters, bosses, summons and NPCs for Dofus ones and drops the
bones/icons that would have been drawn. copy_assets() runs after the generated files are written and copies the Dofus bones, skins and
portraits the world now names into game/worlds/vertebre/Content (git-ignored: never commit Ankama assets). Without game/content, nothing changes."""
from __future__ import annotations

import json
import os
import shutil

from common import CONTENT, R, ROOT

import dofus_map
import lore

SRC = os.path.join(ROOT, "game", "content", "Content")
USED = {"bones": set(), "skins": set(), "portraits": set(), "icons": set(), "renames": []}
_cache: dict = {}


def available():
    return os.path.isdir(os.path.join(SRC, "Characters", "Bones"))


def table(name):
    if name not in _cache:
        _cache[name] = json.load(open(os.path.join(SRC, "Data", name + "dataroot.json"), encoding="utf-8"))["objectsById"]
    return _cache[name]


def parts(look):
    """{bone|skins|colors|scale|extra...} -> (bone, skins, colors, scale, extra); '|' inside nested {} does not split."""
    out, depth, cur = [], 0, ""
    for ch in look.strip()[1:-1]:
        depth += ch == "{"
        depth -= ch == "}"
        if ch == "|" and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    out.append(cur)
    out += [""] * (4 - len(out))
    return out[0], out[1], out[2], int(out[3] or 100), out[4:]


def mklook(dlook, vscale):
    bone, skins, colors, scale, extra = parts(dlook)
    USED["bones"].add(bone)
    USED["skins"].update(s for s in skins.split(",") if s)
    return "{" + "|".join([bone, skins, colors, str(round(scale * vscale / 100))] + extra) + "}"


def _monster(mid):
    m = table("monsters")[str(mid)]
    return m["look"], m["gfxId"]


def _drop(bone):
    R.bones.pop(bone, None)
    R.icons[:] = [i for i in R.icons if i[0] != "Picto/Monsters/%s" % bone]


def _swap_grades(rows, by_name):
    for row in rows.values():
        did = by_name.get(row["name"])
        if did is None:
            continue
        dlook, gfx = _monster(did)
        for g in row["grades"]:
            bone, _s, _c, vscale, _x = parts(g["look"])
            g["look"] = mklook(dlook, vscale)
            if "portrait" in g and g["portrait"]:
                g["portrait"] = gfx
                USED["portraits"].add(gfx)
            _drop(bone)


def apply(look_bone):
    """look_bone: world._look_bone (NPC kind -> generated bone id)."""
    if not available():
        return
    names = dict(dofus_map.MONSTERS)
    for f, did in dofus_map.BOSS_BY_FLOOR.items():
        names[lore.BOSSES[f]["name"]] = did
    _swap_grades(R.monsters, names)
    _swap_grades(R.bosses, names)
    for row in R.summons.values():
        did = names.get(row["name"])
        if did is not None:
            bone, _s, _c, vscale, _x = parts(row["look"])
            row["look"] = mklook(_monster(did)[0], vscale)
            _drop(bone)
    apply_items()
    apply_classes()
    by_bone = {b: k for k, b in look_bone.items()}
    for rows in R.npc_placed.values():
        for r in rows:
            bone = parts(r["look"])[0]
            ref = dofus_map.NPCS.get(by_bone.get(bone))
            if ref is None:
                continue
            dlook = _monster(int(ref[1:]))[0] if isinstance(ref, str) else table("npcs")[str(ref)]["look"]
            r["look"] = mklook(dlook, 100)
    for kind, bone in look_bone.items():
        if kind in dofus_map.NPCS:
            _drop(bone)


GENERATED_TYPES = (34, 80, 84)  # resources, scrolls/fragments, quest seals: lore-specific, they keep their drawn icon
SKINNED_TYPES = (16, 17, 82)  # hats, capes, shields: the Dofus ones that have a `skin` show on the character


def apply_items():
    """Equipment takes the icon (and, for hats/capes/shields, the worn skin) of the Dofus item of the same type and nearest level."""
    path = os.path.join(ROOT, "game", "data", "items.json")
    if not available() or not os.path.exists(path):
        return
    pool: dict[int, list] = {}
    for it in json.load(open(path, encoding="utf-8"))["items"]:
        if it.get("icon") and (it["type"] not in SKINNED_TYPES or it.get("skin")):
            pool.setdefault(it["type"], []).append(it)
    used: set[int] = set()
    for row in sorted(R.items, key=lambda r: (r["type"], r["level"], r["id"])):
        if row["type"] in GENERATED_TYPES or row["type"] not in pool:
            continue
        cand = [c for c in pool[row["type"]] if c["id"] not in used] or pool[row["type"]]
        best = min(cand, key=lambda c: (abs(c["level"] - row["level"]), c["id"]))
        used.add(best["id"])
        R.icons[:] = [i for i in R.icons if i[0] != "Picto/Items/%d" % row["icon"]]
        row["icon"] = best["icon"]
        USED["icons"].add(best["icon"])
        if best.get("skin"):
            row["skin"] = best["skin"]
            USED["skins"].add(str(best["skin"]))


def apply_classes():
    """Each class wears a Dofus breed: its look ({1|body skin||scale}, bone 1 is a family kept in game/content), the bodies/faces to pick at
    creation (copied rows, new ids) and the class symbol/portraits (copied under the Vertebre breed id)."""
    breeds = table("breeds")
    own = R.table("breeds")
    bodies, heads = R.table("bodies"), R.table("heads")
    nid = 9_000_000
    for vb, db in dofus_map.BREEDS.items():
        row = own.get(str(vb))
        if row is None:
            continue
        src = breeds[str(db)]
        _drop(str(row["creatureBonesId"]))
        for k in ("maleLook", "femaleLook", "creatureBonesId", "maleColors", "femaleColors"):
            row[k] = src[k]
        for t, dst in (("bodies", bodies), ("heads", heads)):
            for r in table(t).values():
                if r["breed"] == db:
                    nid += 1
                    dst[str(nid)] = dict(r, id=nid, breed=vb)
                    USED["skins"].update(x for x in str(r["skins"]).split(",") if x)
        for rel in ("UI/classes/symbol_%d", "UI/classes/heads/big/Head_%d"):
            for sex in ((0, 1) if "Head" in rel else (None,)):
                n = (db, vb) if sex is None else (db * 10 + sex, vb * 10 + sex)
                USED["renames"].append((rel % n[0], rel % n[1]))
                R.icons[:] = [i for i in R.icons if i[0] != rel % n[1]]
    for k in ("maleLook", "femaleLook"):
        for r in own.values():
            USED["skins"].update(x for x in parts(r[k])[1].split(",") if x)


def _copy(rel, to=None):
    for ext in ("", ".webp", ".png"):
        src = os.path.join(SRC, rel + ext)
        if os.path.exists(src):
            dst = os.path.join(CONTENT, (to or rel) + ext)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            if os.path.isdir(src):
                shutil.copytree(src, dst, dirs_exist_ok=True)
            else:
                shutil.copy2(src, dst)
            return True
    return False


def copy_assets():
    missing = []
    for b in sorted(USED["bones"]):
        if not _copy("Characters/Bones/" + b):
            missing.append("bone " + b)
    for s in sorted(USED["skins"]):
        if not _copy("Characters/Skins/" + s):
            missing.append("skin " + s)
    for g in sorted(USED["portraits"]):
        if not _copy("Picto/Monsters/%s" % g):
            missing.append("portrait %s" % g)
    for i in sorted(USED["icons"]):
        if not _copy("Picto/Items/%s" % i):
            missing.append("icon %s" % i)
    for a, b in USED["renames"]:
        if not _copy(a, b):
            missing.append(a)
    print("dofus assets: %d bones, %d skins, %d portraits, %d icons copied; missing %s" % (
        len(USED["bones"]), len(USED["skins"]), len(USED["portraits"]), len(USED["icons"]), missing or "none"))
