"""The five classes of the Vertebre: lore, look (a bone each) and eight spells each (3 grades).

Each class has its own mechanic built from states the spells read at cast time (mask *E<n> / E<n>):
  Veilleur          Ancre (state)       defence builds it, his big spells spend it
  Fendeur de Breche Faille (state)      marks the target, his finishers punish marked targets
  Tisseur d'Ether   runes               spells lay runes, Detonation / Eclipse set them off
  Chasseur d'Ombre  Invisible + Marque  hits from the shadows hurt more, marked prey takes extra
  Archiviste        Annotations         buffs/heals, a summoned Tome, big finishers
"""
from __future__ import annotations

import icons
import rigs
from common import R, T, state_id
from rigs import Pal
from spells_lib import (E, ap, class_spell, dmg, heal, heal_pct, hidden, mp, monster_spell, pull, push, scaled, shield, state, stat,
                        steal, summon_def, unstate)

S_ANCRE, S_FAILLE, S_INVIS, S_MARQUE, S_NOTE = (state_id() for _ in range(5))
FLAGS_INVIS = ["invisible"]


def sc(v, s):
    return max(1, round(v * s))


# ── the classes (id, texts, look) ──────────────────────────────────────────────

CLASSES = {
    901: dict(key="veilleur", name="Veilleur", tag="Gardien de pierre",
              desc="Les Veilleurs montent la garde au pied de la Tour depuis trois siècles. Ils encaissent, ancrent leur position dans la pierre, "
                   "puis rendent le choc au centuple. Plus ils tiennent debout, plus ils frappent fort.",
              symbol="shield", color=(176, 150, 96),
              look=dict(arch="upright", pal=Pal((104, 118, 142), (255, 206, 96), (190, 160, 90)), h=33, w=13, leg=24, arm=15, fore=14, hs=8.5,
                        head="helm", body="armor", weapon="mace", off="shield", limbs="armor", arm_w=3.6, leg_w=3.8, attack="slam", extras=["cape"], wsize=28)),
    902: dict(key="fendeur", name="Fendeur de Brèche", tag="Lame entre les plans",
              desc="Un Fendeur ne se bat pas : il apparaît. Sa lame ouvre des brèches dans l'air, et il passe à travers. "
                   "Marquez une cible d'une faille, puis refermez-la sur elle.",
              symbol="dagger", color=(220, 90, 110),
              look=dict(arch="upright", pal=Pal((112, 52, 76), (255, 96, 120), (200, 90, 100)), h=29, w=10, leg=27, arm=14, fore=13, hs=8,
                        head="mask", body="rags", weapon="sword", off="dagger", limbs="sleeve", arm_w=2.7, attack="slash", extras=["cape"], wsize=24)),
    903: dict(key="tisseur", name="Tisseur d'Éther", tag="Mage des runes",
              desc="Les Tisseurs ont bâti la Tour avec des fils d'éther, et certains savent encore les nouer. Ils posent des runes sur le champ de bataille "
                   "et les font toutes parler d'un seul mot.",
              symbol="orb", color=(150, 120, 255),
              look=dict(arch="upright", pal=Pal((86, 72, 150), (150, 230, 255), (210, 190, 255)), h=31, w=11, leg=25, arm=14, fore=13, hs=8.5,
                        head="hood", body="robe", weapon="staff", limbs="sleeve", arm_w=2.9, attack="cast", motif="rune", wsize=30)),
    904: dict(key="chasseur", name="Chasseur d'Ombre", tag="Traqueur invisible",
              desc="Il vous voit avant que vous ne le voyiez, et il vous a déjà marqué. Le Chasseur d'Ombre frappe de loin, disparaît, "
                   "et n'a pas de pitié pour ce qui porte sa marque.",
              symbol="bow", color=(110, 200, 120),
              look=dict(arch="upright", pal=Pal((60, 84, 82), (170, 255, 120), (130, 170, 120)), h=30, w=10, leg=27, arm=14, fore=14, hs=8.5,
                        head="hood", body="robe", weapon="bow", limbs="sleeve", arm_w=2.7, attack="slash", extras=["cape"], motif="rune", wsize=26)),
    905: dict(key="archiviste", name="Archiviste", tag="Gardien des mémoires",
              desc="Les Archivistes consignent tout ce que la Tour a oublié. Leur encre soigne, protège, retire aux ennemis ce qu'ils savaient, "
                   "et leurs Tomes se battent à leur place.",
              symbol="tome", color=(230, 210, 140),
              look=dict(arch="upright", pal=Pal((196, 184, 150), (255, 222, 120), (90, 110, 160)), h=30, w=11, leg=25, arm=14, fore=13, hs=9,
                        head="round", body="robe", weapon="staff", limbs="sleeve", arm_w=2.8, attack="cast", motif="core", wsize=28)),
}

