## Dungeons in the sim (P4.01d): WorldDungeons through LocalBackend (door checks, private rooms,
## chained rooms, boss, win / defeat / leave / disconnect, group runs) and over a real socket. The world
## is a hand-made one: the entrance (map 1), a plain map (3) and the rooms (11-13); the fights are
## won or lost by force (the fight engine has its own tests). The real Bouftou Royal (dofus world) is
## walked through in test_royal_bouftou_run.
extends TestCase

const NetTests := preload("res://tests/test_net.gd")
const LOOK := "{1|120,2195||56}"
const KEY := 1568
const BOSS := 900


func _init() -> void:
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()


static func _source() -> WorldSource:
	var tofu := {"look": "{4907|||130}", "name": "Tofu", "name_id": 5, "level": 3, "hp": 20, "ap": 4, "mp": 3, "xp": 10}
	var boss := {"look": "{4907|||130}", "name": "Chef", "name_id": 6, "level": 8, "hp": 30, "ap": 4, "mp": 3, "xp": 50}
	var mon := {"subareas": {"5": {"level": 3, "area": 1, "monsters": [100]}},
			"monsters": {"100": {"name_id": 5, "race": 1, "grades": [tofu]}},
			"bosses": {str(BOSS): {"name_id": 6, "race": 1, "grades": [boss]}}}
	var maps: Array = []
	for id: int in [3, 1, 11, 12, 13]:
		maps.append({"id": id, "coords": [id, 0], "subarea": 5, "monster_spawn": false, "monster_aggression": false})
	var s := WorldSource.from_dicts({"id": "dg", "name": "Dg", "start_map": 3, "start_cell": 300, "wander_ms": [600000, 600000]}, maps, mon)
	s.set_dungeons({
		7: {"id": 7, "name": "Cour du Test", "level": 5, "min_level": 3, "difficulty": 1, "maps": [11, 12, 13], "entrance_map": 1,
				"exit_map": 1, "keys": [{"item": KEY, "qty": 1}], "bosses": [BOSS]},
		8: {"id": 8, "name": "Cave du Test", "level": 5, "min_level": 1, "difficulty": 1, "maps": [12], "entrance_map": 1,
				"exit_map": 3, "keys": [], "bosses": []},
	})
	return s


class Conn:
	var backend := LocalBackend.new()
	var server: LocalServer
	var events: Array = []
	var you := -1

	func _init(p_server: LocalServer, name := "Tester", account := "local", world := "dg") -> void:
		server = p_server
		backend.account = account
		backend.server = server
		backend.event.connect(func(ev: Dictionary) -> void:
			events.append(ev)
			if ev["t"] == Protocol.WELCOME:
				you = int(ev["you"]))
		backend.send(Protocol.hello(world, name, LOOK))
		run(0.1)

	func run(seconds: float, step := 0.05) -> void:
		for i in int(seconds / step):
			server.tick(int(step * 1000.0))
			backend.poll(step)

	func send(cmd: Dictionary) -> void:
		backend.send(cmd)
		run(0.1)

	func sim() -> WorldSim:
		return backend.sim

	func player() -> PlayerActor:
		return sim().players[you]

	func take(type: String) -> Array:
		var out := events.filter(func(e: Dictionary) -> bool: return e["t"] == type)
		events = events.filter(func(e: Dictionary) -> bool: return e["t"] != type)
		return out

	func codes() -> Array:
		return take(Protocol.ERROR).map(func(e: Dictionary) -> String: return str(e["code"]))

	## the character at the door of the dungeons: level, (key), on map 1
	func at_door(level := 30, key := true, map := 1) -> void:
		player().character.level = level
		if key:
			sim().give_item(player(), KEY)
		sim().teleport(player(), map, 300)
		run(0.1)
		events.clear()

	func keys() -> int:
		return player().character.inventory.bag_count(KEY)

	func groups() -> Array:
		return sim().maps[player().map_id].actors.values().filter(func(a: SimActor) -> bool: return a is MonsterGroup)

	func in_run() -> bool:
		return sim().dungeons.of.has(you)

	func instances() -> Array:
		return sim().maps.keys().filter(func(k: int) -> bool: return k < 0)

	## attacks the first group of the room and wins (or loses) the fight at once
	func fight(win := true) -> void:
		send(Protocol.fight_attack(groups()[0].id))
		var f: Fight = sim().fights.values()[0]
		for fighter: Fighter in f.fighters.values():
			if (fighter.team == 1) == win:
				fighter.alive = false
				fighter.hp = 0
		f._check_end()
		run(0.3)


