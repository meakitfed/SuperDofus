## Invisibility and per-team views of a fight (roadmap P1.13c): effect 150 (state
## 250 "Invisible"), 202 (reveal), FightVisibility.view, the AI's knowledge.
extends TestCase

const INVIS := 1040916 # Sram "Invisibilité" grade 1: invisible 1 turn (+1 MP to an ally)
const PERCEPTION := 1040794 # Eniripsa "Perception" grade 1: reveals the invisibles in a circle 3
const TRAP := 1040895 # Sram "Piège Sournois" grade 1


func _init() -> void:
	SpellBook.use_file("")


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
		me.mp = 6
		me.max_mp = 6
		me.spells = [INVIS, TRAP]
		me.stats = {"agility": 1000} # plays first
		foe.id = 2
		foe.team = 1
		foe.cell = at(3, 0)
		foe.hp = 500
		foe.max_hp = 500
		foe.ap = 6
		foe.max_ap = 6
		foe.mp = 6
		foe.max_mp = 6
		foe.spells = [PERCEPTION]
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


func _kinds(effects: Array) -> Array:
	return effects.map(func(e: Dictionary) -> String: return str(e["kind"]))


func test_the_extracted_invisibility() -> void:
	var e: Dictionary = SpellBook.get_spell(INVIS)["effects"][0]
	eq([str(e["kind"]), int(e["state"])], ["state", 250], "150 -> spellstates 250 \"Invisible\"")
	check((e["flags"] as Array).has("invisible"))
	check(_kinds(SpellBook.get_spell(PERCEPTION)["effects"]).has("reveal"), "202")


func test_the_other_team_does_not_see_an_invisible_walk() -> void:
	var a := Arena.new()
	eq(a.fight.cast(a.me, INVIS, a.me.cell, 0), "")
	check(a.me.has_flag("invisible"))
	eq(a.fight.move(a.me, a.at(0, 2), 0), "")
	var ev := a.last(Protocol.FIGHTER_MOVE)
	eq((FightVisibility.view(ev, a.fight, 0)["path"] as Array).size(), 3, "its team sees the walk")
	eq((FightVisibility.view(ev, a.fight, 1)["path"] as Array).size(), 0, "the other team does not")
	eq((ev["path"] as Array).size(), 3, "the event itself is untouched")
	var begin := {"t": Protocol.FIGHT_BEGIN, "fighters": a.fight.fighters_dicts()}
	var mine: Dictionary = (FightVisibility.view(begin, a.fight, 1)["fighters"] as Array).filter(
			func(f: Dictionary) -> bool: return int(f["id"]) == a.me.id)[0]
	eq(int(mine["cell"]), -1, "nor its cell in a fighter dict")


func test_the_ai_does_not_know_where_an_invisible_is() -> void:
	var a := Arena.new()
	a.fight.cast(a.me, INVIS, a.me.cell, 0)
	eq(FightAI._enemies(a.fight, a.foe).size(), 0)
	var best := FightAI._best_cast(a.fight, a.foe)
	check(best.is_empty() or int(best["cell"]) != a.me.cell, "its cell is not aimed at")


func test_a_spell_reveals_and_everyone_gets_the_cell() -> void:
	var a := Arena.new()
	a.fight.cast(a.me, INVIS, a.me.cell, 0)
	a.fight.end_turn(0)
	eq(a.fight.current(), a.foe)
	eq(a.fight.cast(a.foe, PERCEPTION, a.me.cell, 0), "", "it can still aim at the cell")
	check(not a.me.has_flag("invisible"), "revealed in the circle 3")
	var shown := (a.last(Protocol.SPELL_CAST)["effects"] as Array).filter(func(e: Dictionary) -> bool: return e["kind"] == "reveal")
	eq(shown.size(), 1)
	eq(int(shown[0]["cell"]), a.me.cell)


func test_invisibility_ends_with_a_reveal() -> void:
	var a := Arena.new()
	a.fight.cast(a.me, INVIS, a.me.cell, 0)
	a.fight.end_turn(0)
	a.fight.end_turn(0) # my turn again: 1 turn is over
	check(not a.me.has_flag("invisible"))
	check(_kinds(a.last(Protocol.FIGHT_TURN)["effects"]).has("reveal"))


func test_a_cast_shows_where_from_but_stays_invisible() -> void:
	var a := Arena.new()
	a.fight.cast(a.me, INVIS, a.me.cell, 0)
	a.fight.cast(a.me, TRAP, a.at(0, 3), 0)
	var ev := a.last(Protocol.SPELL_CAST)
	eq(int(FightVisibility.view(ev, a.fight, 1).get("from", -2)), a.me.cell)
	check(not FightVisibility.view(ev, a.fight, 0).has("from"), "its team knows")
	check(a.me.has_flag("invisible"))


func test_traps_are_not_sent_to_the_other_team() -> void:
	var a := Arena.new()
	a.fight.cast(a.me, TRAP, a.at(0, 3), 0)
	var ev := a.last(Protocol.SPELL_CAST)
	eq(_kinds(FightVisibility.view(ev, a.fight, 0)["effects"]), ["mark_add"])
	eq(_kinds(FightVisibility.view(ev, a.fight, 1)["effects"]), [], "the monsters do not get it")