TOME_BONE_SPEC = dict(arch="floater", pal=Pal((120, 82, 56), (255, 222, 120)), r=11, core="tome", sats=0, wisps=0, hover=14)
STELE_BONE_SPEC = dict(arch="floater", pal=Pal((130, 126, 138), (255, 206, 96)), r=13, core="crystal", sats=2, wisps=0, hover=18)


def _bone(spec):
    from common import bone_id
    b = str(bone_id())
    R.bones[b] = spec
    return b


def _rowzero():
    return {}


# ── spells ─────────────────────────────────────────────────────────────────────

def veilleur(breed):
    A = S_ANCRE
    mark = lambda pid, s, shape="circle", size=2: {"shape": shape, "size": size}
    sp = {}
    sp["rempart"] = class_spell(breed, "Coup de Rempart", "Un coup de bouclier. Ancré, il repousse la cible d'une case.", "hammer", "earth", 3, (1, 1),
        lambda s, h: [dmg("earth", sc(11, s), sc(15, s), mask="A,*e%d" % A), dmg("earth", sc(14, s), sc(19, s), mask="A,*E%d" % A),
                      push(1, mask="A,*E%d" % A)], learn=1)
    sp["garde"] = class_spell(breed, "Garde de Pierre", "Vous vous ancrez : bouclier et résistances pendant quelques tours.", "shield", "neutral", 3, (0, 0),
        lambda s, h: [shield(sc(16, s), duration=2), state(A, 3), stat("res_all", sc(10, s), 2)], learn=1, cooldown=3, cooldown_up=0, per_turn=1)

    def sentinelle(s, h):
        gid = h("Sentinelle (glyphe)", "earth", [dmg("earth", 7, 10, mask="A")])
        return [E("glyph_end", target="all", mask="a,A", duration=3, color="#a8763c", mark={"shape": "circle", "size": 2}, origin=h.parent, spell=gid)]
    sp["sentinelle"] = class_spell(breed, "Sentinelle", "Un glyphe de pierre : qui finit son tour dedans est frappé.", "glyph", "earth", 4, (1, 4), sentinelle, learn=5, cooldown=2, cooldown_up=0)
    sp["harpon"] = class_spell(breed, "Harpon de Garde", "Attire un ennemi à vous et lui retire un PA.", "chain", "neutral", 2, (2, 5),
        lambda s, h: [dmg("neutral", sc(5, s), sc(8, s)), pull(3), ap(1, duration=1)], learn=9, line=True, per_turn=1, cooldown=2, cooldown_up=0)
    sp["onde"] = class_spell(breed, "Onde de Choc", "Une onde autour de vous ; plus forte si vous êtes ancré.", "burst", "earth", 4, (0, 0),
        lambda s, h: [dmg("earth", sc(11, s), sc(15, s), area=("circle", 2)), dmg("earth", sc(6, s), sc(9, s), area=("circle", 2), mask="A,*E%d" % A),
                      push(2, area=("circle", 2))], learn=14, area={"shape": "circle", "size": 2}, cooldown=2, cooldown_up=0, per_turn=1)

    steles = {}

    def stele(s, h):
        mid = steles.get("mid")
        if mid is None:
            starts = []
            for sc_ in (1.0, 1.3, 1.6):
                gid = hidden("Veille de la stèle", "earth", [heal(sc(6, sc_), sc(9, sc_), target="allies", mask="a")])
                starts.append(hidden("Stèle de Veille", "earth", [E("glyph_start", target="allies", mask="a", duration=-1,
                              color="#ffd06a", mark={"shape": "circle", "size": 2}, origin=0, spell=gid)]))
            steles["mid"] = mid = summon_def("Stèle de Veille", _bone(STELE_BONE_SPEC), 38, 0, 0, plays=False, scale=100, res=15, start=starts)
        return [E("summon", target="all", mask="a,A", monster=mid, grade=h.i + 1)]
    sp["stele"] = class_spell(breed, "Stèle de Veille", "Dresse une stèle qui soigne les alliés proches à chaque tour.", "summon", "earth", 4, (1, 3), stele,
        learn=20, free=True, cooldown=4, cooldown_up=0, per_turn=1)
    sp["represailles"] = class_spell(breed, "Représailles", "Les coups reçus sont en partie rendus à leur auteur.", "fist", "neutral", 2, (0, 0),
        lambda s, h: [E("reflect", sc(14, s), sc(14, s), target="caster", mask="C", on=["D"], turns=2, boosted=True), state(A, 2)],
        learn=28, gap=7, cooldown=3, cooldown_up=0, per_turn=1)
    sp["chute"] = class_spell(breed, "Chute de la Tour", "L'étage entier tombe sur la cible. Dépense l'Ancre pour frapper bien plus fort.", "rock", "earth", 6, (1, 5),
        lambda s, h: [dmg("earth", sc(28, s), sc(36, s), area=("circle", 2)), dmg("earth", sc(24, s), sc(30, s), area=("circle", 2), mask="A,*E%d" % A),
                      unstate(A)], learn=36, gap=7, area={"shape": "circle", "size": 2}, cooldown=4, cooldown_up=1, per_turn=1)
    return sp


