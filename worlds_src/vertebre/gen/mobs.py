"""The bestiary of the Vertebre: 9 creatures + 1 boss per floor (50 in all).

Each creature is a visual spec (a bone, rigs.py), a role that decides its spells (the fight AI deduces its
profile from them: kamikaze / summoner / healer / cautious / aggressive) and its numbers (level, hp, resistances).
Damage per AP is calibrated on the level: base(L) = 1.8 + 0.12 L, multiplied by the monster's element stat (1.5 L).
"""
from __future__ import annotations

import icons
import lore
from common import R, T, bone_id, monster_id
from items import ITEM
from rigs import Pal, mix
from spells_lib import (E, ap, dmg, heal, heal_pct, hidden, monster_spell, mp, pull, push, shield, state, stat, steal, summon_def)

FLOOR_PAL = {f: (lore.FLOORS[f]["color"], lore.FLOORS[f]["accent"]) for f in range(1, 6)}
STAT_OF = {"earth": "strength", "fire": "intelligence", "water": "chance", "air": "agility", "neutral": "strength"}


def base(level, ap_=3, k=1.0):
    b = (1.8 + 0.12 * level) * ap_ * k
    return max(2, round(b * 0.85)), max(3, round(b * 1.15))


def pal(floor, dm=(0, 0, 0), acc=None, light=0.0):
    m, a = FLOOR_PAL[floor]
    main = tuple(max(10, min(250, int(m[i] + dm[i]))) for i in range(3))
    if light:
        main = mix(main, (255, 255, 255), light)
    return Pal(main, acc or a)


UP = dict(arch="upright", h=30, w=11, leg=25, arm=14, fore=13, hs=8.5, body="robe", head="round", limbs="sleeve", attack="slash", motif="core")


def up(floor, dm=(0, 0, 0), acc=None, **kw):
    d = dict(UP)
    d.update(kw)
    d["pal"] = pal(floor, dm, acc)
    return d


def bst(floor, dm=(0, 0, 0), acc=None, **kw):
    d = dict(arch="beast", body_len=20, body_h=12, leg=13, hs=8, head="wolf")
    d.update(kw)
    d["pal"] = pal(floor, dm, acc)
    return d


def flt(floor, dm=(0, 0, 0), acc=None, **kw):
    d = dict(arch="floater", r=12, core="eye", sats=2, wisps=1, hover=20)
    d.update(kw)
    d["pal"] = pal(floor, dm, acc)
    return d


def srp(floor, dm=(0, 0, 0), acc=None, **kw):
    d = dict(arch="serpent", segs=6, w=6)
    d.update(kw)
    d["pal"] = pal(floor, dm, acc)
    return d


# ── spell patterns: each returns a spell id ─────────────────────────────────────

def strike(name, el, L, ap_=3, rng=(1, 1), k=1.0, extra=(), cd=0, symbol="fist", **o):
    lo, hi = base(L, ap_, k)
    return monster_spell(name, el, ap_, rng, [dmg(el, lo, hi)] + list(extra), symbol=symbol, cooldown=cd, **o)


def bolt(name, el, L, rng=(2, 5), ap_=3, k=0.9, extra=(), cd=0, symbol="flame", **o):
    lo, hi = base(L, ap_, k)
    return monster_spell(name, el, ap_, rng, [dmg(el, lo, hi)] + list(extra), symbol=symbol, cooldown=cd, **o)


def aoe(name, el, L, size=1, rng=(1, 5), ap_=4, k=0.85, extra=(), cd=2, symbol="burst", **o):
    lo, hi = base(L, ap_, k)
    return monster_spell(name, el, ap_, rng, [dmg(el, lo, hi, area=("circle", size))] + list(extra), symbol=symbol, area={"shape": "circle", "size": size}, cooldown=cd, **o)


def drain(name, el, L, rng=(1, 3), ap_=3, k=0.8, cd=0):
    lo, hi = base(L, ap_, k)
    return monster_spell(name, el, ap_, rng, [steal(el, lo, hi)], symbol="skull", cooldown=cd)


def mend(name, L, rng=(1, 4), ap_=3, k=1.0, size=0, cd=1):
    lo, hi = base(L, ap_, k * 1.2)
    return monster_spell(name, "water", ap_, rng, [heal(lo, hi, target="allies", mask="a", area=("circle", size) if size else ("point", 0))], symbol="heal",
                         area={"shape": "circle", "size": size} if size else {"shape": "point", "size": 0}, cooldown=cd)


def mend_self(name, L, pct=15, cd=3):
    return monster_spell(name, "water", 3, (0, 0), [heal_pct(pct, target="caster", mask="C")], symbol="heal", cooldown=cd)


def guard(name, L, pct=25, cd=3, el="neutral"):
    return monster_spell(name, el, 3, (0, 0), [shield(pct, duration=2, target="caster", mask="C")], symbol="shield", cooldown=cd)


def hex_ap(name, el, L, n=2, rng=(1, 5), cd=2, k=0.5):
    lo, hi = base(L, 2, k)
    return monster_spell(name, el, 3, rng, [dmg(el, lo, hi), ap(n, duration=1)], symbol="eye", cooldown=cd)


def hex_mp(name, el, L, n=2, rng=(1, 5), cd=2, k=0.5):
    lo, hi = base(L, 2, k)
    return monster_spell(name, el, 3, rng, [dmg(el, lo, hi), mp(n, duration=1)], symbol="chain", cooldown=cd)


def shove(name, el, L, n=2, rng=(1, 1), ap_=3, k=0.9, cd=2):
    lo, hi = base(L, ap_, k)
    return monster_spell(name, el, ap_, rng, [dmg(el, lo, hi), push(n)], symbol="fist", cooldown=cd)


