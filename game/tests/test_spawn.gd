## Monster spawns by subarea (roadmap P1.09): groups composed by the sim from
## the subarea's monsters (MonsterSpawner), respawn with a new composition,
## the subarea's stars (SubareaBonus = the fight's rewardRate) and aggressive
## groups (Dofus 2.45 rules).
extends TestCase

const LOOK := "{1|120,2195||56}"


func _init() -> void:
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()
	SpellBook.use_file("res://tests/fixtures/spells.json")


static func _member(level := 3, aggro := {}) -> Dictionary:
	return {"look": "{4907|||130}", "name": "Tofu", "name_id": 5, "level": level, "hp": 20, "ap": 4, "mp": 3,
			"xp": 100, "aggro": aggro}


## A world whose map 1 (subarea 7) is filled by the spawner, map 2 holds one fixed group.
static func _world(fixed_leader := {}, map2 := {}) -> WorldSource:
	var db := {"subareas": {"7": {"level": 3, "area": 0, "monsters": [1]}},
			"monsters": {"1": {"name_id": 5, "grades": [_member(2), _member(3), _member(4)]}}}
	var m2 := {"id": 2, "coords": [1, 0], "groups": [{"name": "Tofus", "members": [fixed_leader if not fixed_leader.is_empty() else _member()]}]}
	m2.merge(map2, true)
	return WorldSource.from_dicts(
		{"id": "arena", "name": "Arena", "start_map": 1, "start_cell": 300, "wander_ms": [600000, 600000]},
		[{"id": 1, "coords": [0, 0], "subarea": 7}, m2], db)


class Client:
	var backend := LocalBackend.new()
	var events: Array = []

	func _init(source: WorldSource, start_map := 1) -> void:
		backend.sources["arena"] = source
		backend.event.connect(func(ev: Dictionary) -> void: events.append(ev))
		backend.send(Protocol.hello("arena", "Tester", LOOK))
		run(0.1)
		if start_map != 1:
			sim().teleport(player(), start_map, 300)
			run(0.1)

	func sim() -> WorldSim:
		return backend.sim

	func player() -> PlayerActor:
		return sim().players[backend.player_id]

	func groups(map_id: int) -> Array:
		return sim().get_map(map_id).actors.values().filter(func(a: SimActor) -> bool: return a is MonsterGroup)

	func run(seconds: float, step := 0.05) -> void:
		for i in int(seconds / step):
			backend.poll(step)

	func take(type: String) -> Array:
		var out := events.filter(func(e: Dictionary) -> bool: return e["t"] == type)
		events = events.filter(func(e: Dictionary) -> bool: return e["t"] != type)
		return out

	## Tool shortcut: the monsters of the running fight die.
	func win() -> void:
		for f: Fight in sim().fights.values():
			for m: Fighter in f.fighters.values():
				if m.team == 1:
					m.alive = false
					m.hp = 0
			f._check_end()
		run(0.2)


func test_incarnam_groups_come_from_their_subarea() -> void:
	var sim := WorldSim.new(JsonWorldSource.for_world("incarnam"))
	var names := {} # subarea -> name ids of its monsters
	for sub: String in sim.spawner.subareas:
		names[int(sub)] = sim.spawner.pool(int(sub)).map(func(id: Variant) -> int: return int(sim.spawner.monsters[str(int(id))]["name_id"]))
	var with_groups := 0
	var without := 0
	for id: Variant in sim.info["maps"]:
		var m := sim.get_map(int(id))
		# the extracted data only: groups mods add (Mods, e.g. Joss) are checked in test_mods.gd
		var mod_spawns := sim.source.get_mod_spawns(int(id))
		var gs: Array = m.actors.values().filter(func(a: SimActor) -> bool: return a is MonsterGroup and not mod_spawns.has((a as MonsterGroup).spawn))
		if not m.data.monster_spawn or (names.get(m.data.subarea, []) as Array).is_empty():
			eq(gs.size(), 0, "no groups on map %d (no respawn capability or no monsters)" % int(id))
			without += 1
			continue
		with_groups += 1
		check(gs.size() >= MonsterSpawner.MIN_GROUPS and gs.size() <= sim.spawner.max_groups, "2 to 3 groups on %d" % int(id))
		for g: MonsterGroup in gs:
			eq(g.subarea, m.data.subarea)
			check(g.members.size() >= 1 and g.members.size() <= MonsterSpawner.MAX_SIZE, "1 to 4 monsters")
			for mem: Dictionary in g.members:
				check(names[m.data.subarea].has(int(mem["name_id"])), "monster %d from subarea %d" % [int(mem["name_id"]), m.data.subarea])
			eq(int(g.members[0]["level"]), g.members.map(func(x: Dictionary) -> int: return int(x["level"])).max(), "the leader is the strongest")
	check(with_groups >= 40, "most Incarnam maps have monsters (%d)" % with_groups)
	check(without >= 5, "zaap maps, the Tavern and its cellar have none (%d)" % without)
	for zaap_map: int in [153880064, 154010371, 153879813, 153357316]:
		eq(sim.get_map(zaap_map).data.monster_spawn, false, "mapsinformation.m_flags bit 13 off on %d" % zaap_map)


