## Displacements of the fights (split from FightEffects, R.01): push / pull / recoil /
## advance, teleports and swaps (Telefrag), and who can be swapped.
class_name FightDisplace
extends RefCounted


## push / pull move the target, recoil / advance move the caster (away from /
## towards the target). A push stopped by an obstacle or a fighter hurts.
static func push(fight: Fight, caster: Fighter, t: Fighter, e: Dictionary, center: int) -> Array:
	var kind := str(e.get("kind", "push"))
	var from := FightEffects.origin(fight, caster)
	var ref := t.cell if t != caster else center
	var mover := t
	var dir := Vector2i.ZERO
	match kind:
		"push":
			dir = FightRules.direction(center if t.cell != center else from, t.cell)
		"pull": # towards the area's centre ("attire vers son centre": traps, Pandikulation),
			# towards the caster for a pull on its target
			dir = FightRules.direction(t.cell, center if t.cell != center else from)
		"recoil":
			mover = caster
			dir = FightRules.direction(ref, caster.cell)
		"advance":
			mover = caster
			dir = FightRules.direction(caster.cell, ref)
	if dir == Vector2i.ZERO or mover.has_flag("cant_be_moved") or (mover == t and mover.has_flag("cant_be_pushed")) 			or mover.carried_by != -1:
		return []
	var path: Array = [mover.cell]
	var cur := mover.cell
	var left := int(e.get("min", 1))
	var blocked := false
	while left > 0:
		var nx := FightRules.step(cur, dir)
		if nx < 0 or not fight.map.is_fight_walkable(nx) or fight.fighter_at(nx) != null:
			blocked = true
			break
		cur = nx
		path.append(cur)
		left -= 1
		if not FightMarks.trap_at(fight, mover, cur).is_empty(): # stops on a trap
			left = 0
	var out: Array = []
	if path.size() > 1:
		mover.cell = cur
		Carry.follow(fight, mover)
		fight.log_cast(mover, "moved")
		out.append({"kind": "move", "target": mover.id, "path": path, "how": kind})
		# P1.13i, gzp.bmzy: M moved, P pushed (push, recoil) / MA attracted (pull, advance)
		FightTriggers.event(fight, mover, ["M", "P" if kind in ["push", "recoil"] else "MA"], caster.id)
		FightTriggers.event(fight, caster, ["PO"], mover.id) # P1.13m, gzp.bnaa: its author moved someone
	if blocked and left > 0 and kind == "push" and bool(e.get("damage", true)):
		var dmg := maxi(0, (caster.level / 2 + 32 + caster.stat("push_damage") - mover.stat("push_res")) * left / 4)
		FightTriggers.hit(fight, caster, mover, "push", dmg)
		out.append(FightEffects.hurt(mover, dmg, "push"))
	if path.size() > 1:
		out.append_array(FightMarks.entered(fight, mover))
	return out


## effects ids of the move kinds (spells.py MOVES), for spells extracted before P1.13n kept them
const MOVE_EFFECT := {"teleport": 4, "swap": 8, "sym_target": 1104, "sym_caster": 1105, "sym_impact": 1106,
		"rollback_prev": 1100, "rollback_turn": 1099, "to_start": 784}
## client code gzj.bmxr: the effects a cantSwitchPosition state stops (8 CharacterExchangePlaces,
## 784 CharacterTeleportToFightStartPos, 1099 / 1100 FightRollback*, 1104-1106 FightTeleswapMirror*)
const SWITCH_EFFECTS := [8, 784, 1099, 1100, 1104, 1105, 1106]
## client code gzj.bmww: the effects that move a monster whose canSwitchPos is off all the same
## (4 CharacterTeleportOnSameMap, 1023 CharacterExchangePlacesForce)
const FORCE_EFFECTS := [4, 1023]
## breeds.id of the Xelor: its swaps are Telefrags (client code hai.bnca: gzw isTelefrag = breedId 5)
const TELEFRAG_BREED := 5


