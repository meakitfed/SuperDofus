## Monster AI profiles (roadmap P1.16, FightAI.profile): aggressive, cautious, healer, summoner,
## kamikaze, read from the spells; each makes its own choice in a scripted fight.
extends TestCase

const HIT := 9001
const SHOT := 9002
const CURE := 9003
const CALL := 9004
const BOOM := 9005


func _init() -> void:
	SpellBook.use_file("")


static func _spell(effects: Array, range := [1, 1]) -> Dictionary:
	return {"ap": 3, "range": range, "range_boost": false, "los": false, "in_line": false,
			"need_free_cell": false, "need_taken_cell": false, "per_turn": 9, "per_target": 9,
			"cooldown": 0, "initial_cooldown": 0, "crit": 0, "area": {"shape": "point", "size": 0},
			"effects": effects, "crit_effects": []}


static func _dmg() -> Dictionary:
	return {"target": "enemies", "min": 20, "max": 20, "duration": 0, "delay": 0, "mask": "", "kind": "damage", "element": "neutral", "area": {"shape": "point", "size": 0}}


static func _eff(kind: String, who: String) -> Dictionary:
	return {"target": who, "min": 20, "max": 20, "duration": 0, "delay": 0, "mask": "", "kind": kind, "area": {"shape": "point", "size": 0}}


## `mon` (team 1, plays first, AI) and a player `foe` `gap` cells away on the same line.
class Arena:
	var fight: Fight
	var mon := Fighter.new()
	var foe := Fighter.new()
	var ally := Fighter.new()
	var events: Array = []

	func _init(spells: Dictionary, gap: int) -> void:
		fight = Fight.new(1, MapData.new(), 7, func(ev: Dictionary) -> void: events.append(ev))
		_fighter(mon, 1, 1, 300)
		mon.ai = true
		mon.ap = 6
		mon.max_ap = 6
		mon.mp = 4
		mon.max_mp = 4
		mon.stats = {"agility": 1000}
		mon.own_spells = spells
		mon.spells = spells.keys()
		_fighter(foe, 2, 0, at(gap, 0))
		fight.add_fighter(mon)
		fight.add_fighter(foe)
		fight.start_placement(0)
		fight.begin(0)

	func _fighter(f: Fighter, id: int, team: int, cell: int) -> void:
		f.id = id
		f.team = team
		f.cell = cell
		f.level = 10
		f.hp = 100
		f.max_hp = 100
		f.ap = 0
		f.max_ap = 0
		f.mp = 0
		f.max_mp = 0

	func at(dx: int, dy: int) -> int:
		return MapGeometry.from_iso(MapGeometry.to_iso(300) + Vector2i(dx, dy))

	func gap() -> int:
		return FightRules.distance(mon.cell, foe.cell)


func test_the_profile_comes_from_the_spells() -> void:
	var cases := {
		FightAI.AGGRESSIVE: {HIT: _spell([_dmg()])},
		FightAI.CAUTIOUS: {SHOT: _spell([_dmg()], [2, 5])},
		FightAI.HEALER: {HIT: _spell([_dmg()]), CURE: _spell([_eff("heal", "allies")], [1, 4])},
		FightAI.SUMMONER: {HIT: _spell([_dmg()]), CALL: _spell([{"kind": "summon", "target": "all", "monster": 5894, "grade": 1}], [1, 4])},
		FightAI.KAMIKAZE: {BOOM: _spell([_dmg(), _eff("kill", "caster")])},
	}
	for want: String in cases:
		var a := Arena.new(cases[want], 5)
		eq(FightAI.profile(a.mon), want)
	var mixed := Arena.new({HIT: _spell([_dmg()]), SHOT: _spell([_dmg()], [2, 5])}, 5)
	eq(FightAI.profile(mixed.mon), FightAI.AGGRESSIVE, "one melee spell is enough")


func test_aggressive_closes_in() -> void:
	var a := Arena.new({HIT: _spell([_dmg()])}, 6)
	FightAI.act(a.fight, a.mon, 0)
	check(a.gap() < 6, "walked to the enemy")
	eq(a.gap(), 2, "4 MP")


func test_cautious_keeps_its_casting_range() -> void:
	var a := Arena.new({SHOT: _spell([_dmg()], [2, 5])}, 9)
	FightAI.act(a.fight, a.mon, 0)
	check(a.gap() <= 5 and a.gap() >= 4, "moves into range but no closer, gap %d" % a.gap())
	a = Arena.new({SHOT: _spell([_dmg()], [2, 5])}, 3)
	a.mon.ap = 0
	FightAI.act(a.fight, a.mon, 0)
	eq(a.gap(), 5, "backs off to its range")


func test_cautious_flees_when_hurt() -> void:
	var a := Arena.new({SHOT: _spell([_dmg()], [2, 5])}, 3)
	a.mon.hp = 20
	a.mon.ap = 0
	check(FightAI.fleeing(a.mon))
	FightAI.act(a.fight, a.mon, 0)
	eq(a.gap(), 7, "as far as 4 MP take it")
	var b := Arena.new({HIT: _spell([_dmg()])}, 3)
	b.mon.hp = 20
	check(not FightAI.fleeing(b.mon), "aggressive monsters fight to the end")


func test_fleeing_casts_without_walking_first() -> void:
	var a := Arena.new({SHOT: _spell([_dmg()], [2, 5])}, 4)
	a.mon.hp = 20
	FightAI.act(a.fight, a.mon, 0)
	eq(a.foe.hp, 80, "it shoots from where it stands")
	eq(a.gap(), 4)


