## P2.12a: achievements. The rules (Achievements, AchievementLog, CriteriaEval counters), the flow through a
## LocalBackend (a real fight unlocks one, rewards, points, chained achievements, persistence) and the same
## over WebSockets (NetBackend on 127.0.0.1). The definitions are a small fixture; one test reads the real file.
extends TestCase

const Players := preload("res://tests/test_players.gd")
const NetTests := preload("res://tests/test_net.gd")

const LOOK := "{1|120,2195||56}"
const MONSTER := 55
const POTION := 683
const SWORD := 44


func _init() -> void:
	SpellBook.use_file("res://tests/fixtures/spells.json")


func _row(criteria: String, xp := 0.0, kamas := 0.0, items := [], titles := []) -> Dictionary:
	return {"criteria": criteria, "xp": xp, "kamas": kamas, "scale": 1, "items": items, "emotes": [], "spells": [], "titles": titles}


func _a(id: int, order: int, points: int, criteria: Array, rewards := []) -> Dictionary:
	var objectives := []
	for i in criteria.size():
		objectives.append({"id": id * 10 + i, "name_id": 0, "criterion": criteria[i]})
	return {"id": id, "name_id": 100 + id, "desc_id": 0, "category": 1, "icon": 0, "points": points, "level": 20, "order": order,
			"objectives": objectives, "rewards": rewards}


## 9001 level 5 (kamas, a sword once, a title); 9002 beat monster 55 (XP); 9003 beat it twice AND enter subarea 7;
## 9004 use a potion; 9005 finish quest 7001; 9006 reach 12 points (chains on the others); 9007 own 9002 and 9004.
func _defs() -> Dictionary:
	return {
		"9001": _a(9001, 1, 10, ["PL>4"], [_row("", 0.0, 1.0), _row("Ob!9001", 0.0, 0.0, [[SWORD, 1]], [3])]),
		"9002": _a(9002, 2, 5, ["(EM>%d,0,d)" % MONSTER], [_row("", 1.0)]),
		"9003": _a(9003, 3, 7, ["(EM>%d,1)" % MONSTER, "(ES>7,0)"]),
		"9004": _a(9004, 4, 3, ["EI>%d,0" % POTION]),
		"9005": _a(9005, 5, 2, ["(QF>7001,0)"]),
		"9006": _a(9006, 6, 20, ["(Oa>11)"]),
		"9007": _a(9007, 7, 1, ["(OA=9002)", "(OA=9004)"])}


func _log() -> AchievementLog:
	Achievements.set_defs(_defs())
	return AchievementLog.new()


func _values(level := 1) -> Dictionary:
	return {"level": level}


# -- the rules ----------------------------------------------------------------------------------

func test_counters_move_with_the_events() -> void:
	var log := _log()
	Achievements.count_event(log, {"kind": "fight", "win": false, "monsters": [MONSTER]})
	eq(log.counters.size(), 0, "a lost fight counts for nothing")
	Achievements.count_event(log, {"kind": "fight", "win": true, "monsters": [MONSTER, MONSTER, 9]})
	eq(int(log.counters["EM:55"]), 2)
	eq(int(log.counters["EM:9"]), 1)
	Achievements.count_event(log, {"kind": "map", "map": 1, "subarea": 7})
	Achievements.count_event(log, {"kind": "use", "item": POTION})
	Achievements.count_event(log, {"kind": "quest", "quest": 7001})
	Achievements.count_event(log, {"kind": "talk", "npc": 3})
	eq([int(log.counters["ES:7"]), int(log.counters["EI:683"]), int(log.counters["QF:7001"])], [1, 1, 1])
	Achievements.reset()


