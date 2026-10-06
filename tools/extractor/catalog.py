"""Generates docs/data_catalog.md: which Dofus 3 data table serves what.

    python extract.py --tables all      # export every table (incremental)
    python catalog.py                   # rewrite docs/data_catalog.md

The per-table rows (count, size, fields, example) are computed from the
exported JSON; the role of the key tables and the roadmap lots using them
live in KEY_TABLES below — update it when a lot starts using a new table.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "game" / "content" / "Content" / "Data"
OUT = ROOT / "docs" / "data_catalog.md"

# table (without "dataroot") -> (role, roadmap lots)
KEY_TABLES = {
    "breeds": ("Classes : looks, couleurs, coûts du capital par palier (statsPointsFor*), sorts de classe", "P1.02, P1.04"),
    "heads": ("Têtes par classe et sexe", "P1.02"),
    "skinslotsrules": ("Règles de slots de skin du look", "A.01, P1.02"),
    "namingrules": ("Règles de nom (longueur, regexp) pour les personnages, guildes…", "P1.01"),
    "characterxpmappings": ("Table d'XP des personnages", "A.04"),
    "characteristics": ("Caractéristiques (keyword, catégorie, formule d'échelle)", "P1.04"),
    "luaformulas": ("Formules officielles (XP, prospection, …) en Lua", "A.03, P1.04, P1.14"),
    "constants": ("Constantes du jeu", "P1.04"),
    "notifications": ("Tutoriel : titre, message, déclencheur (12-14 : mort, énergie, fantôme)", "P1.10"),
    "infomessages": ("Messages de jeu → texte i18n (énergie perdue, récupérée…)", "P1.10"),
    "spells": ("Sorts : nom, icône, scripts de FX, niveaux", "A.03, P1.03"),
    "spelllevels": ("Niveaux de sort : coûts, portée, effets, critiques, niveau requis", "A.03, P1.03, P1.11–P1.17"),
    "spellvariants": ("Paires de variantes Dofus 3", "P1.03"),
    "spellstates": ("États (flags : invulnérable, pesanteur, enraciné…)", "A.03, P1.14"),
    "spellscripts": ("Scripts de FX des sorts", "A.03"),
    "effects": ("Définition des effets (caractéristique, opérateur, catégorie)", "P1.05, P1.06, P2.07"),
    "items": ("Objets : type, niveau, poids, prix, conditions, possibleEffects, arme", "P1.05, P1.06, P2.02"),
    "itemtypes": ("Types d'objets et catégories (slot d'équipement)", "P1.05, P1.06"),
    "itemsupertypes": ("Super-types d'objets", "P1.06"),
    "itemsets": ("Panoplies : objets et bonus par nombre d'objets portés", "P1.06"),
    "monsters": ("Monstres : grades, sorts, drops, sous-zones, agressivité", "A.03, P1.09, P1.16"),
    "monsterraces": ("Races de monstres, agressivité", "P1.09"),
    "monsterminibosses": ("Correspondance archimonstres / miniboss", "P4.02"),
    "mapsinformation": ("Maps : coordonnées, sous-zone", "P1.07"),
    "mapscoordinates": ("Coordonnées → maps", "P1.07, P1.08"),
    "mapscrollactions": ("Voisins réels des maps (haut, bas, gauche, droite)", "P1.07"),
    "subareas": ("Sous-zones : maps, niveau, monstres, ressources, zaap associé, voisins", "P1.07, P1.09, P2.05"),
    "areas": ("Zones", "P1.07"),
    "superareas": ("Continents", "P1.08"),
    "worldmaps": ("Cartes du monde", "P1.08"),
    "waypoints": ("Zaaps (map, sous-zone)", "P1.08"),
    "pointsofinterest": ("Points d'intérêt de la carte", "P1.08"),
    "npcs": ("PNJ : look, messages et réponses de dialogue, actions", "P2.01"),
    "npcmessages": ("Textes des messages de PNJ", "P2.01"),
    "npcactions": ("Actions de PNJ (parler, acheter, …)", "P2.01, P2.02"),
    "quests": ("Quêtes : catégorie, répétition, niveaux, étapes, condition de départ", "P2.03, P2.04"),
    "queststeps": ("Étapes : objectifs, récompenses, dialogue", "P2.03"),
    "questobjectives": ("Objectifs : type, paramètres, map", "P2.03"),
    "questobjectivetypes": ("Types d'objectifs", "P2.03"),
    "queststeprewards": ("Récompenses d'étape", "P2.03"),
    "questcategories": ("Catégories de quêtes", "P2.03"),
    "jobs": ("Métiers", "P2.05"),
    "skills": ("Compétences : métier, ressource récoltée, objets craftables, animation", "P2.05, P2.06"),
    "interactives": ("Types d'éléments interactifs", "P2.05"),
    "recipes": ("Recettes : ingrédients, quantités, métier, niveau", "P2.06"),
    "auctionhouses": ("Hôtels de vente : type, quantités autorisées", "P2.10"),
    "achievements": ("Succès : points, niveau, objectifs, récompenses", "P2.12"),
    "achievementobjectives": ("Objectifs de succès (critères)", "P2.12"),
    "achievementrewards": ("Récompenses de succès", "P2.12"),
    "almanaxcalendars": ("Almanax : jour, quête, bonus", "P2.12"),
    "mounts": ("Montures", "P2.14"),
    "mountfamilies": ("Familles de montures", "P2.14"),
    "rides": ("Montures (Dofus 3)", "P2.14"),
    "chatchannels": ("Canaux de chat", "P3.02"),
    "smileys": ("Smileys", "P3.02"),
    "guildrights": ("Droits de guilde", "P3.06"),
    "guildranks": ("Rangs de guilde", "P3.06"),
    "emblemsymbols": ("Emblèmes (guildes, alliances)", "P3.06, P3.07"),
    "alliancerights": ("Droits d'alliance", "P3.07"),
    "alignmentsides": ("Camps d'alignement", "P3.08"),
    "alignmentranks": ("Rangs d'alignement", "P3.08"),
    "alignmentorders": ("Ordres d'alignement", "P3.08"),
    "arenaleagues": ("Ligues du Kolizéum", "P3.09"),
    "challenges": ("Challenges de combat : critères d'activation et de réussite", "P1.15"),
    "dungeons": ("Donjons : maps, entrée, sortie, niveau", "P4.01"),
    "titles": ("Titres", "P4.03"),
    "ornaments": ("Ornements", "P4.03"),
    "emoticons": ("Émotes : animation, durée, persistance", "P4.03"),
    "havenbagthemes": ("Thèmes de havre-sac", "P4.04"),
    "havenbagfurnitures": ("Meubles de havre-sac", "P4.04"),
    "houses": ("Maisons : prix, pièces", "P4.05"),
    "paddocks": ("Enclos", "P4.05, P2.14"),
    "calendarevents": ("Événements du calendrier", "P4.06"),
    "worldevents": ("Événements du monde", "P4.06"),
    "soundbones": ("Sons des animations", "P5.01"),
    "randomdropgroups": ("Groupes de drops aléatoires (coffres, sacs)", "P1.05"),
    "bonuses": ("Bonus (étoiles, …)", "P1.09"),
    "idles": ("Animations d'inactivité", "P5.05"),
}

# Data a real game needs that the client does not ship (it lives on Ankama's servers).
MISSING = [
    ("Position des PNJ sur les maps", "P2.01", "à relever à la main ou à déduire des quêtes (questobjectives.mapId). Voir aussi les éléments des maps."),
    ("Contenu des boutiques PNJ", "P2.02", "à définir par monde (JSON du monde), `APPROX`."),
    ("Kamas lâchés par les monstres", "A.03", "`APPROX` [2·niveau, 4·niveau+6] (maps.py)."),
    ("Composition et fréquence des groupes de monstres", "P1.09", "`subareas.monsters` donne la liste (`monsters.json`, `MonsterSpawner`) ; nombre et taille des groupes `APPROX`. Étoiles : par sous-zone (−50 % à +100 %, Dofus 2.51), vitesse `APPROX`. Agression : `monsters.aggressive*` + devblog 2.45 ; `aggressiveAttackDelay` non compris."),
    ("Prix des zaaps", "P1.08", "`APPROX` : wiki Dofus (10 × distance entière en ligne droite, ÷ 4 depuis Incarnam), `shared/travel.gd`. Position des zaaps : `waypoints.mapId` ; cellule relevée sur capture (`links.json`)."),
    ("Destination des portes, escaliers et trappes", "P1.07", "`APPROX` : `game/worlds/<id>/links.json`, cellules relevées sur les captures (`client_shot` goto + mark + grid). Les intérieurs sont les maps de `mapsinformation.worldMap = -1` aux mêmes coordonnées."),
    ("Position des éléments interactifs (ressources, ateliers, zaaps)", "P2.05", "dans les données de map (éléments graphiques avec un id d'interactif) : à vérifier dans `maps.py`."),
]


def human(n: int) -> str:
    for unit in ("o", "Ko", "Mo", "Go"):
        if n < 1024:
            return f"{n:.0f} {unit}"
        n /= 1024
    return f"{n:.1f} To"


def main() -> None:
    tables = sorted(DATA.glob("*dataroot.json"))
    if not tables:
        raise SystemExit(f"No table in {DATA}: run `python extract.py --tables all` first")
    rows = []
    for path in tables:
        name = path.name[:-len("dataroot.json")]
        objects = json.loads(path.read_text(encoding="utf-8"))["objectsById"]
        first = next(iter(objects.values()), {})
        fields = ", ".join(f"`{k}`" for k in first.keys() if k != "m_flags")
        rows.append((name, len(objects), path.stat().st_size, fields))

    out = ["# Catalogue des données Dofus 3",
           "",
           "Généré par `python tools/extractor/catalog.py` : ne pas éditer les tableaux à la main. Les rôles et les lots se modifient dans `KEY_TABLES` du script.",
           "",
           "- Extraction : `python tools/extractor/extract.py --tables all`, incrémentale, qui s'arrête sous 2 Go libres. Les fichiers vont dans `game/content/Content/Data/<table>dataroot.json` (`{objectsById: {id: ligne}}`), qu'on ne commite jamais.",
           "- Lecture côté jeu : `GameData.table(\"<table>\")` et `GameData.row(\"<table>\", id)`. Les copies légères livrées avec le jeu (`game/data/tables/<table>.json`, `gamedata.py table <table>`) passent avant le contenu brut ; voir `shared/game_data.gd`.",
           "- Textes : les `nameId`, `descriptionId`… sont des clés i18n de `Content/I18n/fr.bin` (`python tools/extractor/maps.py i18n`).",
           f"- {len(rows)} tables, {human(sum(r[2] for r in rows))} au total.",
           "",
           "## Tables clés et lots de la roadmap",
           "",
           "| Table | Rôle | Lots | Lignes |",
           "|---|---|---|---|"]
    counts = {r[0]: r[1] for r in rows}
    for name, (role, lots) in KEY_TABLES.items():
        mark = counts.get(name)
        out.append(f"| `{name}` | {role} | {lots} | {mark if mark is not None else '**absente**'} |")
    out += ["",
            "## Absent du client (données serveur Ankama)",
            "",
            "| Donnée | Lot | Solution |",
            "|---|---|---|"]
    out += [f"| {a} | {b} | {c} |" for a, b, c in MISSING]
    out += ["",
            "## Toutes les tables",
            "",
            "| Table | Lignes | Taille | Champs |",
            "|---|---|---|---|"]
    out += [f"| `{n}` | {c} | {human(s)} | {f} |" for n, c, s, f in rows]
    OUT.write_text("\n".join(out) + "\n", encoding="utf-8")
    print(f"{OUT} : {len(rows)} tables")


if __name__ == "__main__":
    main()
