## Telefrag (roadmap P1.13n): a teleport onto an occupied cell swaps the two fighters (client code
## hai.bnca / dht / hbl / mwk, gvr.st, gvr.bmdf); when a Xelor casts it, both are telefragged
## (gzw isTelefrag, targetMask T).
extends TestCase

const FRAPPE_DE_XELOR := 1041556 # sym_caster (1105), then Téléfrag on "a,A,T"
const TELEFRAG_ENEMY := 251
const TELEFRAG_ALLY := 244


func _init() -> void:
	SpellBook.use_file("")


## me (a Xelor, cell 300), a foe monster on my right, another on my left: the symmetry of each
## other around me.
class Arena:
	var fight: Fight
	var me := Fighter.new()
	var foe := Fighter.new()
	var other := Fighter.new()
	var events: Array = []

	func _init() -> void:
		fight = Fight.new(1, MapData.new(), 7, func(ev: Dictionary) -> void: events.append(ev))
		_fighter(me, 1, 0, 300)
		me.breed = 5
		_fighter(foe, 2, 1, at(1, 0))
		foe.monster = 31
		_fighter(other, 3, 1, at(-1, 0))
		other.monster = 32
		fight.start_placement(0)
		fight.begin(0)

	func _fighter(f: Fighter, id: int, team: int, cell: int) -> void:
		f.id = id
		f.team = team
		f.cell = cell
		f.hp = 100
		f.max_hp = 100
		f.ai = team == 1
		fight.add_fighter(f)

	func at(dx: int, dy: int) -> int:
		return MapGeometry.from_iso(MapGeometry.to_iso(300) + Vector2i(dx, dy))

	## `me` sends `foe` to the other side of itself (sym_caster, effect 1105 unless given)
	func mirror(effect := 1105) -> Array:
		return FightDisplace.teleport(fight, me, foe, "sym_caster", foe.cell, effect)


func test_a_teleport_onto_a_fighter_swaps_them() -> void:
	var a := Arena.new()
	var out := a.mirror()
	eq([a.foe.cell, a.other.cell], [a.at(-1, 0), a.at(1, 0)], "swapped")
	eq(out.map(func(e: Dictionary) -> int: return int(e["target"])), [3, 2], "the occupant's move first (hai.bnca)")
	eq(out[0]["path"], [a.at(-1, 0), a.at(1, 0)], "the occupant goes where the mover was")
	eq([out[0]["how"], out[0]["swapped"], out[0]["telefrag"]], ["swap", 2, true])
	eq([out[1]["swapped"], out[1]["telefrag"]], [3, true], "a Xelor's swap: a Telefrag")
	check(bool(a.fight.cast_log[2].get("telefrag", false)) and bool(a.fight.cast_log[3].get("telefrag", false)))


func test_only_a_xelor_makes_telefrags() -> void:
	var a := Arena.new()
	a.me.breed = 4
	var out := a.mirror()
	eq(a.foe.cell, a.at(-1, 0), "any caster swaps")
	eq([out[0]["telefrag"], out[1]["telefrag"]], [false, false], "gzw isTelefrag: breedId 5 only")
	eq(TargetMask.affects(a.fight, a.me, a.foe, {"mask": "A,T"}), false)
	eq(TargetMask.affects(a.fight, a.me, a.foe, {"mask": "A,W"}), true, "W: moved")


func test_a_stabilised_or_carried_fighter_is_not_swapped() -> void:
	var a := Arena.new()
	FightEffects.add_state(a.fight, a.me, a.other, {"state": 6, "flags": ["cant_be_moved"]}, 1, 0)
	eq(a.mirror(), [], "gvr.bmdf: the occupant is stabilised (cantBeMoved): nothing moves")
	eq([a.foe.cell, a.other.cell], [a.at(1, 0), a.at(-1, 0)])
	var b := Arena.new()
	b.other.carrying = 9
	eq(b.mirror(), [], "gvr.st: the occupant carries someone (state 3)")


func test_a_rooted_fighter_is_only_kept_by_some_effects() -> void:
	var a := Arena.new()
	FightEffects.add_state(a.fight, a.me, a.other, {"state": 6, "flags": ["cant_switch"]}, 1, 0)
	eq(a.mirror(1105), [], "cantSwitchPosition stops 1105 (gzj.bmxr)")
	check(not a.mirror(1101).is_empty(), "not 1101 FightTeleswap")
	eq(a.other.cell, a.at(1, 0))


func test_monsters_that_cannot_switch_places() -> void:
	var a := Arena.new()
	a.other.can_switch = false
	eq(a.mirror(1105), [], "monsters.canSwitchPos off")
	eq(a.foe.cell, a.at(1, 0))
	# 4 CharacterTeleportOnSameMap moves it all the same (gzj.bmww): me onto its cell
	var out := FightDisplace.teleport(a.fight, a.me, a.other, "teleport", a.other.cell, 4)
	eq([a.me.cell, a.other.cell], [a.at(-1, 0), 300], "a forced teleport swaps it")
	eq(out.size(), 2)
	var b := Arena.new()
	b.foe.can_switch_on_target = false
	b.foe.can_switch = true
	check(not b.mirror(1105).is_empty(), "the moved one is not the caster: canSwitchPos")


## The whole spell: Frappe de Xélor on a foe with another fighter on the other side of me swaps
## them, and its Téléfrag sub-spell puts the Telefrag state on both.
func test_frappe_de_xelor_telefrags_both() -> void:
	var a := Arena.new()
	a.me.ap = 12
	a.me.spells = [FRAPPE_DE_XELOR]
	eq(a.fight.cast(a.me, FRAPPE_DE_XELOR, a.foe.cell, 0), "")
	eq([a.foe.cell, a.other.cell], [a.at(-1, 0), a.at(1, 0)])
	check(a.foe.has_state(TELEFRAG_ENEMY) and a.other.has_state(TELEFRAG_ENEMY), "both telefragged")
	var cast: Dictionary = a.events.filter(func(ev: Dictionary) -> bool: return ev["t"] == Protocol.SPELL_CAST)[-1]
	var moves: Array = cast["effects"].filter(func(e: Dictionary) -> bool: return e["kind"] == "move")
	eq(moves.map(func(e: Dictionary) -> bool: return bool(e["telefrag"])), [true, true])
	check(not a.me.has_state(TELEFRAG_ALLY), "the caster did not move")