def fendeur(breed):
    F = S_FAILLE
    sp = {}
    sp["entaille"] = class_spell(breed, "Entaille", "Une entaille qui laisse une faille dans la cible.", "sword", "air", 3, (1, 1),
        lambda s, h: [dmg("air", sc(10, s), sc(14, s)), state(F, 3, target="enemies")], learn=1)
    sp["breche"] = class_spell(breed, "Brèche", "Vous traversez l'air jusqu'à la case visée.", "wing", "air", 3, (2, 6),
        lambda s, h: [E("teleport", 9, 9, target="all", mask="a,A", area={"shape": "from_caster", "size": 1, "max": 63, "stop": True}, effect=4)],
        learn=1, line=True, free=True, cooldown=2, cooldown_up=0, per_turn=1)
    sp["echange"] = class_spell(breed, "Échange Spatial", "Échange votre place avec celle d'un autre combattant.", "swap", "neutral", 2, (1, 5),
        lambda s, h: [E("swap", target="all", mask="g,A", effect=8)], learn=5, taken=True, cooldown=3, cooldown_up=0, per_turn=1)

    def dechirure(s, h):
        gid = h("Déchirure", "air", [dmg("air", 12, 16, area=("circle", 1), mask="A"), E("state", 0, 0, target="enemies", duration=3, area=("circle", 1), state=F, state_name_id=0, flags=[])])
        return [E("trap", target="all", mask="a,A", color="#c05878", mark={"shape": "circle", "size": 1}, origin=h.parent, spell=gid)]
    sp["dechirure"] = class_spell(breed, "Déchirure", "Un piège d'air : qui l'effleure est lacéré et marqué d'une faille.", "trap", "air", 3, (1, 5), dechirure, learn=9, free=True, per_turn=2)
    sp["double"] = class_spell(breed, "Double Lame", "Deux coups. Sur une faille, le second lacère plus profond.", "dagger", "neutral", 4, (1, 1),
        lambda s, h: [dmg("air", sc(9, s), sc(12, s)), dmg("neutral", sc(7, s), sc(10, s)), dmg("neutral", sc(9, s), sc(12, s), mask="A,E%d" % F)], learn=14)
    sp["fantome"] = class_spell(breed, "Pas Fantôme", "Vous disparaissez un tour et gagnez deux PM.", "moon", "shadow", 3, (0, 0),
        lambda s, h: [state(S_INVIS, 2, flags=FLAGS_INVIS), mp(2, sign=1, duration=1, target="caster", dodge=False)], learn=20, cooldown=4, cooldown_up=0, per_turn=1)
    sp["sillage"] = class_spell(breed, "Sillage de Lames", "Une ligne de lames devant vous.", "arrow", "air", 4, (1, 4),
        lambda s, h: [dmg("air", sc(8, s), sc(11, s), area={"shape": "line", "size": 4}), dmg("air", sc(6, s), sc(9, s), area={"shape": "line", "size": 4}, mask="A,E%d" % F)],
        learn=28, gap=7, line=True, area={"shape": "line", "size": 4}, per_turn=1)
    sp["fracture"] = class_spell(breed, "Fracture de l'Instant", "Un coup brutal. Sur une faille, il rend un PA et frappe plus fort.", "burst", "neutral", 6, (1, 3),
        lambda s, h: [dmg("neutral", sc(26, s), sc(34, s)), dmg("neutral", sc(14, s), sc(18, s), mask="A,E%d" % F), E("ap", 1, 1, target="enemies", mask="A,E%d" % F, sign=1, dodge=False, duration=0, steal=True),
                      unstate(F, target="enemies", mask="A,E%d" % F)], learn=36, gap=7, cooldown=3, cooldown_up=1, per_turn=1)
    return sp