static func _server() -> LocalServer:
	var s := LocalServer.new()
	s.sources["dg"] = _source()
	return s


# -- the door ---------------------------------------------------------------------

func test_the_entrance_map_lists_its_dungeons() -> void:
	var c := Conn.new(_server())
	c.at_door(30, false)
	c.sim().teleport(c.player(), 3, 300)
	c.run(0.1)
	var plain: Dictionary = c.take(Protocol.MAP_ENTER)[-1]["map"]
	check(not plain.has("dungeons"), "no dungeons on a plain map")
	c.sim().teleport(c.player(), 1, 300)
	c.run(0.1)
	var door: Dictionary = c.take(Protocol.MAP_ENTER)[-1]["map"]
	eq(door["dungeons"].size(), 2)
	eq(int(door["dungeons"][0]["id"]), 7)
	eq(str(door["dungeons"][0]["name"]), "Cour du Test")
	eq(int(door["dungeons"][0]["min_level"]), 3)
	eq(int(door["dungeons"][1]["id"]), 8)
	eq(LocalBackend.schema_errors.size(), 0, "events match the schema")


func test_the_door_refuses() -> void:
	var c := Conn.new(_server())
	c.player().character.level = 30
	c.send(ProtocolDungeon.enter(7))
	eq(c.codes(), [ProtocolDungeon.E_DUNGEON_NOT_AT_ENTRANCE], "not at the entrance")
	c.at_door(1, false)
	c.send(ProtocolDungeon.enter(99))
	eq(c.codes(), [ProtocolDungeon.E_DUNGEON_UNKNOWN])
	c.send(ProtocolDungeon.enter(7))
	eq(c.codes(), [ProtocolDungeon.E_DUNGEON_LEVEL], "level 1 < 3")
	c.player().character.level = 30
	c.send(ProtocolDungeon.enter(7))
	eq(c.codes(), [ProtocolDungeon.E_DUNGEON_KEY], "no key")
	c.send(ProtocolDungeon.leave())
	eq(c.codes(), [ProtocolDungeon.E_DUNGEON_NOT_IN])
	eq(c.player().map_id, 1, "still at the door")
	check(not c.in_run() and c.instances().is_empty(), "no run was opened")


# -- a run -------------------------------------------------------------------------

func test_a_run_through_every_room_to_the_boss() -> void:
	var c := Conn.new(_server())
	c.at_door()
	eq(c.keys(), 1)
	c.send(ProtocolDungeon.enter(7))
	eq(c.codes(), [])
	eq(c.keys(), 0, "the key is taken")
	var rooms: Array = c.take(ProtocolDungeon.ROOM)
	eq(rooms.size(), 1)
	eq(int(rooms[0]["room"]), 0)
	eq(int(rooms[0]["total"]), 3)
	check(not bool(rooms[0]["boss"]))
	eq(int(c.take(Protocol.MAP_ENTER)[-1]["map"]["id"]), 11, "the player is shown the room's map")
	check(c.player().map_id < 0, "in a private instance")
	check(not c.sim().maps.has(11), "the shared map 11 is not used")
	check(c.groups().size() >= 2, "the room holds groups")
	var seen_rooms: Array = [0]
	var boss_seen := false
	var guard := 0
	while c.in_run() and guard < 40:
		guard += 1
		var members: Array = []
		for g: MonsterGroup in c.groups():
			members.append_array(g.members.map(func(m: Dictionary) -> int: return int(m.get("monster", 0))))
		if seen_rooms.size() == 3:
			boss_seen = members.has(BOSS)
			eq(c.groups().size(), 1, "the boss room is one group")
		else:
			check(not members.has(BOSS), "no boss before the last room")
		c.fight(true)
		for r: Dictionary in c.take(ProtocolDungeon.ROOM):
			seen_rooms.append(int(r["room"]))
			if int(r["room"]) == 2:
				check(bool(r["boss"]), "the last room is the boss room")
	check(boss_seen, "the boss is in the last room")
	eq(seen_rooms, [0, 1, 2], "rooms in order")
	var ends := c.take(ProtocolDungeon.END)
	eq(ends.size(), 1)
	eq(str(ends[0]["reason"]), ProtocolDungeon.REASON_WON)
	eq(int(ends[0]["dungeon"]), 7)
	eq(c.player().map_id, 1, "back at the door")
	eq(c.player().cell, 300, "on the cell it came from")
	check(c.instances().is_empty() and c.sim().dungeons.runs.is_empty() and c.sim().dungeons.by_key.is_empty(), "the run is cleaned up")
	eq(c.player().character.xp > 0, true, "the fights gave their rewards")
	eq(LocalBackend.schema_errors.size(), 0)


