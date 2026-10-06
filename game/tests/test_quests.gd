## P2.03: quests (QuestEngine, QuestLog): offers, objective runs, hand-in, kills, rewards, the real Incarnam data.
extends TestCase

const LOOK := "{1|120,2195||56}"
const BREAD := 468 # 2 pods, not usable... (a resource for the tests)
const POTION := 683 # usable consumable
const SWORD := 44

## Hand-made quests (QuestEngine format). 7001: talk to B and C, back to A (steps 1), then bring 2 bread to B.
## 7002 (after 7001): win against monster 55 twice, reach map 2, use a potion. 7003: talk, win, talk, back (the order matters).
static func _quests() -> Dictionary:
	return {
		7001: {"id": 7001, "name_id": 1, "criteria": "BT=1", "start": {"npc": 9001, "map": 1}, "steps": [
			{"id": 1, "name_id": 0, "desc_id": 0, "level": 5, "objectives": [
				{"id": 11, "type": 1, "map": 1, "params": [9002], "args": []},
				{"id": 12, "type": 1, "map": 1, "params": [9003], "args": []},
				{"id": 13, "type": 9, "map": 1, "params": [9001], "args": []}],
				"rewards": [{"level_min": -1, "level_max": -1, "xp": 1.0, "kamas": 2.0, "scale": 0, "items": [[POTION, 2]],
					"emotes": [7], "spells": [], "titles": []}]},
			{"id": 2, "name_id": 0, "desc_id": 0, "level": 5, "objectives": [
				{"id": 21, "type": 3, "map": 1, "params": [9002, BREAD, 2], "args": []}],
				"rewards": [{"level_min": -1, "level_max": -1, "xp": 0.0, "kamas": 0.0, "scale": 0, "items": [[SWORD, 1]],
					"emotes": [], "spells": [], "titles": []}]}]},
		7002: {"id": 7002, "name_id": 2, "criteria": "Qf=7001", "start": {"npc": 9001, "map": 1}, "steps": [
			{"id": 3, "name_id": 0, "desc_id": 0, "level": 5, "objectives": [
				{"id": 31, "type": 14, "map": 0, "params": [55, 2], "args": []},
				{"id": 32, "type": 14, "map": 0, "params": [56, 1], "args": []}],
				"rewards": [{"level_min": 10, "level_max": -1, "xp": 9.0, "kamas": 9.0, "scale": 0, "items": [], "emotes": [], "spells": [], "titles": []},
					{"level_min": -1, "level_max": 9, "xp": 1.0, "kamas": 1.0, "scale": 0, "items": [], "emotes": [], "spells": [], "titles": []}]},
			{"id": 4, "name_id": 0, "desc_id": 0, "level": 5, "objectives": [
				{"id": 41, "type": 0, "map": 2, "params": [1], "args": []},
				{"id": 42, "type": 8, "map": 0, "params": [POTION], "args": []}],
				"rewards": [{"level_min": -1, "level_max": -1, "xp": 0.0, "kamas": 5.0, "scale": 1, "items": [], "emotes": [], "spells": [], "titles": []}]}]},
		7003: {"id": 7003, "name_id": 3, "criteria": "", "start": {"npc": 9001, "map": 1}, "steps": [
			{"id": 5, "name_id": 0, "desc_id": 0, "level": 1, "objectives": [
				{"id": 51, "type": 1, "map": 1, "params": [9002], "args": []},
				{"id": 52, "type": 6, "map": 0, "params": [55, 2], "args": []},
				{"id": 53, "type": 1, "map": 1, "params": [9002], "args": []},
				{"id": 54, "type": 17, "map": 0, "params": [BREAD, 1], "args": []}],
				"rewards": []}]},
		# P2.04: 7004 repeatable at once, 7005 daily, 7006 once (repeat -1), all offered by 9003, "talk to 9002"
		7004: _repeating(7004, 1, 41),
		7005: _repeating(7005, 2, 42),
		7006: _repeating(7006, -1, 43)}


