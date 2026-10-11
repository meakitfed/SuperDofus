## Plays one SpellCases line in a SpellArena: its setup, its steps, its expectations. A case is data:
##   {name, source, breed?: the caster's class, rolls?: "max" (default) | "min" | "random",
##    setup?: {<slot>: {stats, states: [ids], hp, max_hp, level, at: Vector2i (layout offset), spells: [grades]}},
##    steps: [step, ...]}
## Steps (a target `at` is a slot name, "free", a Vector2i offset from the caster's start, or a cell):
##   ["cast", grade, at, {by?: slot, crit?: bool}]   a cast resolved as Fight.cast does once its checks pass
##   ["fight_cast", grade, at, slot?]                a real Fight.cast (AP, range, cooldowns: must succeed)
##   ["turn", slot]          turns end until `slot` starts its own (poisons tick, glyphs hit, delays land)
##   ["walk", slot, at]      `slot` walks there on its turn (traps, portals, auras on the way)
##   ["hit", from, to, amount, element?]  a plain hit of `amount` (before resistances), its triggers fire
##   ["expect", {<slot>: expectation, summons: n, marks: {<kind>: n}}]
## An expectation of a fighter: lost (HP lost since the case began; [lo, hi] for a range), hp, max_hp,
## cell (an `at`), moved (bool), alive, ap, mp, states / no_states: [ids], stat: {<name>: value},
## buff: {<kind>: n} (its buffs of that kind), carried_by: slot, invisible: bool, pass_turn: bool.
class_name SpellCaseRunner
extends RefCounted

var arena: SpellArena
var errors: PackedStringArray = []
var _start := {} # fighter id -> FighterSnapshot when the case began


## The failures of case `c` (empty: it holds).
static func run(c: Dictionary) -> PackedStringArray:
	var r := SpellCaseRunner.new()
	r._play(c)
	return r.errors


func _play(c: Dictionary) -> void:
	arena = SpellArena.new(int(c.get("breed", 0)))
	var rolls := str(c.get("rolls", "max"))
	if rolls != "random":
		arena.me.stats["roll_" + rolls] = 1
	for slot: String in c.get("setup", {}):
		_setup(arena.at(slot), c["setup"][slot])
	_start = arena.snapshot()
	for step: Array in c["steps"]:
		_step(step)


func _setup(f: Fighter, s: Dictionary) -> void:
	for k: String in s.get("stats", {}):
		f.stats[k] = int(s["stats"][k])
	for st: int in s.get("states", []):
		arena.give_state(f, st)
	if s.has("at"):
		f.cell = SpellArena.cell_at(s["at"])
	f.level = int(s.get("level", f.level))
	f.max_hp = int(s.get("max_hp", f.max_hp))
	f.hp = int(s.get("hp", mini(f.hp, f.max_hp)))
	for g: int in s.get("spells", []):
		f.spells.append(g)


func _step(step: Array) -> void:
	match str(step[0]):
		"cast":
			var opts: Dictionary = step[3] if step.size() > 3 else {}
			var by := arena.at(str(opts.get("by", "me")))
			var spell := by.spell(int(step[1])) # with its spell modifiers (Fighter.spell)
			if spell.is_empty():
				errors.append("spell %d unknown" % int(step[1]))
				return
			arena.cast(spell, cell(step[2]), bool(opts.get("crit", false)), by)
		"fight_cast":
			var by := arena.at(str(step[3]) if step.size() > 3 else "me")
			if arena.fight.current() != by:
				arena.play_until(by)
			if not by.spells.has(int(step[1])):
				by.spells.append(int(step[1]))
			var err := arena.fight.cast(by, int(step[1]), cell(step[2]), 0)
			if err != "":
				errors.append("%s cannot cast %d: %s" % [step[3] if step.size() > 3 else "me", step[1], err])
		"turn":
			arena.play_until(arena.at(str(step[1])))
		"walk":
			var f := arena.at(str(step[1]))
			if arena.fight.current() != f:
				arena.play_until(f)
			f.mp = maxi(f.mp, 6)
			var err := arena.fight.move(f, cell(step[2]), 0)
			if err != "":
				errors.append("%s cannot walk to %s: %s" % [step[1], step[2], err])
		"hit":
			var from := arena.at(str(step[1]))
			FightLife.damage(arena.fight, from, arena.at(str(step[2])), str(step[4]) if step.size() > 4 else "neutral", int(step[3]))
			FightTriggers.flush(arena.fight)
			arena.fight.handle_deaths()
		"expect":
			_expect(step[1])
		_:
			errors.append("unknown step %s" % step[0])


## The cell named by `at`.
func cell(at: Variant) -> int:
	if at is Vector2i:
		return SpellArena.cell_at(at)
	if at is int:
		return at
	if str(at) == "free":
		return arena.free_cell()
	return (_start[arena.at(str(at)).id] as FighterSnapshot).cell if not _start.is_empty() else arena.at(str(at)).cell


func _expect(spec: Dictionary) -> void:
	for key: String in spec:
		match key:
			"summons":
				var n := arena.fighters().filter(func(f: Fighter) -> bool: return f.alive and f.summoner == arena.me.id).size()
				_check(n == int(spec[key]), "the caster has %d summons, expected %d" % [n, spec[key]])
			"marks":
				for kind: String in spec[key]:
					var n := arena.fight.marks.filter(func(m: Dictionary) -> bool: return m["kind"] == kind).size()
					_check(n == int(spec[key][kind]), "%d %s marks, expected %d" % [n, kind, spec[key][kind]])
			_:
				_expect_fighter(key, spec[key])


func _expect_fighter(slot: String, want: Dictionary) -> void:
	var f := arena.at(slot)
	var was: FighterSnapshot = _start[f.id]
	for key: String in want:
		var v: Variant = want[key]
		match key:
			"lost":
				var lost := was.hp - f.hp
				var ok := (lost >= int(v[0]) and lost <= int(v[1])) if v is Array else lost == int(v)
				_check(ok, "%s lost %d HP, expected %s" % [slot, lost, v])
			"hp", "max_hp", "ap", "mp", "alive", "pass_turn":
				_check(f.get(key) == v, "%s %s %s, expected %s" % [slot, key, f.get(key), v])
			"cell":
				_check(f.cell == cell(v), "%s on cell %d, expected %d (%s)" % [slot, f.cell, cell(v), v])
			"moved":
				_check((f.cell != was.cell) == bool(v), "%s %s" % [slot, "did not move" if v else "moved"])
			"states":
				for st: int in v:
					_check(f.has_state(st), "%s not in state %d" % [slot, st])
			"no_states":
				for st: int in v:
					_check(not f.has_state(st), "%s still in state %d" % [slot, st])
			"stat":
				for name: String in v:
					_check(f.stat(name) == int(v[name]), "%s %s %d, expected %d" % [slot, name, f.stat(name), v[name]])
			"buff":
				for kind: String in v:
					var n := f.buffs.filter(func(b: Buff) -> bool: return b.kind == kind).size()
					_check(n == int(v[kind]), "%s has %d %s buffs, expected %d" % [slot, n, kind, v[kind]])
			"carried_by":
				_check(f.carried_by == arena.at(str(v)).id, "%s not carried by %s" % [slot, v])
			"invisible":
				_check(f.has_flag("invisible") == bool(v), "%s %s" % [slot, "visible" if v else "invisible"])
			_:
				errors.append("unknown expectation %s" % key)


func _check(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)