func test_exit_map_can_differ_from_the_entrance() -> void:
	var c := Conn.new(_server())
	c.at_door(5, false)
	c.send(ProtocolDungeon.enter(8))
	eq(c.codes(), [])
	eq(c.take(ProtocolDungeon.ROOM).size(), 1)
	var guard := 0
	while c.in_run() and guard < 20:
		guard += 1
		c.fight(true)
	eq(c.take(ProtocolDungeon.END).map(func(e: Dictionary) -> String: return str(e["reason"])), [ProtocolDungeon.REASON_WON])
	eq(c.player().map_id, 3, "the dungeon's exit map")


func test_defeat_ends_the_run() -> void:
	var c := Conn.new(_server())
	c.at_door()
	c.send(ProtocolDungeon.enter(7))
	c.take(ProtocolDungeon.ROOM)
	var fighting := c.groups().size()
	c.fight(false)
	var ends := c.take(ProtocolDungeon.END)
	eq(ends.size(), 1)
	eq(str(ends[0]["reason"]), ProtocolDungeon.REASON_DEFEAT)
	eq(c.player().map_id, 3, "back to the save point")
	check(not c.in_run() and c.instances().is_empty(), "the run is gone")
	check(fighting >= 2)
	eq(c.keys(), 0, "the key is not given back")


func test_leave_and_reenter() -> void:
	var c := Conn.new(_server())
	c.at_door()
	c.send(ProtocolDungeon.enter(7))
	c.send(ProtocolDungeon.leave())
	var ends := c.take(ProtocolDungeon.END)
	eq(ends.size(), 1)
	eq(str(ends[0]["reason"]), ProtocolDungeon.REASON_LEFT)
	eq(c.player().map_id, 1)
	check(c.instances().is_empty() and not c.in_run())
	c.send(ProtocolDungeon.enter(7))
	eq(c.codes(), [ProtocolDungeon.E_DUNGEON_KEY], "the key was spent")


func test_free_keys_opens_every_dungeon() -> void:
	var server := _server()
	server.rates = WorldRates.from_options({"free-keys": "1"})
	var c := Conn.new(server)
	c.at_door(30, false)
	c.send(ProtocolDungeon.enter(7))
	eq(c.codes(), [], "no key needed")
	check(c.in_run(), "in the dungeon without its key")
	c.send(ProtocolDungeon.leave())
	c.send(ProtocolDungeon.enter(7))
	check(c.in_run(), "and again")
	c.send(ProtocolDungeon.leave())
	c.sim().give_item(c.player(), KEY)
	c.send(ProtocolDungeon.enter(7))
	eq(c.keys(), 1, "a key in the bag is not spent")
	c.send(ProtocolDungeon.leave())
	c.player().character.level = 1
	c.send(ProtocolDungeon.enter(7))
	eq(c.codes(), [ProtocolDungeon.E_DUNGEON_LEVEL], "the level still counts")
	check(not WorldRates.from_options({"free-keys": "0"}).free_keys)


