"""Items of the Vertebre: 10 sets, boss uniques, resources, consumables, keys and the 20 memory fragments.

An item row is the Dofus one (data/items.json): effects are [effect_id, min, max, value]; set bonuses are
sets[].effects[n-1]. Names and descriptions go through the text registry (name_id / description_id).
"""
from __future__ import annotations

import lore
import icons
from common import R, T, item_id, set_id

# effect ids (data/tables/effects.json)
VIT, STR, AGI, CHA, WIS, INT = 125, 118, 119, 123, 124, 126
AP, MP, PWR, DMG, CRIT, RANGE, INIT, PROSP, HEAL, SUMMON = 111, 128, 138, 112, 115, 117, 174, 176, 178, 182
RES = {"earth": 210, "water": 211, "air": 212, "fire": 213, "neutral": 214}
DMG_EL = {"earth": 422, "fire": 424, "water": 426, "air": 428, "neutral": 430}
WPN = {"water": 96, "earth": 97, "air": 98, "fire": 99, "neutral": 100}
DODGE_AP, DODGE_MP, REM_AP, REM_MP = 160, 161, 410, 412

TYPE = {"amulet": 1, "bow": 2, "wand": 3, "staff": 4, "dagger": 5, "sword": 6, "hammer": 7, "ring": 9, "belt": 10, "boots": 11,
        "potion": 12, "hat": 16, "cape": 17, "resource": 34, "quest": 80, "shield": 82, "key": 84}
WEAPON_SHAPE = {  # ap, min_range, range, crit%, crit_bonus, in_line
    "bow": (4, 2, 6, 25, 6, 0), "wand": (3, 1, 3, 30, 5, 0), "staff": (4, 1, 4, 30, 7, 1), "dagger": (3, 1, 1, 35, 6, 0),
    "sword": (3, 1, 1, 30, 5, 0), "hammer": (4, 1, 2, 25, 8, 1), "mace": (3, 1, 1, 25, 6, 0),
}
SYMBOL = {"amulet": "amulet", "bow": "bow", "wand": "staff", "staff": "staff", "dagger": "dagger", "sword": "sword", "hammer": "hammer",
          "ring": "ring", "belt": "belt", "boots": "boots", "potion": "potion", "hat": "hat", "cape": "cloak", "shield": "shield", "key": "key"}

ITEM: dict[str, int] = {}  # key -> item id (what monsters, shops and quests refer to)


def _add(key, name, desc, slot, level, effects, price=0, rarity=1, weapon=None, color=(160, 150, 140), set_=None, usable=False, symbol=None):
    iid = item_id()
    typ = TYPE[slot] if slot in TYPE else TYPE["staff" if slot == "mace" else "wand"]
    row = {"id": iid, "name_id": T(name), "name": name, "icon": iid, "type": typ, "level": level, "weight": 1 if slot not in ("resource",) else 1,
           "price": price, "description_id": T(desc) if desc else 0, "usable": usable, "criteria": "", "effects": effects}
    if weapon:
        row["weapon"] = weapon
    if set_:
        row["set"] = set_
    R.items.append(row)
    ITEM[key] = iid
    sym = symbol or SYMBOL.get(slot, "gem")
    R.icons.append(("Picto/Items/%d" % iid, lambda s=sym, c=color, r=rarity: icons.icon(s, c, rarity=r)))
    return iid


def stats(**kw):
    """vit=40, str=10, ap=1, res_fire=8, dmg_air=5 ... -> effect list."""
    out = []
    table = {"vit": VIT, "str": STR, "agi": AGI, "cha": CHA, "wis": WIS, "int": INT, "pwr": PWR, "dmg": DMG, "crit": CRIT, "range": RANGE,
             "init": INIT, "prosp": PROSP, "heal": HEAL, "summon": SUMMON, "ap": AP, "mp": MP, "dodge_ap": DODGE_AP, "dodge_mp": DODGE_MP,
             "rem_ap": REM_AP, "rem_mp": REM_MP}
    for k, v in kw.items():
        if k.startswith("res_"):
            out.append([RES[k[4:]], int(v), 0, 0])
        elif k.startswith("dmg_"):
            out.append([DMG_EL[k[4:]], int(v), 0, 0])
        else:
            out.append([table[k], int(v), 0, 0])
    return out


def weapon_effects(kind, element, level, bonus):
    lo, hi = 3 + round(level * 0.55), 6 + round(level * 0.8)
    return [[WPN[element], lo, hi, 0]] + bonus