def tisseur(breed):
    sp = {}
    sp["trait"] = class_spell(breed, "Trait d'Éther", "Un trait d'énergie pure.", "flame", "fire", 3, (1, 6), lambda s, h: [dmg("fire", sc(9, s), sc(13, s))], learn=1, boost=True)

    def rune_feu(s, h):
        gid = h("Rune de Feu", "fire", [dmg("fire", 11, 15, area=("circle", 1), mask="A")])
        return [E("rune", target="all", mask="a,A", duration=4, color="#ff7a3a", mark={"shape": "point", "size": 0}, origin=h.parent, spell=gid)]
    sp["rune_feu"] = class_spell(breed, "Rune de Feu", "Pose une rune ; Détonation la fait exploser.", "glyph", "fire", 3, (1, 5), rune_feu, learn=1, free=True, per_turn=2)

    def rune_givre(s, h):
        gid = h("Rune de Givre", "water", [dmg("water", 6, 9, mask="A"), ap(2, duration=1, mask="A")])
        return [E("rune", target="all", mask="a,A", duration=4, color="#7ac0ff", mark={"shape": "point", "size": 0}, origin=h.parent, spell=gid)]
    sp["rune_givre"] = class_spell(breed, "Rune de Givre", "Une rune qui gèle : dégâts d'eau et retrait de PA.", "drop", "water", 3, (1, 5), rune_givre, learn=5, free=True, per_turn=2)
    sp["detonation"] = class_spell(breed, "Détonation", "Fait parler toutes les runes de la zone.", "burst", "ether", 3, (1, 5),
        lambda s, h: [E("runes", target="all", mask="a,A", area=("circle", 3))], learn=9, area={"shape": "circle", "size": 3}, cooldown=2, cooldown_up=0, per_turn=1)
    sp["fil"] = class_spell(breed, "Fil Tendu", "Un fil d'éther attire la cible et la ralentit.", "chain", "water", 3, (2, 6),
        lambda s, h: [dmg("water", sc(8, s), sc(12, s)), pull(3), mp(1, duration=1)], learn=14, line=True, per_turn=1)
    sp["voile"] = class_spell(breed, "Voile d'Éther", "Un voile protège les alliés proches.", "cloak", "ether", 3, (1, 4),
        lambda s, h: [shield(sc(20, s), duration=2, target="allies", mask="a", area=("circle", 1)), stat("res_all", sc(10, s), 2, target="allies", mask="a", area=("circle", 1))],
        learn=20, area={"shape": "circle", "size": 1}, cooldown=3, cooldown_up=0, per_turn=1)

    def tempete(s, h):
        gid = h("Tempête Nouée", "fire", [dmg("fire", 9, 12, mask="A"), mp(1, duration=1, mask="A")])
        return [E("glyph_start", target="all", mask="a,A", duration=3, color="#ff9a4a", mark={"shape": "circle", "size": 2}, origin=h.parent, spell=gid)]
    sp["tempete"] = class_spell(breed, "Tempête Nouée", "Un glyphe de tempête qui brûle et ralentit au début de chaque tour.", "wind", "fire", 5, (2, 5), tempete, learn=28, gap=7, cooldown=3, cooldown_up=0, per_turn=1)
    sp["eclipse"] = class_spell(breed, "Éclipse d'Éther", "Une nova d'éther qui déclenche ensuite toutes les runes touchées.", "orb", "ether", 6, (1, 5),
        lambda s, h: [dmg("fire", sc(22, s), sc(28, s), area=("circle", 3)), E("runes", target="all", mask="a,A", area=("circle", 3))],
        learn=36, gap=7, area={"shape": "circle", "size": 3}, cooldown=4, cooldown_up=1, per_turn=1)
    return sp


