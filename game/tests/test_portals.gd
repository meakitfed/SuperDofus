## Eliotrope portals (roadmap P1.13f): effects 1181 / 1182 / 1183, projected spells (targetMask
## R / r), triggers PT / CPT.
extends TestCase

const PORTAIL := 1044339 # "Portail" grade 1: a portal on a free cell
const TELEPORTAIL := 1044338 # what a fighter entering a portal gets (1181 diceSide)
const EXIL := 1044431 # "Exil" grade 1: a portal under the target, which crosses (1182)
const NEUTRAL := 1044363 # "Neutral" grade 1: disables a portal for 1 turn
const INTERRUPTION := 1044429 # "Interruption" grade 1: disables every portal
const POING := 1044345 # "Poing Fulgurant" grade 1: water damage, pushes 2 (r) or 4 (R)
const STATE_PORTAIL := 3737


func _init() -> void:
	SpellBook.use_file("")


class Arena extends SpellArena:
	func _init(spells: Array, foe_at: Vector2i) -> void:
		super._init(0, {
			"me": {"at": Vector2i(0, 0), "team": 0, "level": 10, "hp": 200, "ap": 12, "mp": 6, "ai": false, "spells": spells, "stats": {"agility": 1000}},
			"foe": {"at": foe_at, "team": 1, "level": 1, "hp": 500, "ap": 0, "mp": 0, "ai": true}})
		give_state(me, STATE_PORTAIL) # the variant Portail (spells.py VARIANT_STATES)

	## A portal of mine on (dx, dy), whatever the cast limits.
	func put(dx: int, dy: int) -> Dictionary:
		FightEffects.apply_spell(fight, me, SpellBook.get_spell(PORTAIL), xy(dx, dy), false)
		return FightMarks.portal_at(fight, xy(dx, dy), me)

	func portals() -> Array:
		return fight.marks.filter(func(m: Dictionary) -> bool: return m["kind"] == "portal")

	func effects(kind: String) -> Array:
		var out: Array = []
		for ev: Dictionary in events:
			for key: String in ["effects", "triggered"]:
				for e: Dictionary in ev.get(key, []):
					if e["kind"] == kind:
						out.append(e)
		return out

	func rounds(n: int) -> void:
		for i in n * 2:
			fight.end_turn(0)

func test_the_extracted_portals() -> void:
	var e: Dictionary = SpellBook.get_spell(PORTAIL)["effects"][0]
	eq([e["kind"], int(e["per_cell"]), int(e["bonus"])], ["portal", 2, 0], "1181: +#3 % and +#1 % per cell")
	eq(SpellBook.get_spell(int(e["spell"]))["name"], "Téléportail")
	eq(SpellBook.get_spell(int(e["spell"]))["effects"][0]["kind"], "teleportal")
	eq((SpellBook.get_spell(PORTAIL).get("start_states", []) as Array).map(func(x: Variant) -> int: return int(x)), [STATE_PORTAIL])
	check(SpellBook.get_spell(INTERRUPTION)["effects"][0]["all"])
	var pushes: Array = SpellBook.get_spell(POING)["effects"].filter(func(x: Dictionary) -> bool: return x["kind"] == "push")
	eq(pushes.map(func(x: Dictionary) -> Array: return [int(x["min"]), x["cond"]]),
			[[2, [{"portal": false}]], [4, [{"portal": true}]]], "targetMask r / R")
	check(not SpellBook.get_spell(EXIL).has("partial"))


func test_the_network_goes_to_the_nearest_portal() -> void:
	var a := Arena.new([], Vector2i(0, -5))
	var p1 := a.put(2, 0)
	check(FightMarks.network(a.fight, p1).is_empty(), "one portal: no network")
	a.put(2, 3)
	a.put(4, 3)
	var chain := FightMarks.network(a.fight, p1)
	eq(chain.map(func(m: Dictionary) -> int: return int(m["cell"])), [a.xy(2, 0), a.xy(2, 3), a.xy(4, 3)])
	eq(FightMarks.chain_bonus(chain), 2 * (3 + 2), "+2 % per cell travelled")


func test_walking_into_a_portal() -> void:
	var a := Arena.new([], Vector2i(0, -5))
	a.put(2, 0)
	a.put(2, 3)
	eq(a.fight.move(a.me, a.xy(4, 0), 0), "")
	eq(a.me.cell, a.xy(2, 3), "the walk stops on the portal and comes out of the other one")
	eq(a.me.mp, 4)
	var moves := a.effects("move")
	eq(moves.size(), 1)
	eq(moves[0]["how"], "portal")
	eq(moves[0]["path"], [a.xy(2, 0), a.xy(2, 3)])