def _weapon(kind):
    ap, mn, rg, cr, cb, line = WEAPON_SHAPE[kind]
    return {"ap": ap, "min_range": mn, "range": rg, "crit": cr, "crit_bonus": cb, "in_line": line, "los": 1, "per_turn": 1}


# ── the ten sets ───────────────────────────────────────────────────────────────
# floor, key, name, color, flavour, pieces: [(slot, name, stat dict)], bonuses (index = pieces - 1)

SETS = [
    dict(floor=1, key="seve", name="Panoplie de la Sève-Mère", color=(120, 170, 90),
         flavor="Tissée dans les fibres que Mère Ysmène donnait à la Tour. Elle est tiède, comme un être vivant.",
         pieces=[("hat", "Capuche de Sève", dict(vit=14, int=6, heal=3)), ("cape", "Manteau de Mousse", dict(vit=12, wis=6, res_earth=3)),
                 ("amulet", "Pendentif de Résine", dict(vit=10, cha=7, heal=3)), ("belt", "Ceinture de Lianes", dict(vit=12, int=5, init=30)),
                 ("boots", "Bottes de Racine", dict(vit=11, mp=0, cha=5, res_water=3)), ("ring", "Anneau de Bourgeon", dict(vit=8, int=5, pwr=4))],
         bonus=[None, dict(vit=10), dict(vit=14, heal=3), dict(int=14, cha=14), dict(heal=6, vit=22), dict(ap=0, pwr=14, heal=9, vit=30)]),
    dict(floor=1, key="ecorce", name="Panoplie de l'Écorce Ferrée", color=(140, 110, 80),
         flavor="Les gardes des Racines laissaient l'écorce pousser sur leurs armures, jusqu'à ne plus savoir où finissait la peau.",
         pieces=[("hat", "Heaume d'Écorce", dict(vit=16, str=6, res_earth=4)), ("shield", "Bouclier de Mousse-Ferrée", dict(vit=18, res_neutral=4, dodge_ap=3)),
                 ("ring", "Anneau de Lichen", dict(vit=9, str=6, dmg=2)), ("boots", "Brodequins d'Écorce", dict(vit=13, str=5, res_air=3)),
                 ("hammer", "Masse de Bois-Dur", dict(vit=10, str=8, dmg=3))],
         bonus=[None, dict(vit=12), dict(str=12, res_earth=4), dict(vit=24, dmg=4), dict(str=18, vit=30, res_neutral=6)]),
    dict(floor=2, key="cendrelame", name="Panoplie Cendrelame", color=(220, 100, 60),
         flavor="Le Capitaine Korvus fit forger ces pièces dans le feu même du lac. Elles ne refroidissent jamais tout à fait.",
         pieces=[("hat", "Heaume Calciné", dict(vit=26, agi=12, crit=2)), ("cape", "Cape de Braise", dict(vit=22, agi=10, dmg_air=4)),
                 ("amulet", "Collier de Médailles Fondues", dict(vit=20, agi=12, pwr=6)), ("belt", "Ceinture du Capitaine", dict(vit=24, agi=11, init=60)),
                 ("boots", "Bottes de Suie", dict(vit=22, agi=10, res_fire=5)), ("ring", "Anneau de Cendre", dict(vit=16, agi=9, dmg=4))],
         bonus=[None, dict(vit=18), dict(agi=18, crit=2), dict(dmg_air=6, vit=30), dict(agi=30, pwr=12, rem_mp=0), dict(ap=0, dmg=8, agi=40, crit=4, vit=40)]),
    dict(floor=2, key="brume", name="Voile de Brume", color=(150, 170, 180),
         flavor="Les chasseurs du marais s'enveloppaient de brume pour qu'on ne les voie pas arriver. La brume les a gardés.",
         pieces=[("hat", "Capuche de Brume", dict(vit=22, cha=12, range=1)), ("bow", "Arc de Brume", dict(vit=14, cha=10, dmg_water=5)),
                 ("ring", "Anneau de Vapeur", dict(vit=14, cha=9, pwr=5)), ("boots", "Bottes de Fumée", dict(vit=20, cha=9, dodge_mp=4)),
                 ("belt", "Ceinture de Gaze", dict(vit=22, cha=11, init=50))],
         bonus=[None, dict(vit=16), dict(cha=16, range=0), dict(dmg_water=7, vit=26), dict(cha=30, pwr=14, vit=36, range=1)]),
    dict(floor=3, key="rouage", name="Panoplie du Rouage-Inversé", color=(190, 150, 70),
         flavor="Chaque pièce tourne sur elle-même quand on ne la regarde pas. Les Renversés prétendent qu'ainsi elle garde l'heure.",
         pieces=[("hat", "Casque de Cuivre", dict(vit=38, str=15, res_neutral=5)), ("cape", "Cape de Poulies", dict(vit=34, str=13, res_earth=5)),
                 ("amulet", "Amulette d'Horloge", dict(vit=30, str=14, dodge_ap=4)), ("belt", "Ceinture à Engrenages", dict(vit=34, str=13, init=70)),
                 ("boots", "Bottes à Ressort", dict(vit=32, str=12, mp=0, dodge_mp=5)), ("ring", "Anneau de Pignon", dict(vit=24, str=11, dmg=5))],
         bonus=[None, dict(vit=24), dict(str=24, res_neutral=5), dict(vit=40, dmg=6), dict(str=40, res_earth=8, dodge_ap=6), dict(mp=0, vit=70, str=50, res_neutral=10, dmg=10)]),
    dict(floor=3, key="mecano", name="Panoplie du Mécanicien Muet", color=(80, 190, 180),
         flavor="Tarq-9 ne parle plus, mais ses outils, eux, continuent de le faire à sa place : un cliquetis, de loin en loin.",
         pieces=[("hat", "Chapeau de Mécanicien", dict(vit=32, int=14, pwr=6)), ("shield", "Bouclier d'Engrenage", dict(vit=34, int=10, res_fire=6, dodge_ap=4)),
                 ("ring", "Anneau de Rivet", dict(vit=22, int=11, dmg_fire=4)), ("boots", "Brodequins de Fonte", dict(vit=30, int=11, res_air=5)),
                 ("hammer", "Marteau de Tarq", dict(vit=20, int=13, dmg_fire=6))],
         bonus=[None, dict(vit=22), dict(int=22, pwr=8), dict(dmg_fire=8, vit=36), dict(int=40, pwr=16, vit=50, summon=1)]),
    dict(floor=4, key="maree", name="Panoplie de la Marée-Savante", color=(90, 140, 220),
         flavor="Les pages gorgées d'eau ne s'effacent pas : elles pèsent. Ces vêtements portent trois siècles de lecture.",
         pieces=[("hat", "Capuche Détrempée", dict(vit=46, wis=16, heal=6)), ("cape", "Cape de Pages", dict(vit=42, int=16, heal=5)),
                 ("amulet", "Collier d'Encrier", dict(vit=38, int=17, pwr=8)), ("belt", "Ceinture de Reliure", dict(vit=42, wis=15, init=90)),
                 ("boots", "Bottes Gorgées", dict(vit=40, cha=15, res_water=7)), ("ring", "Anneau Marque-Page", dict(vit=30, int=13, heal=5))],
         bonus=[None, dict(vit=30), dict(int=30, heal=6), dict(vit=50, pwr=10), dict(heal=14, int=50, vit=60, res_water=8), dict(ap=0, heal=22, pwr=24, int=70, vit=90)]),
    dict(floor=4, key="encre", name="Panoplie de l'Encre-Noire", color=(60, 50, 90),
         flavor="L'encre de Séléné ne sèche pas. On dit qu'elle écrit encore, la nuit, dans la marge de ceux qui l'ont lue.",
         pieces=[("hat", "Chapeau de Scribe Noir", dict(vit=40, agi=15, crit=3)), ("dagger", "Dague de Plume", dict(vit=28, agi=14, dmg_air=6)),
                 ("ring", "Anneau d'Index", dict(vit=28, agi=12, crit=2)), ("boots", "Bottes de Papier", dict(vit=38, agi=13, dodge_mp=6)),
                 ("shield", "Livre-Bouclier", dict(vit=42, agi=10, res_neutral=7, dodge_ap=5))],
         bonus=[None, dict(vit=28), dict(agi=28, crit=3), dict(dmg_air=10, vit=48), dict(agi=50, crit=6, pwr=18, vit=60)]),
    dict(floor=5, key="aurore", name="Panoplie de l'Aurore-Brisée", color=(250, 200, 120),
         flavor="Les Aurés laissent tomber des éclats en passant. Quelqu'un a eu l'idée de les coudre.",
         pieces=[("hat", "Diadème d'Aurore", dict(vit=60, int=20, pwr=10, ap=0)), ("cape", "Cape d'Azur", dict(vit=54, wis=18, res_fire=8, init=100)),
                 ("amulet", "Amulette de la Couronne", dict(vit=50, cha=20, pwr=10)), ("belt", "Ceinture de Lumière", dict(vit=54, str=18, init=110)),
                 ("boots", "Bottes d'Éclat", dict(vit=52, agi=18, dodge_mp=7)), ("ring", "Anneau d'Aube", dict(vit=40, int=16, dmg=7))],
         bonus=[None, dict(vit=40), dict(pwr=14, vit=44), dict(dmg=12, vit=60), dict(ap=0, pwr=24, vit=80, res_fire=8), dict(ap=1, pwr=32, dmg=14, vit=120, res_air=8)]),
    dict(floor=5, key="gravit", name="Panoplie du Premier Gravit", color=(235, 232, 250),
         flavor="Les armes d'Aurelian, fondues à la lueur de la Couronne. Elles pèsent le poids de ce qu'on perd en montant.",
         pieces=[("hat", "Heaume du Gravit", dict(vit=70, str=24, res_neutral=9)), ("sword", "Lame du Premier Gravit", dict(vit=36, str=22, dmg=9, crit=3)),
                 ("shield", "Bouclier de Voûte", dict(vit=66, res_earth=10, res_water=10, dodge_ap=7)), ("ring", "Anneau de Cime", dict(vit=46, str=18, dmg=8)),
                 ("boots", "Bottes de Cime", dict(vit=58, str=20, dodge_mp=8))],
         bonus=[None, dict(vit=50), dict(str=40, res_neutral=8), dict(dmg=16, vit=80), dict(ap=1, str=60, vit=100, dmg=14, crit=5)]),
]
FLOOR_LEVEL = {1: 4, 2: 14, 3: 24, 4: 34, 5: 44}

