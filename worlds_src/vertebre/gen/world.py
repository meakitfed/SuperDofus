"""The maps of the Vertebre and everything that sits on them: NPCs, collectibles, groups, stairs.

12 maps: the hub, five floors (each a field map with an entrance, a core and an antechamber, two sealed alcoves
and four searchable objects), five boss arenas and the summit. Exploration is the point of a floor: hidden pockets
behind a gap in the rocks, readable zones, a shortcut from a quest, objects to search (the memory fragments).
"""
from __future__ import annotations

import lore
import mapgen
import story
from common import CONTENT, OUT, R, T, WORLD_ID, Counter, bone_id, dump, element_id
from items import ITEM
from mapgen import FloorMap, GfxBank, cid, neighbors
from mobs import BOSS_IDS, FLOOR_MONSTERS
from rigs import Pal

HUB, SUMMIT = 9001, 9300
FLOOR = {f: 9100 + f for f in range(1, 6)}
ARENA = {f: 9200 + f for f in range(1, 6)}
THEME = {1: "roots", 2: "marsh", 3: "city", 4: "archive", 5: "crown"}
skill_id = Counter(9_501)

CLUTTER = {  # (heavy props, light props)
    1: (["shroom", "root"], ["rock", "boulder"]),
    2: (["dead_tree", "boulder"], ["rock", "bones"]),
    3: (["gear", "pillar", "crate"], ["rock", "barrel", "lamp"]),
    4: (["bookshelf", "pillar", "statue"], ["rock", "barrel"]),
    5: (["crystal", "statue", "pillar"], ["rock", "banner"]),
}
CLUTTER_N = {1: (14, 9), 2: (16, 10), 3: (18, 12), 4: (14, 8), 5: (12, 8)}

# per floor (col, row): entry, stairs up, boss door, NPCs, secret alcove, second pocket, open collectibles, river rows
LAYOUT = {
    1: dict(entry=(2, 36), stair=(11, 4), door=(5, 4), npcs={"cueilleuse": (4, 30), "novice": (10, 25)}, nook=(11, 14), pocket=(2, 17), frags=[(1, 22), (8, 9)], river=None),
    2: dict(entry=(11, 36), stair=(2, 4), door=(8, 4), npcs={"cendreux": (10, 29), "passeur": (3, 25)}, nook=(2, 15), pocket=(12, 11), frags=[(12, 21), (6, 10)], river=None),
    3: dict(entry=(1, 20), stair=(12, 6), door=(7, 4), npcs={"automate": (4, 29), "horloger": (10, 21)}, nook=(12, 33), pocket=(3, 9), frags=[(5, 17), (9, 26)], river=None),
    4: dict(entry=(7, 36), stair=(2, 4), door=(11, 6), npcs={"noye": (5, 31), "libraire": (9, 18)}, nook=(7, 11), pocket=(12, 33), frags=[(1, 31), (11, 22)], river=(24, 27)),
    5: dict(entry=(7, 36), stair=(7, 4), door=(2, 7), npcs={"aure": (5, 22)}, nook=(12, 11), pocket=(1, 31), frags=[(12, 27), (4, 13)], river=(15, 18)),
}
FRAG_PROPS = {1: "bones", 2: "chest", 3: "crate", 4: "chest"}  # props of fragments 1..4 (4 = the main secret alcove)

