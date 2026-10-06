## Spell definitions (data/spells.json), read by the sim for the rules
## and by the client for the spell bar, spell book, range preview and visuals.
## data/spells.json is generated from the real Dofus spells (tools/extractor/spells.py classes):
##   spells: every castable spell *grade*, id = LEVEL_SPELL + spelllevels.id (classes and
##           monsters alike). Class grades also carry {spell (spells.id), grade, breed,
##           description_id}; monster ones have bar: false.
##   classes: breeds.id -> {start_states, pairs: [[spell, variant], ...]} (spellvariants:
##           in Dofus 3 each slot of the spell book has two spells, one is used at a time)
##   grades: spells.id -> [castable id of grade 1, 2, ...]
## A castable spell is a plain Dictionary:
##   {id, name, name_id, icon, level (spelllevels.minPlayerLevel), ap, range: [min, max],
##    range_boost, los, in_line, need_free_cell, need_taken_cell, per_turn, per_target,
##    cooldown, initial_cooldown, crit (%), criterion ("HS=498&HS!8": caster states),
##    area: {shape, size}, effects: [effect], crit_effects: [effect], anim, fx,
##    partial?: [effect ids not simulated yet, its sub-spells' too]}
## An effect: {kind, target: "enemies"|"allies"|"all"|"caster", min, max, duration (turns,
##   -1 = whole fight), area?, cond?: [{who: caster|target, state, has}], ...}; kinds:
##   damage / steal / heal {element}, push / pull / recoil / advance {damage},
##   teleport, swap, sym_target, sym_caster, sym_impact, rollback_prev, rollback_turn, to_start, ap / mp {sign, dodge}, stat {stat, sign},
##   shield {of: level|max_hp}, state / unstate {state, state_name_id, flags},
##   summon / double / replace {monster, grade, replaces?} (applied once on the target cell).
##   carry {states} / throw (P1.12, once on the target cell); `carried`: only the carried fighter (K).
##   A spell may have `carry_range` (more range while carrying).
##   trap / glyph_start / glyph_end / aura {spell, color, mark, origin}, unmark {origin} (P1.13a);
##   cast {spell, by?: "target"}, taken / healed {pct}, unbuff {origin}, kill, heal_pct (P1.13b).
##   glyph_now {spell, color, mark, origin}, intercept / share, reflect {boosted} (P1.13o), heal_attackers {pct} (P1.13e, always
##   with `on`). area shapes: FightRules.zone; from_caster has `max`.
##   ap / mp `steal` (84 / 77: the caster wins what the target lost), dispel (132), `dispellable`
##   (2: only at death, 3: never; P1.13m).
##   `on` (trigger codes) + `turns`: fires later, as a trigger buff (sim FightTriggers); `now`: also at
##   once; `delay`: lands after that many of the caster's turns. A spell also has origin
##   (spells.id) and max_stack.
## fx: {caster, target, target2, missile...} Dofus FX bone ids, or for hand-written
## spells {type: "impact"|"projectile"|"area", color}.
## Test fixtures without `classes` use the old format: class spells with bar: true
## and key, known by level only.
class_name SpellBook
extends RefCounted

const PATH := "data/spells.json"
const LEVEL_SPELL := 1_000_000
## slots of the spell bar. APPROX(P1.03): Dofus 3 shows pages of spell shortcuts;
## the page count is a client setting not in the data
const BAR_SLOTS := 40

static var _spells := {}
static var _start_states: Array = []
static var _classes := {} # breed -> {start_states, pairs}
static var _grades := {} # spells.id -> [castable ids]
static var _summons := {} # monsters.id -> summon data (P1.11)
static var _path := PATH


## Use another spell file (tests use fixed spells); "" = back to the default.
static func use_file(path: String) -> void:
	_path = path if path != "" else PATH
	_spells.clear()
	_classes.clear()
	_grades.clear()
	_summons.clear()


## Forget what was read (the active world changed: ContentSource.use_world).
static func reload() -> void:
	use_file("" if _path == PATH else _path)


## What a summon effect brings in: {name_id, look, portrait, slot, bomb, plays, tackles,
## grades: [{grade, hp, ap, mp, stats, res, bonus, spells}]} (sim/fight/Summons), {} if unknown.
static func summon(monster_id: int) -> Dictionary:
	_ensure()
	return _summons.get(monster_id, {})


static func get_spell(id: int) -> Dictionary:
	_ensure()
	return _spells.get(id, {})


static func all_ids() -> Array:
	_ensure()
	var ids := _spells.keys()
	ids.sort()
	return ids


## Old format: the class spells, in bar order (by "key").
static func bar_ids() -> Array:
	var ids := all_ids().filter(func(id: int) -> bool: return bool(_spells[id].get("bar", true)) and not _spells[id].has("spell"))
	ids.sort_custom(func(a: int, b: int) -> bool: return int(_spells[a].get("key", 99)) < int(_spells[b].get("key", 99)))
	return ids


## The spell pairs of a class, in spell book order (spellvariants, breeds.breedSpellsId).
static func pairs(breed: int) -> Array:
	_ensure()
	return _classes.get(breed, {}).get("pairs", [])