WEAPON_ELEMENT = {"bow": "air", "wand": "fire", "staff": "water", "dagger": "air", "sword": "neutral", "hammer": "earth", "mace": "earth"}


def build_sets():
    for st in SETS:
        sid = set_id()
        base = FLOOR_LEVEL[st["floor"]]
        ids = []
        for n, (slot, name, ef) in enumerate(st["pieces"]):
            level = base + n * (2 if st["floor"] < 5 else 1) + (1 if len(st["pieces"]) == 5 else 0)
            level = min(level, base + 9)
            effects = stats(**{k: v for k, v in ef.items() if v})
            weapon = None
            if slot in WEAPON_SHAPE:
                effects = weapon_effects(slot, WEAPON_ELEMENT[slot], level, effects)
                weapon = _weapon(slot)
            tier = {1: 2, 2: 2, 3: 3, 4: 3, 5: 4}[st["floor"]]
            ids.append(_add("%s_%s" % (st["key"], slot), name, st["flavor"] if n == 0 else "Fait partie de la %s. %s" % (st["name"], st["flavor"].split(".")[0] + "."),
                            slot, level, effects, price=level * level * 12 + 200, rarity=tier, weapon=weapon, color=st["color"], set_=sid))
        bonus = []
        for b in st["bonus"]:
            bonus.append([] if b is None else stats(**{k: v for k, v in b.items() if v}))
        R.sets.append({"id": sid, "name_id": T(st["name"]), "items": ids, "effects": bonus})
        st["id"] = sid