static func _repeating(id: int, repeat: int, obj: int) -> Dictionary:
	return {"id": id, "name_id": id, "criteria": "", "repeat": repeat, "start": {"npc": 9003, "map": 1}, "steps": [
		{"id": id, "name_id": 0, "desc_id": 0, "level": 1, "objectives": [{"id": obj * 100, "type": 1, "map": 1, "params": [9002], "args": []}],
			"rewards": []}]}


class Conn:
	var backend := LocalBackend.new()
	var events: Array = []
	var entered: Array = [] # the events of the connection
	var npcs := {} # npcs.id -> actor id

	func _init(server: LocalServer, world := "quests") -> void:
		backend.server = server
		backend.event.connect(func(ev: Dictionary) -> void:
			events.append(ev)
			if ev["t"] == Protocol.MAP_ENTER:
				npcs.clear()
				for a: Dictionary in ev["actors"]:
					if a["kind"] == "npc":
						npcs[int(a["npc"])] = int(a["id"]))
		backend.send(Protocol.hello(world, "Eli", LOOK))
		backend.poll(0.0)
		entered = events.duplicate()

	func send(cmd: Dictionary) -> Array:
		events = []
		backend.send(cmd)
		backend.poll(0.0)
		return events

	func of(type: String) -> Array:
		return events.filter(func(e: Dictionary) -> bool: return e["t"] == type)

	func last(type: String) -> Dictionary:
		var l := of(type)
		return l.back() if not l.is_empty() else {}

	func player() -> PlayerActor:
		return backend.sim.players[backend.player_id]

	func character() -> Character:
		return player().character

	## Talks to an NPC of the map (stands beside it first).
	func talk(npc: int) -> Array:
		var map := backend.sim.get_map(player().map_id)
		var cell := (map.actors[npcs[npc]] as SimActor).cell
		for c: int in MapGeometry.neighbors(cell):
			if map.data.is_walkable(c):
				send(Protocol.move(c, false))
				break
		return send(Protocol.npc_talk(npcs[npc]))

	## Talks to the NPC and takes the quest it offers.
	func accept(npc: int, quest: int) -> Array:
		talk(npc)
		return send(Protocol.dialog_reply(QuestEngine.REPLY_BASE + quest))

	func event(ev: Dictionary) -> Array:
		events = []
		backend.sim._quest_event(player(), ev)
		backend.poll(0.0)
		return events


static func _conn(level := 1) -> Conn:
	var s := LocalServer.new()
	var src := WorldSource.from_dicts({"id": "quests", "name": "Quests", "start_map": 1, "start_cell": 301},
		[{"id": 1, "coords": [0, 0], "neighbors": {}}, {"id": 2, "coords": [1, 0], "neighbors": {}}])
	src.set_npcs({1: [{"npc": 9001, "cell": 300, "dir": 3, "look": "{714}", "name_id": 8306},
			{"npc": 9002, "cell": 330, "dir": 1, "look": "{714}", "name_id": 8306},
			{"npc": 9003, "cell": 360, "dir": 1, "look": "{714}", "name_id": 8306}]},
			{9001: {"start": "a", "nodes": {"a": {"text": "Bonjour", "replies": []}}}, 9002: {"start": "a", "nodes": {"a": {"text": "Salut", "replies": []}}},
			9003: {"start": "a", "nodes": {"a": {"text": "Yo", "replies": []}}}})
	src.set_quests(_quests())
	s.sources["quests"] = src
	var c := Conn.new(s)
	c.character().level = level
	return c