## Castable ids of a spell (spells.id), grade 1 first.
static func grade_ids(spell: int) -> Array:
	_ensure()
	return _grades.get(spell, [])


## Level a spell is learnt at: its first grade's spelllevels.minPlayerLevel.
static func unlock_level(spell: int) -> int:
	var g := grade_ids(spell)
	return int(_spells[g[0]].get("level", 1)) if not g.is_empty() else 999


## The grade a character of `level` casts: the highest whose minPlayerLevel <= level
## (spelllevels.minPlayerLevel), 0 if the spell is not learnt yet.
static func grade_for(spell: int, level: int) -> int:
	var best := 0
	for id: int in grade_ids(spell):
		if int(_spells[id].get("level", 1)) <= level:
			best = id
	return best


## The pair `spell` belongs to in `breed`'s spell book ([] = not a spell of that class).
static func pair_of(breed: int, spell: int) -> Array:
	for p: Array in pairs(breed):
		if p.has(spell):
			return p
	return []


## Spells (spells.id) a character uses, in spell book order: of each pair, the
## chosen variant (`variants` lists the chosen spells) once learnt, else the other
## one if learnt.
static func chosen_spells(breed: int, level: int, variants: Array) -> Array:
	var out: Array = []
	for p: Array in pairs(breed):
		var pick := 0
		for sid: int in p:
			if unlock_level(sid) <= level and (pick == 0 or variants.has(sid)):
				pick = sid
		if pick != 0:
			out.append(pick)
	return out


## Castable ids a character knows (its fighter's spells).
static func known_ids(breed: int, level: int, variants: Array = []) -> Array:
	_ensure()
	if _classes.is_empty(): # old format (test fixtures)
		return bar_ids().filter(func(id: int) -> bool: return int(_spells[id].get("level", 1)) <= level)
	return chosen_spells(breed, level, variants).map(func(sid: int) -> int: return grade_for(sid, level))


## Why `spell` cannot become the used variant of its pair ("" = it can).
static func variant_error(breed: int, level: int, spell: int) -> String:
	if pair_of(breed, spell).is_empty():
		return Protocol.E_UNKNOWN_SPELL
	if unlock_level(spell) > level:
		return Protocol.E_SPELL_LOCKED
	return ""


## The spell bar: BAR_SLOTS spells.id (0 = empty). `stored` is the player's layout;
## a slot keeps its pair (a changed variant takes the other's place), spells no
## longer used are removed and newly learnt ones fill the first empty slots.
static func bar_layout(breed: int, level: int, variants: Array, stored: Array) -> Array:
	var used := chosen_spells(breed, level, variants)
	var out: Array = []
	out.resize(BAR_SLOTS)
	out.fill(0)
	for i in mini(stored.size(), BAR_SLOTS):
		var sid := int(stored[i])
		for s: int in pair_of(breed, sid):
			if used.has(s) and not out.has(s):
				out[i] = s
	for s: int in used:
		if not out.has(s):
			var free := out.find(0)
			if free >= 0:
				out[free] = s
	return out


## `bar` after putting `spell` in `slot` (the spell there takes `spell`'s old slot).
static func move_in_bar(bar: Array, spell: int, slot: int) -> Array:
	var out := bar.duplicate()
	var from := out.find(spell)
	var there: int = out[slot]
	out[slot] = spell
	if from >= 0 and from != slot:
		out[from] = there
	return out


## States the class starts its fights in (Pandawa: Sober).
static func start_states(breed := 12) -> Array:
	_ensure()
	if _classes.is_empty():
		return _start_states
	return _classes.get(breed, {}).get("start_states", [])


static func _ensure() -> void:
	if not _spells.is_empty():
		return
	var data: Variant = DataFiles.read_json(_path)
	if not data is Dictionary:
		push_error("SpellBook: cannot read " + _path)
		return
	_start_states = (data.get("start_states", []) as Array).map(func(s: Variant) -> int: return int(s))
	var classes: Dictionary = data.get("classes", {})
	for b: String in classes:
		_classes[int(b)] = {
			"start_states": (classes[b].get("start_states", []) as Array).map(func(s: Variant) -> int: return int(s)),
			"pairs": (classes[b].get("pairs", []) as Array).map(func(p: Array) -> Array: return p.map(func(s: Variant) -> int: return int(s)))}
	var grades: Dictionary = data.get("grades", {})
	for sid: String in grades:
		_grades[int(sid)] = (grades[sid] as Array).map(func(s: Variant) -> int: return int(s))
	for s: Dictionary in data.get("spells", []):
		s["id"] = int(s["id"])
		_spells[s["id"]] = s
	if _path == PATH: # mod spells (Mods), never over the real ones nor in test fixtures
		for mod: Dictionary in Mods.read_all("spells.json"):
			for s: Dictionary in mod.get("spells", []):
				s["id"] = int(s["id"])
				if not _spells.has(s["id"]):
					_spells[s["id"]] = s
	var summons: Dictionary = data.get("summons", {})
	for m: String in summons:
		_summons[int(m)] = summons[m]