# ── boss uniques ───────────────────────────────────────────────────────────────

UNIQUES = [
    ("ysmene_staff", "Bâton de la Racine-Mère", "Le bois n'est plus tout à fait mort. Parfois, une feuille y pousse, au printemps qui n'existe plus.", "staff", 10, (190, 120, 255), dict(int=22, heal=6, pwr=8, vit=30), 1),
    ("ysmene_ring", "Anneau de Mère Ysmène", "Elle l'a retiré une seule fois : pour le donner à quelqu'un qui n'est pas revenu.", "ring", 10, (190, 120, 255), dict(vit=40, wis=14, heal=5, prosp=12), 1),
    ("korvus_sword", "Épée Cendrelame", "Elle ne perd jamais son tranchant, ni sa chaleur. Elle a gardé la poignée de Korvus, brûlée à l'endroit exact de sa main.", "sword", 20, (255, 140, 70), dict(agi=24, dmg=9, crit=3, vit=30), 2),
    ("korvus_amulet", "Médaille du Capitaine", "« Pour avoir marché sur l'eau. » L'eau est partie. La médaille, non.", "amulet", 20, (255, 140, 70), dict(vit=50, str=18, dmg_fire=8, init=80), 2),
    ("tarq_bow", "Arc de Cuivre-Tendu", "Les cordes sont des câbles d'horlogerie. Il tire des flèches à la seconde exacte.", "bow", 30, (110, 220, 210), dict(cha=28, dmg=10, range=1, vit=40), 3),
    ("tarq_belt", "Ceinture de l'Architecte", "Chaque boucle est un plan. Aucune ne se termine.", "belt", 30, (110, 220, 210), dict(vit=70, int=24, ap=0, init=120, dodge_ap=6), 3),
    ("selene_wand", "Baguette de Séléné", "Elle écrit toute seule dans l'air des mots qu'on a oubliés d'avoir lus.", "wand", 40, (240, 230, 170), dict(int=30, pwr=14, heal=8, vit=50), 4),
    ("selene_cape", "Cape de Marges", "Brodée de notes. Une main inconnue y a écrit : « Orsolan savait. »", "cape", 40, (240, 230, 170), dict(vit=76, wis=24, res_water=9, init=100), 4),
    ("aurelian_dagger", "Dague d'Aurelian", "Il n'en a jamais eu besoin. Il la gardait pour couper le Fil, s'il le fallait. Il ne l'a pas fait.", "dagger", 50, (255, 230, 120), dict(agi=36, dmg=14, crit=6, vit=60), 5),
    ("aurelian_crown", "Couronne du Dormeur", "Elle est très légère. C'est cela qui est inquiétant.", "hat", 50, (255, 230, 120), dict(vit=110, int=30, pwr=22, ap=1, dodge_mp=8), 5),
]


