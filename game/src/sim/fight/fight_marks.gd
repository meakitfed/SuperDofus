## Marks on the ground (P1.13a): traps and glyphs (effects 400, 401, 402; the
## effect names the spell the mark casts, its colour and its cells: spells.py).
##   trap:        cast by a fighter entering one of its cells (walking stops there,
##                pushes and teleports too); its spell is cast by the trap's owner
##                on the trap's centre, then the trap is gone. Hidden from the
##                other team (`hidden`: FightVisibility does not send it to them).
##   glyph_start: its spell hits a fighter starting its turn in it;
##   glyph_end:   ... a fighter ending its turn in it (only that fighter);
##   aura:        (1091 "Pose un glyphe-aura", P1.13b) its spell's effects are given to
##                whoever stands in it (buffs tagged with the mark, lasting while
##                inside) and taken back when they leave or the aura goes (`auras`).
##   rune:        (2022 "Pose une rune", P1.13d) goes off only by effect 2023 "Déclenche
##                les runes" reaching a fighter on it (`runes`): its owner casts its spell on
##                the rune's cell, then the rune is gone. Only the caster's own runes.
##                APPROX(P1.13d): one rune of a caster per cell, the new one replaces the old
##                (Lance-flamme places its rune twice: 2022 and its sub-spell "Rune de Feu").
##   glyph_now:   (1165 "Pose un glyphe" = ActionId FightAddGlyphCastingSpellImmediate, P1.13e) its
##                spell hits at once each fighter standing in it (the fighter it triggers for);
##                always placed with an aura (1091) of the same spell. APPROX(P1.13e): nothing more
##                afterwards (the name says "Immediate"; the aura does the lasting part).
##   wall:        (P1.13d, spellbombwalls) between two bombs of the same summoner and the
##                same monster, in a line with minHop..maxHop cells between them, all
##                walkable (`walls`, kept up to date with the auras); its spell (at the first
##                bomb's grade) hits a fighter starting its turn in it or arriving on it,
##                cast by the first bomb. APPROX(P1.13d): same-monster pairs, the hop = the
##                cells between, the triggers of a glyph plus arrival (a walk through it
##                does not trigger it, only one ending on it).
##   portal:      (1181 "Pose un portail", P1.13f, Eliotrope) one cell. A caster's active portals
##                make a network once there are two: a fighter walking into one (its walk stops
##                there) gets the portal's spell "Téléportail" (1182, `cross`): it goes from portal to
##                portal and comes out of the last one; a spell its owner casts on one of them is
##                projected (`projection`): it lands on the exit cell, coming from the portal before,
##                with +bonus% + per_cell% per cell travelled on its damage and heals (1181 #3 / #1).
##                1183 disables portals for `duration` of the disabler's turns (`unportal`).
##                "Les combattants ennemis ne peuvent pas emprunter un portail au premier tour de jeu"
##                (spell Portail's text): the owner's enemies do not walk into them in round 1
##                (APPROX(P1.13f): Exil still sends them through).
##                APPROX(P1.13f), none of this is in the data: the path goes to the nearest portal
##                not visited yet (lowest cell on a tie) until all are visited (Dofus 2 rule); a
##                network is one caster's portals; at most MAX_PORTALS per caster, the oldest goes;
##                a new portal replaces the caster's one on that cell; only a walk ending on a portal
##                (not a push or a teleport) crosses it; no crossing when the exit is taken; a spell
##                is projected only on its caster's own portals, never on its own cell, and not the
##                spells handling portals.
##   Who triggers a mark: the effect's `target` side and `cond` (targetMask).
##   Duration: the effect's, counted on the owner's turns like buffs (0 = until
##   triggered); the owner's death removes its marks. unmark (2018): the owner's
##   marks of one spell (`origin`), e.g. Pâturage replaces its previous glyph.
## Marks are dicts: {id, kind, caster, team, spell, origin, cell, cells, color,
## turns, hidden} (Protocol "mark dict"), plus `who` / `cond` (sim only).
class_name FightMarks
extends RefCounted

const KINDS := ["trap", "glyph_start", "glyph_end", "aura", "rune", "glyph_now"]
const PORTAL_KINDS := ["portal", "unportal", "teleportal"]
const MAX_PORTALS := 4