func test_healer_heals_its_ally_before_hitting() -> void:
	var a := Arena.new({HIT: _spell([_dmg()]), CURE: _spell([_eff("heal", "allies")], [1, 4])}, 1)
	a._fighter(a.ally, 3, 1, a.at(0, 2))
	a.ally.team = 1
	a.ally.cell = a.at(0, 2)
	a.ally.hp = 40
	a.ally.max_hp = 100
	a.fight.add_fighter(a.ally)
	FightAI.act(a.fight, a.mon, 0)
	check(a.ally.hp > 40, "ally healed")
	eq(a.foe.hp, 100, "enemy not hit first")


func test_healer_walks_to_a_hurt_ally() -> void:
	var a := Arena.new({CURE: _spell([_eff("heal", "allies")], [1, 1])}, 8)
	a.mon.ap = 0
	a._fighter(a.ally, 3, 1, a.at(0, 2))
	a.ally.team = 1
	a.ally.cell = a.at(0, 6)
	a.ally.hp = 40
	a.ally.max_hp = 100
	a.fight.add_fighter(a.ally)
	var before := FightRules.distance(a.mon.cell, a.ally.cell)
	FightAI.act(a.fight, a.mon, 0)
	check(FightRules.distance(a.mon.cell, a.ally.cell) < before, "went to the ally")


func test_summoner_calls_before_hitting() -> void:
	var a := Arena.new({HIT: _spell([_dmg()]), CALL: _spell([{"kind": "summon", "target": "all", "monster": 5894, "grade": 1}], [1, 4])}, 1)
	a.mon.ap = 3
	FightAI.act(a.fight, a.mon, 0)
	var calls := a.fight.fighters.values().filter(func(f: Fighter) -> bool: return f.summoner == a.mon.id)
	eq(calls.size(), 1, "summoned")
	eq(a.foe.hp, 100, "did not hit")


func test_kamikaze_rushes() -> void:
	var a := Arena.new({BOOM: _spell([_dmg(), _eff("kill", "caster")])}, 6)
	a.mon.hp = 10
	check(not FightAI.fleeing(a.mon), "never flees")
	FightAI.act(a.fight, a.mon, 0)
	eq(a.gap(), 2)


func test_a_decision_stays_under_the_budget() -> void:
	var spells := {}
	for i in 6:
		spells[HIT + i] = _spell([_dmg(), _eff("heal", "allies")], [1, 6])
	var a := Arena.new(spells, 7)
	a.mon.ap = 12
	var t := Time.get_ticks_usec()
	FightAI.act(a.fight, a.mon, 0)
	var ms := (Time.get_ticks_usec() - t) / 1000.0
	check(ms < 150.0, "decision took %.0f ms" % ms)


# ── an enemy that stops playing (bug: "after two deaths, one enemy stopped playing") ─────────────

func test_a_cornered_runner_fights_back() -> void:
	var a := Arena.new({SHOT: _spell([_dmg()], [2, 5])}, 9)
	a.mon.cell = 0 # a corner: every cell it can reach is nearer to the enemy
	a.foe.cell = a.at(5, 5)
	a.mon.hp = 10
	check(FightAI.fleeing(a.mon))
	var before := a.gap()
	var wait := FightAI.act(a.fight, a.mon, 0)
	check(wait >= 0 and a.gap() < before, "it moves or casts instead of ending its turn doing nothing (gap %d -> %d)" % [before, a.gap()])


func test_a_runner_turns_round_after_a_few_turns() -> void:
	var a := Arena.new({SHOT: _spell([_dmg()], [2, 5])}, 7)
	a.mon.hp = 20
	a.mon.ap = 0
	a.fight._ai_actions = 1
	FightAI.act(a.fight, a.mon, 0)
	check(a.gap() > 7, "it runs at first")
	var b := Arena.new({SHOT: _spell([_dmg()], [2, 5])}, 7)
	b.mon.hp = 20
	b.mon.ap = 0
	b.mon.flee_turns = FightAI.FLEE_MAX_TURNS
	b.fight._ai_actions = 1
	FightAI.act(b.fight, b.mon, 0)
	eq(b.mon.flee_turns, FightAI.FLEE_MAX_TURNS + 1)
	check(b.gap() < 7, "after %d turns of running it closes in again, gap %d" % [FightAI.FLEE_MAX_TURNS, b.gap()])


func test_it_walks_round_an_obstacle() -> void:
	var a := Arena.new({HIT: _spell([_dmg()])}, 8)
	for dy in range(-2, 3): # a wall between the two: no nearer cell, the way round starts sideways
		a.fight.map.fight_blocked[a.at(1, dy)] = true
	var walk_before := int(FightRules.reachable(a.fight.map, {}, a.foe.cell, 99)[a.mon.cell])
	var start := a.mon.cell
	check(FightAI.act(a.fight, a.mon, 0) >= 0, "it moves")
	check(a.mon.cell != start, "it left its cell")
	check(int(FightRules.reachable(a.fight.map, {}, a.foe.cell, 99)[a.mon.cell]) < walk_before, "and it is nearer to the enemy by the road")


func test_a_ranged_monster_without_a_line_of_sight_closes_in() -> void:
	var spell := _spell([_dmg()], [2, 5])
	spell["los"] = true
	var a := Arena.new({SHOT: spell}, 5)
	for dy in range(-7, 8):
		a.fight.map.los_blocked[a.at(1, dy)] = true
	check(FightAI.act(a.fight, a.mon, 0) >= 0)
	check(a.gap() < 5, "it cannot shoot from its range: it walks nearer (gap %d)" % a.gap())
