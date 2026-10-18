"""Spell construction kit: effect builders and the registration of class spells (3 grades) and
monster spells (1 grade) in the format of shared/spell_book.gd.

Mask letters (sim/fight/target_mask.gd): A enemies, a allies (caster included), g allies, C the caster,
j/J summons, E<n>/e<n> has / has not state n, *E<n> state of the caster, "a,A" everybody.
"""
from __future__ import annotations

import copy

import icons
from common import R, T, grade_id, spell_id

ELEMENTS = ("earth", "fire", "water", "air", "neutral")
FX_COLOR = {"earth": "#a8763c", "fire": "#ff6a2a", "water": "#3f9bff", "air": "#8be29c", "neutral": "#d8d4e0", "ether": "#b078ff",
            "light": "#ffe27a", "shadow": "#6e4c96"}
SIDE = {"enemies": "A", "allies": "a", "others": "g", "caster": "C", "all": "a,A", "summons": "j,J"}


def E(kind, lo=0, hi=None, target="enemies", mask=None, area=("point", 0), duration=0, delay=0, **kw):
    """One effect. `area` = (shape, size) or a dict."""
    a = area if isinstance(area, dict) else {"shape": area[0], "size": area[1]}
    e = {"target": target, "min": int(lo), "max": int(lo if hi is None else hi), "duration": duration, "delay": delay,
         "area": a, "mask": SIDE[target] if mask is None else mask, "kind": kind}
    e.update(kw)
    return e


def dmg(element, lo, hi, **kw):
    return E("damage", lo, hi, element=element, **kw)


def steal(element, lo, hi, **kw):
    return E("steal", lo, hi, element=element, **kw)


def heal(lo, hi, target="allies", **kw):
    return E("heal", lo, hi, target=target, element="air", **kw)


def heal_pct(pct, target="allies", **kw):
    return E("heal_pct", pct, pct, target=target, **kw)


def shield(pct, duration=1, target="caster", **kw):
    return E("shield", pct, pct, target=target, duration=duration, of="max_hp", **kw)


def stat(name, amount, duration, target="caster", sign=1, **kw):
    return E("stat", amount, amount, target=target, duration=duration, stat=name, sign=sign, **kw)


def state(sid, duration, target="caster", flags=(), **kw):
    return E("state", 0, 0, target=target, duration=duration, state=sid, state_name_id=0, flags=list(flags), **kw)


def unstate(sid, target="caster", **kw):
    return E("unstate", 0, 0, target=target, state=sid, **kw)


def push(n, damage=True, target="enemies", **kw):
    return E("push", n, n, target=target, damage=damage, **kw)


def pull(n, target="enemies", **kw):
    return E("pull", n, n, target=target, **kw)


def ap(n, sign=-1, duration=1, target="enemies", dodge=True, **kw):
    return E("ap", n, n, target=target, duration=duration, sign=sign, dodge=dodge, dispellable=3, **kw)


def mp(n, sign=-1, duration=1, target="enemies", dodge=True, **kw):
    return E("mp", n, n, target=target, duration=duration, sign=sign, dodge=dodge, dispellable=3, **kw)


def scaled(effects, k):
    """Effects with their numbers multiplied by k (damage/heal/shield only, never counts or durations)."""
    out = copy.deepcopy(effects)
    for e in out:
        if e["kind"] in ("damage", "steal", "heal"):
            e["min"], e["max"] = max(1, round(e["min"] * k)), max(1, round(e["max"] * k))
        elif e["kind"] in ("shield", "heal_pct"):
            e["min"] = e["max"] = max(1, round(e["min"] * k))
    return out


def crit_of(effects, k=1.25):
    return scaled(effects, k)


