"""The five bosses (the Fragments of the Council) and the minions they and other creatures summon.

A boss is not a bigger creature: it has its own six or seven spells (summons, glyphs, shields, pulls, debuffs),
8 AP, 4 MP, and 7-10 times the hp of a regular creature of its level. Its story lives in lore.BOSSES.
"""
from __future__ import annotations

import lore
from common import R, T, bone_id, monster_id
from items import ITEM
from mobs import (BOSS_IDS, MINIONS, kill_xp, _portrait, _stats, aoe, base, bolt, dash, drain, flt, guard, glyph, hex_ap, hex_mp, mend, mend_self, shove, spawn,
                  srp, strike, thorns, tug, up)
from spells_lib import E, ap, dmg, monster_spell, mp, stat, summon_def


def make_minions():
    """Summoned creatures (data/spells.json "summons"). Used by bosses and by the Archiviste Dévoyé."""
    def mk(key, name, spec, hp, ap_, mp_, spells, scale=90, plays=True, res=0):
        bone = str(bone_id())
        R.bones[bone] = spec
        MINIONS[key] = summon_def(name, bone, hp, ap_, mp_, spells=spells, plays=plays, scale=scale, res=res)
        return MINIONS[key]
    mk("livre", "Livre invoqué", flt(4, (30, 10, -10), core="tome", r=10, sats=2, wisps=0, hover=18), 70, 6, 3,
       [bolt("Coup de reliure", "water", 34, (1, 3)), hex_ap("Page avalée", "water", 34, 2, (1, 3), cd=3)], scale=95)
    mk("pousse", "Jeune Pousse", srp(1, (30, 30, -20), segs=4, w=5), 60, 6, 3,
       [strike("Griffe verte", "earth", 10, 3, (1, 1)), mend("Photosynthèse", 10, (1, 4), cd=2)], scale=90)
    mk("braise_liee", "Braise liée", flt(2, (40, -20, -10), core="flame", r=10, sats=0, wisps=2, hover=16), 60, 6, 4,
       [bolt("Étincelle liée", "fire", 20, (1, 4)),
        monster_spell("Dernière flamme", "fire", 3, (0, 0), [dmg("fire", *base(20, 4, 1.3), area=("circle", 2)), E("kill", target="caster", mask="C")], symbol="burst",
                      area={"shape": "circle", "size": 2})], scale=90)
    mk("tourelle", "Tourelle de Plan", flt(3, (20, 20, 20), core="crystal", r=12, sats=2, wisps=0, hover=14), 110, 6, 0,
       [bolt("Tir réglé", "neutral", 30, (2, 6), k=1.0), hex_ap("Calibrage", "neutral", 30, 2, (2, 5), cd=3)], plays=True, scale=105, res=15)
    mk("spectre_livre", "Spectre de Marge", flt(4, (30, 30, 30), core="ghost", r=12, sats=0, wisps=0, hover=22), 160, 6, 3,
       [bolt("Mot de passe", "neutral", 40, (2, 5)), hex_mp("Silence", "neutral", 40, 2, (2, 5), cd=3)], scale=95)
    mk("eclat", "Éclat de Couronne", flt(5, (30, 30, 30), core="crystal", r=12, sats=3, wisps=0, hover=22), 320, 6, 3,
       [bolt("Rayon d'azur", "air", 50, (2, 6)), aoe("Éclatement", "air", 50, 1, (1, 4), 4, 0.8, cd=2)], scale=105)