NPC_LOOK = {
    "elder": dict(arch="upright", pal=Pal((130, 118, 110), (255, 190, 90), (190, 160, 100)), h=29, w=11, leg=24, arm=14, fore=13, hs=9, head="round", body="robe", weapon="staff", motif="core", wsize=30),
    "smith": dict(arch="upright", pal=Pal((120, 80, 60), (255, 150, 60), (180, 130, 90)), h=31, w=15, leg=22, arm=15, fore=14, hs=8.5, head="round", body="armor", weapon="hammer", limbs="fist", arm_w=3.8, attack="slam"),
    "merchant": dict(arch="upright", pal=Pal((110, 120, 80), (255, 220, 120), (170, 150, 90)), h=29, w=12, leg=24, arm=14, fore=13, hs=9, head="round", body="robe", extras=["cape"], limbs="sleeve"),
    "priest": dict(arch="upright", pal=Pal((200, 196, 210), (255, 232, 140), (160, 150, 190)), h=31, w=11, leg=25, arm=14, fore=13, hs=8.5, head="hood", body="robe", weapon="staff", motif="rune"),
    "young": dict(arch="upright", pal=Pal((70, 120, 130), (120, 230, 220), (200, 190, 150)), h=26, w=9, leg=23, arm=13, fore=12, hs=8.5, head="round", body="rags", weapon="staff", wsize=22),
    "ghost": dict(arch="floater", pal=Pal((160, 190, 220), (140, 240, 255)), r=14, core="ghost", sats=0, wisps=0, hover=22),
    "guard": dict(arch="upright", pal=Pal((70, 66, 80), (255, 190, 90), (150, 140, 120)), h=33, w=13, leg=24, arm=15, fore=14, hs=8.5, head="helm", body="armor", weapon="mace", off="shield", limbs="armor", arm_w=3.5),
    "hood": dict(arch="upright", pal=Pal((70, 100, 80), (170, 255, 140), (150, 170, 110)), h=29, w=11, leg=25, arm=14, fore=13, hs=8.5, head="hood", body="robe", weapon="staff", motif="rune"),
    "golem": dict(arch="upright", pal=Pal((140, 120, 84), (110, 220, 210)), h=33, w=15, leg=22, arm=16, fore=15, hs=9, head="cyclops", body="plate", limbs="armor", arm_w=4, weapon="mace", motif="rune"),
    "seal": dict(arch="floater", pal=Pal((150, 146, 160), (255, 220, 110)), r=13, core="crystal", sats=3, wisps=0, hover=26),
    "door": dict(arch="floater", pal=Pal((90, 70, 70), (255, 90, 70)), r=13, core="eye", sats=2, wisps=0, hover=26),
}
_look_bone: dict[str, str] = {}


def npc_look(kind, scale=100):
    if kind not in _look_bone:
        b = str(bone_id())
        R.bones[b] = NPC_LOOK[kind]
        _look_bone[kind] = b
    return "{%s|||%d}" % (_look_bone[kind], scale)


NPC_KIND = {k: v["look"] for k, v in lore.NPCS.items()}
for _f in range(1, 6):
    NPC_KIND["stair%d" % _f] = "seal"
    NPC_KIND["door%d" % _f] = "door"


