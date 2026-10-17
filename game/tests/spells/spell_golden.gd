## Golden of the class spells (H.02): every grade of every class spell (spells.id) cast in the standard
## SpellArena duel, what it did written down as data and compared with tests/golden/spells/classe_<NN>.json.
## Any change of behaviour of a spell (a formula, a rule, the data) shows up as a diff of that file.
##
## A grade is played in up to three scenarios, each a fresh arena (caster with 100 in every element, its
## rolls forced to the max, seed SpellArena.SEED):
##   "cast"  the spell cast on its usual target, the state right after, then "round" one whole round later
##           (poisons, glyphs, delays, buffs wearing off);
##   "crit"  the same cast as a critical hit (only when the grade has critical effects of its own);
##   "cast+states" / "round+states"  the same again once the fighters hold the states the effects' conditions
##           ask for (Sobre / Saoul, Rune...; only when a condition asks for one).
## The record is a diff against the arena before the cast: only what changed is written.
class_name SpellGolden
extends RefCounted

const DIR := "res://tests/golden/spells/"
const STAT_ELEMENTS := ["strength", "intelligence", "chance", "agility"]


static func file_of(breed: int) -> String:
	return "%sclasse_%02d.json" % [DIR, breed]


## Do we rewrite the golden files instead of comparing (--update-golden after `--`, or GOLDEN_UPDATE=1)?
static func updating() -> bool:
	return OS.get_environment("GOLDEN_UPDATE") == "1" or OS.get_cmdline_user_args().has("--update-golden")


## spells.id -> its grade ids (rank order), for the class spells of `breed`.
static func spells_of(breed: int) -> Dictionary:
	var out := {}
	for id: int in SpellIndex.class_grades():
		var s := SpellBook.get_spell(id)
		if int(s.get("breed", 0)) == breed:
			var sid := int(s.get("spell", id))
			if not out.has(sid):
				out[sid] = []
			out[sid].append(id)
	for sid: int in out:
		out[sid].sort_custom(func(a: int, b: int) -> bool: return int(SpellBook.get_spell(a).get("rank", 1)) < int(SpellBook.get_spell(b).get("rank", 1)))
	return out


static func breeds() -> Array:
	var seen := {}
	for id: int in SpellIndex.class_grades():
		seen[int(SpellBook.get_spell(id)["breed"])] = true
	var out := seen.keys()
	out.sort()
	return out


## The record of one spell: {name, grades: {<rank>: {<scenario>: record}}}.
static func spell(sid: int, grade_ids: Array) -> Dictionary:
	var grades := {}
	for id: int in grade_ids:
		var s := SpellBook.get_spell(id)
		grades[str(int(s.get("rank", 1)))] = grade(id)
	return {"name": str(SpellBook.get_spell(grade_ids[0]).get("name", "?")), "grades": grades}


static func grade(id: int) -> Dictionary:
	var spell := SpellBook.get_spell(id)
	var out := {}
	var states := _wanted_states(spell)
	out.merge(_scenario(spell, false, false, ""))
	if spell.get("crit_effects", []) != spell.get("effects", []):
		out.merge(_scenario(spell, true, false, "crit", false))
	if not states.is_empty():
		out.merge(_scenario(spell, false, true, "+states"))
	return out


## Plays one fresh duel: returns {<prefix>cast: record, <prefix>round: record}.
static func _scenario(spell: Dictionary, crit: bool, with_states: bool, suffix: String, rounds := true) -> Dictionary:
	var arena := SpellArena.new(int(spell.get("breed", 0)))
	arena.me.stats["roll_max"] = 1
	for stat: String in STAT_ELEMENTS:
		arena.me.stats[stat] = 100
	if with_states:
		for w: Array in _wanted_states(spell):
			for f: Fighter in arena.fighters():
				if (f == arena.me or not bool(w[0])) and not f.has_state(int(w[1])):
					arena.give_state(f, int(w[1]))
	var before := arena.snapshot()
	var before_buffs := _buff_ids(arena)
	var effects := arena.cast(spell, SpellSmoke.aim(arena, spell), crit)
	var out := {}
	var cast_key := "cast" if suffix == "" else ("crit" if suffix == "crit" else "cast" + suffix)
	out[cast_key] = _record(arena, before, before_buffs, effects)
	if rounds:
		var mid := arena.snapshot()
		var mid_buffs := _buff_ids(arena)
		var turn_effects := arena.play_until(arena.me)
		out["round" + suffix] = _record(arena, mid, mid_buffs, turn_effects)
	return out


## The states the effects' conditions ask for: [[on the caster?, state], ...] (as SpellCheck does).
static func _wanted_states(spell: Dictionary) -> Array:
	var wants: Array = []
	for list_name: String in ["effects", "crit_effects"]:
		for e: Dictionary in spell.get(list_name, []):
			for c: Dictionary in e.get("cond", []):
				if c.has("state") and bool(c["has"]):
					var w := [str(c.get("who", "")) == "caster", int(c["state"])]
					if not wants.has(w):
						wants.append(w)
			for tok: String in str(e.get("mask", "")).split(",", false):
				var body := tok.trim_prefix("*")
				if body.length() > 1 and body[0] == "E" and body.substr(1).is_valid_int():
					var w2 := [tok.begins_with("*"), int(body.substr(1))]
					if not wants.has(w2):
						wants.append(w2)
	return wants


static func _buff_ids(arena: SpellArena) -> Dictionary:
	var out := {}
	for f: Fighter in arena.fighters():
		for b: Buff in f.buffs:
			out[b.id] = true
	return out