func test_the_offer_depends_on_the_criteria() -> void:
	var log := QuestLog.new()
	var values := {"quests_finished": [], "quests_active": []}
	eq(QuestEngine.offers(_quests(), log, 9001, values), [7001, 7003], "BT=1 and an empty criteria, Qf=7001 not yet")
	eq(QuestEngine.offers(_quests(), log, 9002, values), [], "another NPC")
	eq(QuestEngine.offers(_quests(), log, 9003, values), [7004, 7005, 7006], "the repeatable ones are offered the first time")
	values["quests_finished"] = [7001]
	log.finished = [7001]
	eq(QuestEngine.offers(_quests(), log, 9001, values), [7002, 7003], "finished: no longer offered, the next one is")
	log.begin(7002)
	values["quests_active"] = [7002]
	eq(QuestEngine.offers(_quests(), log, 9001, values), [7003], "under way: not offered twice")


func test_criteria_quest_keys() -> void:
	var v := {"quests_finished": [5], "quests_active": [6]}
	check(CriteriaEval.ok("BT=1", v))
	check(not CriteriaEval.ok("BT=2", v))
	check(CriteriaEval.ok("Qf=5", v))
	check(not CriteriaEval.ok("Qf=6", v))
	check(CriteriaEval.ok("Qa=6&Qf=5", v))
	check(CriteriaEval.ok("Qf!7", v))
	check(not CriteriaEval.ok("Qa!6", v))
	eq(CriteriaEval.unknown_keys("BT=1&Qf=3&Qa=2"), PackedStringArray(), "read by the evaluator")


func test_the_objectives_of_a_run_come_in_any_order_then_the_next_run() -> void:
	var c := _conn()
	var ev := c.accept(9001, 7001)
	var start := c.last(Protocol.QUEST_START)
	check(not start.is_empty(), "quest_start")
	var objs: Array = start["quest"]["objectives"]
	eq(objs.size(), 3)
	check(not objs[0]["locked"] and not objs[1]["locked"] and objs[2]["locked"], "the return waits for the visits")
	check(c.of(Protocol.DIALOG_END).size() == 1, "the dialog ends after accepting (%s)" % str(ev.size()))
	c.talk(9001) # not asked yet (the return is locked)
	eq(c.last(Protocol.QUEST_UPDATE), {}, "talking to the starter does nothing yet")
	c.talk(9003)
	var up := c.last(Protocol.QUEST_UPDATE)
	check(bool(up["quest"]["objectives"][1]["done"]) and not bool(up["quest"]["objectives"][0]["done"]), "C first")
	c.talk(9002)
	up = c.last(Protocol.QUEST_UPDATE)
	check(not bool(up["quest"]["objectives"][2]["locked"]), "the return is open once the visits are done")
	c.send(Protocol.dialog_close())
	var kamas := c.character().kamas
	var xp := c.character().xp
	c.talk(9001)
	up = c.last(Protocol.QUEST_UPDATE)
	check(not up.is_empty() and int(up["quest"]["step"]) == 1, "second step")
	check(up.has("rewards") and int(up["rewards"]["kamas"]) > 0, "the first step gave its rewards")
	eq(c.character().kamas, kamas + int(up["rewards"]["kamas"]))
	eq(c.character().xp, xp + int(up["rewards"]["xp"]))
	eq(c.character().inventory.bag_count(POTION), 2)
	eq(c.character().emotes, [7], "the emote is kept")


func test_handing_in_takes_the_items() -> void:
	var c := _conn()
	c.accept(9001, 7001)
	c.talk(9002)
	c.talk(9003)
	c.talk(9001)
	check(c.character().quests.is_active(7001))
	eq(c.character().quests.step_of(7001), 1)
	c.talk(9002)
	eq(c.character().quests.step_of(7001), 1, "no bread, no hand-in")
	c.backend.sim.give_item(c.player(), BREAD, 1)
	c.talk(9002)
	eq(c.character().quests.step_of(7001), 1, "one bread is not enough")
	c.backend.sim.give_item(c.player(), BREAD, 1)
	c.talk(9002)
	var done := c.last(Protocol.QUEST_COMPLETE)
	check(not done.is_empty(), "quest_complete")
	eq(int(done["quest"]), 7001)
	eq(c.character().inventory.bag_count(BREAD), 0, "the bread is taken")
	eq(c.character().inventory.bag_count(SWORD), 1, "the last reward")
	check(c.character().quests.is_finished(7001))
	check(not c.character().quests.is_active(7001))
	# the follow-up quest is now offered
	var ev := c.talk(9001)
	var d := c.last(Protocol.DIALOG)
	var offered: Array = (d["replies"] as Array).map(func(r: Dictionary) -> int: return int(r.get("quest", 0)))
	check(offered.has(7002) and offered.has(7003) and not offered.has(7001), "offers after the first quest: %s (%d events)" % [str(offered), ev.size()])