def tug(name, el, L, n=3, rng=(2, 6), ap_=3, k=0.8, cd=2):
    lo, hi = base(L, ap_, k)
    return monster_spell(name, el, ap_, rng, [dmg(el, lo, hi), pull(n)], symbol="chain", line=True, cooldown=cd)


def blast(name, el, L, size=2, k=1.4):
    """Kamikaze: damages around itself and dies (the AI classes it by the `kill` on the caster)."""
    lo, hi = base(L, 4, k)
    return monster_spell(name, el, 3, (0, 0), [dmg(el, lo, hi, area=("circle", size)), E("kill", target="caster", mask="C")], symbol="burst",
                         area={"shape": "circle", "size": size})


def veil(name, L, turns=2):
    return monster_spell(name, "shadow", 2, (0, 0), [state(960_900, turns, flags=["invisible"])], symbol="moon", cooldown=4)


def backstab(name, el, L, k=1.3, cd=2):
    lo, hi = base(L, 4, k)
    return monster_spell(name, el, 4, (1, 1), [dmg(el, lo, hi)], symbol="dagger", cooldown=cd)


def empower(name, L, amount=None, area=2, cd=3):
    amount = amount or 10 + L
    return monster_spell(name, "neutral", 3, (0, 0), [stat("power", amount, 3, target="allies", mask="a", area=("circle", area))], symbol="arrow",
                         area={"shape": "circle", "size": area}, cooldown=cd)


def glyph(name, el, L, size=2, rng=(2, 5), turns=3, ap_=4, k=0.55, extra=(), cd=3):
    lo, hi = base(L, ap_, k)
    gid = hidden(name + " (glyphe)", el, [dmg(el, lo, hi, mask="A")] + list(extra))
    return monster_spell(name, el, ap_, rng, [E("glyph_start", target="all", mask="a,A", duration=turns, color="#ff8040", mark={"shape": "circle", "size": size},
                                                  origin=0, spell=gid)], symbol="glyph", cooldown=cd)


def trap(name, el, L, size=1, rng=(1, 5), ap_=3, k=0.9, extra=(), cd=2):
    lo, hi = base(L, ap_, k)
    gid = hidden(name + " (piège)", el, [dmg(el, lo, hi, area=("circle", size), mask="A")] + list(extra))
    return monster_spell(name, el, ap_, rng, [E("trap", target="all", mask="a,A", color="#b04030", mark={"shape": "circle", "size": size}, origin=0, spell=gid)],
                         symbol="trap", free=True, cooldown=cd)


def spawn(name, mid, ap_=4, rng=(1, 3), cd=3):
    return monster_spell(name, "neutral", ap_, rng, [E("summon", target="all", mask="a,A", monster=mid, grade=1)], symbol="summon", free=True, cooldown=cd)


def thorns(name, pct=15, turns=2, cd=3):
    return monster_spell(name, "neutral", 2, (0, 0), [E("reflect", pct, pct, target="caster", mask="C", on=["D"], turns=turns, boosted=True)], symbol="fist", cooldown=cd)


def dash(name, el, L, k=1.0, rng=(2, 6), cd=2):
    lo, hi = base(L, 4, k)
    return monster_spell(name, el, 4, rng, [E("advance", 3, 3, target="caster", mask="C", damage=False), dmg(el, lo, hi)], symbol="arrow", line=True, cooldown=cd)


def fan(name, el, L, k=0.8, rng=(1, 4), cd=2):
    lo, hi = base(L, 4, k)
    return monster_spell(name, el, 4, rng, [dmg(el, lo, hi, area={"shape": "line", "size": 3})], symbol="arrow", line=True, area={"shape": "line", "size": 3}, cooldown=cd)


# ── the roster ─────────────────────────────────────────────────────────────────
# (floor, key, name, spec factory, role/element, level, hp factor, res, drops key, scale, spell factory, note)

MOBS: list[dict] = []
MINIONS: dict[str, dict] = {}
FLOOR_MONSTERS: dict[int, list[int]] = {f: [] for f in range(1, 6)}
BOSS_IDS: dict[int, int] = {}


def M(floor, key, name, spec, el, level, spells, hp=1.0, res=None, scale=100, drops=(), note="", elite=False, ap_=5, mp_=3, aggro=3, dodge=(0, 0)):
    MOBS.append(dict(floor=floor, key=key, name=name, spec=spec, el=el, level=level, spells=spells, hp=hp, res=res or {}, scale=scale, drops=list(drops),
                     note=note, elite=elite, ap=ap_, mp=mp_, aggro=aggro, dodge=dodge))