def _boss(floor, level, spec, el, hp_mult, res, spells, drops, scale=115, mp_=4, ap_=7):
    info = lore.BOSSES[floor]
    mid = monster_id()
    bone = str(bone_id())
    R.bones[bone] = spec
    hp = int((12 + 5.5 * level + 0.05 * level * level) * hp_mult)
    st = {k: int(v * 1.15) for k, v in _stats(level, el).items()}
    st["ap_dodge"] = level // 2
    st["mp_dodge"] = level // 2
    dl = [{"item": ITEM[k], "pct": float(p)} for k, p in drops if k in ITEM]
    sp = [s for s in spells(int(level * 0.8)) if s]  # they hit a little under their level: the hp, the AP and the tricks make the fight
    grade = {"monster": mid, "name_id": T(info["name"]), "name": info["name"], "look": "{%s|||%d}" % (bone, scale), "portrait": int(bone), "grade": 1,
             "level": level, "hp": hp, "ap": ap_, "mp": mp_, "xp": kill_xp(level, floor, boss=True), "stats": st, "res": {e: int(res.get(e, 0)) for e in ("earth", "fire", "water", "air", "neutral")},
             "spells": sp, "drops": dl, "kamas": [level * 40, level * 90], "aggro": {"zone": 5, "level_diff": 80, "immunity": "", "delay": 4000}}
    R.bosses[str(mid)] = {"name_id": T(info["name"]), "name": info["name"], "race": 0, "grades": [grade]}
    BOSS_IDS[floor] = mid
    R.icons.append(("Picto/Monsters/%d" % int(bone), (lambda b=bone, s=spec: _portrait(b, s))))
    return grade