func test_the_order_of_runs_matters() -> void:
	var c := _conn()
	c.accept(9001, 7003)
	c.talk(9002)
	var up := c.last(Protocol.QUEST_UPDATE)
	check(bool(up["quest"]["objectives"][0]["done"]) and not bool(up["quest"]["objectives"][2]["done"]), "only the first talk counts")
	c.talk(9002)
	eq(c.last(Protocol.QUEST_UPDATE), {}, "the second talk waits for the fight")
	c.event({"kind": "fight", "win": true, "monsters": [55, 55], "map": 1})
	up = c.last(Protocol.QUEST_UPDATE)
	check(bool(up["quest"]["objectives"][1]["done"]), "the fight")
	c.talk(9002)
	up = c.last(Protocol.QUEST_UPDATE)
	check(bool(up["quest"]["objectives"][2]["done"]), "the second talk")
	check(c.character().quests.is_active(7003), "the craft is left (bread)")
	c.events = []
	c.backend.sim.give_item(c.player(), BREAD, 1)
	c.backend.poll(0.0)
	check(not c.last(Protocol.QUEST_COMPLETE).is_empty(), "owning the item finishes the quest (APPROX crafting)")


func test_a_single_fight_needs_all_the_kills() -> void:
	var c := _conn()
	c.accept(9001, 7003)
	c.talk(9002)
	c.event({"kind": "fight", "win": true, "monsters": [55], "map": 1})
	c.talk(9002)
	check(not bool(c.character().quests.count(7003, 52) >= 2), "one monster is not enough in one fight")
	c.event({"kind": "fight", "win": false, "monsters": [55, 55], "map": 1})
	eq(c.character().quests.count(7003, 52), 0, "a lost fight counts for nothing")
	c.event({"kind": "fight", "win": true, "monsters": [55, 55, 3], "map": 1})
	eq(c.character().quests.count(7003, 52), 2)


func test_kills_add_up_over_fights_and_the_reward_follows_the_level() -> void:
	var c := _conn(12)
	c.character().quests.finished = [7001]
	c.accept(9001, 7002)
	c.event({"kind": "fight", "win": true, "monsters": [55], "map": 1})
	var up := c.last(Protocol.QUEST_UPDATE)
	eq(int(up["quest"]["objectives"][0]["count"]), 1, "1 / 2")
	c.event({"kind": "fight", "win": true, "monsters": [55, 56], "map": 1})
	up = c.last(Protocol.QUEST_UPDATE)
	eq(int(up["quest"]["step"]), 1, "both kills are done: next step")
	var r: Dictionary = up["rewards"]
	check(int(r["xp"]) > 0 and int(r["kamas"]) > 0, "the level 10+ row (xp 9.0) applies at level 12")
	check(int(r["kamas"]) == floori(9.0 * QuestEngine.KAMAS_PER_LEVEL * 5), "kamas = ratio x level of the step x KAMAS_PER_LEVEL")
	# a low level gets the other row
	var low := QuestEngine.rewards({"rows": _quests()[7002]["steps"][0]["rewards"], "level": 5}, 3)
	eq(int(low["kamas"]), 1 * QuestEngine.KAMAS_PER_LEVEL * 5)