def build():
    bank = GfxBank()
    npcs: dict[str, list] = {}
    inter: dict[str, list] = {}
    M = dict(hub=HUB, summit=SUMMIT, floor=FLOOR, arena=ARENA, entry={}, after_stair={}, door_front={}, arena_entry={}, hub_gate=cid(7, 8), summit_cell=cid(7, 34))
    maps: list[FloorMap] = []

    def put_npc(fm, key, col, row, d=3):
        """An NPC standing on (col, row): the cell is blocked, its neighbours kept free and reachable."""
        c = cid(col, row)
        fm.blocked.add(c)
        fm.keep |= {n for n in neighbors(c)}
        fm.anchors["acc_" + key] = next(n for n in neighbors(c) if n not in fm.blocked)
        nid = story.NPC[key]
        scale = 108 if key.startswith(("stair", "door")) else 100
        npcs.setdefault(str(fm.id), []).append({"npc": nid, "cell": c, "dir": d, "look": npc_look(NPC_KIND[key], scale), "name_id": T(story.NPC_NAME[nid])})
        return c

    def collectible(fm, key, kind, col, row):
        c = cid(col, row)
        fm.props.append((kind, c))
        fm.blocked.add(c)
        fm.collect.append((key, kind, c))

    # ── the hub: the camp at the foot of the Tower ──────────────────────────────
    hub = FloorMap(HUB, "Le Pied-de-Tour", "camp", 1, (0, 0))
    hub.anchor("start", 7, 36)
    hub.anchor("gate_arrival", 7, 8)
    hub.place("door", 7, 2, force=True)
    for key, (c, r) in dict(porte=(7, 5), orsolan=(6, 14), brenna=(3, 19), tomas=(10, 19), ilda=(3, 27), kael=(11, 27), echo=(7, 31), dorn=(10, 34)).items():
        put_npc(hub, key, c, r)
    for kind, c, r in (("tent", 1, 12), ("tent", 12, 12), ("tent", 1, 22), ("tent", 12, 22), ("lamp", 5, 11), ("lamp", 9, 11), ("lamp", 5, 24), ("lamp", 9, 24),
                       ("crate", 4, 17), ("barrel", 5, 19), ("crate", 11, 17), ("barrel", 9, 21), ("banner", 6, 7), ("banner", 8, 7), ("crate", 2, 29), ("barrel", 12, 29),
                       ("tent", 2, 33), ("bones", 12, 36), ("lamp", 7, 27), ("lamp", 5, 33)):
        hub.place(kind, c, r)
    hub.clutter(["rock", "crate", "barrel"], 10, (1, 2), rows=(6, 38))
    # the phoenix of the camp: a glowing crystal where the fallen come back to life
    hub.extra.update(monster_spawn=False, outdoor=True, phoenix=hub.place("crystal", 7, 25, force=True) or -1)
    maps.append(hub)

    # ── the five floors and their arenas ────────────────────────────────────────
    skills, jobs = R.table("skills"), R.table("jobs")
    jobs["9001"] = {"id": 9001, "nameId": T("Fouilleur"), "iconId": 0, "hasLegendaryCraft": 0}
    for f in range(1, 6):
        L = LAYOUT[f]
        fm = FloorMap(FLOOR[f], lore.FLOORS[f]["name"], THEME[f], 10 + f, (0, f))
        ex, er = L["entry"]
        fm.anchor("entry", ex, er)
        M["entry"][f] = cid(ex, er)
        sc, sr = L["stair"]
        put_npc(fm, "stair%d" % f, sc, sr)
        arrival = fm.anchor("after_stair", sc, sr + 2)
        M["after_stair"][f] = arrival
        dc, dr = L["door"]
        put_npc(fm, "door%d" % f, dc, dr)
        M["door_front"][f] = fm.anchor("door_front", dc, dr + 2)
        for key, (c, r) in L["npcs"].items():
            put_npc(fm, key, c, r)
        for pk, (c, r), idx in (("nook", L["nook"], 4), ("pocket", L["pocket"], 2)):
            fm.secret_nook(pk, c, r)
            collectible(fm, "frag%d" % idx, FRAG_PROPS[idx], c, r)
        for idx, (c, r) in zip((1, 3), L["frags"]):
            collectible(fm, "frag%d" % idx, FRAG_PROPS[idx], c, r)
            fm.anchors["acc_frag%d" % idx] = next(n for n in neighbors(cid(c, r)) if n not in fm.blocked)
            fm.keep |= set(neighbors(cid(c, r)))
        if L["river"]:  # water / sky gaps across the floor, crossable by a bridge in the middle and one at the left edge
            r0, r1 = L["river"]
            for rr in range(r0, r1 + 1):
                for cc in range(14):
                    cell = cid(cc, rr)
                    if abs(cc - 7) <= 1 or cc <= 1 or cell in fm._keep_free() or cell in fm.blocked:
                        continue
                    try:
                        fm.pit([cell])
                    except ValueError:
                        pass
        heavy, light = CLUTTER[f]
        n_h, n_l = CLUTTER_N[f]
        fm.clutter(heavy, n_h, (2, 4))
        fm.clutter(light, n_l, (1, 2))
        fm.extra.update(subarea=9100 + f, area=9100, monster_spawn=True, outdoor=False)
        maps.append(fm)
        # the arena: a closed room with the boss, one exit
        am = FloorMap(ARENA[f], "Antre : %s" % lore.BOSSES[f]["name"], THEME[f], 20 + f, (1, f))
        am.anchor("entry", 7, 34)
        M["arena_entry"][f] = cid(7, 34)
        am.anchor("centre", 7, 20)
        am.anchor("exit", 7, 37)
        for c, r in ((3, 14), (11, 14), (3, 26), (11, 26), (2, 20), (12, 20)):
            am.place("pillar" if f != 1 else "root", c, r)
        am.clutter(CLUTTER[f][1], 6, (1, 2), rows=(8, 32))
        am.extra.update(monster_spawn=False, outdoor=False)
        am.groups = [{"name": lore.BOSSES[f]["name"], "members": [dict(R.bosses[str(BOSS_IDS[f])]["grades"][0])]}]
        maps.append(am)

    # ── the summit ──────────────────────────────────────────────────────────────
    sm = FloorMap(SUMMIT, "Le Sommet de la Vertèbre", "crown", 99, (0, 6))
    sm.anchor("arrival", 7, 34)
    sm.anchor("exit", 7, 37)
    put_npc(sm, "voix", 7, 12, 1)
    for kind, c, r in (("statue", 5, 10), ("statue", 9, 10), ("pillar", 3, 20), ("pillar", 11, 20), ("pillar", 2, 28), ("pillar", 12, 28),
                       ("crystal", 1, 8), ("crystal", 12, 8), ("crystal", 1, 33), ("crystal", 12, 34), ("crystal", 4, 4), ("crystal", 10, 4)):
        sm.place(kind, c, r)
    sm.extra.update(monster_spawn=False, outdoor=False)
    maps.append(sm)

    # ── stairs and exits (a step on the trigger cell leads there) ───────────────
    by_id = {fm.id: fm for fm in maps}
    for f in range(1, 6):
        fm = by_id[FLOOR[f]]
        down_map = FLOOR[f - 1] if f > 1 else HUB
        down_cell = M["after_stair"][f - 1] if f > 1 else M["hub_gate"]
        fm.triggers.append({"cell": cid(LAYOUT[f]["entry"][0], 39), "to_map": down_map, "to_cell": down_cell})
        by_id[ARENA[f]].triggers.append({"cell": cid(7, 38), "to_map": FLOOR[f], "to_cell": M["door_front"][f]})
    by_id[SUMMIT].triggers.append({"cell": cid(7, 38), "to_map": FLOOR[5], "to_cell": M["after_stair"][5]})

    story.dialogs(M)
    story.quests(M)

    # ── write maps (+ visuals), searchable objects ──────────────────────────────
    for fm in maps:
        mapgen.write_map(fm, bank, OUT, CONTENT)
    bank.write(CONTENT + "/Maps/Gfx")
    skills = R.table("skills")
    for fm in maps:
        for key, kind, cell in fm.collect:
            f = fm.id - 9100
            item = ITEM["frag_%d_%d" % (f, int(key.replace("frag", "")))]
            sid = skill_id()
            skills[str(sid)] = {"id": sid, "nameId": T("Fouiller : %s" % R.items_by_id[item]["name"]), "parentJobId": 9001, "isForgemagus": 0, "modifiableItemTypeIds": [],
                                "gatheredRessourceItem": item, "craftableItemIds": [], "range": 1, "useRangeInClient": 0, "useAnimation": "AnimAttaque0",
                                "cursor": 5, "elementActionId": 1, "availableInHouse": 0, "clientDisplay": 1, "levelMin": 1, "allowMarking": 0}
            gfx = bank.of[(fm.theme, kind, mapgen.variant_of(kind, cell))]
            inter.setdefault(str(fm.id), []).append({"e": element_id(), "cell": cell, "gfx": gfx, "skill": sid})
    R.maps, R.npc_placed, R.interactives = maps, npcs, inter
    return M