func test_free_keys_over_websocket() -> void:
	var rig := NetTests.Rig.new()
	rig.host.server.sources["dg"] = _source()
	rig.host.server.rates = WorldRates.from_options({"free-keys": "1"})
	var c := rig.client("dg", "Tester")
	check(rig.run(5.0, func() -> bool: return c.has(Protocol.MAP_ENTER)), "in the world")
	check(bool(c.take(Protocol.WELCOME)[0]["world"]["rates"]["free_keys"]), "welcome.world.rates.free_keys")
	c.take(Protocol.MAP_ENTER)
	var sim := rig.sim_of("dg")
	var p: PlayerActor = sim.players[c.you]
	p.character.level = 30
	sim.teleport(p, 1, 300)
	check(rig.run(2.0, func() -> bool: return c.has(Protocol.MAP_ENTER)))
	c.backend.send(ProtocolDungeon.enter(7))
	check(rig.run(3.0, func() -> bool: return c.has(ProtocolDungeon.ROOM)), "dungeon_room without a key")
	eq(c.take(Protocol.ERROR).size(), 0)
	eq(c.backend.schema_errors.size(), 0, "every event matches the schema: %s" % [c.backend.schema_errors])
	rig.host.shutdown()


func test_a_walk_off_by_teleport_leaves_the_run() -> void:
	var c := Conn.new(_server())
	c.at_door()
	c.send(ProtocolDungeon.enter(7))
	c.sim().teleport(c.player(), 3, 300) # a recall potion, a GM tp...
	c.run(0.1)
	eq(c.take(ProtocolDungeon.END).size(), 1)
	check(not c.in_run() and c.instances().is_empty())


func test_disconnecting_cleans_the_run_and_saves_at_the_door() -> void:
	var server := _server()
	var c := Conn.new(server)
	c.at_door()
	c.send(ProtocolDungeon.enter(7))
	var sim := c.sim()
	sim.disconnect_player(c.you)
	check(sim.dungeons.runs.is_empty() and sim.dungeons.of.is_empty(), "no run left")
	check(sim.maps.keys().all(func(k: int) -> bool: return k > 0), "no instance left")
	var saved := server.persistence.load_character("dg", "Tester")
	eq(int(saved["map"]), 1, "saved at the entrance")
	eq(int(saved["cell"]), 300)


func test_json_round_trip_of_the_messages() -> void:
	for m: Dictionary in [ProtocolDungeon.enter(7), ProtocolDungeon.leave(), ProtocolDungeon.room(7, 1, 3, false, "x"), ProtocolDungeon.end(7, "won")]:
		var back: Dictionary = JSON.parse_string(JSON.stringify(m))
		eq(Protocol.validate(back, Protocol.C2S if m["t"] in [ProtocolDungeon.ENTER, ProtocolDungeon.LEAVE] else Protocol.S2C), "", str(m))


# -- a group ---------------------------------------------------------------------

func test_a_group_goes_in_together() -> void:
	var server := _server()
	var a := Conn.new(server, "Alice", "alice")
	var b := Conn.new(server, "Bob", "bob")
	a.at_door()
	b.at_door(1, false)
	a.send(ProtocolParty.invite("Bob"))
	b.send(ProtocolParty.accept("Alice"))
	a.events.clear()
	b.events.clear()
	b.send(ProtocolDungeon.enter(7))
	eq(b.codes(), [ProtocolParty.E_NOT_PARTY_LEADER], "only the leader opens the door")
	a.send(ProtocolDungeon.enter(7))
	eq(a.codes(), [ProtocolDungeon.E_DUNGEON_LEVEL], "every member needs the level")
	eq(a.keys(), 1, "nothing was taken")
	b.player().character.level = 30
	a.send(ProtocolDungeon.enter(7))
	eq(a.codes(), [])
	eq(a.keys(), 0, "one key for the group")
	eq(a.take(ProtocolDungeon.ROOM).size(), 1)
	b.run(0.2)
	eq(b.take(ProtocolDungeon.ROOM).size(), 1, "the member is told too")
	eq(a.player().map_id, b.player().map_id, "same room")
	check(a.player().map_id < 0)
	eq(a.sim().dungeons.runs.size(), 1, "one run for both")
	a.fight(true) # Alice wins one group alone, Bob watches
	b.send(ProtocolDungeon.leave())
	b.run(0.2)
	eq(b.take(ProtocolDungeon.END).size(), 1)
	eq(b.player().map_id, 1)
	check(a.in_run() and not b.in_run(), "Alice goes on")
	a.send(ProtocolDungeon.leave())
	check(a.sim().dungeons.runs.is_empty() and a.instances().is_empty(), "the run is dropped once empty")