func test_map_and_item_use_objectives() -> void:
	var c := _conn(3)
	c.character().quests.finished = [7001]
	c.accept(9001, 7002)
	c.event({"kind": "fight", "win": true, "monsters": [55, 55, 56], "map": 1})
	eq(c.character().quests.step_of(7002), 1)
	c.backend.sim.give_item(c.player(), POTION, 1)
	var uid: int = c.character().inventory.to_array()[0]["uid"]
	c.send(Protocol.use_item(uid))
	eq(c.character().quests.count(7002, 42), 0, "the potion comes after the map (runs in order)")
	c.backend.sim.give_item(c.player(), POTION, 1)
	uid = c.character().inventory.to_array()[0]["uid"]
	c.backend.sim.teleport(c.player(), 2, 300)
	c.backend.poll(0.0)
	eq(c.character().quests.count(7002, 41), 1, "arriving on map 2")
	check(c.character().quests.is_active(7002))
	c.send(Protocol.use_item(uid))
	check(c.character().quests.is_finished(7002), "using the potion finished the quest")


func test_the_quests_are_saved_with_the_character() -> void:
	var c := _conn()
	c.accept(9001, 7001)
	c.talk(9002)
	var saved := c.character().to_dict(0)
	var json: Variant = JSON.parse_string(JSON.stringify(saved))
	var back := Character.from_dict(json, 0)
	eq(back.quests.active.keys(), [7001])
	eq(back.quests.count(7001, 11), 1, "progress survives JSON")
	eq(back.quests.step_of(7001), 0)
	back.quests.finished = [3, 4]
	eq(Character.from_dict(JSON.parse_string(JSON.stringify(back.to_dict(0))), 0).quests.finished, [3, 4])


func test_the_quest_list_is_sent_on_connection() -> void:
	var c := _conn()
	var first: Array = c.entered.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.QUEST_LIST)
	eq(first.size(), 1, "one quest_list at the connection")
	eq((first[0]["active"] as Array).size(), 0)
	c.accept(9001, 7001)
	var ev := {"t": Protocol.QUEST_LIST, "active": c.backend.sim._quest_views(c.player()), "finished": [1]}
	eq(Protocol.validate(ev, Protocol.S2C), "")
	eq((ev["active"] as Array).size(), 1)
	eq(int(ev["active"][0]["id"]), 7001)


func test_no_quest_of_another_npc_is_offered_nor_started_by_a_forged_reply() -> void:
	var c := _conn()
	c.talk(9002)
	var d := c.last(Protocol.DIALOG)
	eq((d["replies"] as Array).size(), 0, "9002 offers nothing")
	c.send(Protocol.dialog_reply(QuestEngine.REPLY_BASE + 7001))
	check(not c.character().quests.is_active(7001), "the reply was not offered")


func test_a_won_fight_counts_for_the_kill_objectives() -> void:
	var fixtures := load("res://tests/test_fight.gd")
	SpellBook.use_file("res://tests/fixtures/spells.json")
	var src: WorldSource = fixtures._world(5, {"monster": 55})
	src.set_quests({7004: {"id": 7004, "name_id": 4, "criteria": "", "start": {"npc": 9001, "map": 1}, "steps": [
		{"id": 6, "name_id": 0, "desc_id": 0, "level": 1, "objectives": [
			{"id": 61, "type": 6, "map": 0, "params": [55, 2], "args": []}],
			"rewards": [{"level_min": -1, "level_max": -1, "xp": 0.0, "kamas": 1.0, "scale": 0, "items": [], "emotes": [], "spells": [], "titles": []}]}]}})
	var c = fixtures.Client.new(src)
	c.character().quests.begin(7004)
	c.start_fight()
	var me: Fighter = c.me()
	var mons: Array = c.monsters()
	var around := FightRules.neighbors4(me.cell).filter(func(x: int) -> bool: return c.fight().map.is_fight_walkable(x))
	for i in mons.size():
		mons[i].cell = around[i]
	c.send(Protocol.fight_cast(1, mons[0].cell))
	c.send(Protocol.fight_cast(1, mons[1].cell))
	c.run(0.1)
	check(c.character().quests.is_finished(7004), "two monsters 55 beaten in one fight finish the single-fight objective")
	check(not c.take(Protocol.QUEST_COMPLETE).is_empty(), "quest_complete after the fight")