func test_the_counter_criteria_read_the_counters() -> void:
	var v := {"counters": {"EM:55": 2}, "achievements": [5, 6], "achievement_points": 40}
	check(CriteriaEval.ok("(EM>55,0,d)", v), "more than 0")
	check(CriteriaEval.ok("(EM>55,1)", v), "more than 1")
	check(not CriteriaEval.ok("(EM>55,2)", v), "not more than 2")
	check(not CriteriaEval.ok("(EM>56,0)", v), "another monster")
	check(CriteriaEval.ok("OA=5", v) and not CriteriaEval.ok("OA=7", v), "achievement obtained")
	check(CriteriaEval.ok("Ob!7", v) and not CriteriaEval.ok("Ob!5", v), "not obtained")
	check(CriteriaEval.ok("(Oa>39)", v) and not CriteriaEval.ok("(Oa>40)", v), "points")
	eq(CriteriaEval.unknown_keys("EM>1,0&ES>2,0&EI>3,0&QF>4,0&OA=5&Ob!6&Oa>7"), PackedStringArray(), "read by the evaluator")


func test_an_achievement_is_obtained_when_all_its_objectives_hold() -> void:
	var log := _log()
	eq(Achievements.check(log, _values(1), 100), [], "nothing yet")
	Achievements.count_event(log, {"kind": "fight", "win": true, "monsters": [MONSTER]})
	eq(Achievements.check(log, _values(1), 100), [9002])
	eq(int(log.done[9002]), 100, "with its day")
	Achievements.count_event(log, {"kind": "fight", "win": true, "monsters": [MONSTER]})
	eq(Achievements.check(log, _values(1), 101), [], "9003 still waits for the subarea")
	Achievements.count_event(log, {"kind": "map", "map": 1, "subarea": 7})
	eq(Achievements.check(log, _values(1), 101), [9003, 9006], "and 5 + 7 points open 9006")
	eq(Achievements.check(log, _values(1), 102), [], "once only")
	Achievements.reset()


func test_points_chain_into_other_achievements() -> void:
	var log := _log()
	Achievements.count_event(log, {"kind": "fight", "win": true, "monsters": [MONSTER]})
	Achievements.count_event(log, {"kind": "use", "item": POTION})
	var got := Achievements.check(log, _values(5), 7)
	eq(got, [9001, 9002, 9004, 9006, 9007], "10 + 5 + 3 = 18 points open 9006 (Oa>11), 9002 + 9004 open 9007")
	eq(Achievements.points(log), 10 + 5 + 3 + 20 + 1)
	Achievements.reset()


func test_rewards_add_up_the_rows_that_hold() -> void:
	var log := _log()
	var r := Achievements.rewards(9001, Achievements.with_state(_values(10), log), 10)
	eq(r["kamas"], 1 * QuestEngine.KAMAS_PER_LEVEL * 10, "kamas ratio x level (the quests' formula)")
	eq(r["items"], [[SWORD, 1]], "the Ob!9001 row holds before it is obtained")
	eq(r["titles"], [3])
	log.done[9001] = 1
	r = Achievements.rewards(9001, Achievements.with_state(_values(10), log), 10)
	eq(r["items"], [], "...and no more once obtained")
	var xp := Achievements.rewards(9002, Achievements.with_state(_values(10), log), 10)
	check(int(xp["xp"]) > 0, "an XP ratio gives XP")
	Achievements.reset()


func test_the_view_lists_done_and_partial_progress() -> void:
	var log := _log()
	Achievements.count_event(log, {"kind": "map", "map": 1, "subarea": 7})
	Achievements.count_event(log, {"kind": "fight", "win": true, "monsters": [MONSTER]})
	log.done[9002] = 4
	var v := Achievements.view(log, _values(1))
	eq(v["done"], [{"id": 9002, "day": 4}])
	var partial: Array = v["progress"].filter(func(e: Dictionary) -> bool: return int(e["id"]) == 9003)
	eq(partial.size(), 1, "9003 has its subarea objective")
	eq(partial[0]["objectives"], [90031], "only the objective that holds")
	eq(v["points"], 5)
	eq(v["total"], 10 + 5 + 7 + 3 + 2 + 20 + 1)
	Achievements.reset()


