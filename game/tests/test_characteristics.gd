## Characteristics (roadmap P1.04): capital cost by tier (breeds.statsPointsFor*),
## boost with a capital amount, reset, derived characteristics shared by the
## character sheet and the fighter (StatFormulas). Real data, through LocalBackend.
extends TestCase


func _init() -> void:
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()


static func _server() -> LocalServer:
	var s := LocalServer.new()
	s.sources["stats"] = WorldSource.from_dicts(
		{"id": "stats", "name": "Stats", "start_map": 1, "start_cell": 300},
		[{"id": 1, "coords": [0, 0], "neighbors": {}}])
	return s


## Plays a character whose save got `extra` (level, capital, stats…).
static func _play(server: LocalServer, extra: Dictionary) -> Array:
	var b := LocalBackend.new()
	b.server = server
	var events: Array = []
	b.event.connect(func(ev: Dictionary) -> void: events.append(ev))
	b.send(Protocol.hello("stats"))
	b.send(Protocol.create_character("Bob"))
	b.poll(0.0)
	var saved := server.persistence.load_character("stats", "Bob")
	saved.merge(extra, true)
	server.persistence.save_character("stats", "Bob", saved)
	events.clear()
	b.send(Protocol.select_character("Bob"))
	b.poll(0.0)
	return [b, events]


static func _stats(events: Array) -> Dictionary:
	var st := events.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.PLAYER_STATS)
	return st[-1]["stats"] if not st.is_empty() else {}


func test_capital_cost_by_tier() -> void:
	# breeds.statsPointsForStrength (every class): 1 per point to 99, then 2 / 3 / 4
	eq(StatFormulas.point_cost(12, "strength", 0), 1)
	eq(StatFormulas.point_cost(12, "strength", 99), 1)
	eq(StatFormulas.point_cost(12, "strength", 100), 2)
	eq(StatFormulas.point_cost(12, "agility", 250), 3)
	eq(StatFormulas.point_cost(8, "chance", 300), 4)
	eq(StatFormulas.point_cost(12, "vitality", 500), 1, "statsPointsForVitality")
	eq(StatFormulas.point_cost(12, "wisdom", 0), 3, "statsPointsForWisdom")
	eq(StatFormulas.boost(12, "strength", 98, 10), [6, 10], "2 points at 1, then 4 at 2")
	eq(StatFormulas.boost(12, "strength", 98, 9), [5, 8], "the rest is kept")
	eq(StatFormulas.capital_for(12, "strength", 104), 100 + 2 * 4, "0..99 at 1, 100..103 at 2")


func test_boost_and_reset() -> void:
	var r := _play(_server(), {"level": 21, "capital": 100})
	var b: LocalBackend = r[0]
	var events: Array = r[1]
	b.send(Protocol.boost_stat("strength", 10))
	b.send(Protocol.boost_stat("wisdom"))
	b.send(Protocol.boost_stat("vitality", 50))
	b.poll(0.0)
	var st := _stats(events)
	eq([int(st["stats"]["strength"]), int(st["stats"]["wisdom"]), int(st["stats"]["vitality"])], [10, 1, 50])
	eq(int(st["capital"]), 100 - 10 - 3 - 50)
	eq(int(st["max_hp"]), 50 + 5 * 21 + 50)
	events.clear()
	b.send(Protocol.boost_stat("wisdom", 2)) # 37 capital left but only 2 offered
	b.send(Protocol.boost_stat("luck"))
	b.poll(0.0)
	eq(events.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.ERROR).map(func(e: Dictionary) -> String: return e["code"]),
			[Protocol.E_NOT_ENOUGH_CAPITAL, Protocol.E_UNKNOWN_STAT])
	b.send(Protocol.reset_stats())
	b.poll(0.0)
	st = _stats(events)
	eq(int(st["capital"]), 100, "every capital point back")
	eq(int(st["stats"]["strength"]) + int(st["stats"]["wisdom"]) + int(st["stats"]["vitality"]), 0)
	check(int(st["hp"]) <= int(st["max_hp"]))


func test_derived_stats_are_the_same_in_and_out_of_fight() -> void:
	var c := Character.new()
	c.level = 50
	c.stats = {"vitality": 100, "wisdom": 45, "strength": 120, "intelligence": 3, "chance": 57, "agility": 88}
	var now := 0
	var d := c.derived_stats(now)
	eq(int(d["tackle"]), 8, "agility / 10")
	eq(int(d["ap_dodge"]), 4, "wisdom / 10")
	eq(int(d["prospecting"]), 105, "100 + chance / 10")
	eq(int(d["pods"]), 1000 + 5 * 120)
	eq(int(d["initiative"]), 100 + 120 + 3 + 57 + 88)
	var f := Fighter.new() # as WorldSim builds a player fighter
	f.stats = c.fight_stats()
	f.max_hp = c.max_hp()
	f.hp = c.hp_at(now)
	eq(f.initiative(), int(d["initiative"]))
	eq(f.tackle(), int(d["tackle"]))
	eq(f.escape(), int(d["escape"]))
	eq(FightRewards.prospecting(f), int(d["prospecting"]))
	f.hp = f.max_hp / 2
	eq(f.initiative(), int(d["initiative"]) / 2, "weighted by the HP left")


func test_hp_ap_mp_and_pods_formula() -> void:
	eq(StatFormulas.max_hp(1, 0), 55)
	eq(StatFormulas.max_hp(200, 1000), 2050)
	eq([StatFormulas.max_ap(99), StatFormulas.max_ap(100), StatFormulas.max_mp(200)], [6, 7, 3])
	# luaformulas 46: 12 pods per job level, one less every 200 levels
	eq(StatFormulas.job_pods(200), 2400)
	eq(StatFormulas.job_pods(201), 2411)