def build_uniques():
    for key, name, desc, slot, level, color, ef, floor in UNIQUES:
        effects = stats(**{k: v for k, v in ef.items() if v})
        weapon = None
        if slot in WEAPON_SHAPE:
            effects = weapon_effects(slot, WEAPON_ELEMENT[slot], level, effects)
            weapon = _weapon(slot)
        _add(key, name, desc, slot, level, effects, price=level * level * 30, rarity=4, weapon=weapon, color=color)


# ── resources, consumables, keys, fragments ─────────────────────────────────────

RESOURCES = {
    1: [("spore", "Spore Luisante", "Elle éclaire à peine, mais elle éclaire toujours.", (170, 110, 255), "gem"),
        ("seve", "Sève Épaisse", "Elle s'écoule lentement des murs, comme un souvenir.", (150, 190, 90), "potion"),
        ("ecorce", "Écorce Durcie", "Arrachée à une racine qui n'a pas protesté.", (140, 110, 80), "cloth"),
        ("larme", "Larme de Racine", "Un sanglot figé. Il fait chaud dans la paume.", (190, 120, 255), "essence")],
    2: [("cendre", "Cendre Vive", "Elle rougeoie encore. Elle rougeoiera toujours.", (255, 120, 60), "essence"),
        ("braise", "Braise Éteinte", "Elle a été éteinte, une fois. Elle n'a pas apprécié.", (200, 90, 50), "ore"),
        ("suie", "Suie Grasse", "Ce qui reste d'un feu qui n'a rien consumé d'autre que l'air.", (110, 100, 100), "cloth"),
        ("lame_fondue", "Lame Fondue", "Un éclat de l'épée du Capitaine, tordu par sa propre chaleur.", (255, 140, 70), "ore")],
    3: [("rouage", "Rouage Cuivré", "Il tourne encore, à vide, si on le tient assez longtemps.", (200, 150, 70), "ore"),
        ("ressort", "Ressort Brisé", "Il a tenu des siècles. Puis il a lâché, d'un coup, sans bruit.", (170, 170, 180), "ore"),
        ("huile", "Huile Noire", "On s'en servait pour le temps. Elle en garde le goût.", (50, 50, 60), "potion"),
        ("plan", "Plan Calciné", "Un plan de la Cité, brûlé sur le bord. Au centre, un cercle : la Couronne.", (110, 220, 210), "scroll")],
    4: [("page", "Page Mouillée", "On peut la lire. Il vaut mieux ne pas.", (220, 210, 170), "scroll"),
        ("encre", "Encre Sombre", "Elle s'écrit seule, dès qu'on détourne les yeux.", (50, 50, 110), "potion"),
        ("reliure", "Reliure Gorgée", "Le cuir a bu trois siècles d'éther. Il en suinte.", (110, 80, 60), "cloth"),
        ("index", "Index Effacé", "Il listait des noms. Il n'en reste qu'un, rayé.", (240, 230, 170), "scroll")],
    5: [("eclat", "Éclat d'Azur", "Un fragment du ciel, tombé par mégarde.", (120, 180, 255), "gem"),
        ("plume", "Plume d'Aurore", "Légère, tiède, et tout à fait indifférente à la gravité.", (255, 220, 150), "wing"),
        ("poussiere", "Poussière de Ciel", "On la respire sans s'en rendre compte, et l'on rêve ensuite d'en haut.", (200, 200, 240), "essence"),
        ("coeur", "Cœur d'Aurelian", "Il bat, très lentement. Une fois par heure. Peut-être moins.", (255, 230, 120), "gem")],
}