func test_the_log_is_saved() -> void:
	var log := _log()
	log.done[9002] = 12
	log.bump("EM", MONSTER, 3)
	var back := AchievementLog.from_dict(JSON.parse_string(JSON.stringify(log.to_dict())))
	eq(back.done, {9002: 12})
	eq(back.counters, {"EM:55": 3})
	Achievements.reset()


func test_the_real_definitions_are_readable() -> void:
	Achievements.reset()
	var defs := Achievements.defs()
	if defs.is_empty():
		skip("data/achievements.json absent (gamedata.py achievements)")
		return
	check(defs.size() > 500, "the achievements the sim follows")
	for a: Dictionary in defs.values():
		for o: Dictionary in a["objectives"]:
			eq(CriteriaEval.unknown_keys(str(o["criterion"])), PackedStringArray(), "%s" % o["criterion"])
	Achievements.reset()


# -- through a LocalBackend ---------------------------------------------------------------------

static func _source(on := true) -> WorldSource:
	var mob := {"look": "{4907|||130}", "name": "Bouftou", "name_id": 5, "level": 1, "hp": 20, "ap": 4, "mp": 3, "xp": 10, "monster": MONSTER}
	return WorldSource.from_dicts(
		{"id": "duo", "name": "Duo", "start_map": 1, "start_cell": 300, "wander_ms": [600000, 600000], "achievements": on},
		[{"id": 1, "coords": [0, 0], "neighbors": {}, "groups": [{"name": "Bouftou", "members": [mob]}]}])


func _local(on := true) -> Players.Conn:
	Achievements.set_defs(_defs())
	var s := LocalServer.new()
	s.sources["duo"] = _source(on)
	var c := Players.Conn.new(s, "Eli", LOOK)
	c.run(0.2)
	return c


func test_a_fight_unlocks_an_achievement_and_pays_it() -> void:
	var c := _local()
	var p := c.player()
	var kamas := p.character.kamas
	c.events.clear()
	c.send(Protocol.fight_attack(c.sim().get_map(1).actors.values().filter(func(a: SimActor) -> bool: return a is MonsterGroup)[0].id))
	c.run(0.2)
	var f: Fight = c.sim().fights.values()[0]
	for fighter: Fighter in f.fighters.values():
		if fighter.team == 1:
			fighter.alive = false
			fighter.hp = 0
	f._check_end()
	c.run(0.5)
	var got := c.take(ProtocolAchievement.UNLOCKED)
	eq(got.map(func(e: Dictionary) -> int: return int(e["achievement"])), [9002], "the win unlocks 9002 (the player is level 1)")
	eq(int(got[0]["points"]), 5)
	eq(int(got[0]["total_points"]), 5)
	eq(int(got[0]["name_id"]), 9102)
	check(int(got[0]["rewards"]["xp"]) > 0, "its XP")
	check(p.character.achievements.has(9002))
	eq(LocalBackend.schema_errors.size(), 0, "events match the schema")
	check(p.character.kamas >= kamas)
	Achievements.reset()


func test_level_items_titles_and_the_list() -> void:
	var c := _local()
	var p := c.player()
	p.character.level = 6
	var kamas := p.character.kamas
	c.events.clear()
	c.sim()._quest_event(p, {"kind": "item"})
	c.run(0.1)
	var got := c.take(ProtocolAchievement.UNLOCKED)
	eq(got.map(func(e: Dictionary) -> int: return int(e["achievement"])), [9001])
	check(p.character.titles.has(3), "the title")
	eq(p.character.inventory.count(SWORD), 1, "the sword")
	eq(p.character.kamas - kamas, QuestEngine.KAMAS_PER_LEVEL * 6, "kamas at the player's level (scale 1)")
	c.send(ProtocolAchievement.open())
	c.run(0.1)
	var list := c.take(ProtocolAchievement.LIST)
	eq(list.size(), 1)
	eq(list[0]["done"].map(func(e: Dictionary) -> int: return int(e["id"])), [9001])
	eq(int(list[0]["points"]), 10)
	eq(LocalBackend.schema_errors.size(), 0)
	Achievements.reset()