# -- over a socket -------------------------------------------------------------------

func test_the_run_over_websocket() -> void:
	var rig := NetTests.Rig.new()
	rig.host.server.sources["dg"] = _source()
	var c := rig.client("dg", "Tester")
	check(rig.run(5.0, func() -> bool: return c.has(Protocol.MAP_ENTER)), "in the world")
	var sim := rig.sim_of("dg")
	var p: PlayerActor = sim.players[c.you]
	p.character.level = 30
	sim.give_item(p, KEY)
	sim.teleport(p, 1, 300)
	check(rig.run(2.0, func() -> bool: return c.has(Protocol.MAP_ENTER)))
	var door: Dictionary = c.take(Protocol.MAP_ENTER)[-1]["map"]
	eq(door["dungeons"].size(), 2, "the door's dungeons are on the wire")
	c.backend.send(ProtocolDungeon.enter(7))
	check(rig.run(3.0, func() -> bool: return c.has(ProtocolDungeon.ROOM)), "dungeon_room arrives")
	eq(int(c.take(ProtocolDungeon.ROOM)[0]["total"]), 3)
	var groups: Array = sim.maps[p.map_id].actors.values().filter(func(a: SimActor) -> bool: return a is MonsterGroup)
	c.backend.send(Protocol.fight_attack(groups[0].id))
	check(rig.run(3.0, func() -> bool: return not sim.fights.is_empty()), "a room fight starts")
	var f: Fight = sim.fights.values()[0]
	for fighter: Fighter in f.fighters.values():
		if fighter.team == 1:
			fighter.alive = false
			fighter.hp = 0
	f._check_end()
	check(rig.run(3.0, func() -> bool: return c.has(Protocol.FIGHT_END)), "won")
	eq(str(c.take(Protocol.FIGHT_END)[0]["result"]), "win")
	c.backend.send(ProtocolDungeon.leave())
	check(rig.run(3.0, func() -> bool: return c.has(ProtocolDungeon.END)), "dungeon_end arrives")
	eq(str(c.take(ProtocolDungeon.END)[0]["reason"]), ProtocolDungeon.REASON_LEFT)
	eq(p.map_id, 1)
	eq(c.take(Protocol.ERROR).size(), 0)
	eq(c.backend.schema_errors.size(), 0, "every event matches the schema: %s" % [c.backend.schema_errors])
	rig.host.shutdown()


# -- the real Bouftou Royal (dofus world) --------------------------------------------

func test_royal_bouftou_run() -> void:
	var src := JsonWorldSource.for_world("dofus")
	if src.get_dungeon(1).is_empty():
		skip("no dungeons in the dofus world")
		return
	var server := LocalServer.new()
	server.sources["dofus"] = src
	var c := Conn.new(server, "Royal", "local", "dofus")
	c.at_door(60, true, 120063489)
	var before := c.keys()
	c.send(ProtocolDungeon.enter(1))
	eq(c.codes(), [])
	eq(c.keys(), before - 1)
	var rooms := c.take(ProtocolDungeon.ROOM).size()
	var guard := 0
	while c.in_run() and guard < 60:
		guard += 1
		if c.groups().is_empty():
			break
		c.fight(true)
		rooms += c.take(ProtocolDungeon.ROOM).size()
	eq(rooms, 5, "five rooms")
	var ends := c.take(ProtocolDungeon.END)
	eq(ends.size(), 1)
	eq(str(ends[0]["reason"]), ProtocolDungeon.REASON_WON)
	eq(c.player().map_id, 120063489, "back at the door")