static func add(fight: Fight, caster: Fighter, e: Dictionary, center: int) -> Array:
	var cells: Array = FightRules.zone(e.get("mark", {}), center, caster.cell).filter(
			func(c: int) -> bool: return fight.map.is_fight_walkable(c))
	if not cells.has(center) or int(e.get("spell", 0)) == 0:
		return []
	var duration := int(e.get("duration", 0))
	var out: Array = []
	if str(e["kind"]) == "rune":
		out = _remove(fight, func(x: Dictionary) -> bool:
			return x["kind"] == "rune" and int(x["caster"]) == caster.id and int(x["cell"]) == center)
	var m := {"id": fight.next_mark_id(), "kind": str(e["kind"]), "caster": caster.id, "team": caster.team,
			"spell": int(e["spell"]), "origin": int(e.get("origin", 0)), "cell": center, "cells": cells,
			"color": str(e.get("color", "#ffffff")), "turns": duration if duration > 0 else -1,
			"hidden": str(e["kind"]) == "trap", "who": str(e.get("target", "all")), "cond": e.get("cond", []),
			"inside": []}
	fight.marks.append(m)
	out.append({"kind": "mark_add", "target": caster.id, "mark": public(m)})
	if m["kind"] == "glyph_now":
		for f: Fighter in fight.fighters.values():
			if f.alive and f.carried_by == -1 and cells.has(f.cell) and _triggers(fight, m, f):
				fight.hit_source = "glyph"
				out.append_array(FightEffects.apply_spell(fight, caster, SpellBook.get_spell(int(m["spell"])), f.cell, false, f))
				fight.hit_source = ""
	return out


## What the clients get of a mark.
static func public(m: Dictionary) -> Dictionary:
	var d := m.duplicate()
	d.erase("who")
	d.erase("cond")
	d.erase("inside")
	d.erase("pair")
	d.erase("off")
	d.erase("off_by")
	return d


## Updates the walls, then gives the aura marks' effects to who just came in, takes them
## back from who left.
static func auras(fight: Fight) -> Array:
	var out: Array = walls(fight)
	for m: Dictionary in fight.marks.duplicate():
		if m["kind"] != "aura" or not fight.marks.has(m):
			continue
		var owner: Fighter = fight.fighters.get(int(m["caster"]))
		for f: Fighter in fight.fighters.values():
			var inside: bool = owner != null and owner.alive and f.alive and f.carried_by == -1 \
					and (m["cells"] as Array).has(f.cell) and _triggers(fight, m, f)
			var was: bool = (m["inside"] as Array).has(f.id)
			if inside and not was:
				m["inside"].append(f.id)
				fight.aura_tag = int(m["id"])
				out.append_array(FightEffects.apply_spell(fight, owner, SpellBook.get_spell(int(m["spell"])), f.cell, false, f))
				fight.aura_tag = 0
			elif was and not inside:
				m["inside"].erase(f.id)
				out.append_array(_take_back(f, int(m["id"])))
	return out


static func _take_back(f: Fighter, mark_id: int) -> Array:
	var out: Array = []
	for b: Buff in f.buffs.duplicate():
		if b.aura == mark_id:
			out.append_array(FightEffects.remove_buff(f, b))
	return out


## The walls between the bombs as they stand now: missing ones added, broken ones removed.
static func walls(fight: Fight) -> Array:
	var want := {}
	var bombs: Array = fight.fighters.values().filter(func(f: Fighter) -> bool:
		return f.alive and f.carried_by == -1 and SpellBook.summon(f.monster).has("wall"))
	for i in bombs.size():
		for j in range(i + 1, bombs.size()):
			var a: Fighter = bombs[i]
			var b: Fighter = bombs[j]
			if a.summoner != b.summoner or a.monster != b.monster:
				continue
			var w: Dictionary = SpellBook.summon(a.monster)["wall"]
			var cells := _between(fight, a.cell, b.cell, bool(w.get("linear", true)))
			if cells.size() >= int(w.get("min", 1)) and cells.size() <= int(w.get("max", 7)):
				var first: Fighter = a if a.id < b.id else b
				want["%d:%d" % [mini(a.id, b.id), maxi(a.id, b.id)]] = {"bomb": first, "wall": w, "cells": cells}
	var out := _remove(fight, func(m: Dictionary) -> bool:
		return m["kind"] == "wall" and not (want.has(m["pair"]) and want[m["pair"]]["cells"] == m["cells"]))
	for key: String in want:
		if fight.marks.any(func(m: Dictionary) -> bool: return m["kind"] == "wall" and m["pair"] == key):
			continue
		var bomb: Fighter = want[key]["bomb"]
		var spells: Array = want[key]["wall"]["spells"]
		var m := {"id": fight.next_mark_id(), "kind": "wall", "caster": bomb.id, "team": bomb.team,
				"spell": int(spells[clampi(bomb.grade, 1, spells.size()) - 1]), "origin": 0,
				"cell": want[key]["cells"][0], "cells": want[key]["cells"], "color": str(want[key]["wall"]["color"]),
				"turns": -1, "hidden": false, "who": "all", "cond": [], "inside": [], "pair": key}
		fight.marks.append(m)
		out.append({"kind": "mark_add", "target": bomb.id, "mark": public(m)})
	return out


