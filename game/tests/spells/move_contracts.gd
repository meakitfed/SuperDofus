## Contracts of the displacements: pushes and pulls (the target, along the axis from the area's
## centre), recoils and advances (the caster), teleports, swaps and symmetries, rollbacks,
## carry and throw.
class_name MoveContracts
extends RefCounted

## where every fighter "was" before (rollbacks): its layout cell shifted this far, free cells
const HISTORY_SHIFT := Vector2i(0, 6)


static func register(table: Dictionary) -> void:
	table["push"] = Push.new()
	table["pull"] = Push.new()
	table["recoil"] = Recoil.new()
	table["advance"] = Recoil.new()
	table["teleport"] = Teleport.new()
	table["swap"] = Swap.new()
	table["sym_target"] = Mirror.new()
	table["sym_caster"] = Mirror.new()
	table["sym_impact"] = Mirror.new()
	table["rollback_prev"] = Rollback.new()
	table["rollback_turn"] = Rollback.new()
	table["to_start"] = Rollback.new()
	table["carry"] = CarryTarget.new()
	table["throw"] = Throw.new()


## `cell` + `n` steps of `dir`, -1 off the map.
static func walk(cell: int, dir: Vector2i, n: int) -> int:
	return MapGeometry.from_iso(MapGeometry.to_iso(cell) + dir * n)


## The cell `cell` mirrored around `pivot`.
static func mirror(cell: int, pivot: int) -> int:
	return MapGeometry.from_iso(MapGeometry.to_iso(pivot) * 2 - MapGeometry.to_iso(cell))


## `f` went from `from` along `dir` and stopped at most `n` cells further, either after `n` or
## in front of a fighter / the map's edge; returns how many cells (-1: not on that line).
static func moved_along(p: EffectProbe, f: Fighter, from: int, dir: Vector2i, n: int) -> int:
	for k in n + 1:
		if walk(from, dir, k) == f.cell:
			if k < n:
				var nx := walk(from, dir, k + 1)
				p.expect(nx < 0 or p.arena.fight.fighter_at(nx) != null or not p.arena.fight.map.is_fight_walkable(nx), f,
						"stopped after %d of %d cells with the way free" % [k, n])
			return k
	p.fail("%s: moved off its line: %d -> %d (%s x %d)" % [p.arena.slot_of(f), from, f.cell, dir, n])
	return -1


## push: away from the area's centre (from the caster when it stands on it); pull: towards it, at
## most up to it. A push stopped early hurts (when its effect says so), a pull never does.
class Push extends EffectContract:
	func check(p: EffectProbe, t: Fighter) -> void:
		var from := p.was(t).cell
		var ref := p.center if from != p.center else p.was(p.me()).cell
		if t == p.me() and from == p.center:
			return # pushing oneself from one's own cell: no direction
		var dir := FightRules.direction(ref, from) if p.kind() == "push" else FightRules.direction(from, ref)
		var n := int(p.effect.get("min", 1))
		if p.kind() == "pull": # up to the cell it is pulled to, not past it
			n = mini(n, FightDisplace.along(from, ref, dir))
		var k := MoveContracts.moved_along(p, t, from, dir, n)
		if k < 0:
			return
		var hurt := p.kind() == "push" and k < n and bool(p.effect.get("damage", true))
		p.expect((p.hp_lost(t) > 0) == hurt, t, "%s of %d stopped after %d: %d HP lost" % [p.kind(), n, k, p.hp_lost(t)])


## recoil: the caster moves away from its target (the centre when it targets itself); advance:
## towards it.
class Recoil extends EffectContract:
	func prepare(p: EffectProbe) -> void:
		p.may_change[p.me().id] = true

	func check_cast(p: EffectProbe) -> void:
		if p.oracle.fighters.is_empty():
			return
		var t: Fighter = p.oracle.fighters[0]
		var me := p.me()
		var ref := p.was(t).cell if t != me else p.center
		var from := p.was(me).cell
		if ref == from:
			return
		var dir := FightRules.direction(ref, from) if p.kind() == "recoil" else FightRules.direction(from, ref)
		MoveContracts.moved_along(p, me, from, dir, int(p.effect.get("min", 1)) * p.oracle.fighters.size())

	func check(p: EffectProbe, t: Fighter) -> void:
		if t != p.me():
			p.expect(t.cell == p.was(t).cell, t, "moved by the caster's own move")


## 4: the caster goes to the target cell (empty), whatever its mask names (FightEffects.CELL_KINDS).
class Teleport extends EffectContract:
	func aim() -> Aim:
		return Aim.FREE

	func prepare(p: EffectProbe) -> void:
		p.may_change[p.me().id] = true

	func check_cast(p: EffectProbe) -> void:
		p.expect(p.me().cell == p.center, p.me(), "teleported to %d, expected the target cell %d" % [p.me().cell, p.center])