def chasseur(breed):
    I, M = S_INVIS, S_MARQUE
    sp = {}
    sp["tir"] = class_spell(breed, "Tir Silencieux", "Un tir précis. Depuis l'ombre, il frappe de moitié plus fort.", "arrow", "air", 3, (2, 7),
        lambda s, h: [dmg("air", sc(9, s), sc(13, s)), dmg("air", sc(5, s), sc(7, s), mask="A,*E%d" % I)], learn=1, boost=True)
    sp["fleche"] = class_spell(breed, "Flèche Perçante", "Traverse jusqu'à quatre cibles alignées.", "bow", "water", 4, (2, 6),
        lambda s, h: [dmg("water", sc(10, s), sc(14, s), area={"shape": "line", "size": 4})], learn=1, line=True, area={"shape": "line", "size": 4}, per_turn=1)

    def piege(s, h):
        gid = h("Piège d'Ombre", "air", [dmg("air", 10, 14, area=("circle", 1), mask="A"), mp(2, duration=1, area=("circle", 1), mask="A")])
        return [E("trap", target="all", mask="a,A", color="#4a7a58", mark={"shape": "circle", "size": 1}, origin=h.parent, spell=gid)]
    sp["piege"] = class_spell(breed, "Piège d'Ombre", "Blesse et ralentit qui marche dessus.", "trap", "air", 3, (1, 5), piege, learn=5, free=True, per_turn=2)
    sp["disparition"] = class_spell(breed, "Disparition", "Invisible pendant deux tours : vos tirs frappent plus fort.", "moon", "shadow", 2, (0, 0),
        lambda s, h: [state(I, 2, flags=FLAGS_INVIS)], learn=9, cooldown=4, cooldown_up=0, per_turn=1)
    sp["marque"] = class_spell(breed, "Marque du Chasseur", "La proie est marquée et perd des résistances.", "eye", "shadow", 2, (1, 7),
        lambda s, h: [state(M, 3, target="enemies"), stat("res_all", sc(10, s), 3, target="enemies", sign=-1)], learn=14, cooldown=2, cooldown_up=0, per_turn=1, boost=True)
    sp["pluie"] = class_spell(breed, "Pluie d'Ombre", "Une pluie de traits en croix.", "wind", "water", 5, (2, 6),
        lambda s, h: [dmg("water", sc(10, s), sc(14, s), area=("cross", 2)), dmg("water", sc(4, s), sc(6, s), area=("cross", 2), mask="A,E%d" % M)],
        learn=20, area={"shape": "cross", "size": 2}, per_turn=1, cooldown=1, cooldown_up=0)
    sp["repli"] = class_spell(breed, "Repli", "Vous reculez de trois cases et gagnez un PM.", "dash", "air", 2, (0, 0),
        lambda s, h: [E("recoil", 3, 3, target="caster", mask="C", damage=False), mp(1, sign=1, duration=1, target="caster", dodge=False)], learn=28, gap=7, cooldown=3, cooldown_up=0, per_turn=1)
    sp["execution"] = class_spell(breed, "Exécution", "Un tir mortel. Sur une proie marquée, il frappe beaucoup plus fort.", "skull", "air", 6, (3, 8),
        lambda s, h: [dmg("air", sc(24, s), sc(30, s)), dmg("air", sc(14, s), sc(18, s), mask="A,E%d" % M), unstate(M, target="enemies", mask="A,E%d" % M)],
        learn=36, gap=7, line=False, cooldown=3, cooldown_up=1, per_turn=1, boost=True)
    return sp