def _spell(sid, parent, name, desc, element, ap_cost, rng, effects, **o):
    g = {"id": sid, "name_id": T(name), "name": name, "description_id": T(desc) if desc else 0,
         "icon": o.get("icon", parent), "level": o.get("level", 1), "ap": ap_cost,
         "range": list(rng), "range_boost": o.get("boost", False), "los": o.get("los", True), "in_line": o.get("line", False),
         "need_free_cell": o.get("free", False), "need_taken_cell": o.get("taken", False),
         "per_turn": o.get("per_turn", 1 if ap_cost > 3 else 2), "per_target": o.get("per_target", 99),
         "cooldown": o.get("cooldown", 0), "initial_cooldown": o.get("initial_cooldown", 0), "crit": o.get("crit", 5),
         "area": o.get("area", {"shape": "point", "size": 0}), "effects": effects, "crit_effects": o.get("crit_effects", crit_of(effects)),
         "anim": o.get("anim", ["AnimAttaque0"]), "fx": o.get("fx", {"type": "impact", "color": FX_COLOR.get(element, "#ffffff")}),
         "origin": parent, "spell": parent, "max_stack": 0, "bar": o.get("bar", True)}
    if o.get("criterion"):
        g["criterion"] = o["criterion"]
    for k in ("breed", "grade", "rank"):
        if k in o:
            g[k] = o[k]
    return g


def hidden(name, element, effects, rng=(0, 63), area=None):
    """A spell nobody casts by hand (what a trap / glyph / rune / trigger fires): returns its grade id."""
    gid = grade_id()
    R.spells.append(_spell(gid, spell_id(), name, "", element, 0, rng, effects, bar=False, area=area or {"shape": "point", "size": 0}, per_turn=99, los=False))
    return gid


def class_spell(breed, name, desc, symbol, element, ap_cost, rng, build, learn=1, gap=14, scales=(1.0, 1.35, 1.75), **o):
    """A class spell with 3 grades. build(s, hid) -> effects, where s is the scale of the grade and hid(name,
    element, effects) registers the hidden spell of a trap / glyph / rune (scaled with the grade)."""
    parent = spell_id()
    gids = []
    for i, s in enumerate(scales):
        gid = grade_id()
        gids.append(gid)

        def hid(hname, helem, heff, _s=s, **hk):
            return hidden(hname, helem, scaled(heff, _s), **hk)
        hid.parent = parent
        hid.i = i  # grade index (0..2): a summon effect picks the matching summon grade
        effects = build(s, hid)
        extra = dict(o)
        extra.update(level=min(60, learn + gap * i), breed=breed, grade=i + 1)
        if i > 0 and "cooldown_up" in o:
            extra["cooldown"] = max(0, o.get("cooldown", 0) - i * o["cooldown_up"])
        R.spells.append(_spell(gid, parent, name, desc, element, ap_cost, rng, effects, **extra))
    R.grades[str(parent)] = gids
    sym_color = icons.ELEMENT.get(element, icons.ELEMENT["neutral"])
    R.icons.append(("Picto/Spells/%d" % parent, lambda sy=symbol, c=sym_color: icons.icon(sy, c, rarity=2)))
    return parent


def monster_spell(name, element, ap_cost, rng, effects, symbol="burst", **o):
    """A one-grade spell of a monster (not on the bar)."""
    gid = grade_id()
    o.setdefault("bar", False)
    R.spells.append(_spell(gid, 0, name, o.pop("desc", ""), element, ap_cost, rng, effects, **o))
    R.icons.append(("Picto/Spells/%d" % gid, lambda sy=symbol, c=icons.ELEMENT.get(element, icons.ELEMENT["neutral"]): icons.icon(sy, c, rarity=1)))
    return gid


def summon_def(name, bone, hp, ap_, mp_, spells=(), plays=True, slot=True, scale=90, res=0, stats=None, grades=3, hp_step=0.4, start=None):
    """A summoned creature (data/spells.json "summons"): returns its monster id. 3 grades, hp growing with the grade."""
    from common import monster_id
    mid = monster_id()
    gl = []
    for g in range(grades):
        k = 1 + hp_step * g
        d = {"grade": g + 1, "hp": int(hp * k), "ap": ap_, "mp": mp_,
             "stats": dict({"strength": 0, "intelligence": 0, "chance": 0, "agility": 0, "wisdom": 0, "ap_dodge": 0, "mp_dodge": 0}, **(stats or {})),
             "res": {e: res for e in ELEMENTS}, "bonus": {}, "spells": list(spells[g] if spells and isinstance(spells[0], (list, tuple)) else spells)}
        if start:
            d["start"] = start[g] if isinstance(start, (list, tuple)) else start
        gl.append(d)
    R.summons[str(mid)] = {"name_id": T(name), "name": name, "look": "{%s|||%d}" % (bone, scale), "portrait": 0, "slot": slot, "bomb": False,
                           "plays": plays, "tackles": plays, "switch": False, "switch_on_target": False, "grades": gl}
    return mid