# ── the real Incarnam data ─────────────────────────────────────────────────────

func test_incarnam_quests_are_loaded_and_their_npcs_stand_on_the_maps() -> void:
	var src := JsonWorldSource.for_world("incarnam")
	var quests := src.get_quests()
	check(quests.size() >= 15, "the Incarnam quests (%d)" % quests.size())
	for id: int in quests:
		var q: Dictionary = quests[id]
		var found := false
		for n: Dictionary in src.get_npcs(int(q["start"]["map"])):
			if int(n["npc"]) == int(q["start"]["npc"]):
				found = true
		check(found, "the starter of quest %d stands on its map" % id)
		for st: Dictionary in q["steps"]:
			for o: Dictionary in st["objectives"]:
				if int(o["type"]) in [1, 3, 9]:
					var there := false
					for n: Dictionary in src.get_npcs(int(o["map"])):
						if int(n["npc"]) == int(o["params"][0]):
							there = true
					check(there, "NPC %d of quest %d stands on map %d" % [int(o["params"][0]), id, int(o["map"])])


func test_the_dofus_world_has_its_quests_too() -> void:
	var src := JsonWorldSource.for_world("dofus")
	var quests := src.get_quests()
	check(quests.size() > 500, "quests of the whole world (%d)" % quests.size())
	var missing := 0
	for id: int in quests:
		var found := false
		for n: Dictionary in src.get_npcs(int(quests[id]["start"]["map"])):
			if int(n["npc"]) == int(quests[id]["start"]["npc"]):
				found = true
		if not found:
			missing += 1
	eq(missing, 0, "every starter stands on its map")


func test_an_incarnam_quest_from_start_to_finish() -> void:
	# 1639 "Transport peu commun" (level 3): talk to 2882, examine the zaap of the Pâturages (a map), go back to 2905
	var s := LocalServer.new()
	var c := Conn.new(s, "incarnam")
	var sim := c.backend.sim
	var map_a := 154010371
	var map_b := 153879813
	sim.teleport(c.player(), map_a, sim.get_map(map_a).data.nearest_walkable(300))
	c.backend.poll(0.0)
	check(c.npcs.has(2905), "the quest NPC stands there")
	c.accept(2905, 1639)
	check(not c.last(Protocol.QUEST_START).is_empty(), "quest 1639 begins")
	eq(c.character().quests.step_of(1639), 0)
	sim.teleport(c.player(), map_b, sim.get_map(map_b).data.nearest_walkable(300))
	c.backend.poll(0.0)
	eq(c.character().quests.count(1639, 9815), 0, "the map comes after the talk (runs in order)")
	c.talk(2882)
	check(c.character().quests.count(1639, 9814) == 1, "talked to 2882")
	check(c.character().quests.count(1639, 9815) == 1, "already on the map when the run opened")
	sim.teleport(c.player(), map_a, sim.get_map(map_a).data.nearest_walkable(300))
	c.backend.poll(0.0)
	var level := c.character().level
	c.talk(2905)
	var done := c.last(Protocol.QUEST_COMPLETE)
	check(not done.is_empty(), "quest_complete")
	check(c.character().quests.is_finished(1639))
	check(c.character().inventory.bag_count(16513) == 5, "5 x item 16513 as the table says")
	check(c.character().kamas > 0 and c.character().xp > 0, "xp and kamas")
	check(c.character().level >= level)
	# the next quest of the chain is offered
	c.talk(2905)
	var offered: Array = (c.last(Protocol.DIALOG).get("replies", []) as Array).map(func(r: Dictionary) -> int: return int(r.get("quest", 0)))
	check(offered.has(1640), "1640 follows 1639 (Qf=1639): %s" % str(offered))


# ── P2.04: repeatable quests, chains, abandon, markers ─────────────────────────