static func teleport(fight: Fight, caster: Fighter, t: Fighter, kind: String, center: int, effect: int) -> Array:
	var mover := caster
	var to := -1
	match kind:
		"teleport":
			to = center
		"swap": # client code hai.bnca (gzj.bmwu: 8 / 1023): the caster goes to the target's cell
			if t == caster:
				return []
			to = t.cell
		"sym_target": # the caster jumps to the other side of the target
			var pivot := MapGeometry.to_iso(t.cell if t != caster else center)
			to = MapGeometry.from_iso(pivot * 2 - MapGeometry.to_iso(caster.cell))
		"sym_caster": # the target jumps to the other side of the caster
			if t == caster:
				return []
			mover = t
			to = MapGeometry.from_iso(MapGeometry.to_iso(caster.cell) * 2 - MapGeometry.to_iso(t.cell))
		"sym_impact": # P1.13q, 1106 "Téléportation symétrique": the target jumps to the other side of the
			# impact point. APPROX(P1.13q): the client's symmetry point is not read, the cast cell is taken
			mover = t
			to = MapGeometry.from_iso(MapGeometry.to_iso(center) * 2 - MapGeometry.to_iso(t.cell))
		"rollback_prev": # P1.13q, 1100 "Téléporte à la position précédente" (history hai.bnbz)
			mover = t
			to = t.prev_cell
		"rollback_turn": # 1099 "Téléporte à la position de début de tour"
			mover = t
			to = t.turn_begin_cell
		"to_start": # 784 "Téléporte à la position de début de combat"
			mover = t
			to = t.start_cell
	if to < 0 or to == mover.cell or not fight.map.is_fight_walkable(to) or mover.carried_by != -1:
		return []
	var other := fight.fighter_at(to)
	if other != null:
		return _swap(fight, caster, mover, other, effect)
	if mover.has_flag("cant_be_moved"):
		return []
	var from := mover.cell
	mover.cell = to
	Carry.follow(fight, mover)
	fight.log_cast(mover, "moved")
	FightTriggers.event(fight, mover, ["M"], caster.id)
	FightTriggers.event(fight, caster, ["PO"], mover.id) # P1.13m, gzp.bnaa
	var out: Array = [{"kind": "move", "target": mover.id, "path": [from, to], "how": "teleport"}]
	out.append_array(FightMarks.entered(fight, mover))
	return out


## Client code hai.bnca / dht / hbl / mwk: `mover` teleported onto `other`'s cell. They swap when
## gvr.st allows it both ways (other then mover, 1023 CharacterExchangePlacesForce skips it).
static func _swap(fight: Fight, caster: Fighter, mover: Fighter, other: Fighter, effect: int) -> Array:
	if effect != 1023 and not (can_swap(other, mover, effect, false) and can_swap(mover, other, effect, mover == caster)):
		return []
	var a := mover.cell
	mover.cell = other.cell
	other.cell = a
	Carry.follow(fight, mover)
	Carry.follow(fight, other)
	var telefrag := caster.monster == 0 and caster.breed == TELEFRAG_BREED
	for f in [other, mover]:
		fight.log_cast(f, "moved")
		if telefrag:
			fight.log_cast(f, "telefrag")
		# P1.13m, gzp.bmzy: MS both were swapped (their move outputs have swappedEntityId); PO its author
		FightTriggers.event(fight, f, ["M", "MS"], caster.id)
	for f in [other, mover]:
		if f != caster:
			FightTriggers.event(fight, caster, ["PO"], f.id)
	# the occupant's move first (hai.bnca adds its gzw before the mover's)
	var out: Array = [{"kind": "move", "target": other.id, "path": [mover.cell, a], "how": "swap",
			"swapped": mover.id, "telefrag": telefrag},
			{"kind": "move", "target": mover.id, "path": [a, mover.cell], "how": "swap",
			"swapped": other.id, "telefrag": telefrag}]
	out.append_array(FightMarks.entered(fight, other))
	out.append_array(FightMarks.entered(fight, mover))
	return out


## Client code gvr.st then gvr.bmdf: can `who` be swapped with `with` by `effect`? Not when either
## carries (state 3 "Porteur") or `who` is carried (state 8 "Porte"); not when `who` is stabilised
## (spellstates.cantBeMoved = state property 3); not by the SWITCH_EFFECTS when it is rooted
## (cantSwitchPosition = property 18); a monster needs monsters.canSwitchPos (canSwitchPosOnTarget
## when it is the caster), except for the FORCE_EFFECTS.
static func can_swap(who: Fighter, with: Fighter, effect: int, who_is_caster: bool) -> bool:
	if who.carrying != -1 or with.carrying != -1 or who.carried_by != -1:
		return false
	if who.has_flag("cant_be_moved") or (who.has_flag("cant_switch") and SWITCH_EFFECTS.has(effect)):
		return false
	if who.monster != 0 and not (who.can_switch_on_target if who_is_caster else who.can_switch):
		return FORCE_EFFECTS.has(effect)
	return true