def archiviste(breed):
    N = S_NOTE
    sp = {}
    sp["plume"] = class_spell(breed, "Plume Acérée", "Une plume d'encre.", "book" if False else "dagger", "water", 3, (1, 5), lambda s, h: [dmg("water", sc(8, s), sc(12, s))], learn=1, boost=True)
    sp["soin"] = class_spell(breed, "Soin d'Encre", "Soigne un allié.", "heal", "water", 3, (1, 5),
        lambda s, h: [heal(sc(10, s), sc(14, s), mask="a")], learn=1, boost=True, per_turn=2)
    tomes = {}

    def tome(s, h):
        mid = tomes.get("mid")
        if mid is None:
            heals = [hidden("Marge soignante", "water", [heal(sc(6, k), sc(9, k), target="allies", mask="g", area=("circle", 1))], area={"shape": "circle", "size": 1}) for k in (1.0, 1.3, 1.6)]
            bolts = [hidden("Trait d'encre", "water", [dmg("water", sc(5, k), sc(8, k))]) for k in (1.0, 1.3, 1.6)]
            mid = summon_def("Tome Gardien", _bone(TOME_BONE_SPEC), 30, 5, 3, spells=[[heals[g], bolts[g]] for g in range(3)], scale=100)
            tomes["mid"] = mid
        return [E("summon", target="all", mask="a,A", monster=mid, grade=h.i + 1)]
    sp["tome"] = class_spell(breed, "Tome Gardien", "Invoque un Tome qui soigne vos alliés et frappe vos ennemis.", "tome", "water", 4, (1, 3), tome, learn=5, free=True, cooldown=3, cooldown_up=0, per_turn=1)
    sp["annotation"] = class_spell(breed, "Annotation", "Annote les alliés proches : puissance accrue.", "scroll", "light", 2, (1, 5),
        lambda s, h: [stat("power", sc(18, s), 3, target="allies", mask="a", area=("circle", 1)), state(N, 3, target="allies", mask="a", area=("circle", 1))],
        learn=9, area={"shape": "circle", "size": 1}, cooldown=2, cooldown_up=0, per_turn=1)
    sp["citation"] = class_spell(breed, "Citation", "Vole des PA à l'ennemi.", "eye", "water", 3, (2, 6),
        lambda s, h: [dmg("water", sc(6, s), sc(9, s)), E("ap", 2, 2, target="enemies", sign=-1, dodge=True, duration=1, steal=True)], learn=14, per_turn=1, cooldown=2, cooldown_up=0)
    sp["marque_page"] = class_spell(breed, "Marque-page", "Échangez votre place avec un allié et protégez-le.", "swap", "light", 2, (1, 6),
        lambda s, h: [E("swap", target="allies", mask="g"), shield(sc(15, s), duration=2, target="allies", mask="g")], learn=20, taken=True, cooldown=3, cooldown_up=0, per_turn=1)
    sp["chapitre"] = class_spell(breed, "Chapitre Final", "Soigne les alliés et blesse les ennemis de la zone. Les annotés guérissent plus.", "burst", "light", 6, (1, 4),
        lambda s, h: [heal(sc(18, s), sc(24, s), mask="a", area=("circle", 2)), heal(sc(8, s), sc(11, s), mask="a,E%d" % N, area=("circle", 2)),
                      dmg("earth", sc(16, s), sc(22, s), area=("circle", 2))], learn=28, gap=7, area={"shape": "circle", "size": 2}, cooldown=4, cooldown_up=1, per_turn=1)
    sp["reecriture"] = class_spell(breed, "Réécriture", "Efface les blessures : soin massif autour de vous.", "essence", "light", 5, (0, 0),
        lambda s, h: [heal_pct(sc(28, s), mask="a", area=("circle", 3)), shield(sc(10, s), duration=2, target="allies", mask="a", area=("circle", 3))],
        learn=36, gap=7, area={"shape": "circle", "size": 3}, cooldown=6, cooldown_up=1, per_turn=1)
    return sp


BUILDERS = {901: veilleur, 902: fendeur, 903: tisseur, 904: chasseur, 905: archiviste}


def build():
    from tilegen import THEMES  # noqa: F401
    breeds, symbols = R.table("breeds"), []
    for bid, c in CLASSES.items():
        bone = _bone(c["look"])
        spells = BUILDERS[bid](bid)
        pairs = [[pid, pid] for pid in spells.values()]
        R.classes[str(bid)] = {"start_states": [], "pairs": pairs}
        row = {"id": bid, "shortNameId": str(T(c["name"])), "descriptionId": T(c["desc"]), "gameplayDescriptionId": str(T(c["tag"])),
               "maleLook": "{%s|||100}" % bone, "femaleLook": "{%s|||96}" % bone, "creatureBonesId": int(bone),
               "statsPointsForStrength": [{"values": [0, 1]}], "statsPointsForIntelligence": [{"values": [0, 1]}],
               "statsPointsForChance": [{"values": [0, 1]}], "statsPointsForAgility": [{"values": [0, 1]}],
               "statsPointsForVitality": [{"values": [0, 1]}], "statsPointsForWisdom": [{"values": [0, 3]}],
               "breedSpellsId": [pid for pid in spells.values()], "breedRoles": [], "maleColors": [], "femaleColors": [],
               "complexity": 2, "sortIndex": bid - 900}
        breeds[str(bid)] = row
        col = c["color"]
        R.icons.append(("UI/classes/symbol_%d" % bid, lambda sy=c["symbol"], co=col: icons.icon(sy, co, rarity=3)))
        for sex in (0, 1):  # the class portraits of the character select / creation screens
            R.icons.append(("UI/classes/heads/big/Head_%d" % (bid * 10 + sex), lambda b=bone, sp=c["look"]: __import__("mobs")._portrait(b, sp)))
    return CLASSES