## 8 / 1023: the caster and its target exchange their cells (with several targets, one after the
## other: the caster ends on one of their cells, nobody else moves).
class Swap extends EffectContract:
	func prepare(p: EffectProbe) -> void:
		p.may_change[p.me().id] = true

	func check(p: EffectProbe, t: Fighter) -> void:
		if t == p.me() or p.oracle.fighters.size() > 1:
			return
		p.expect(t.cell == p.was(p.me()).cell and p.me().cell == p.was(t).cell, t,
				"not swapped with the caster (%d / %d)" % [t.cell, p.me().cell])

	func check_cast(p: EffectProbe) -> void:
		var others := p.oracle.fighters.filter(func(f: Fighter) -> bool: return f != p.me())
		if others.size() < 2:
			return
		var cells := others.map(func(f: Fighter) -> int: return p.was(f).cell)
		p.expect(cells.has(p.me().cell), p.me(), "ended on %d, not on one of its targets' cells" % p.me().cell)


## sym_target (1104): the caster jumps to the other side of its target; sym_caster (1105): the
## target to the other side of the caster; sym_impact (1106): the target to the other side of the
## cast cell. Onto an occupied cell, the two swap (FightDisplace._swap), once: the other one is not
## mirrored back (FightDisplace.SYMMETRIES).
class Mirror extends EffectContract:
	func prepare(p: EffectProbe) -> void:
		p.may_change[p.me().id] = true
		for f: Fighter in p.arena.fighters():
			p.may_change[f.id] = true # an occupant of the arrival cell swaps

	func check(p: EffectProbe, t: Fighter) -> void:
		var me := p.me()
		var mover := t
		var to := -1
		match p.kind():
			"sym_target":
				mover = me
				to = MoveContracts.mirror(p.was(me).cell, p.was(t).cell if t != me else p.center)
			"sym_caster":
				to = MoveContracts.mirror(p.was(t).cell, p.was(me).cell)
			"sym_impact":
				to = MoveContracts.mirror(p.was(t).cell, p.center)
		if (p.kind() == "sym_caster" and t == me) or to < 0 or to == p.was(mover).cell:
			return # FightDisplace: no symmetry of the caster around itself, nor off the map
		p.expect(mover.cell == to, mover, "%s went to %d, expected %d" % [p.kind(), mover.cell, to])


## 1100 / 1099 / 784: the target goes back to its previous cell / where its turn began / where the
## fight began (each fighter gets a free cell for all three beforehand).
class Rollback extends EffectContract:
	func prepare(p: EffectProbe) -> void:
		for slot: String in SpellArena.LAYOUT:
			var f := p.arena.at(slot)
			var back := SpellArena.cell_at(SpellArena.LAYOUT[slot]["at"] + MoveContracts.HISTORY_SHIFT)
			f.prev_cell = back
			f.turn_begin_cell = back
			f.start_cell = back

	func check(p: EffectProbe, t: Fighter) -> void:
		var back := SpellArena.cell_at(SpellArena.LAYOUT[p.arena.slot_of(t)]["at"] + MoveContracts.HISTORY_SHIFT)
		if back >= 0:
			p.expect(t.cell == back, t, "%s went to %d, expected %d" % [p.kind(), t.cell, back])


## 50: the fighter next to the caster goes onto its cell, carried (Carry).
class CarryTarget extends EffectContract:
	func aim() -> Aim:
		return Aim.ADJACENT

	func prepare(p: EffectProbe) -> void:
		p.may_change[p.me().id] = true
		p.may_change[p.arena.at("ally").id] = true

	func check_cast(p: EffectProbe) -> void:
		var ally := p.arena.at("ally")
		p.expect(ally.carried_by == p.me().id and p.me().carrying == ally.id, ally, "not carried by the caster")


## 51: the carried fighter lands on the target cell.
class Throw extends EffectContract:
	func aim() -> Aim:
		return Aim.FREE

	func prepare(p: EffectProbe) -> void:
		var ally := p.arena.at("ally")
		Carry.apply(p.arena.fight, p.me(), {}, ally.cell, 0)
		p.may_change[p.me().id] = true
		p.may_change[ally.id] = true

	func check_cast(p: EffectProbe) -> void:
		var ally := p.arena.at("ally")
		p.expect(ally.cell == p.center and ally.carried_by == -1 and p.me().carrying == -1, ally,
				"thrown to %d (carried by %d), expected %d" % [ally.cell, ally.carried_by, p.center])