def build_bosses():
    def drops(f, extra):
        mat = {1: "larme", 2: "lame_fondue", 3: "plan", 4: "index", 5: "coeur"}[f]
        return [("key%d" % f, 100), ("res_" + mat, 100)] + extra

    _boss(1, 10,
          up(1, (40, -10, 60), head="hood", body="robe", weapon="staff", extras=["feather"], limbs="sleeve", arm_w=3.2, attack="cast", motif="rune", h=34, w=14, hs=9.5, wing=42),
          "earth", 4.4, dict(earth=25, water=25, fire=-25, air=-10),
          lambda lv: [tug("Étreinte des racines", "earth", lv, 3, (2, 6), 4, 0.9), aoe("Floraison", "earth", lv, 2, (1, 5), 5, 0.9, cd=2),
                      hex_mp("Sporée", "water", lv, 2, (1, 5), cd=2), mend_self("Sève nourricière", lv, 12, cd=3), spawn("Éveil des pousses", MINIONS["pousse"], 4, (1, 3), 3),
                      glyph("Racines enchevêtrées", "earth", lv, 2, (1, 5), 3, 4, 0.5, extra=[mp(1, duration=1, mask="A")]), guard("Bouclier d'écorce", lv, 30)],
          drops(1, [("seve_hat", 30), ("seve_cape", 30), ("seve_amulet", 30), ("seve_belt", 30), ("seve_boots", 30), ("seve_ring", 30), ("ysmene_staff", 25), ("ysmene_ring", 25)]), scale=125)
    _boss(2, 20,
          up(2, (30, -20, -20), head="helm", body="armor", weapon="sword", extras=["cape"], limbs="armor", arm_w=3.8, attack="slash", motif="cracks", h=34, w=14, hs=9, leg=26),
          "fire", 4.4, dict(fire=40, earth=15, neutral=15, water=-30, air=-10),
          lambda lv: [strike("Estoc ardent", "fire", lv, 4, (1, 1), 1.15), dash("Charge du Capitaine", "fire", lv, 1.0, (2, 7)),
                      glyph("Brasier", "fire", lv, 3, (1, 5), 4, 4, 0.55, extra=[mp(1, duration=1, mask="A")], cd=3), aoe("Cercle de feu", "fire", lv, 2, (0, 0), 5, 0.9, cd=3),
                      spawn("Braise liée", MINIONS["braise_liee"], 3, (1, 3), 2), guard("Cuirasse de braise", lv, 35),
                      monster_spell("Ordre de garde", "fire", 2, (0, 0), [stat("power", 40, 3, target="caster", mask="C"), stat("res_all", 12, 3)], symbol="arrow", cooldown=4)],
          drops(2, [("cendrelame_hat", 30), ("cendrelame_cape", 30), ("cendrelame_amulet", 30), ("cendrelame_belt", 30), ("cendrelame_boots", 30), ("cendrelame_ring", 30),
                    ("brume_hat", 25), ("brume_bow", 25), ("korvus_sword", 25), ("korvus_amulet", 25)]), scale=120)
    _boss(3, 30,
          up(3, (0, 20, 20), head="cyclops", body="plate", weapon="hammer", off="orb", limbs="armor", arm_w=5, leg_w=4.8, h=38, w=17, leg=24, arm=18, fore=17, hs=10, attack="slam", motif="rune", heavy=True),
          "neutral", 4.6, dict(neutral=35, earth=20, fire=15, water=-30, air=-10),
          lambda lv: [spawn("Tourelle de plan", MINIONS["tourelle"], 4, (1, 4), 2), glyph("Plan de masse", "neutral", lv, 3, (1, 5), 3, 4, 0.55, cd=3),
                      tug("Intégration", "neutral", lv, 3, (2, 6), 4, 1.0), hex_ap("Réajustement", "neutral", lv, 3, (1, 5), cd=2),
                      mend_self("Réparation", lv, 18, cd=3), guard("Bouclier de plans", lv, 35), aoe("Découpe", "fire", lv, 2, (1, 5), 5, 0.9, cd=2)],
          drops(3, [("rouage_hat", 30), ("rouage_cape", 30), ("rouage_amulet", 30), ("rouage_belt", 30), ("rouage_boots", 30), ("rouage_ring", 30),
                    ("mecano_hat", 25), ("mecano_hammer", 25), ("tarq_bow", 25), ("tarq_belt", 25)]), scale=125)
    _boss(4, 40,
          up(4, (60, 70, 60), head="mask", body="robe", weapon="orb", off="orb", extras=["cape"], limbs="sleeve", arm_w=3, attack="cast", motif="core", h=33, w=13, hs=9),
          "water", 4.8, dict(water=40, neutral=20, fire=-30, earth=-10),
          lambda lv: [thorns("Citation en retour", 25, 2, 3), shove("Page tournée", "water", lv, 3, (1, 4), 4, 1.0), aoe("Ruée d'encre", "water", lv, 3, (1, 5), 6, 0.9, cd=3),
                      spawn("Spectre de marge", MINIONS["spectre_livre"], 4, (1, 3), 2), hex_ap("Silence", "water", lv, 3, (2, 6), cd=2), drain("Lecture dévorante", "water", lv, (1, 4), 4, 0.9),
                      glyph("Marée haute", "water", lv, 3, (1, 5), 3, 4, 0.55, extra=[ap(1, duration=1, mask="A")], cd=3), guard("Voile d'encre", lv, 35)],
          drops(4, [("maree_hat", 30), ("maree_cape", 30), ("maree_amulet", 30), ("maree_belt", 30), ("maree_boots", 30), ("maree_ring", 30),
                    ("encre_hat", 25), ("encre_dagger", 25), ("selene_wand", 25), ("selene_cape", 25)]), scale=120)
    _boss(5, 50,
          up(5, (30, 30, 20), head="helm", body="armor", weapon="sword", off="shield", extras=["cape", "feather"], limbs="armor", arm_w=4, attack="slash", motif="core", h=36, w=15, hs=10, leg=27, wing=48),
          "neutral", 5.1, dict(neutral=30, air=30, fire=20, earth=-15, water=-15),
          lambda lv: [strike("Lame du Premier Gravit", "neutral", lv, 4, (1, 1), 1.2), dash("Piqué céleste", "air", lv, 1.1, (2, 7)),
                      aoe("Éclat de couronne", "air", lv, 3, (1, 5), 6, 0.9, cd=3), glyph("Cime", "fire", lv, 3, (1, 5), 3, 4, 0.55, extra=[mp(1, duration=1, mask="A")], cd=3),
                      spawn("Appel des Aurés", MINIONS["eclat"], 4, (1, 3), 2), guard("Armure d'aurore", lv, 35),
                      monster_spell("Gravir", "neutral", 2, (0, 0), [ap(2, sign=1, duration=1, target="caster", mask="C", dodge=False), stat("power", 40, 2, target="caster", mask="C")], symbol="arrow", cooldown=4),
                      mend_self("Pardon", lv, 10, cd=4)],
          drops(5, [("aurore_hat", 30), ("aurore_cape", 30), ("aurore_amulet", 30), ("aurore_belt", 30), ("aurore_boots", 30), ("aurore_ring", 30),
                    ("gravit_hat", 25), ("gravit_sword", 25), ("gravit_shield", 25), ("gravit_ring", 25), ("gravit_boots", 25), ("aurelian_dagger", 25), ("aurelian_crown", 25)]), scale=130)