## The cells strictly between `a` and `b` when they are in a line (else none), all walkable.
static func _between(fight: Fight, a: int, b: int, linear: bool) -> Array:
	var d := MapGeometry.to_iso(b) - MapGeometry.to_iso(a)
	if not linear or (d.x != 0 and d.y != 0) or d == Vector2i.ZERO:
		return []
	var step := Vector2i(signi(d.x), signi(d.y))
	var out: Array = []
	var p := MapGeometry.to_iso(a) + step
	while p != MapGeometry.to_iso(b):
		var c := MapGeometry.from_iso(p)
		if c < 0 or not fight.map.is_fight_walkable(c):
			return []
		out.append(c)
		p += step
	return out


## Effect 2023 reaching `t`: `caster`'s runes under it go off (see the header).
static func runes(fight: Fight, caster: Fighter, t: Fighter) -> Array:
	var out: Array = []
	for m: Dictionary in fight.marks.duplicate():
		if m["kind"] != "rune" or int(m["caster"]) != caster.id or not (m["cells"] as Array).has(t.cell) \
				or not fight.marks.has(m):
			continue
		out.append_array(_remove(fight, func(x: Dictionary) -> bool: return x == m))
		out.append_array(FightEffects.apply_spell(fight, caster, SpellBook.get_spell(int(m["spell"])), int(m["cell"]), false))
	return out


## Effect 1026 (P1.17b) reaching `t`: `caster`'s glyphs under it go off now, and stay. APPROX(P1.17b):
## only the i18n text "Déclenche les glyphes": the caster's glyphs of both kinds, none of the others'.
static func trigger_glyphs(fight: Fight, caster: Fighter, t: Fighter) -> Array:
	var out: Array = []
	if not t.alive or t.carried_by != -1:
		return out
	for m: Dictionary in fight.marks.duplicate():
		if not ["glyph_start", "glyph_end"].has(m["kind"]) or int(m["caster"]) != caster.id 				or not (m["cells"] as Array).has(t.cell) or not t.alive:
			continue
		fight.hit_source = "glyph"
		out.append_array(FightEffects.apply_spell(fight, caster, SpellBook.get_spell(int(m["spell"])), t.cell, false, t))
		fight.hit_source = ""
	return out


## Removes the owner's marks of spell `e.origin` (effect 2018).
static func unmark(fight: Fight, caster: Fighter, e: Dictionary) -> Array:
	return _remove(fight, func(m: Dictionary) -> bool:
		return int(m["caster"]) == caster.id and int(m["origin"]) == int(e.get("origin", -1)))


## The first trap on `cell` that `f` sets off, {} if none.
static func trap_at(fight: Fight, f: Fighter, cell: int) -> Dictionary:
	for m: Dictionary in fight.marks:
		if m["kind"] == "trap" and (m["cells"] as Array).has(cell) and _triggers(fight, m, f):
			return m
	return {}


## `f` just arrived on its cell (walk, push, teleport): the trap there goes off.
static func entered(fight: Fight, f: Fighter) -> Array:
	if not f.alive or f.carried_by != -1:
		return []
	var m := trap_at(fight, f, f.cell)
	if m.is_empty():
		return glyphs(fight, f, "wall")
	var out := _remove(fight, func(x: Dictionary) -> bool: return x == m)
	var owner: Fighter = fight.fighters.get(int(m["caster"]))
	if owner != null and owner.alive:
		fight.hit_source = "trap" # DT / CDT (P1.13i, FightTriggers)
		out.append_array(FightEffects.apply_spell(fight, owner, SpellBook.get_spell(int(m["spell"])), int(m["cell"]), false))
		fight.hit_source = ""
	return out


