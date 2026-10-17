## P2.03b: the emotes, titles and spells a quest step gives are really applied (Character), through
## LocalBackend and through the network (NetBackend, 127.0.0.1).
extends TestCase

const LOOK := "{1|120,2195||56}"
const QUEST := 7101
const EMOTE := 35
const TITLE := 200


static func _quests(spell: int) -> Dictionary:
	return {QUEST: {"id": QUEST, "name_id": 1, "criteria": "", "start": {"npc": 9001, "map": 1}, "steps": [
		{"id": 1, "name_id": 0, "desc_id": 0, "level": 1, "objectives": [{"id": 11, "type": 1, "map": 1, "params": [9002], "args": []}],
			"rewards": [{"level_min": -1, "level_max": -1, "xp": 0.0, "kamas": 0.0, "scale": 0, "items": [],
				"emotes": [EMOTE], "spells": [], "titles": []}]},
		{"id": 2, "name_id": 0, "desc_id": 0, "level": 1, "objectives": [{"id": 21, "type": 1, "map": 1, "params": [9002], "args": []}],
			"rewards": [{"level_min": -1, "level_max": -1, "xp": 0.0, "kamas": 0.0, "scale": 0, "items": [],
				"emotes": [EMOTE], "spells": [spell], "titles": [TITLE]}]}]}}


static func _source(spell: int, id: String) -> WorldSource:
	var src := WorldSource.from_dicts({"id": id, "name": id, "start_map": 1, "start_cell": 301},
		[{"id": 1, "coords": [0, 0], "neighbors": {}}])
	src.set_npcs({1: [{"npc": 9001, "cell": 300, "dir": 3, "look": "{714}", "name_id": 8306},
			{"npc": 9002, "cell": 302, "dir": 1, "look": "{714}", "name_id": 8306}]},
			{9001: {"start": "a", "nodes": {"a": {"text": "Bonjour", "replies": []}}}, 9002: {"start": "a", "nodes": {"a": {"text": "Salut", "replies": []}}}})
	src.set_quests(_quests(spell))
	return src


## A spell (spells.id) learnt at level 1 that a character of `breed` does not have.
static func _foreign_spell(breed: int, known: Array) -> int:
	for b in range(1, 20):
		if b == breed:
			continue
		for pair: Array in SpellBook.pairs(b):
			for sid: int in pair:
				var grade := SpellBook.grade_for(sid, 1)
				if grade != 0 and not known.has(grade):
					return sid
	return 0


func _check_applied(c: Character, spell: int, label: String) -> void:
	eq(c.emotes, [EMOTE], label + ": the emote is kept once")
	eq(c.titles, [TITLE], label + ": the title")
	check(c.known_spells().has(SpellBook.grade_for(spell, c.level)), label + ": the spell is castable (fight spells)")
	var back := Character.from_dict(JSON.parse_string(JSON.stringify(c.to_dict(0))), 0)
	eq(back.emotes, [EMOTE], label + ": emotes survive the save")
	check(back.known_spells().has(SpellBook.grade_for(spell, c.level)), label + ": the spell survives the save")


func test_rewards_of_emotes_titles_and_spells_are_applied_locally() -> void:
	var s := LocalServer.new()
	var probe := Character.new()
	var spell := _foreign_spell(probe.breed, probe.known_spells())
	check(spell != 0, "a foreign level 1 spell exists")
	s.sources["q"] = _source(spell, "q")
	var b := LocalBackend.new()
	b.server = s
	var events: Array = []
	var npcs := {}
	b.event.connect(func(ev: Dictionary) -> void:
		events.append(ev)
		if ev["t"] == Protocol.MAP_ENTER:
			for a: Dictionary in ev["actors"]:
				if a["kind"] == "npc":
					npcs[int(a["npc"])] = int(a["id"]))
	b.send(Protocol.hello("q", "Eli", LOOK))
	b.poll(0.0)
	var c: Character = b.sim.players[b.player_id].character
	check(not c.known_spells().has(SpellBook.grade_for(spell, 1)), "the spell is not known before")
	b.send(Protocol.npc_talk(npcs[9001]))
	b.poll(0.0)
	b.send(Protocol.dialog_reply(QuestEngine.REPLY_BASE + QUEST))
	b.poll(0.0)
	b.send(Protocol.npc_talk(npcs[9002])) # step 1 done: the emote
	b.poll(0.0)
	eq(c.emotes, [EMOTE], "the first step gave the emote")
	eq(c.titles, [], "no title yet")
	events.clear()
	b.send(Protocol.npc_talk(npcs[9002])) # step 2: emote again (no duplicate), title, spell
	b.poll(0.0)
	_check_applied(c, spell, "local")
	var stats: Array = events.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.PLAYER_STATS)
	check(not stats.is_empty(), "player_stats is sent")
	var sent: Dictionary = stats.back()["stats"]
	eq((sent.get("titles", []) as Array).map(func(v: Variant) -> int: return int(v)), [TITLE], "the client is told its titles")
	eq((sent.get("emotes", []) as Array).map(func(v: Variant) -> int: return int(v)), [EMOTE], "and its emotes")
	check((sent.get("spells", []) as Array).map(func(v: Variant) -> int: return int(v)).has(SpellBook.grade_for(spell, 1)), "and its spells")


func test_rewards_are_applied_over_the_network() -> void:
	var probe := Character.new()
	var spell := _foreign_spell(probe.breed, probe.known_spells())
	var rig = preload("res://tests/test_net.gd").Rig.new()
	rig.host.server.sources["q"] = _source(spell, "q")
	var c = rig.client("q", "Eli")
	var npcs := {}
	check(rig.run(5.0, func() -> bool: return c.has(Protocol.MAP_ENTER)), "entered")
	for ev: Dictionary in c.take(Protocol.MAP_ENTER):
		for a: Dictionary in ev["actors"]:
			if a["kind"] == "npc":
				npcs[int(a["npc"])] = int(a["id"])
	c.backend.send(Protocol.npc_talk(npcs[9001]))
	rig.run(0.3)
	c.backend.send(Protocol.dialog_reply(QuestEngine.REPLY_BASE + QUEST))
	rig.run(0.3)
	c.backend.send(Protocol.npc_talk(npcs[9002]))
	rig.run(0.3)
	c.backend.send(Protocol.npc_talk(npcs[9002]))
	rig.run(0.5)
	var ch: Character = rig.sim_of("q").players[c.you].character
	_check_applied(ch, spell, "net")
	var stats := c.take(Protocol.PLAYER_STATS)
	check(not stats.is_empty(), "player_stats arrives")
	eq(c.take(Protocol.ERROR).size(), 0, "no error")
	eq(c.backend.schema_errors.size(), 0, "events match the schema: %s" % [c.backend.schema_errors])
	rig.host.shutdown()
