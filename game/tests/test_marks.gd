## Traps and glyphs (roadmap P1.13a): the real spells (spells.json) and the
## spells their marks cast: a trap stops a walk and goes off once, glyphs hit
## whoever starts / ends a turn in them, marks count down on their owner's turns
## and go with their owner, Pâturage-like unmark.
extends TestCase

const TRAP := 1040895 # Sram "Piège Sournois" grade 1: trap (cross 1) -> 1040964: fire 10-12 to enemies, pull 1
const PRAIRIE := 1041075 # Eliotrope-like "Prairie" grade 1: start-of-turn glyph (star 2, 2 turns) -> air 20-22
const DEFIANCE := 1041063 # "Défiance" grade 1: end-of-turn glyph (cross 1, 1 turn) -> 4 x 17-18


func _init() -> void:
	SpellBook.use_file("")


## A bare fight on an empty map: `me` (plays first) and `foe` 6 cells away.
class Arena:
	var fight: Fight
	var me := Fighter.new()
	var foe := Fighter.new()
	var events: Array = []

	func _init() -> void:
		fight = Fight.new(1, MapData.new(), 7, func(ev: Dictionary) -> void: events.append(ev))
		me.id = 1
		me.cell = 300
		me.level = 10
		me.hp = 100
		me.max_hp = 100
		me.ap = 12
		me.max_ap = 12
		me.spells = [TRAP, PRAIRIE, DEFIANCE]
		me.stats = {"agility": 1000} # plays first
		foe.id = 2
		foe.team = 1
		foe.cell = at(6, 0)
		foe.hp = 500
		foe.max_hp = 500
		foe.mp = 6
		foe.max_mp = 6
		fight.add_fighter(me)
		fight.add_fighter(foe)
		fight.start_placement(0)
		fight.begin(0)

	func at(dx: int, dy: int) -> int:
		return MapGeometry.from_iso(MapGeometry.to_iso(300) + Vector2i(dx, dy))

	func last(type: String) -> Dictionary:
		for i in range(events.size() - 1, -1, -1):
			if events[i]["t"] == type:
				return events[i]
		return {}

	## ends turns until it is `f`'s
	func turn_of(f: Fighter) -> void:
		fight.end_turn(0)
		while fight.current() != f:
			fight.end_turn(0)


func _kinds(effects: Array) -> Array:
	return effects.map(func(e: Dictionary) -> String: return str(e["kind"]))


func test_the_extracted_marks_name_their_spells() -> void:
	var e: Dictionary = SpellBook.get_spell(TRAP)["effects"][0]
	eq(str(e["kind"]), "trap")
	eq(int(e["spell"]), 1040964, "effect 400: diceNum = spell 12929, diceSide = its grade (1 here)")
	eq(str(e["color"]), "#b9121b", "effect value = the mark colour")
	eq([str(e["mark"]["shape"]), int(e["mark"]["size"])], ["cross", 1])
	check(not (SpellBook.get_spell(TRAP).get("partial", []) as Array).has(400.0), "the trap is simulated (its sub-spells may not be)")
	eq(str(SpellBook.get_spell(int(e["spell"]))["effects"][0]["element"]), "fire")


func test_a_trap_stops_the_walk_and_goes_off_once() -> void:
	var a := Arena.new()
	eq(a.fight.cast(a.me, TRAP, a.at(3, 0), 0), "")
	eq(a.fight.marks.size(), 1)
	var mark: Dictionary = a.last(Protocol.SPELL_CAST)["effects"][0]["mark"]
	check(bool(mark["hidden"]), "a trap is hidden from the other team")
	eq((mark["cells"] as Array).size(), 5)
	a.turn_of(a.foe)
	eq(a.fight.move(a.foe, a.at(1, 0), 0), "")
	var ev := a.last(Protocol.FIGHTER_MOVE)
	eq(int(ev["path"][-1]), a.at(4, 0), "stops on the first trap cell")
	var trig: Array = ev["triggered"]
	eq(_kinds(trig)[0], "mark_remove")
	check(_kinds(trig).has("damage"), "the trap's fire damage")
	eq(a.foe.cell, a.at(3, 0), "pulled 1 cell to the trap's centre")
	eq(a.fight.marks.size(), 0, "gone off: removed")


func test_a_trap_does_not_go_off_for_nobody_else() -> void:
	var a := Arena.new()
	a.fight.cast(a.me, TRAP, a.at(3, 0), 0)
	eq(a.fight.move(a.me, a.at(0, 2), 0), "", "walking elsewhere")
	eq(a.fight.marks.size(), 1)


func test_a_start_of_turn_glyph_hits_who_starts_there() -> void:
	var a := Arena.new()
	a.foe.cell = a.at(1, 0)
	eq(a.fight.cast(a.me, PRAIRIE, a.at(1, 2), 0), "", "star 2 around (1, 2) covers (1, 0)")
	check(a.fight.marks.any(func(m: Dictionary) -> bool: return m["kind"] == "glyph_start"), "glyph laid")
	var hp := a.foe.hp
	a.turn_of(a.foe)
	check(a.foe.hp < hp, "hit at the start of its turn")
	var dmg := _kinds(a.last(Protocol.FIGHT_TURN)["effects"]).filter(func(k: String) -> bool: return k == "damage")
	eq(dmg.size(), 1, "only the fighter starting its turn")


func test_an_end_of_turn_glyph_hits_who_ends_there_then_expires() -> void:
	var a := Arena.new()
	eq(a.fight.cast(a.me, DEFIANCE, a.at(3, 0), 0), "")
	a.turn_of(a.foe)
	a.fight.move(a.foe, a.at(4, 0), 0) # into the cross around (3, 0)
	var hp := a.foe.hp
	a.fight.end_turn(0)
	check(a.foe.hp <= hp - 4 * 17, "4 hits of 17-18 at the end of its turn")
	eq(a.fight.current(), a.me)
	check(not a.fight.marks.any(func(m: Dictionary) -> bool: return m["kind"] == "glyph_end"), "1 turn: gone at my next turn")


func test_marks_go_with_their_owner() -> void:
	var a := Arena.new()
	a.fight.cast(a.me, TRAP, a.at(3, 0), 0)
	FightEffects.hurt(a.me, 1000, "neutral")
	check(_kinds(a.fight.handle_deaths()).has("mark_remove"), "owner dead: its trap is removed")
	eq(a.fight.marks.size(), 0)


func test_unmark_removes_the_owners_marks_of_a_spell() -> void:
	var a := Arena.new()
	a.fight.cast(a.me, TRAP, a.at(3, 0), 0)
	var out := FightMarks.unmark(a.fight, a.me, {"origin": 12906})
	eq(_kinds(out), ["mark_remove"])
	eq(a.fight.marks.size(), 0)


func test_star_zone() -> void:
	var cells := FightRules.zone({"shape": "star", "size": 2}, 300)
	eq(cells.size(), 17, "centre + 4 axes x 2 + 4 diagonals x 2")
