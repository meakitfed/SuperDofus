## Rollbacks and symmetries (roadmap P1.13q): 1100 "Téléporte à la position précédente", 1099 "à la
## position de début de tour", 784 "à la position de début de combat" (their i18n texts; the cell comes
## from the fighter's position history), 1106 "Téléportation symétrique". An occupied arrival cell swaps
## as in P1.13n (hai.bnca), a Xelor's swap is a Telefrag; 1023 swaps without gvr.st.
extends TestCase

const REMBOBINAGE := 1041529 # 1099 on an ally, 2 AP, range 0-4


func _init() -> void:
	SpellBook.use_file("")


class Arena extends SpellArena:
	var ally: Fighter

	func _init() -> void:
		super._init(5, {
			"me": {"at": Vector2i(0, 0), "team": 0, "level": 1, "hp": 100, "ai": false},
			"ally": {"at": Vector2i(2, 0), "team": 0, "level": 1, "hp": 100, "ai": false},
			"foe": {"at": Vector2i(0, 3), "team": 1, "level": 1, "hp": 100}})
		ally = at("ally")

	func go(kind: String, target: Fighter, effect: int, center := -1) -> Array:
		return FightDisplace.teleport(fight, me, target, kind, center if center >= 0 else target.cell, effect)

func test_the_history_is_kept() -> void:
	var a := Arena.new()
	eq([a.ally.start_cell, a.ally.turn_begin_cell, a.ally.prev_cell], [a.xy(2, 0), a.xy(2, 0), -1])
	a.ally.cell = a.xy(3, 0)
	a.ally.cell = a.xy(3, 1)
	eq([a.ally.prev_cell, a.ally.turn_begin_cell, a.ally.start_cell], [a.xy(3, 0), a.xy(2, 0), a.xy(2, 0)])


func test_back_to_the_previous_position() -> void:
	var a := Arena.new()
	eq(a.go("rollback_prev", a.ally, 1100), [], "no move yet: nothing to go back to")
	a.ally.cell = a.xy(3, 0)
	var out := a.go("rollback_prev", a.ally, 1100)
	eq(a.ally.cell, a.xy(2, 0))
	eq([out[0]["target"], out[0]["how"]], [2, "teleport"])


func test_back_to_the_start_of_the_turn_and_of_the_fight() -> void:
	var a := Arena.new()
	a.ally.cell = a.xy(3, 0)
	a.ally.turn_begin_cell = a.xy(3, 0)
	a.ally.cell = a.xy(4, 0)
	a.go("rollback_turn", a.ally, 1099)
	eq(a.ally.cell, a.xy(3, 0), "1099: where its turn began")
	a.go("to_start", a.ally, 784)
	eq(a.ally.cell, a.xy(2, 0), "784: where the fight began")


func test_a_rollback_onto_an_occupied_cell_swaps_and_telefrags() -> void:
	var a := Arena.new()
	a.ally.cell = a.xy(3, 0)
	a.foe.cell = a.xy(2, 0) # took the cell the ally came from
	var out := a.go("rollback_prev", a.ally, 1100)
	eq([a.ally.cell, a.foe.cell], [a.xy(2, 0), a.xy(3, 0)], "swapped")
	eq(out.map(func(e: Dictionary) -> int: return int(e["target"])), [3, 2], "the occupant's move first")
	eq([out[0]["telefrag"], out[1]["telefrag"]], [true, true], "a Xelor's swap")
	a.ally.cell = a.xy(5, 0)
	a.foe.cell = a.xy(6, 0)
	FightBuffs.add_state(a.fight, a.me, a.foe, {"state": 6, "flags": ["cant_be_moved"]}, 1, 0)
	a.ally.prev_cell = a.xy(6, 0)
	eq(a.go("rollback_prev", a.ally, 1100), [], "the occupant is stabilised: nothing moves")


func test_the_symmetry_around_the_impact_point() -> void:
	var a := Arena.new()
	var out := a.go("sym_impact", a.ally, 1106, a.xy(1, 0))
	eq(a.ally.cell, 300, "(2, 0) around (1, 0) = (0, 0): the caster's cell, swapped")
	eq(a.me.cell, a.xy(2, 0))
	eq(out.size(), 2)
	var b := Arena.new()
	b.go("sym_impact", b.ally, 1106, b.xy(3, 0))
	eq(b.ally.cell, b.xy(4, 0))
	eq(b.go("sym_impact", b.ally, 1106, b.ally.cell), [], "on the impact point itself: nothing")


func test_the_forced_exchange_skips_the_checks() -> void:
	var a := Arena.new()
	FightBuffs.add_state(a.fight, a.me, a.ally, {"state": 6, "flags": ["cant_be_moved"]}, 1, 0)
	eq(a.go("swap", a.ally, 8), [], "8: refused")
	var out := a.go("swap", a.ally, 1023)
	eq([a.me.cell, a.ally.cell], [a.xy(2, 0), 300], "1023 CharacterExchangePlacesForce")
	eq(out.size(), 2)


func test_rembobinage_the_whole_spell() -> void:
	var a := Arena.new()
	a.me.ap = 12
	a.me.spells = [REMBOBINAGE]
	a.ally.turn_begin_cell = a.xy(1, 0)
	eq(a.fight.cast(a.me, REMBOBINAGE, a.ally.cell, 0), "")
	eq(a.ally.cell, a.xy(1, 0), "the ally is back where its turn began")