func test_a_defeated_group_respawns_with_a_new_composition() -> void:
	var c := Client.new(_world())
	var gs := c.groups(1)
	check(gs.size() >= 2, "the spawner filled map 1")
	var g: MonsterGroup = gs[0]
	eq(int(g.to_dict(0)["members"][0]["xp"]), 100, "the tooltip gets the base XP")
	c.backend.send(Protocol.fight_attack(g.id))
	c.run(0.2)
	c.win()
	eq(c.take(Protocol.FIGHT_END)[0]["result"], "win")
	eq(c.groups(1).size(), gs.size() - 1, "the beaten group is gone")
	c.take(Protocol.ACTOR_ADD)
	c.run(MapInstance.new(MapData.new(), 1).respawn_ms / 1000.0 + 0.5)
	eq(c.groups(1).size(), gs.size(), "it came back")
	var back := c.take(Protocol.ACTOR_ADD).filter(func(e: Dictionary) -> bool: return e["actor"]["kind"] == "monster_group")
	eq(back.size(), 1, "actor_add for the new group")
	for mem: Dictionary in back[0]["actor"]["members"]:
		eq(int(mem["name_id"]), 5, "composed from the subarea again")


func test_stars_grow_cap_drop_and_persist() -> void:
	var store := Persistence.new()
	var s := SubareaBonus.new(store, "w")
	var h := 3_600_000
	eq(s.bonus(7, 0, 0), 0, "never seen: no bonus")
	s.set_bonus(7, 0, 0)
	eq(s.bonus(7, 0, 2 * h), 40, "20 % per hour")
	eq(s.bonus(7, 0, 10 * h), SubareaBonus.MAX, "capped at +100 %")
	s.on_defeat(7, 0, 10 * h)
	eq(s.bonus(7, 0, 10 * h), 80, "a beaten group takes one star")
	s.set_bonus(7, -80, 0)
	eq(s.bonus(7, 0, 0), SubareaBonus.MIN, "down to -50 %")
	s.set_bonus(8, 100, 0)
	eq(s.bonus(8, 45, 0), 0, "Incarnam has no stars")
	eq(s.bonus(8, 18, 0), 0, "Astrub neither")
	eq(SubareaBonus.new(store, "w").bonus(8, 0, 0), 100, "kept in Persistence")


func test_stars_multiply_the_rewards() -> void:
	eq(FightXp.group_xp(100.0, 3, 1, 1, true, 2.0), 2 * FightXp.group_xp(100.0, 3, 1, 1, true, 1.0), "rewardRate (luaformulas 99)")
	var c := Client.new(_world())
	c.sim().stars.set_bonus(7, 100, c.sim().clock.now_unix_ms())
	var g: MonsterGroup = c.groups(1)[0]
	c.backend.send(Protocol.fight_attack(g.id))
	c.run(0.1)
	var fight: Fight = c.sim().fights.values()[0]
	eq(fight.reward_rate, 2.0, "+100 % -> rewardRate 2")
	c.win()
	eq(c.sim().stars.bonus(7, 0, c.sim().clock.now_unix_ms()), 80, "the subarea lost a star")
	eq(FightXp.estimate([{"level": 3, "xp": 100}], 1, 0, 100), 2 * FightXp.estimate([{"level": 3, "xp": 100}], 1, 0, 0),
			"the tooltip estimate follows the stars")


func test_an_aggressive_group_attacks_after_3_seconds() -> void:
	# leader level 3, level_diff -200: aggressive whatever the level (Wabbits)
	var c := Client.new(_world(_member(3, {"zone": 3, "level_diff": -200, "immunity": ""})), 2)
	var g: MonsterGroup = c.groups(2)[0]
	g.cell = 328 # 2 cells from the player (300)
	check(MapGeometry.distance(g.cell, c.player().cell) <= 3)
	c.run(0.5)
	var alert := c.take(Protocol.GROUP_ALERT)
	eq(alert.size(), 1, "the group saw the player")
	eq(int(alert[0]["group"]), g.id)
	eq(int(alert[0]["target"]), c.player().id)
	eq(c.take(Protocol.FIGHT_START).size(), 0, "not yet")
	c.run(3.0)
	eq(c.take(Protocol.FIGHT_START).size(), 1, "attacked after 3 s")
	check(c.player().fight_id != 0)


func test_no_aggression_when_far_strong_immune_or_forbidden() -> void:
	var cases := {
		"far": [{"zone": 3, "level_diff": -200, "immunity": ""}, 3, 20, {}],
		"level gap under 50": [{"zone": 3, "level_diff": 50, "immunity": ""}, 40, 328, {}],
		"immune": [{"zone": 3, "level_diff": -200, "immunity": "PL>0"}, 3, 328, {}],
		"no vision": [{"zone": 0, "level_diff": -200, "immunity": ""}, 3, 328, {}],
		"map forbids it": [{"zone": 3, "level_diff": -200, "immunity": ""}, 3, 328, {"monster_aggression": false}],
	}
	for name: String in cases:
		var k: Array = cases[name]
		var c := Client.new(_world(_member(k[1], k[0]), k[3]), 2)
		c.groups(2)[0].cell = k[2]
		c.run(4.0)
		eq(c.take(Protocol.FIGHT_START).size(), 0, name)
	# the 50-level rule: a level 60 leader attacks a level 1 character
	var c2 := Client.new(_world(_member(60, {"zone": 3, "level_diff": 50, "immunity": ""})), 2)
	c2.groups(2)[0].cell = 328
	c2.run(4.0)
	eq(c2.take(Protocol.FIGHT_START).size(), 1, "level 60 vs level 1: more than 50 levels above")
