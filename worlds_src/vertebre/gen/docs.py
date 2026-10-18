"""Writes docs/MONDE_VERTEBRE.md (the guide of the world: lore, classes, bestiary, items, quests) from the registry."""
from __future__ import annotations

import os

import lore
import mobs
import story
from common import R, ROOT, T


def pct(v):
    return "%d%%" % v if v else "-"


def write():
    out = ["# La Vertèbre : guide du monde", "",
           "> Généré par `worlds_src/vertebre/gen/build_all.py` : ne pas éditer à la main (modifier `worlds_src/vertebre/`).", "",
           lore.TAGLINE, "",
           "Monde `vertebre` : %d maps, %d classes, %d créatures (dont %d boss), %d objets en %d panoplies, %d quêtes, %d PNJ. Aucun asset Dofus : "
           "tout est dessiné par le code de `worlds_src/vertebre/build` (os, icônes, sols, décors)." % (
               len(R.maps), len(R.classes), len(R.monsters) + len(R.bosses), len(R.bosses), len(R.items), len(R.sets), len(R.quests), len(story.NPC)),
           "", "## Chronologie", ""]
    for date, text in lore.CHRONOLOGY:
        out.append("- **%s** : %s" % (date, text))
    out += ["", "## Les factions", ""]
    for k, (name, text) in lore.FACTIONS.items():
        out.append("- **%s** : %s" % (name, text))
    out += ["", "## Les classes", ""]
    from classes import CLASSES
    names = {s["id"]: s for s in R.spells}
    for bid, c in CLASSES.items():
        out += ["### %s (%s)" % (c["name"], c["tag"]), "", c["desc"], ""]
        out.append("| Niveau | Sort | PA | Portée | Description |")
        out.append("|---|---|---|---|---|")
        rows = []
        for pair in R.classes[str(bid)]["pairs"]:
            g1 = names[R.grades[str(pair[0])][0]]
            rows.append((g1["level"], g1["name"], g1["ap"], "%d-%d" % tuple(g1["range"]), T.by_id.get(g1["description_id"], "")))
        for lv, name, ap_, rng, desc in sorted(rows):
            out.append("| %d | %s | %d | %s | %s |" % (lv, name, ap_, rng, desc))
        out.append("")
    out += ["## Les étages", ""]
    for f in range(0, 6):
        info = lore.FLOORS[f]
        out += ["### %s (niveaux %d-%d)" % (info["name"], info["lv"][0], info["lv"][1]), "", info["blurb"], ""]
        if f == 0:
            continue
        out.append("| Créature | Niv. | Élément | PV | Rôle (sorts) | Note |")
        out.append("|---|---|---|---|---|---|")
        for m in mobs.MOBS:
            if m["floor"] != f:
                continue
            g = R.monsters[str(m["id"])]["grades"][0]
            sp = ", ".join(names[s]["name"] for s in g["spells"] if s in names)
            out.append("| **%s**%s | %d | %s | %d | %s | %s |" % (m["name"], " (élite)" if m["elite"] else "", g["level"], m["el"], g["hp"], sp, m["note"]))
        b = lore.BOSSES[f]
        bg = R.bosses[str(mobs.BOSS_IDS[f])]["grades"][0]
        out += ["", "**Boss : %s, %s** (niv. %d, %d PV) : %s" % (b["name"], b["title"], bg["level"], bg["hp"], b["story"]), "",
                "> %s" % b["intro"], ">", "> %s" % b["defeat"], "",
                "Sorts : " + ", ".join(names[s]["name"] for s in bg["spells"] if s in names), ""]
    out += ["## Les panoplies", ""]
    by_id = {i["id"]: i for i in R.items}
    for st in R.sets:
        out += ["### %s" % T.by_id[st["name_id"]], ""]
        for iid in st["items"]:
            it = by_id[iid]
            out.append("- %s (niv. %d) : %s" % (it["name"], it["level"], T.by_id.get(it["description_id"], "")))
        out.append("")
    out += ["## Les quêtes", ""]
    for qid, q in R.quests.items():
        out += ["### %s" % T.by_id[q["name_id"]], ""]
        for st in q["steps"]:
            out.append("- **%s** : %s" % (T.by_id[st["name_id"]], T.by_id[st["desc_id"]]))
        out.append("")
    out += ["## Les deux fins", ""]
    for k, e in lore.ENDINGS.items():
        out.append("- **%s** : %s" % (e["name"], e["text"]))
    out += ["", "## Les fragments de mémoire", ""]
    for f, lst in lore.FRAGMENTS.items():
        out.append("**%s**" % lore.FLOORS[f]["name"])
        out.append("")
        for name, text in lst:
            out.append("- *%s* : %s" % (name, text))
        out.append("")
    path = os.path.join(ROOT, "docs", "MONDE_VERTEBRE.md")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
    return path