## Glyphs of `kind` (glyph_start / glyph_end / wall) under `f`: their spells hit `f`.
static func glyphs(fight: Fight, f: Fighter, kind: String) -> Array:
	var out: Array = []
	if f == null or not f.alive or f.carried_by != -1:
		return out
	for m: Dictionary in fight.marks.duplicate():
		if m["kind"] != kind or not (m["cells"] as Array).has(f.cell) or not _triggers(fight, m, f):
			continue
		var owner: Fighter = fight.fighters.get(int(m["caster"]))
		if owner != null and owner.alive and f.alive:
			fight.hit_source = "glyph" if kind != "wall" else "" # DG / CDG (P1.13i, FightTriggers)
			out.append_array(FightEffects.apply_spell(fight, owner, SpellBook.get_spell(int(m["spell"])), f.cell, false, f))
			fight.hit_source = ""
	return out


## Start of `f`'s turn: its marks count down, the portals it disabled too.
static func countdown(fight: Fight, f: Fighter) -> Array:
	var out: Array = []
	for m: Dictionary in fight.marks:
		if int(m["caster"]) == f.id and int(m["turns"]) > 0:
			m["turns"] = int(m["turns"]) - 1
		if m["kind"] == "portal" and int(m.get("off_by", -1)) == f.id and int(m.get("off", 0)) > 0:
			m["off"] = int(m["off"]) - 1
			if int(m["off"]) == 0:
				m["active"] = true
				m["off_by"] = -1
				out.append({"kind": "portal", "target": int(m["caster"]), "mark": int(m["id"]), "active": true})
	out.append_array(_remove(fight, func(m: Dictionary) -> bool: return int(m["caster"]) == f.id and int(m["turns"]) == 0))
	return out


## 1181 (see the header): a portal of `caster` on `center`.
static func portal(fight: Fight, caster: Fighter, e: Dictionary, center: int) -> Array:
	if not fight.map.is_fight_walkable(center) or int(e.get("spell", 0)) == 0:
		return []
	var out := _remove(fight, func(x: Dictionary) -> bool:
		return x["kind"] == "portal" and int(x["caster"]) == caster.id and int(x["cell"]) == center)
	var mine := fight.marks.filter(func(x: Dictionary) -> bool: return x["kind"] == "portal" and int(x["caster"]) == caster.id)
	while mine.size() >= MAX_PORTALS:
		var old: Dictionary = mine.pop_front()
		out.append_array(_remove(fight, func(x: Dictionary) -> bool: return x == old))
	var m := {"id": fight.next_mark_id(), "kind": "portal", "caster": caster.id, "team": caster.team,
			"spell": int(e["spell"]), "origin": int(e.get("origin", 0)), "cell": center, "cells": [center],
			"color": "#3fa9ff", "turns": -1, "hidden": false, "who": "all", "cond": [], "inside": [],
			"active": true, "bonus": int(e.get("bonus", 0)), "per_cell": int(e.get("per_cell", 0)), "off": 0, "off_by": -1}
	fight.marks.append(m)
	out.append({"kind": "mark_add", "target": caster.id, "mark": public(m)})
	return out


## The active portal of `owner` (any owner when null) on `cell`, {} if none.
static func portal_at(fight: Fight, cell: int, owner: Fighter = null) -> Dictionary:
	for m: Dictionary in fight.marks:
		if m["kind"] == "portal" and bool(m["active"]) and int(m["cell"]) == cell \
				and (owner == null or int(m["caster"]) == owner.id):
			return m
	return {}


## The portals a crossing from `entry` goes through, entry first, exit last; [] when its
## owner has fewer than two active portals.
static func network(fight: Fight, entry: Dictionary) -> Array:
	if entry.is_empty() or not bool(entry["active"]):
		return []
	var left := fight.marks.filter(func(x: Dictionary) -> bool:
		return x["kind"] == "portal" and bool(x["active"]) and int(x["caster"]) == int(entry["caster"]) and x != entry)
	var chain: Array = [entry]
	while not left.is_empty():
		var cur: int = chain[-1]["cell"]
		left.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var da := FightRules.distance(cur, int(a["cell"]))
			var db := FightRules.distance(cur, int(b["cell"]))
			return da < db or (da == db and int(a["cell"]) < int(b["cell"])))
		chain.append(left.pop_front())
	return chain if chain.size() >= 2 else []


## % bonus of a spell projected through `chain`: 1181 #3 + #1 per cell travelled.
static func chain_bonus(chain: Array) -> int:
	var cells := 0
	for i in range(1, chain.size()):
		cells += FightRules.distance(int(chain[i - 1]["cell"]), int(chain[i]["cell"]))
	return int(chain[0]["bonus"]) + int(chain[0]["per_cell"]) * cells