def floor_1():
    L = lambda n: n  # readability: levels are explicit below
    M(1, "pousse", "Pousse-Gluante", srp(1, (10, 20, -20), segs=5, w=5.5, motif="core"), "earth", 1,
      lambda lv: [strike("Morsure gluante", "earth", lv, 3, (1, 1)), hex_mp("Bave collante", "earth", lv, 1, (1, 3))],
      hp=0.85, res=dict(water=-15, fire=-10, earth=10), drops=[("res_seve", 55), ("res_spore", 20), ("potion1", 6)], aggro=2,
      note="La première chose qu'on rencontre dans les Racines. Elle ne mord pas par méchanceté : elle a faim, et il y a de la sève sur vos bottes.")
    M(1, "rongeur", "Rongeur de Sève", bst(1, (20, 0, -10), body_len=16, body_h=10, leg=11, hs=7, head="boar"), "earth", 2,
      lambda lv: [strike("Coup de groin", "earth", lv, 3, (1, 1)), shove("Charge poussive", "earth", lv, 2)],
      hp=0.95, res=dict(earth=15, fire=-15), drops=[("res_ecorce", 50), ("res_seve", 25)],
      note="Il creuse les galeries à la recherche de sève. Plus c'est profond, plus il est gros. Les plus gros n'ont jamais été vus.")
    M(1, "sporelin", "Sporelin", flt(1, (30, -10, 40), core="jelly", r=11, sats=0, wisps=2, hover=16), "air", 3,
      lambda lv: [bolt("Jet de spores", "air", lv, (2, 5)), hex_mp("Nuage paralysant", "air", lv, 2, (1, 4), cd=3)],
      hp=0.8, res=dict(air=20, fire=-25), drops=[("res_spore", 55), ("res_larme", 4)],
      note="Un champignon qui a décidé de flotter. Ses spores donnent des rêves, puis des maux de tête, puis des rêves plus longs.")
    M(1, "fouisseur", "Fouisseur Cuirassé", bst(1, (-10, -10, -10), body_len=20, body_h=13, leg=10, hs=7, head="bug", motif="rune"), "earth", 4,
      lambda lv: [strike("Mandibule", "earth", lv, 3, (1, 1)), guard("Carapace", lv, 25)],
      hp=1.3, res=dict(earth=25, neutral=15, fire=-20, water=-10), drops=[("res_ecorce", 50), ("res_seve", 25), ("potion1", 6)],
      note="Un insecte de la taille d'un chien, cuirassé d'écorce. Il attend sans bouger qu'on lui tourne le dos.")
    M(1, "acolyte", "Acolyte des Racines", up(1, (20, -20, 30), head="hood", body="robe", weapon="staff", attack="cast", motif="rune"), "water", 5,
      lambda lv: [bolt("Prière de sève", "water", lv, (2, 5)), mend("Bénédiction de la mousse", lv, (1, 5), size=1)],
      hp=0.9, res=dict(water=15, fire=-20), drops=[("res_spore", 45), ("res_seve", 30), ("seve_cape", 3)],
      note="Un fidèle de la Mycélie. Il croit que les racines parlent. Elles parlent, d'ailleurs, mais pas pour lui.")
    M(1, "garde", "Garde-Écorce", up(1, (30, 10, -20), head="helm", body="armor", weapon="mace", off="shield", limbs="armor", arm_w=3.4, attack="slam"), "earth", 6,
      lambda lv: [strike("Coup de bouclier", "earth", lv, 3, (1, 1)), guard("Peau d'écorce", lv, 28), shove("Repoussoir", "earth", lv, 1)],
      hp=1.4, res=dict(earth=20, neutral=15, fire=-25), drops=[("res_ecorce", 55), ("res_seve", 20), ("ecorce_hat", 4), ("ecorce_shield", 3)],
      note="Ce qu'il reste d'un des gardes d'Ysmène. L'écorce a pris l'armure, puis l'homme. Il monte toujours la garde.")
    M(1, "lierre", "Lierre-Étrangleur", srp(1, (-20, 20, -20), segs=8, w=4.5, extras=["horn"]), "air", 7,
      lambda lv: [tug("Étreinte", "air", lv, 3), strike("Étranglement", "air", lv, 3, (1, 1))],
      hp=1.0, res=dict(air=20, fire=-30), drops=[("res_ecorce", 45), ("res_spore", 25)], aggro=4,
      note="Il ne se déplace presque jamais. Il n'en a pas besoin : on finit toujours par passer à portée.")
    M(1, "cueilleur", "Cueilleur Fongique", up(1, (-20, -10, 20), head="mask", body="rags", weapon="scythe", limbs="bone", arm_w=2.4, attack="slash", motif="cracks"), "water", 8,
      lambda lv: [drain("Récolte", "water", lv), shove("Fauchée", "water", lv, 2), veil("Fondu dans la mousse", lv)],
      hp=1.0, res=dict(water=10, fire=-15), drops=[("res_spore", 40), ("res_larme", 6), ("seve_belt", 3)],
      note="Il cueille tout ce qui pousse, y compris ce qui marche. La Mycélie lui en sait gré.")
    M(1, "colosse_mousse", "Colosse de Mousse", up(1, (0, 10, -10), body="bare", head="cyclops", limbs="fist", arm_w=5, leg_w=5, h=38, w=17, leg=21, arm=17, fore=16, hs=9, heavy=True,
                                                    attack="slam", motif="cracks"), "earth", 9,
      lambda lv: [strike("Poing moussu", "earth", lv, 4, (1, 1), 1.0), aoe("Piétinement", "earth", lv, 2, (0, 0), 5, 0.8, cd=3), guard("Mousse épaisse", lv, 30)],
      hp=2.3, res=dict(earth=30, neutral=20, fire=-30, water=-10), scale=125, drops=[("res_ecorce", 75), ("res_larme", 25), ("ecorce_ring", 8), ("ecorce_boots", 8), ("seve_boots", 8)], elite=True,
      note="Il a mis trois siècles à pousser. Il n'a jamais appris à marcher, seulement à tomber vers l'avant.")