static func _offset(cell: int) -> String:
	var d := MapGeometry.to_iso(cell) - MapGeometry.to_iso(SpellArena.CENTER)
	return "%d,%d" % [d.x, d.y]


static func _buff(arena: SpellArena, b: Buff) -> String:
	var what := b.kind
	if b.kind == "stat":
		what += ":" + b.stat
	elif b.kind == "state":
		what += ":%d" % b.state
	elif b.effect.has("kind"):
		what += ":" + str(b.effect["kind"])
	return "%s=%d/%dt spell %d by %s" % [what, b.value, b.turns, b.spell, _who(arena, b.caster)]


static func _who(arena: SpellArena, id: int) -> String:
	var f: Fighter = arena.fight.fighters.get(id)
	return arena.slot_of(f) if f != null else "-"


## What changed since `before`: the effects' kinds, each fighter's changed fields, the marks, the summons.
static func _record(arena: SpellArena, before: Dictionary, before_buffs: Dictionary, effects: Array) -> Dictionary:
	var kinds := {}
	for fx: Variant in effects:
		if fx is Dictionary:
			var k := str((fx as Dictionary).get("kind", "?"))
			kinds[k] = int(kinds.get(k, 0)) + 1
	var out := {"effects": kinds}
	var fighters := {}
	for f: Fighter in arena.fighters():
		var slot := arena.slot_of(f)
		var d := {}
		var was: FighterSnapshot = before.get(f.id)
		if was == null:
			d = {"monster": f.monster, "team": f.team, "cell": _offset(f.cell), "hp": f.hp, "alive": f.alive,
					"summoner": _who(arena, f.summoner)}
		else:
			if f.hp != was.hp:
				d["hp"] = f.hp
			if f.max_hp != was.max_hp:
				d["max_hp"] = f.max_hp
			if f.ap != was.ap:
				d["ap"] = f.ap
			if f.mp != was.mp:
				d["mp"] = f.mp
			if f.cell != was.cell:
				d["cell"] = _offset(f.cell)
			if f.alive != was.alive:
				d["alive"] = f.alive
			if f.shield() != was.shield:
				d["shield"] = f.shield()
			var st := f.state_ids()
			st.sort()
			var st_was := was.states.duplicate()
			st_was.sort()
			if st != st_was:
				d["states"] = st
			if f.carried_by != was.carried_by:
				d["carried_by"] = _who(arena, f.carried_by)
			if f.pass_turn != was.pass_turn:
				d["pass_turn"] = f.pass_turn
			if f.cooldowns != was.cooldowns:
				d["cooldowns"] = f.cooldowns.duplicate()
			var added: Array = []
			for b: Buff in f.buffs:
				if not before_buffs.has(b.id):
					added.append(_buff(arena, b))
			if not added.is_empty():
				d["buffs_added"] = added
			var kept := {}
			for b: Buff in f.buffs:
				kept[b.id] = true
			var removed := 0
			for bid: int in before_buffs:
				if not kept.has(bid) and was.buffs.has(bid):
					removed += 1
			if removed > 0:
				d["buffs_removed"] = removed
		if not d.is_empty():
			fighters[slot] = d
	if not fighters.is_empty():
		out["fighters"] = fighters
	var marks: Array = []
	for m: Dictionary in arena.fight.marks:
		marks.append("%s spell %d at %s, %d cells, %dt by %s" % [m["kind"], int(m["spell"]), _offset(int(m["cell"])),
				(m["cells"] as Array).size(), int(m["turns"]), _who(arena, int(m["caster"]))])
	if not marks.is_empty():
		out["marks"] = marks
	return out


# --- files ----------------------------------------------------------------------------------

## The golden of a class: {spells: {<spells.id>: record}}; empty when the file does not exist.
static func read(breed: int) -> Dictionary:
	var f := FileAccess.open(file_of(breed), FileAccess.READ)
	if f == null:
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	return (data as Dictionary).get("spells", {}) if data is Dictionary else {}


static func write(breed: int, spells: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var f := FileAccess.open(file_of(breed), FileAccess.WRITE)
	f.store_string(JSON.stringify({"_doc": "Golden des sorts de la classe %d (tests/spells/spell_golden.gd) : regenerer avec GOLDEN_UPDATE=1 (docs/COMMANDES.md), relire le diff." % breed,
			"spells": spells}, "\t", true) + "\n")


## Both sides through JSON, so ints and floats compare the way the file does.
static func normalized(v: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(v, "", true))


## Where two grade records differ: ["rank 2 / cast: expected {...}, got {...}"].
static func diff(expected: Dictionary, actual: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	var a: Dictionary = normalized(actual)
	var keys := {}
	for rank: String in (expected.get("grades", {}) as Dictionary):
		keys[rank] = true
	for rank: String in (a["grades"] as Dictionary):
		keys[rank] = true
	var ranks := keys.keys()
	ranks.sort_custom(func(x: String, y: String) -> bool: return int(x) < int(y))
	for rank: String in ranks:
		var eg: Dictionary = (expected.get("grades", {}) as Dictionary).get(rank, {})
		var ag: Dictionary = (a["grades"] as Dictionary).get(rank, {})
		var scenarios := {}
		for k: String in eg:
			scenarios[k] = true
		for k: String in ag:
			scenarios[k] = true
		for sc: String in scenarios:
			var e_s := JSON.stringify(eg.get(sc, "absent"), "", true)
			var a_s := JSON.stringify(ag.get(sc, "absent"), "", true)
			if e_s != a_s:
				out.append("grade %s / %s: golden %s, now %s" % [rank, sc, e_s.left(400), a_s.left(400)])
	return out