def write_all():
    """world.json and the files the sim reads, from what the generators registered."""
    for f in range(1, 6):
        lv = [g["level"] for mid in FLOOR_MONSTERS[f] for g in R.monsters[str(mid)]["grades"]]
        R.subareas[str(9100 + f)] = {"level": sum(lv) // len(lv), "area": 9100, "monsters": FLOOR_MONSTERS[f]}
    dump(OUT + "/world.json", {"id": WORLD_ID, "name": lore.TITLE, "start_map": HUB, "start_cell": cid(7, 34), "wander_ms": [7000, 16000], "max_groups": 5,
                               "challenges": True, "breeds": [901, 902, 903, 904, 905], "default_breed": 901,
                               "maps": [fm.id for fm in R.maps], "phoenixes": [HUB]}, indent="\t")
    dump(OUT + "/monsters.json", {"subareas": R.subareas, "monsters": R.monsters, "bosses": R.bosses})
    dump(OUT + "/npcs.json", {"maps": R.npc_placed, "dialogs": {}})
    dump(OUT + "/dialogs.json", {"dialogs": R.dialogs})
    dump(OUT + "/shops.json", {"shops": R.shops})
    dump(OUT + "/quests.json", {"quests": R.quests})
    dump(OUT + "/interactives.json", {"maps": R.interactives})
    dump(OUT + "/dungeons.json", {"dungeons": {}})
    dump(OUT + "/bank.json", {"bankers": [story.NPC["ilda"]], "placed": {}})