def floor_2():
    M(2, "braise", "Braise-Folle", flt(2, (30, -20, -10), core="flame", r=11, sats=0, wisps=2, hover=18), "fire", 11,
      lambda lv: [blast("Dernière flamme", "fire", lv, 2), bolt("Étincelle", "fire", lv, (1, 4))],
      hp=0.55, res=dict(fire=40, water=-40), drops=[("res_cendre", 55), ("res_braise", 20)], aggro=4,
      note="Une flamme qui n'a plus rien à consumer et ne le sait pas. Elle se jette sur ce qui bouge, puis sur elle-même.")
    M(2, "rodeur", "Rôdeur Cendreux", up(2, (-10, -10, -10), body="rags", head="mask", weapon="dagger", off="dagger", limbs="sleeve", arm_w=2.6, h=28, attack="slash", motif="cracks"),
      "fire", 12, lambda lv: [backstab("Lame de braise", "fire", lv, 1.3), veil("Voile de cendre", lv), hex_mp("Entrave", "fire", lv, 2, (1, 3))],
      hp=0.9, res=dict(fire=15, water=-15, air=10), drops=[("res_suie", 50), ("res_cendre", 25), ("brume_belt", 4)], aggro=4,
      note="Un enfant du marais. Il a appris à ne pas être vu avant d'apprendre à lire. Il ne lira pas.")
    M(2, "crapaud", "Crapaud de Suie", bst(2, (-20, -20, -20), body_len=18, body_h=14, leg=9, hs=9, head="boar", claws=False), "earth", 13,
      lambda lv: [strike("Langue collante", "earth", lv, 3, (1, 3), 0.9, extra=[pull(2)]), aoe("Rot de suie", "fire", lv, 1, (1, 4), 4)],
      hp=1.2, res=dict(earth=15, water=15, fire=-20, air=-10), drops=[("res_suie", 55), ("res_braise", 20)],
      note="Il vit dans les mares de cendre. Il a l'air de sourire, c'est seulement la forme de sa bouche.")
    M(2, "spectre_fumee", "Spectre de Fumée", flt(2, (-10, -10, -10), core="ghost", r=14, sats=0, wisps=0, hover=24), "air", 14,
      lambda lv: [bolt("Souffle de fumée", "air", lv, (2, 5)), hex_mp("Voile asphyxiant", "air", lv, 2, (2, 5), cd=3), hex_ap("Brouillard", "air", lv, 2, (2, 5), cd=3)],
      hp=0.8, res=dict(air=30, fire=-10, earth=10, water=-30), drops=[("res_cendre", 45), ("res_suie", 30), ("brume_hat", 4)],
      note="Ce qu'il reste d'un Cendreux mort sans avoir fini sa phrase. Il tousse, encore.")
    M(2, "ecorcheur", "Écorcheur du Marais", up(2, (30, -20, -20), head="horned", body="bare", limbs="claw", arm_w=3.3, attack="slash", motif="cracks", h=31, w=13), "fire", 15,
      lambda lv: [strike("Griffes brûlantes", "fire", lv, 3, (1, 1), 1.05), shove("Éventrement", "fire", lv, 2), dash("Bond du marais", "fire", lv)],
      hp=1.3, res=dict(fire=20, earth=10, water=-20), drops=[("res_braise", 40), ("res_cendre", 30), ("cendrelame_ring", 4)],
      note="Les Cendreux le dressent, comme d'autres dressent des chiens. Il n'a jamais appris à rapporter.")
    M(2, "sangsue", "Sangsue Ardente", srp(2, (60, -40, -30), segs=6, w=6, motif="core"), "fire", 16,
      lambda lv: [drain("Morsure incandescente", "fire", lv, (1, 1)), strike("Spirale de feu", "fire", lv, 3, (1, 2))],
      hp=1.1, res=dict(fire=30, water=-35), drops=[("res_braise", 45), ("res_suie", 30)],
      note="Elle pompe la chaleur plus que le sang. On sort de là gelé, ce qui, dans le marais, est une expérience nouvelle.")
    M(2, "pretre_cendres", "Prêtre des Cendres", up(2, (10, -10, -20), head="hood", body="robe", weapon="staff", attack="cast", motif="rune"), "fire", 17,
      lambda lv: [bolt("Feu votif", "fire", lv, (2, 5)), mend("Onction de cendre", lv, (1, 4), size=1), empower("Ferveur", lv)],
      hp=1.0, res=dict(fire=20, water=-20), drops=[("res_cendre", 45), ("res_lame_fondue", 6), ("cendrelame_cape", 4)],
      note="Il prie le Capitaine Éteint de ne pas s'éteindre tout à fait. Sa prière est entendue, ce qui est le problème.")
    M(2, "meute", "Meute Charbonnée", bst(2, (-30, -30, -30), body_len=20, body_h=12, leg=14, hs=8, head="wolf", extras=["mane"]), "neutral", 18,
      lambda lv: [strike("Morsure charbonneuse", "neutral", lv, 3, (1, 1), 1.0), dash("Course de meute", "neutral", lv, 0.9)],
      hp=1.0, res=dict(fire=15, neutral=10, water=-15), drops=[("res_suie", 50), ("res_cendre", 25), ("brume_boots", 4)], mp_=5, aggro=5,
      note="Ils chassaient ensemble, avant. Maintenant ils chassent aussi ensemble, mais avec les mêmes yeux.")
    M(2, "bourreau", "Bourreau Calciné", up(2, (20, -10, -10), head="helm", body="bare", weapon="axe", limbs="fist", arm_w=4.4, leg_w=4.4, h=36, w=16, leg=22, arm=17, fore=16, hs=9, heavy=True,
                                         attack="slam", motif="cracks"), "fire", 19,
      lambda lv: [strike("Hache rougie", "fire", lv, 4, (1, 1), 1.1), aoe("Décapitation en rond", "fire", lv, 1, (0, 0), 5, 0.9, cd=3), guard("Cuirasse de braise", lv, 30)],
      hp=2.4, res=dict(fire=35, earth=15, neutral=15, water=-30), scale=120, drops=[("res_lame_fondue", 28), ("res_cendre", 70), ("cendrelame_hat", 8), ("cendrelame_boots", 8), ("cendrelame_belt", 8)], elite=True,
      note="Le bourreau du Capitaine. Il n'a jamais eu de condamné. Il a donc élargi la définition.")


