## Rollbacks and symmetries (roadmap P1.13q): 1100 "Téléporte à la position précédente", 1099 "à la
## position de début de tour", 784 "à la position de début de combat" (their i18n texts; the cell comes
## from the fighter's position history), 1106 "Téléportation symétrique". An occupied arrival cell swaps
## as in P1.13n (hai.bnca), a Xelor's swap is a Telefrag; 1023 swaps without gvr.st.
extends TestCase

const REMBOBINAGE := 1041529 # 1099 on an ally, 2 AP, range 0-4


func _init() -> void:
	SpellBook.use_file("")


class Arena:
	var fight: Fight
	var me := Fighter.new()
	var ally := Fighter.new()
	var foe := Fighter.new()
	var events: Array = []

	func _init() -> void:
		fight = Fight.new(1, MapData.new(), 7, func(ev: Dictionary) -> void: events.append(ev))
		_fighter(me, 1, 0, 300)
		me.breed = 5
		_fighter(ally, 2, 0, at(2, 0))
		_fighter(foe, 3, 1, at(0, 3))
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

	func go(kind: String, target: Fighter, effect: int, center := -1) -> Array:
		return FightDisplace.teleport(fight, me, target, kind, center if center >= 0 else target.cell, effect)


func test_the_history_is_kept() -> void:
	var a := Arena.new()
	eq([a.ally.start_cell, a.ally.turn_begin_cell, a.ally.prev_cell], [a.at(2, 0), a.at(2, 0), -1])
	a.ally.cell = a.at(3, 0)
	a.ally.cell = a.at(3, 1)
	eq([a.ally.prev_cell, a.ally.turn_begin_cell, a.ally.start_cell], [a.at(3, 0), a.at(2, 0), a.at(2, 0)])


func test_back_to_the_previous_position() -> void:
	var a := Arena.new()
	eq(a.go("rollback_prev", a.ally, 1100), [], "no move yet: nothing to go back to")
	a.ally.cell = a.at(3, 0)
	var out := a.go("rollback_prev", a.ally, 1100)
	eq(a.ally.cell, a.at(2, 0))
	eq([out[0]["target"], out[0]["how"]], [2, "teleport"])


func test_back_to_the_start_of_the_turn_and_of_the_fight() -> void:
	var a := Arena.new()
	a.ally.cell = a.at(3, 0)
	a.ally.turn_begin_cell = a.at(3, 0)
	a.ally.cell = a.at(4, 0)
	a.go("rollback_turn", a.ally, 1099)
	eq(a.ally.cell, a.at(3, 0), "1099: where its turn began")
	a.go("to_start", a.ally, 784)
	eq(a.ally.cell, a.at(2, 0), "784: where the fight began")


func test_a_rollback_onto_an_occupied_cell_swaps_and_telefrags() -> void:
	var a := Arena.new()
	a.ally.cell = a.at(3, 0)
	a.foe.cell = a.at(2, 0) # took the cell the ally came from
	var out := a.go("rollback_prev", a.ally, 1100)
	eq([a.ally.cell, a.foe.cell], [a.at(2, 0), a.at(3, 0)], "swapped")
	eq(out.map(func(e: Dictionary) -> int: return int(e["target"])), [3, 2], "the occupant's move first")
	eq([out[0]["telefrag"], out[1]["telefrag"]], [true, true], "a Xelor's swap")
	a.ally.cell = a.at(5, 0)
	a.foe.cell = a.at(6, 0)
	FightEffects.add_state(a.fight, a.me, a.foe, {"state": 6, "flags": ["cant_be_moved"]}, 1, 0)
	a.ally.prev_cell = a.at(6, 0)
	eq(a.go("rollback_prev", a.ally, 1100), [], "the occupant is stabilised: nothing moves")


func test_the_symmetry_around_the_impact_point() -> void:
	var a := Arena.new()
	var out := a.go("sym_impact", a.ally, 1106, a.at(1, 0))
	eq(a.ally.cell, 300, "(2, 0) around (1, 0) = (0, 0): the caster's cell, swapped")
	eq(a.me.cell, a.at(2, 0))
	eq(out.size(), 2)
	var b := Arena.new()
	b.go("sym_impact", b.ally, 1106, b.at(3, 0))
	eq(b.ally.cell, b.at(4, 0))
	eq(b.go("sym_impact", b.ally, 1106, b.ally.cell), [], "on the impact point itself: nothing")


func test_the_forced_exchange_skips_the_checks() -> void:
	var a := Arena.new()
	FightEffects.add_state(a.fight, a.me, a.ally, {"state": 6, "flags": ["cant_be_moved"]}, 1, 0)
	eq(a.go("swap", a.ally, 8), [], "8: refused")
	var out := a.go("swap", a.ally, 1023)
	eq([a.me.cell, a.ally.cell], [a.at(2, 0), 300], "1023 CharacterExchangePlacesForce")
	eq(out.size(), 2)


func test_rembobinage_the_whole_spell() -> void:
	var a := Arena.new()
	a.me.ap = 12
	a.me.spells = [REMBOBINAGE]
	a.ally.turn_begin_cell = a.at(1, 0)
	eq(a.fight.cast(a.me, REMBOBINAGE, a.ally.cell, 0), "")
	eq(a.ally.cell, a.at(1, 0), "the ally is back where its turn began")