POTIONS = [("potion1", "Potion de Soin mineure", 1, 30, 40), ("potion2", "Potion de Soin", 12, 75, 120), ("potion3", "Potion de Soin majeure", 24, 140, 260),
           ("potion4", "Élixir de Soin", 36, 220, 480), ("potion5", "Élixir de l'Aurore", 46, 330, 900)]
SCROLLS = [("parch_str", "Parchemin de Force", 607), ("parch_int", "Parchemin d'Intelligence", 611), ("parch_cha", "Parchemin de Chance", 608),
           ("parch_agi", "Parchemin d'Agilité", 609), ("parch_vit", "Parchemin de Vitalité", 610), ("parch_wis", "Parchemin de Sagesse", 606)]
KEYS = [(1, "Sceau de la Racine-Mère", "Un cachet de sève durcie. Il s'ouvre devant l'escalier du premier étage."),
        (2, "Sceau du Capitaine Éteint", "Un anneau de métal noirci, encore tiède."),
        (3, "Sceau de l'Architecte", "Un jeton de cuivre gravé d'un plan en spirale."),
        (4, "Sceau de la Bibliothécaire", "Une plaque d'ivoire fine comme une page."),
        (5, "Sceau du Premier Gravit", "Un éclat de lumière solide. Il ouvre la dernière porte.")]


def build_misc():
    for floor, lst in RESOURCES.items():
        lv = FLOOR_LEVEL[floor]
        for key, name, desc, color, sym in lst:
            _add("res_" + key, name, desc, "resource", lv + 2, [], price=lv * 2, rarity=1 if key not in ("larme", "lame_fondue", "plan", "index", "coeur") else 2,
                 color=color, symbol=sym)
    for key, name, lvl, heal_, price in POTIONS:
        _add(key, name, "Rend %d points de vie. Au goût de ce que l'on trouve par ici." % heal_, "potion", lvl, [[110, heal_, 0, 0]], price=price, rarity=1,
             color=(220, 90, 110), usable=True)
    _add("rappel", "Potion de Rappel du Pied-de-Tour", "Une gorgée, et l'on se retrouve au camp, la bouche pâteuse et le cœur plus lourd.", "potion", 1, [[600, 0, 0, 0]],
         price=60, rarity=1, color=(120, 160, 240), usable=True)
    for key, name, eff in SCROLLS:
        _add(key, name, "Un parchemin d'Orsolan, dont la formule n'a pas changé depuis l'époque du Concile.", "quest", 1, [[eff, 1, 0, 0]], price=900, rarity=2,
             color=(230, 220, 160), usable=True, symbol="scroll")
    for floor, name, desc in KEYS:
        _add("key%d" % floor, name, desc, "key", FLOOR_LEVEL[floor], [], price=0, rarity=3, color=lore.FLOORS[floor]["accent"])
    for floor, frs in lore.FRAGMENTS.items():
        for i, (name, text) in enumerate(frs):
            _add("frag_%d_%d" % (floor, i + 1), name, text, "quest", FLOOR_LEVEL[floor], [[193, 9000 + floor * 10 + i, 0, 0]], price=0, rarity=3,
                 color=lore.FLOORS[floor]["accent"], symbol="fragment")


def build_endings():
    _add("fil_noue", "Fil noué", "Le Fil, renoué à la Couronne. Il vous tient autant que vous le tenez.", "quest", 50, [[193, 9100, 0, 0]], rarity=4, color=(255, 220, 120), symbol="chain")
    _add("fil_tranche", "Fil tranché", "Un bout de corde d'éther, tranché net. Il ne vibre plus.", "quest", 50, [[193, 9101, 0, 0]], rarity=4, color=(150, 150, 200), symbol="chain")


def build():
    build_sets()
    build_endings()
    build_uniques()
    build_misc()
    return ITEM