def floor_3():
    M(3, "rouage_errant", "Rouage Errant", flt(3, (-70, 10, 60), core="crystal", r=11, sats=3, wisps=0, hover=18), "neutral", 21,
      lambda lv: [bolt("Dent de rouage", "neutral", lv, (1, 3)), hex_ap("Grippage", "neutral", lv, 2, (1, 3), cd=3)],
      hp=0.8, res=dict(neutral=20, fire=-10, water=-20), drops=[("res_rouage", 55), ("res_ressort", 20)],
      note="Un rouage échappé d'une machine disparue. Il tourne, il roule, il se cogne. Il cherche son axe.")
    M(3, "sentinelle", "Sentinelle Inversée", up(3, (-70, -40, 30), head="cyclops", body="plate", weapon="sword", off="shield", limbs="armor", arm_w=3.6, h=33, w=13, attack="slash", motif="rune"), "neutral", 22,
      lambda lv: [strike("Lame réglementaire", "neutral", lv, 3, (1, 1)), guard("Garde à vue", lv, 28), shove("Évacuation", "neutral", lv, 2)],
      hp=1.4, res=dict(neutral=25, earth=15, fire=-15, water=-20), drops=[("res_rouage", 50), ("res_huile", 25), ("rouage_hat", 4)],
      note="Elle garde un bâtiment qui n'existe plus, la tête en bas depuis le premier jour. Elle ne s'en est pas aperçue.")
    M(3, "araignee", "Araignée Mécanique", bst(3, (-60, -70, -40), body_len=15, body_h=11, leg=19, hs=7, head="bug", motif="rune", claws=True), "fire", 23,
      lambda lv: [strike("Aiguillon", "fire", lv, 3, (1, 1), 1.0), trap("Toile d'acier", "fire", lv, 1), hex_mp("Fil", "fire", lv, 2, (1, 4), cd=3)],
      hp=1.0, res=dict(fire=20, neutral=10, water=-25), drops=[("res_ressort", 50), ("res_huile", 25), ("mecano_boots", 4)], mp_=4,
      note="Elle tisse. Quelqu'un lui a demandé de tisser une ville. Elle tisse, depuis.")
    M(3, "chanteur", "Automate Chanteur", up(3, (-80, 20, 70), head="mask", body="robe", weapon="orb", attack="cast", motif="rune", off="orb"), "air", 24,
      lambda lv: [aoe("Note aiguë", "air", lv, 1, (2, 5), 4, 0.8, extra=[push(1)]), hex_ap("Refrain", "air", lv, 2, (2, 5), cd=3), empower("Crescendo", lv)],
      hp=0.9, res=dict(air=25, earth=-20, neutral=10), drops=[("res_ressort", 40), ("res_huile", 30), ("res_plan", 5)],
      note="Il chante la même chanson depuis l'Effondrement. Ceux qui l'ont écoutée jusqu'au bout ne sont plus là pour la juger.")
    M(3, "nettoyeur", "Nettoyeur Fou", up(3, (60, -60, -50), head="mask", body="bare", weapon="hammer", limbs="sleeve", arm_w=3.4, attack="slam", h=32, w=14), "earth", 25,
      lambda lv: [strike("Coup de balai", "earth", lv, 3, (1, 1), 1.0, extra=[push(1)]), aoe("Grand nettoyage", "earth", lv, 2, (0, 0), 5, 0.85, cd=3)],
      hp=1.3, res=dict(earth=20, air=-20), drops=[("res_huile", 50), ("res_rouage", 30), ("rouage_belt", 4)],
      note="Il nettoie. Il nettoie tout ce qui bouge. Ce qui ne bouge plus est propre.")
    M(3, "drone", "Drone d'Alarme", flt(3, (50, 60, 70), core="eye", r=11, sats=2, wisps=0, hover=26), "air", 26,
      lambda lv: [bolt("Sirène", "air", lv, (2, 6), k=0.8), empower("Alerte générale", lv, area=3, cd=3), mend("Rapport de dégâts", lv, (1, 5), size=1)],
      hp=0.7, res=dict(air=25, earth=-25), drops=[("res_ressort", 45), ("res_plan", 8)], aggro=6,
      note="Il crie dès qu'il vous voit. Il n'a jamais appris à faire autre chose.")
    M(3, "mecano", "Mécano Rouillé", up(3, (-50, 30, -20), head="helm", body="armor", weapon="dagger", limbs="armor", arm_w=3.2, attack="slash"), "fire", 27,
      lambda lv: [trap("Piège à clef", "fire", lv, 1), strike("Clef à molette", "fire", lv, 3, (1, 1)), glyph("Zone de maintenance", "fire", lv, 2, (2, 5))],
      hp=1.0, res=dict(fire=25, neutral=15, water=-20), drops=[("res_huile", 45), ("res_rouage", 35), ("mecano_hat", 4), ("mecano_ring", 3)],
      note="Il répare, il règle, il pose des pièges. Pour lui, la différence n'est pas évidente.")
    M(3, "chien_fonte", "Chien de Garde en Fonte", bst(3, (-90, -80, -70), body_len=21, body_h=13, leg=14, hs=9, head="wolf", extras=["spikes"], motif="rune"), "earth", 28,
      lambda lv: [strike("Morsure d'acier", "earth", lv, 3, (1, 1), 1.0), dash("Course de garde", "earth", lv, 0.9)],
      hp=1.5, res=dict(earth=30, neutral=25, fire=-15, water=-30), drops=[("res_rouage", 50), ("res_ressort", 30)], mp_=4,
      note="Ses maîtres ne reviennent jamais. Il garde la porte, sans se demander de quel côté.")
    M(3, "colosse_pendule", "Colosse-Pendule", up(3, (-10, -10, 0), body="plate", head="cyclops", limbs="armor", arm_w=5.2, leg_w=5, h=39, w=18, leg=21, arm=18, fore=17, hs=9.5, heavy=True, attack="slam", motif="cracks"),
      "neutral", 29,
      lambda lv: [strike("Balancier", "neutral", lv, 4, (1, 1), 1.1, extra=[push(2)]), glyph("Mouvement perpétuel", "neutral", lv, 3, (1, 4), 3, 5, 0.5), guard("Contrepoids", lv, 30)],
      hp=2.6, res=dict(neutral=35, earth=20, fire=-20, water=-30), scale=125, drops=[("res_plan", 30), ("res_rouage", 70), ("rouage_ring", 8), ("rouage_boots", 8), ("rouage_amulet", 8)], elite=True,
      note="Il balance, d'un côté, de l'autre, depuis trois siècles. Ça marque.")