func test_chained_events_quest_use_and_zone() -> void:
	var c := _local()
	var p := c.player()
	var sim := c.sim()
	sim._quest_event(p, {"kind": "use", "item": POTION})
	sim._quest_event(p, {"kind": "quest", "quest": 7001})
	sim._quest_event(p, {"kind": "map", "map": 1, "subarea": 7})
	sim._quest_event(p, {"kind": "fight", "win": true, "monsters": [MONSTER, MONSTER], "map": 1})
	c.run(0.1)
	var ids := c.take(ProtocolAchievement.UNLOCKED).map(func(e: Dictionary) -> int: return int(e["achievement"]))
	eq(ids, [9004, 9005, 9002, 9003, 9006, 9007], "each as its event arrives, 9006 on the points, 9007 once 9002 and 9004 are both there")
	eq(Achievements.points(p.character.achievements), 3 + 2 + 5 + 7 + 20 + 1)
	Achievements.reset()


func test_progress_is_saved_with_the_character() -> void:
	var c := _local()
	var p := c.player()
	c.sim()._quest_event(p, {"kind": "use", "item": POTION})
	var saved := p.character.to_dict(c.sim().now)
	var back := Character.from_dict(JSON.parse_string(JSON.stringify(saved)), c.sim().now)
	check(back.achievements.has(9004), "obtained")
	eq(int(back.achievements.counters["EI:683"]), 1, "and the counter")
	Achievements.reset()


func test_a_world_without_the_flag_has_no_achievements() -> void:
	var c := _local(false)
	var p := c.player()
	p.character.level = 6
	c.sim()._quest_event(p, {"kind": "use", "item": POTION})
	c.run(0.1)
	eq(c.take(ProtocolAchievement.UNLOCKED).size(), 0)
	eq(p.character.achievements.done.size(), 0)
	Achievements.reset()


# -- the same over WebSockets -----------------------------------------------------------------------

func test_achievements_over_websocket() -> void:
	Achievements.set_defs(_defs())
	var rig := NetTests.Rig.new()
	var a := rig.client("tiny", "Alice")
	rig.run(2.0, func() -> bool: return a.has(Protocol.MAP_ENTER))
	var sim := rig.sim()
	sim.info["achievements"] = true
	var p: PlayerActor = sim.players[a.you]
	sim._quest_event(p, {"kind": "fight", "win": true, "monsters": [MONSTER], "map": 1})
	check(rig.run(2.0, func() -> bool: return a.has(ProtocolAchievement.UNLOCKED)), "the unlock reaches the client")
	var got: Dictionary = a.take(ProtocolAchievement.UNLOCKED)[0]
	eq(int(got["achievement"]), 9002, "ids survive the JSON round trip as ints")
	eq(int(got["total_points"]), 5)
	a.backend.send(ProtocolAchievement.open())
	check(rig.run(2.0, func() -> bool: return a.has(ProtocolAchievement.LIST)), "the list is asked for")
	var list: Dictionary = a.take(ProtocolAchievement.LIST)[0]
	eq(int(list["points"]), 5)
	eq(int(list["done"][0]["id"]), 9002)
	eq(a.backend.schema_errors.size(), 0, "every event matches the schema: %s" % [a.backend.schema_errors])
	# the progress is saved on the server side with the character
	a.backend.close()
	rig.run(0.5, func() -> bool: return sim.players.is_empty())
	var b := rig.client("tiny", "Alice")
	rig.run(2.0, func() -> bool: return b.has(Protocol.MAP_ENTER))
	check((sim.players[b.you] as PlayerActor).character.achievements.has(9002), "obtained still after a new session")
	rig.host.shutdown()
	Achievements.reset()
