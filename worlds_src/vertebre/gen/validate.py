"""Referential integrity of the generated world (python validate.py): every id a file mentions exists.

Reads game/worlds/vertebre as written (not the in-memory registry), so it checks what the engine will load.
Exit code 1 and one line per problem when something is off.
"""
from __future__ import annotations

import json
import os
import sys
from collections import deque

from common import OUT, CONTENT

problems: list[str] = []


def load(rel):
    with open(os.path.join(OUT, rel), encoding="utf-8") as f:
        return json.load(f)


def bad(msg):
    problems.append(msg)


def main():
    world = load("world.json")
    spells = load("data/spells.json")
    items = load("data/items.json")
    breeds = load("data/tables/breeds.json")["objectsById"]
    skills = load("data/tables/skills.json")["objectsById"]
    monsters = load("monsters.json")
    quests = load("quests.json")["quests"]
    dialogs = load("dialogs.json")["dialogs"]
    npcs = load("npcs.json")["maps"]
    shops = load("shops.json")["shops"]
    inter = load("interactives.json")["maps"]
    texts = load("Content/I18n/extra_fr.json")

    spell_ids = {s["id"] for s in spells["spells"]}
    item_ids = {i["id"] for i in items["items"]}
    set_ids = {s["id"] for s in items["sets"]}
    mob_ids = {int(k) for k in monsters["monsters"]} | {int(k) for k in monsters["bosses"]}
    summon_ids = {int(k) for k in spells["summons"]}
    map_ids = set(world["maps"])
    npc_ids = {n["npc"] for lst in npcs.values() for n in lst}
    quest_ids = {int(k) for k in quests}

    def text(tid, where):
        if tid and str(tid) not in texts:
            bad("%s: text id %s missing" % (where, tid))

    # spells
    for s in spells["spells"]:
        text(s["name_id"], "spell %d" % s["id"])
        for e in s["effects"] + s["crit_effects"]:
            if e["kind"] in ("trap", "glyph_start", "glyph_end", "rune", "cast") and e.get("spell") and e["spell"] not in spell_ids:
                bad("spell %d: sub-spell %s unknown" % (s["id"], e["spell"]))
            if e["kind"] == "summon" and e["monster"] not in summon_ids:
                bad("spell %d: summon %s unknown" % (s["id"], e["monster"]))
    for pid, gl in spells["grades"].items():
        for g in gl:
            if g not in spell_ids:
                bad("grade %s of spell %s missing" % (g, pid))
    for bid, c in spells["classes"].items():
        for p in c["pairs"]:
            for sid in p:
                if str(sid) not in spells["grades"]:
                    bad("class %s: spell %s has no grades" % (bid, sid))
        if int(bid) not in world["breeds"]:
            bad("class %s not offered by the world" % bid)
    for b in world["breeds"]:
        if str(b) not in breeds:
            bad("breed %s has no row" % b)
    for sid, sm in spells["summons"].items():
        for g in sm["grades"]:
            for sp in g["spells"] + ([g["start"]] if g.get("start") else []):
                if sp not in spell_ids:
                    bad("summon %s: spell %s unknown" % (sid, sp))

    # items
    for it in items["items"]:
        text(it["name_id"], "item %d" % it["id"])
        text(it["description_id"], "item %d description" % it["id"])
        if it.get("set") and it["set"] not in set_ids:
            bad("item %d: set %s unknown" % (it["id"], it["set"]))
        if not any(os.path.exists(os.path.join(CONTENT, "Picto", "Items", "%d.%s" % (it["icon"], e))) for e in ("png", "webp")):
            bad("item %d: icon missing" % it["id"])
    for st in items["sets"]:
        for i in st["items"]:
            if i not in item_ids:
                bad("set %d: item %s unknown" % (st["id"], i))
    for sk in skills.values():
        if sk["gatheredRessourceItem"] not in item_ids:
            bad("skill %s: item unknown" % sk["id"])

    # monsters
    for mid, m in list(monsters["monsters"].items()) + list(monsters["bosses"].items()):
        for g in m["grades"]:
            for sp in g["spells"]:
                if sp not in spell_ids:
                    bad("monster %s: spell %s unknown" % (mid, sp))
            for d in g["drops"]:
                if d["item"] not in item_ids:
                    bad("monster %s: drop %s unknown" % (mid, d["item"]))
            bone = g["look"].strip("{}").split("|")[0]
            if not os.path.isdir(os.path.join(CONTENT, "Characters", "Bones", bone)):
                bad("monster %s: bone %s missing" % (mid, bone))
            if not any(os.path.exists(os.path.join(CONTENT, "Picto", "Monsters", "%s.%s" % (g["portrait"], e))) for e in ("png", "webp")):  # webp: copied Dofus portraits
                bad("monster %s: portrait missing" % mid)
    for sa, d in monsters["subareas"].items():
        for mid in d["monsters"]:
            if mid not in mob_ids:
                bad("subarea %s: monster %s unknown" % (sa, mid))

    # maps
    for mid in world["maps"]:
        m = load("maps/%d.json" % mid)
        cells = set(m["blocked"])
        for t in m["triggers"]:
            if t["to_map"] not in map_ids:
                bad("map %d: trigger to unknown map %s" % (mid, t["to_map"]))
            else:
                dest = load("maps/%d.json" % t["to_map"])
                if t["to_cell"] in dest["blocked"]:
                    bad("map %d: trigger arrives on a blocked cell %d of map %d" % (mid, t["to_cell"], t["to_map"]))
        for n in npcs.get(str(mid), []):
            text(n["name_id"], "npc %d" % n["npc"])
        vis = os.path.join(CONTENT, "Maps", "%d.json" % mid)
        if not os.path.exists(vis):
            bad("map %d: visual missing" % mid)
        else:
            v = json.load(open(vis, encoding="utf-8"))
            for e in v["layers"]["background"] + v["layers"]["sortable"]:
                if not any(os.path.exists(os.path.join(CONTENT, "Maps", "Gfx", "%d.%s" % (e["g"], x))) for x in ("png", "webp")):
                    bad("map %d: gfx %s missing" % (mid, e["g"]))
        for it in inter.get(str(mid), []):
            if str(it["skill"]) not in skills:
                bad("map %d: interactive skill unknown" % mid)
            if it["cell"] not in cells:
                bad("map %d: interactive on a free cell" % mid)
    if world["start_map"] not in map_ids:
        bad("start map unknown")

    # dialogues and quests
    for nid, tree in dialogs.items():
        if int(nid) not in npc_ids:
            bad("dialog for unplaced npc %s" % nid)
        for k, node in tree["nodes"].items():
            for r in node["replies"]:
                if r.get("next") and r["next"] not in tree["nodes"]:
                    bad("dialog %s: node %s unknown" % (nid, r["next"]))
                a = r.get("action") or {}
                if a.get("type") == "teleport" and a["map"] not in map_ids:
                    bad("dialog %s: teleport to unknown map" % nid)
                if a.get("type") in ("give_item",) and a["item"] not in item_ids:
                    bad("dialog %s: give_item unknown" % nid)
                crit = r.get("criteria", "")
                for part in crit.replace("|", "&").split("&"):
                    if part.startswith("Qf=") and int(part[3:]) not in quest_ids:
                        bad("dialog %s: criteria on unknown quest %s" % (nid, part))
                    if part.startswith("PO") and int(part[3:]) not in item_ids:
                        bad("dialog %s: criteria on unknown item %s" % (nid, part))
    for nid in shops:
        if int(nid) not in npc_ids:
            bad("shop of unplaced npc %s" % nid)
        for i in shops[nid]["items"]:
            if i not in item_ids:
                bad("shop %s: item %s unknown" % (nid, i))
    for qid, q in quests.items():
        text(q["name_id"], "quest %s" % qid)
        if q["start"]["npc"] not in npc_ids:
            bad("quest %s: giver unplaced" % qid)
        for st in q["steps"]:
            text(st["name_id"], "quest %s step" % qid)
            text(st["desc_id"], "quest %s step" % qid)
            for o in st["objectives"]:
                for a in o["args"]:
                    if "t" in a:
                        text(a["t"], "quest %s objective" % qid)
                if o["type"] in (1, 9, 3) and o["params"][0] not in npc_ids:
                    bad("quest %s: objective npc unplaced" % qid)
                if o["type"] == 3 and o["params"][1] not in item_ids:
                    bad("quest %s: objective item unknown" % qid)
                if o["type"] in (7, 14) and o["params"][0] not in mob_ids:
                    bad("quest %s: objective monster unknown" % qid)
                if o["type"] == 4 and o["map"] not in map_ids:
                    bad("quest %s: objective map unknown" % qid)
            for rw in st["rewards"]:
                for it, _ in rw["items"]:
                    if it not in item_ids:
                        bad("quest %s: reward item unknown" % qid)

    # reachability of every NPC and collectible on its map (4 diagonal moves)
    from mapgen import neighbors
    for mid in world["maps"]:
        m = load("maps/%d.json" % mid)
        blocked = set(m["blocked"])
        free = [c for c in range(560) if c not in blocked]
        seen = {free[0]}
        q = deque([free[0]])
        while q:
            c = q.popleft()
            for n in neighbors(c):
                if n not in blocked and n not in seen:
                    seen.add(n)
                    q.append(n)
        for n in npcs.get(str(mid), []) + inter.get(str(mid), []):
            c = n["cell"]
            if not any(x in seen for x in neighbors(c)):
                bad("map %d: cell %d is not reachable from outside" % (mid, c))
        for t in m["triggers"]:
            if t["cell"] not in seen and t["cell"] not in blocked:
                bad("map %d: trigger cell %d is cut off" % (mid, t["cell"]))
    print("%d problem(s)" % len(problems))
    for p in problems:
        print(" -", p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