def floor_4():
    M(4, "livre", "Livre Vorace", flt(4, (30, 10, -10), core="tome", r=12, sats=3, wisps=0, hover=22), "water", 31,
      lambda lv: [bolt("Coup de reliure", "water", lv, (1, 3)), hex_ap("Page avalée", "water", lv, 3, (1, 4), cd=3), drain("Lecture hâtive", "water", lv, (1, 2))],
      hp=0.9, res=dict(water=25, fire=-30, earth=10), drops=[("res_page", 55), ("res_encre", 20)],
      note="Il dévore les lecteurs distraits. Les autres, il les cite.")
    M(4, "poisson", "Poisson-Scribe", srp(4, (0, 40, 40), segs=7, w=5.2, extras=["horn"]), "water", 32,
      lambda lv: [strike("Morsure d'encre", "water", lv, 3, (1, 2)), tug("Hameçon d'encre", "water", lv, 2, (2, 5))],
      hp=1.0, res=dict(water=30, air=-25), drops=[("res_encre", 45), ("res_reliure", 25)], aggro=4,
      note="Il copie les inscriptions à la nage. Ses fautes d'orthographe sont mortelles.")
    M(4, "spectre_lecteur", "Spectre Lecteur", flt(4, (30, 30, 30), core="ghost", r=14, sats=0, wisps=0, hover=24), "neutral", 33,
      lambda lv: [bolt("Mot de passe", "neutral", lv, (2, 5)), thorns("Citation en retour", 18, 2), hex_mp("Silence de bibliothèque", "neutral", lv, 2, (2, 5), cd=3)],
      hp=0.9, res=dict(neutral=30, water=15, earth=-20), drops=[("res_page", 45), ("res_index", 6), ("maree_hat", 4)],
      note="Il lit par-dessus votre épaule. Si vous le dérangez, il vous fait taire.")
    M(4, "copiste", "Copiste Noyé", up(4, (-20, -20, -20), head="skull", body="rags", weapon="dagger", limbs="bone", arm_w=2.4, attack="slash", motif="cracks"), "water", 34,
      lambda lv: [strike("Plume affûtée", "water", lv, 3, (1, 1)), hex_ap("Rature", "water", lv, 2, (1, 3), cd=3), mend_self("Ré-encrage", lv, 15)],
      hp=1.1, res=dict(water=25, fire=-20, earth=10), drops=[("res_encre", 45), ("res_reliure", 30), ("encre_hat", 4)],
      note="Il recopie. Il recopie ce qu'il vient de recopier. Il y a longtemps qu'il n'a plus de livre.")
    M(4, "gardien_encre", "Gardien d'Encre", up(4, (20, 0, 40), head="hood", body="robe", weapon="staff", attack="cast", motif="rune", h=32), "water", 35,
      lambda lv: [aoe("Marée d'encre", "water", lv, 2, (2, 5), 5, 0.85, extra=[mp(1, duration=1)]), bolt("Goutte", "water", lv, (2, 6)), guard("Voile d'encre", lv, 25)],
      hp=1.0, res=dict(water=30, fire=-25, air=10), drops=[("res_encre", 50), ("res_page", 30), ("maree_cape", 4)],
      note="Il garde les pages blanches, qui sont les plus dangereuses : on n'y a pas encore écrit ce qu'elles diront.")
    M(4, "meduse", "Méduse d'Archive", flt(4, (30, 30, 30), core="jelly", r=15, sats=0, wisps=3, hover=20), "water", 36,
      lambda lv: [bolt("Filament", "water", lv, (1, 4)), mend("Sécrétion salvatrice", lv, (1, 5), size=1), hex_mp("Étreinte molle", "water", lv, 2, (1, 3), cd=3)],
      hp=1.5, res=dict(water=35, air=-30, fire=-10), drops=[("res_reliure", 50), ("res_page", 30), ("maree_belt", 4)],
      note="Elle flotte entre les rayons comme un mauvais souvenir. Son poison est en fait une très vieille encre.")
    M(4, "archiviste_devoye", "Archiviste Dévoyé", up(4, (0, 0, 20), head="mask", body="robe", weapon="staff", off="orb", attack="cast", motif="core"), "neutral", 37,
      lambda lv: [spawn("Appeler un Livre", MINIONS["livre"], 4, (1, 3), 3), bolt("Citation tronquée", "neutral", lv, (2, 5)), empower("Annotation", lv)],
      hp=1.1, res=dict(neutral=20, water=15, earth=-20), drops=[("res_index", 12), ("res_page", 40), ("encre_dagger", 3), ("encre_ring", 4)],
      note="Il a décidé que les livres devaient se défendre. Ils l'ont pris au mot.")
    M(4, "bete_rayons", "Bête des Rayons", bst(4, (10, 0, 20), body_len=22, body_h=15, leg=15, hs=9.5, head="ram", extras=["mane"]), "earth", 38,
      lambda lv: [strike("Coup de corne", "earth", lv, 3, (1, 1), 1.0, extra=[push(2)]), dash("Bousculade", "earth", lv, 1.0)],
      hp=1.6, res=dict(earth=25, water=15, air=-25), drops=[("res_reliure", 50), ("res_encre", 30)], mp_=4,
      note="Elle vit entre les rayons, et mange les plus anciens. On dit qu'elle ne digère que l'éther.")
    M(4, "leviathan", "Léviathan de Papier", srp(4, (30, 30, 10), segs=11, w=8, extras=["horn"], motif="core"), "water", 39,
      lambda lv: [strike("Étreinte de pages", "water", lv, 4, (1, 3), 1.1, extra=[pull(2)]), aoe("Déferlante", "water", lv, 2, (1, 4), 5, 0.9, cd=3), drain("Plongeon", "water", lv, (1, 2))],
      hp=2.6, res=dict(water=40, fire=-35, earth=-10), scale=120, drops=[("res_index", 32), ("res_reliure", 70), ("maree_ring", 8), ("maree_boots", 8), ("maree_amulet", 8)], elite=True,
      note="Mille cahiers de papier mâché, dans lesquels quelqu'un a mis le feu, puis l'eau.")


