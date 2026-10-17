## Smoke test of a whole spell grade (P1.18b): every effect of the grade cast in one go, once as a
## normal hit and once as a critical one, in a fresh SpellArena, then the invariants of a fight
## (the interactions between effects that the isolated contracts of SpellCheck never see).
class_name SpellSmoke
extends RefCounted

const AIM_ORDER := ["foe", "ally_t", "ally", "me", "foe_n", "foe_2", "far"]


## What goes wrong when grade `id` is cast whole, normal then critical (empty: nothing).
static func grade(id: int) -> PackedStringArray:
	var errors: PackedStringArray = []
	for crit: bool in [false, true]:
		var spell := SpellBook.get_spell(id)
		if crit and spell.get("crit_effects", []) == spell.get("effects", []):
			continue
		for msg: String in _cast(spell, crit):
			errors.append("%s%s" % ["crit: " if crit else "", msg])
	return errors


static func _cast(spell: Dictionary, crit: bool) -> PackedStringArray:
	var arena := SpellArena.new(int(spell.get("breed", 0)))
	var out := arena.cast(spell, aim(arena, spell), crit)
	var errors: PackedStringArray = []
	for fx: Variant in out:
		if not (fx is Dictionary) or not (fx as Dictionary).has("kind"):
			errors.append("an effect without a kind: %s" % [fx])
			break
	var seen := {}
	for f: Fighter in arena.fighters():
		var who := arena.slot_of(f)
		if f.hp > f.max_hp:
			errors.append("%s has %d HP over its %d max" % [who, f.hp, f.max_hp])
		if f.hp < 0 or f.ap < 0 or f.mp < 0:
			errors.append("%s has negative HP / AP / MP (%d / %d / %d)" % [who, f.hp, f.ap, f.mp])
		if f.alive and (f.hp <= 0 or f.max_hp <= 0):
			errors.append("%s is alive with %d / %d HP" % [who, f.hp, f.max_hp])
		if not f.alive or f.carried_by != -1:
			continue
		if f.cell < 0 or not arena.fight.map.is_fight_walkable(f.cell):
			errors.append("%s stands on cell %d, outside the board" % [who, f.cell])
		elif seen.has(f.cell):
			errors.append("%s and %s share cell %d" % [who, seen[f.cell], f.cell])
		seen[f.cell] = who
	return errors


static func aim(arena: SpellArena, spell: Dictionary) -> int:
	if int((spell.get("range", [0, 0]) as Array)[1]) == 0:
		return arena.me.cell
	if bool(spell.get("need_free_cell", false)):
		return arena.free_cell()
	return arena.at(AIM_ORDER[0]).cell