func test_a_repeatable_quest_is_offered_again_a_daily_one_the_next_day_a_once_one_never() -> void:
	var c := _conn()
	for q: int in [7004, 7005, 7006]:
		c.accept(9003, q)
		c.talk(9002)
		check(c.character().quests.is_finished(q), "quest %d done" % q)
	var offered := func() -> Array:
		c.talk(9003)
		return c.last(Protocol.DIALOG)["replies"].filter(func(r: Dictionary) -> bool: return r.has("quest")).map(func(r: Dictionary) -> int: return int(r["quest"]))
	eq(offered.call(), [7004], "the same day: only the repeatable quest (repeat 1)")
	c.send(Protocol.dialog_reply(QuestEngine.REPLY_BASE + 7004)) # taken again
	check(c.character().quests.is_active(7004), "repeated: under way again")
	c.talk(9002)
	c.backend.sim.clock.unix_ms += 86400000
	eq(offered.call(), [7004, 7005], "the next day the daily quest is back, the once one never")


func test_the_chain_follows_the_finished_quests() -> void:
	var c := _conn()
	var offered_by_9001 := func() -> Array:
		c.talk(9001)
		return c.last(Protocol.DIALOG)["replies"].filter(func(r: Dictionary) -> bool: return r.has("quest")).map(func(r: Dictionary) -> int: return int(r["quest"]))
	eq(offered_by_9001.call(), [7001, 7003], "7002 asks Qf=7001: not yet")
	c.character().quests.finished.append(7001)
	eq(offered_by_9001.call(), [7002, 7003], "the chain goes on once 7001 is done")


func test_abandoning_a_quest_loses_its_progress_and_it_can_be_taken_again() -> void:
	var c := _conn()
	c.accept(9001, 7001)
	c.talk(9002)
	check(c.character().quests.is_active(7001))
	var ev := c.send(Protocol.quest_abandon(7001))
	check(not c.character().quests.is_active(7001), "no longer under way")
	check(not c.character().quests.is_finished(7001), "not finished either")
	eq((c.last(Protocol.QUEST_LIST)["active"] as Array).size(), 0, "quest_list sent again")
	check(not ev.is_empty())
	c.accept(9001, 7001)
	eq(c.character().quests.count(7001, 11), 0, "taken again from the start")
	eq(c.send(Protocol.quest_abandon(7002)).filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.ERROR).size(), 0, "abandoning an unknown quest is ignored")


func test_map_markers_show_offers_and_goals() -> void:
	var c := _conn()
	var markers: Array = c.entered.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.MAP_MARKERS).back()["markers"]
	var offers := markers.filter(func(m: Dictionary) -> bool: return m["kind"] == "offer")
	check(offers.any(func(m: Dictionary) -> bool: return int(m["npc"]) == 9001 and int(m["quest"]) == 7001), "9001 offers 7001")
	eq(markers.filter(func(m: Dictionary) -> bool: return m["kind"] == "goal").size(), 0, "no goal yet")
	c.accept(9001, 7001)
	markers = c.last(Protocol.MAP_MARKERS)["markers"]
	var goals := markers.filter(func(m: Dictionary) -> bool: return m["kind"] == "goal").map(func(m: Dictionary) -> int: return int(m["npc"]))
	goals.sort()
	eq(goals, [9002, 9003], "talk to B and C (going back to A comes after)")
	check(not markers.any(func(m: Dictionary) -> bool: return m["kind"] == "offer" and int(m["quest"]) == 7001), "no longer offered")
	check(Protocol.validate(Protocol.quest_abandon(7001), Protocol.C2S) == "" and Protocol.validate(Protocol.map_markers(1, []), Protocol.S2C) == "")


func test_the_completion_day_is_saved() -> void:
	var log := QuestLog.new()
	log.finished = [5]
	log.finished_day[5] = 20000
	eq(QuestLog.from_dict(JSON.parse_string(JSON.stringify(log.to_dict()))).finished_day, {5: 20000}, "finished_day survives JSON")