## `f` may cross the portal on `cell` now (`walk`: on its own, walking): {entry, chain} or {}.
static func crossing(fight: Fight, f: Fighter, cell: int, walk := false) -> Dictionary:
	var entry := portal_at(fight, cell)
	if entry.is_empty() or f.carried_by != -1 or f.has_flag("cant_be_moved"):
		return {}
	var owner: Fighter = fight.fighters.get(int(entry["caster"]))
	if owner == null or (walk and owner.team != f.team and fight.fight_round <= 1):
		return {}
	var chain := network(fight, entry)
	if chain.is_empty():
		return {}
	var at := fight.fighter_at(int(chain[-1]["cell"]))
	if at != null and at != f:
		return {}
	return {"entry": entry, "chain": chain}


## `f`'s walk ended on a portal it may cross: the portal's owner casts its spell on it.
static func walked_in(fight: Fight, f: Fighter) -> Array:
	var c := crossing(fight, f, f.cell, true)
	if c.is_empty():
		return []
	var owner: Fighter = fight.fighters.get(int(c["entry"]["caster"]))
	return FightEffects.apply_spell(fight, owner, SpellBook.get_spell(int(c["entry"]["spell"])), f.cell, false, f)


## 1182 "Téléportail" on `t`: it crosses the portals from its cell (PT on it, CPT on everyone),
## then what is on the exit cell goes off.
static func cross(fight: Fight, t: Fighter) -> Array:
	var c := crossing(fight, t, t.cell)
	if c.is_empty():
		return []
	var path: Array = (c["chain"] as Array).map(func(m: Dictionary) -> int: return int(m["cell"]))
	t.cell = path[-1]
	Carry.follow(fight, t)
	fight.log_cast(t, "moved")
	var out: Array = [{"kind": "move", "target": t.id, "path": path, "how": "portal"}]
	out.append_array(FightTriggers.fire(fight, t, ["PT"]))
	for g: Fighter in fight.fighters.values():
		if g.alive:
			out.append_array(FightTriggers.fire(fight, g, ["CPT"]))
	out.append_array(entered(fight, t))
	return out


## `caster` casting `spell` on `target`: {exit, from, path, bonus} when it is projected through
## its portals, else {}.
static func projection(fight: Fight, caster: Fighter, spell: Dictionary, target: int) -> Dictionary:
	if target == caster.cell:
		return {}
	for e: Dictionary in (spell.get("effects", []) as Array) + (spell.get("crit_effects", []) as Array):
		if str(e.get("kind", "")) in PORTAL_KINDS:
			return {}
	var chain := network(fight, portal_at(fight, target, caster))
	if chain.is_empty():
		return {}
	return {"exit": int(chain[-1]["cell"]), "from": int(chain[-2]["cell"]), "bonus": chain_bonus(chain),
			"path": chain.map(func(m: Dictionary) -> int: return int(m["cell"]))}


## 1183 "Désactive un portail": the portals in the effect's area (every one with `all`) stop
## working for `duration` of `caster`'s turns.
static func unportal(fight: Fight, caster: Fighter, e: Dictionary, center: int) -> Array:
	var out: Array = []
	var cells := FightRules.zone(e.get("area", {}), center, caster.cell)
	for m: Dictionary in fight.marks:
		if m["kind"] != "portal" or not bool(m["active"]) or not (bool(e.get("all", false)) or cells.has(int(m["cell"]))):
			continue
		m["active"] = false
		m["off"] = maxi(1, int(e.get("duration", 1)))
		m["off_by"] = caster.id
		out.append({"kind": "portal", "target": int(m["caster"]), "mark": int(m["id"]), "active": false})
	return out


## `fighter_id` died: its marks go.
static func remove_of(fight: Fight, fighter_id: int) -> Array:
	return _remove(fight, func(m: Dictionary) -> bool: return int(m["caster"]) == fighter_id)


static func _triggers(fight: Fight, m: Dictionary, f: Fighter) -> bool:
	var owner: Fighter = fight.fighters.get(int(m["caster"]))
	if owner == null:
		return false
	var e := {"target": m["who"], "cond": m["cond"]}
	return FightEffects.team_ok(e, owner, f) and FightEffects.cond_ok(e, owner, f)


static func _remove(fight: Fight, which: Callable) -> Array:
	var out: Array = []
	for m: Dictionary in fight.marks.duplicate():
		if which.call(m):
			fight.marks.erase(m)
			out.append({"kind": "mark_remove", "target": int(m["caster"]), "mark": int(m["id"])})
			for fid: int in m["inside"]:
				var f: Fighter = fight.fighters.get(fid)
				if f != null:
					out.append_array(_take_back(f, int(m["id"])))
	return out
