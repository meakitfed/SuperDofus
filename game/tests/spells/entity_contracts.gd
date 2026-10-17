## Contracts of the effects that bring something onto the board, once on the target cell
## (FightEffects._apply_spell routes them before targeting): summons, marks, portals; and of the
## effects that only act on such things or on a context (sub-spells, runes, bombs...), which a
## lone effect cannot show: SpellCases plays them.
class_name EntityContracts
extends RefCounted


static func register(table: Dictionary) -> void:
	table["summon"] = Summon.new()
	table["double"] = Summon.new()
	table["illusion"] = Illusion.new()
	table["replace"] = Replace.new()
	for kind: String in FightMarks.KINDS:
		table[kind] = Mark.new()
	table["portal"] = Mark.new()
	table["unmark"] = Unmark.new()
	table["cast"] = SubSpell.new()
	for kind: String in ["unportal", "teleportal", "glyph_trigger", "runes", "detonate"]:
		table[kind] = Contextual.new()


## The new fighter on the target cell: the caster's summon, of the effect's monster.
class Summon extends EffectContract:
	func aim() -> Aim:
		return Aim.FREE

	func strict(_p: EffectProbe) -> bool:
		return false # its start spell (hooks) may touch the others

	func check_cast(p: EffectProbe) -> void:
		var f := p.arena.fight.fighter_at(p.center)
		if f == null or p.before.has(f.id):
			p.fail("no %s on the target cell %d" % [p.kind(), p.center])
			return
		p.expect(f.summoner == p.me().id and f.team == p.me().team, f, "summoned by %d, team %d" % [f.summoner, f.team])
		if p.kind() != "double":
			p.expect(f.monster == int(p.effect["monster"]), f, "monster %d, expected %d" % [f.monster, p.effect["monster"]])


## The caster's summon (of monster `replaces`) on the target cell dies, the new one takes its place.
class Replace extends Summon:
	func prepare(p: EffectProbe) -> void:
		var old := int(p.effect.get("replaces", p.effect["monster"]))
		Summons.apply(p.arena.fight, p.me(), {"kind": "summon", "monster": old, "grade": 1}, p.arena.free_cell())
		p.data["old"] = p.arena.fight.fighter_at(p.arena.free_cell())
		if p.data["old"] == null:
			p.fail("monster %d (replaced) cannot be summoned" % old)

	func check_cast(p: EffectProbe) -> void:
		var old: Fighter = p.data.get("old")
		if old == null:
			return
		p.expect(not old.alive, old, "the replaced summon still lives")
		super.check_cast(p)


## trap / glyphs / aura / rune / portal: a mark of the caster on the target cell, of its spell.
class Mark extends EffectContract:
	func aim() -> Aim:
		return Aim.CELL

	func strict(_p: EffectProbe) -> bool:
		return false # an aura / an instant glyph applies its spell at once

	func check_cast(p: EffectProbe) -> void: # laid (an instant glyph's own spell may take it away at once)
		var want := p.kind()
		var laid := p.outputs(p.me(), "mark_add").filter(func(d: Dictionary) -> bool:
			return d["mark"]["kind"] == want and int(d["mark"]["cell"]) == p.center)
		p.expect(laid.size() == 1, p.me(), "expected a %s laid on cell %d, got %d" % [want, p.center, laid.size()])


## 2018: the caster's marks of spell `origin` go (one is laid beforehand).
class Unmark extends EffectContract:
	func aim() -> Aim:
		return Aim.FREE

	func prepare(p: EffectProbe) -> void:
		var origin := int(p.effect.get("origin", 0))
		FightMarks.add(p.arena.fight, p.me(), {"kind": "glyph_start", "spell": 1, "origin": origin,
				"mark": {"shape": "point", "size": 0}}, p.arena.free_cell())

	func check_cast(p: EffectProbe) -> void:
		var origin := int(p.effect.get("origin", 0))
		var left := p.arena.fight.marks.filter(func(m: Dictionary) -> bool: return int(m["origin"]) == origin)
		p.expect(left.is_empty(), p.me(), "kept %d marks of spell %d" % [left.size(), origin])


## 792 / 1160...: the sub-spell is cast; its own effects are checked as a grade of their own.
class SubSpell extends EffectContract:
	func strict(_p: EffectProbe) -> bool:
		return false


## Effects acting on a context a lone effect does not have (portals, runes, bombs, glyphs): they
## must at least leave everyone alone.
class Contextual extends EffectContract:
	pass


## 1097: `count` illusions of the caster (its look, 1 HP, no turn, no slot) beside it.
class Illusion extends Summon:
	func check_cast(p: EffectProbe) -> void:
		var made := p.newcomers()
		var want := int(p.effect.get("count", 1))
		p.expect(made.size() == want, p.me(), "expected %d illusions, got %d" % [want, made.size()])
		for f: Fighter in made:
			p.expect(f.summoner == p.me().id and f.team == p.me().team, f, "summoned by %d, team %d" % [f.summoner, f.team])
			p.expect(f.looks == p.me().looks and f.hp == 1 and not f.plays and not f.summon_slot, f, "not an illusion of the caster")