func test_enemies_do_not_walk_through_in_the_first_round() -> void:
	var a := Arena.new([], Vector2i(0, -5))
	a.put(2, 0)
	a.put(2, 3)
	check(FightMarks.crossing(a.fight, a.foe, a.xy(2, 0), true).is_empty())
	check(not FightMarks.crossing(a.fight, a.me, a.xy(2, 0), true).is_empty(), "its owner's team may")
	a.rounds(1)
	eq(a.fight.fight_round, 2)
	check(not FightMarks.crossing(a.fight, a.foe, a.xy(2, 0), true).is_empty())


func test_a_projected_spell() -> void:
	var a := Arena.new([POING], Vector2i(4, 3))
	a.put(2, 0)
	a.put(2, 3)
	a.put(4, 3) # the exit, under the foe
	var hp := a.foe.hp
	eq(a.fight.cast(a.me, POING, a.xy(2, 0), 0), "", "a portal needs no fighter on it")
	var p := a.effects("projected")
	eq(p.size(), 1)
	eq(int(p[0]["bonus"]), 10)
	check(a.foe.hp < hp, "the damage lands on the exit")
	eq(a.foe.cell, a.xy(8, 3), "pushed 4 (R) away from the portal before (2, 3)")


func test_the_portal_bonus() -> void:
	var a := Arena.new([], Vector2i(3, 0))
	var base := int(FightLife.damage(a.fight, a.me, a.foe, "water", 100)[0]["amount"])
	a.me.projecting = 10
	eq(int(FightLife.damage(a.fight, a.me, a.foe, "water", 100)[0]["amount"]), base * 110 / 100)


func test_no_projection_without_a_network() -> void:
	var a := Arena.new([POING], Vector2i(2, 1))
	a.put(2, 0)
	eq(a.fight.cast(a.me, POING, a.xy(2, 0), 0), "")
	eq(a.effects("projected").size(), 0, "one portal: cast on the cell itself")
	check(FightMarks.projection(a.fight, a.me, SpellBook.get_spell(POING), a.me.cell).is_empty(), "never on its own cell")


func test_neutral_disables_a_portal_for_a_turn() -> void:
	var a := Arena.new([NEUTRAL], Vector2i(0, -5))
	var p1 := a.put(2, 0)
	a.put(2, 3)
	eq(a.fight.cast(a.me, NEUTRAL, a.xy(2, 0), 0), "")
	check(not bool(p1["active"]))
	eq(a.effects("portal").size(), 1)
	check(FightMarks.projection(a.fight, a.me, SpellBook.get_spell(POING), a.xy(2, 3)).is_empty(), "one active portal left")
	a.rounds(1)
	check(bool(p1["active"]), "back at the start of my next turn")


func test_interruption_disables_every_portal() -> void:
	var a := Arena.new([INTERRUPTION], Vector2i(0, -5))
	a.put(2, 0)
	a.put(2, 3)
	a.put(5, 3)
	eq(a.fight.cast(a.me, INTERRUPTION, a.me.cell, 0), "")
	check(a.portals().all(func(m: Dictionary) -> bool: return not bool(m["active"])))


func test_exil_sends_its_target_through() -> void:
	var a := Arena.new([EXIL], Vector2i(3, 0))
	a.put(0, 3)
	var from := a.foe.cell
	eq(a.fight.cast(a.me, EXIL, from, 0), "")
	eq(a.portals().size(), 2, "a portal under the target (state Portail)")
	eq(a.foe.cell, a.xy(0, 3), "even an enemy in the first round")


func test_at_most_four_portals() -> void:
	var a := Arena.new([], Vector2i(0, -5))
	var first := a.put(2, 0)
	a.put(3, 0)
	a.put(4, 0)
	a.put(5, 0)
	a.put(6, 0)
	eq(a.portals().size(), FightMarks.MAX_PORTALS)
	check(not a.fight.marks.has(first), "the oldest goes")


func test_crossing_fires_pt() -> void:
	var a := Arena.new([], Vector2i(0, -5))
	a.put(2, 0)
	a.put(2, 3)
	a.me.hp = 100
	FightTriggers.add(a.fight, a.me, a.me, {"kind": "heal_pct", "target": "all", "min": 10, "max": 10, "on": ["PT"], "turns": 2}, PORTAIL, 0)
	a.fight.move(a.me, a.xy(2, 0), 0)
	eq(a.me.cell, a.xy(2, 3))
	eq(a.me.hp, 120, "10 % of its max HP when it crosses")