def floor_5():
    M(5, "eclat_celeste", "Éclat Céleste", flt(5, (0, 0, 20), core="crystal", r=12, sats=3, wisps=0, hover=22), "air", 41,
      lambda lv: [bolt("Rayon d'azur", "air", lv, (2, 6)), aoe("Éclatement", "air", lv, 1, (1, 4), 4, 0.8, cd=2)],
      hp=0.8, res=dict(air=30, earth=-25, water=10), drops=[("res_eclat", 55), ("res_poussiere", 20)],
      note="Un morceau de ciel qui a oublié qu'il est tombé. Il continue de briller, par politesse.")
    M(5, "aurore", "Aurore Rampante", srp(5, (20, -20, -40), segs=8, w=6, motif="core"), "air", 42,
      lambda lv: [strike("Morsure de lumière", "air", lv, 3, (1, 2)), tug("Reflet captif", "air", lv, 3, (2, 5))],
      hp=1.1, res=dict(air=25, fire=15, earth=-30), drops=[("res_plume", 45), ("res_eclat", 30)], aggro=4,
      note="Un lever de soleil qui rampe. Elle ne comprend pas pourquoi les gens se cachent le visage.")
    M(5, "seraphin", "Séraphin Déchu", up(5, (-20, -20, 0), head="helm", body="armor", weapon="sword", extras=["feather"], limbs="armor", arm_w=3.4, attack="slash", h=32, w=13, wing=40), "air", 43,
      lambda lv: [strike("Lame d'aurore", "air", lv, 3, (1, 1)), dash("Piqué", "air", lv, 1.0, (2, 6)), guard("Ailes repliées", lv, 25)],
      hp=1.3, res=dict(air=25, neutral=10, earth=-25), drops=[("res_plume", 50), ("res_poussiere", 25), ("aurore_hat", 4)],
      note="Il est tombé de très haut, et n'a pas fini de tomber. Ses ailes ne battent plus, elles se souviennent.")
    M(5, "lame_azur", "Lame d'Azur", up(5, (-30, -30, 20), head="mask", body="rags", weapon="sword", off="sword", limbs="sleeve", arm_w=2.6, h=29, attack="slash", extras=["cape"]), "neutral", 44,
      lambda lv: [backstab("Double azur", "neutral", lv, 1.35), veil("Éclipse", lv), strike("Estoc", "neutral", lv, 3, (1, 1), 1.0)],
      hp=1.0, res=dict(neutral=20, air=15, earth=-25), drops=[("res_eclat", 40), ("res_plume", 35), ("aurore_ring", 4), ("gravit_ring", 3)], aggro=4,
      note="Elle a servi la Couronne. Elle a fini de servir, mais personne n'a osé le lui dire.")
    M(5, "chimere", "Chimère Stellaire", bst(5, (20, -20, -20), body_len=22, body_h=14, leg=15, hs=10, head="wolf", extras=["mane", "spikes"], motif="core"), "fire", 45,
      lambda lv: [strike("Morsure d'étoile", "fire", lv, 3, (1, 1), 1.0), aoe("Souffle céleste", "fire", lv, 2, (1, 4), 5, 0.85, cd=3), dash("Bond stellaire", "fire", lv, 0.9)],
      hp=1.5, res=dict(fire=30, air=15, water=-30, earth=-10), drops=[("res_poussiere", 40), ("res_eclat", 35), ("aurore_boots", 4)], mp_=4,
      note="Une constellation qui a trouvé un corps. Elle a mal choisi.")
    M(5, "oeil", "Œil du Firmament", flt(5, (30, 30, -20), core="eye", r=18, sats=4, wisps=0, hover=30), "fire", 46,
      lambda lv: [aoe("Regard solaire", "fire", lv, 2, (2, 6), 5, 0.9, cd=2), hex_ap("Éblouissement", "fire", lv, 3, (2, 6), cd=3), bolt("Larme brûlante", "fire", lv, (2, 6))],
      hp=1.3, res=dict(fire=35, air=20, earth=-30, water=-15), drops=[("res_eclat", 40), ("res_poussiere", 35), ("aurore_belt", 4)],
      note="Il regarde. C'est tout ce qu'il fait. Ceux qu'il regarde se mettent à brûler, mais ça n'a rien à voir.")
    M(5, "pretre_ciel", "Prêtre du Ciel", up(5, (10, 10, 20), head="hood", body="robe", weapon="staff", attack="cast", motif="rune", h=32, w=12), "air", 47,
      lambda lv: [bolt("Prière stellaire", "air", lv, (2, 6)), mend("Rayon bienfaisant", lv, (1, 5), size=2), empower("Bénédiction d'azur", lv, area=3), guard("Auréole", lv, 28)],
      hp=1.1, res=dict(air=25, neutral=15, earth=-25), drops=[("res_poussiere", 45), ("res_plume", 35), ("aurore_cape", 4), ("aurore_amulet", 4)],
      note="Il prie quelqu'un. Ce quelqu'un le regarde, d'en haut, depuis un peu plus près chaque année.")
    M(5, "gardien_voute", "Gardien de Voûte", up(5, (-10, -10, 10), head="cyclops", body="plate", weapon="hammer", off="shield", limbs="armor", arm_w=4.2, leg_w=4.4, h=36, w=15, leg=23, attack="slam", motif="rune", wsize=30),
      "neutral", 48,
      lambda lv: [strike("Marteau de voûte", "neutral", lv, 4, (1, 1), 1.0, extra=[push(2)]), guard("Mur de lumière", lv, 32), glyph("Seuil", "neutral", lv, 2, (1, 4))],
      hp=2.0, res=dict(neutral=35, earth=20, air=20, fire=-10, water=-15), drops=[("res_eclat", 40), ("res_poussiere", 40), ("gravit_hat", 4), ("gravit_shield", 4)],
      note="La porte de la Couronne lui a été confiée. On ne lui a pas dit de laquelle.")
    M(5, "titan", "Titan Fragmenté", up(5, (0, 0, 0), body="bare", head="cyclops", limbs="fist", arm_w=5.8, leg_w=5.5, h=42, w=19, leg=23, arm=19, fore=18, hs=10, heavy=True, attack="slam", motif="cracks"),
      "earth", 49,
      lambda lv: [strike("Poing du ciel", "earth", lv, 5, (1, 1), 1.1, extra=[push(2)]), aoe("Chute de morceaux", "earth", lv, 3, (1, 4), 6, 0.9, cd=3), guard("Armure de gravats", lv, 30)],
      hp=3.0, res=dict(earth=40, neutral=25, air=-15, water=-15), scale=135, drops=[("res_coeur", 6), ("res_poussiere", 70), ("gravit_boots", 8), ("gravit_ring", 8), ("aurore_ring", 8)], elite=True,
      note="Il y en avait neuf. Il ne reste que celui-là, tenu ensemble par l'habitude.")


# ── building ───────────────────────────────────────────────────────────────────

def _stats(level, el):
    main = round(level * 1.5)
    s = {"strength": 0, "intelligence": 0, "chance": 0, "agility": 0, "wisdom": 0}
    s[STAT_OF[el]] = main
    return s


# XP of a kill = the official base (luaformulas 2: 100 L + 2 L^2) times a floor factor: the Dofus XP curve (5.35 M to
# reach level 50) would take about 400 kills for the last ten levels, so the upper floors pay more (APPROX(V.01)).
XP_FACTOR = {1: 1.0, 2: 1.0, 3: 1.0, 4: 1.5, 5: 3.0}


def kill_xp(level, floor, boss=False):
    return int((level * 100 + level * level * 2) * XP_FACTOR[floor] * (6.0 if boss else 1.0))


def _grade(m, g, mid, bone, spells):
    lv = m["level"] + (1 if g else 0) if not m["elite"] else m["level"]
    lv = m["level"] + g
    hp = int((12 + 5.5 * lv + 0.05 * lv * lv) * m["hp"] * (1.0 + 0.06 * g))
    res = {e: int(m["res"].get(e, 0)) for e in ("earth", "fire", "water", "air", "neutral")}
    st = _stats(lv, m["el"])
    st["ap_dodge"] = m["dodge"][0] or max(0, lv // 3)
    st["mp_dodge"] = m["dodge"][1] or max(0, lv // 3)
    drops = []
    for key, pct in m["drops"]:
        if key in ITEM and pct > 0:
            drops.append({"item": ITEM[key], "pct": float(pct)})
    d = {"monster": mid, "name_id": T(m["name"]), "name": m["name"], "look": "{%s|||%d}" % (bone, m["scale"]), "portrait": int(bone), "grade": g + 1,
         "level": lv, "hp": hp, "ap": m["ap"], "mp": m["mp"], "xp": kill_xp(lv, m["floor"]), "stats": st, "res": res, "spells": spells, "drops": drops,
         "kamas": [lv * 2, lv * 6], "aggro": {"zone": m["aggro"], "level_diff": 60, "immunity": "", "delay": 8000}}
    return d


def build_regular():
    for fn in (floor_1, floor_2, floor_3, floor_4, floor_5):
        fn()
    for m in MOBS:
        mid = monster_id()
        bone = str(bone_id())
        R.bones[bone] = m["spec"]
        m["id"], m["bone"] = mid, bone
        # the Livre summoned by the Archiviste Dévoyé is the Livre Vorace (the creature of the same floor)
        spells = m["spells"](m["level"])
        spells = [s for s in spells if s]
        grades = [_grade(m, g, mid, bone, spells) for g in range(1 if m["elite"] else 2)]
        R.monsters[str(mid)] = {"name_id": T(m["name"]), "name": m["name"], "race": 0, "grades": grades}
        FLOOR_MONSTERS[m["floor"]].append(mid)
        wb = R.bones[bone]
        R.icons.append(("Picto/Monsters/%d" % int(bone), (lambda b=bone, sp=m["spec"]: _portrait(b, sp))))


def _portrait(bone, spec):
    import rigs
    from dofus_bone import render_frame
    b = rigs.build(bone, spec)
    anim = [a for a in b.anims if a.name == "AnimStatique_1"][0]
    im = render_frame(b, anim.frames[0], scale=2.0, size=(260, 260), origin=(130, 200), bg=(0, 0, 0, 0))
    return icons.portrait(im)
