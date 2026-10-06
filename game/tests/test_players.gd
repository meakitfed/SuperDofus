## Several players on one map (roadmap P3.01): each sees the others arrive, walk and
## leave, with their look, name, class and level, and nothing private. Two (or three)
## LocalBackends share one LocalServer; the same flow over WebSockets is in test_net.gd.
extends TestCase

const LOOK := "{1|120,2195||56}"
const EDGE := 20 * 14 + 13 # right edge of the map, an exit cell


func _init() -> void:
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()
	SpellBook.use_file("res://tests/fixtures/spells.json")


static func _server() -> LocalServer:
	var tofu := {"look": "{4907|||130}", "name": "Tofu", "name_id": 5, "level": 1, "hp": 20, "ap": 4, "mp": 3, "xp": 10}
	var s := LocalServer.new()
	s.sources["duo"] = WorldSource.from_dicts(
		{"id": "duo", "name": "Duo", "start_map": 1, "start_cell": 300, "wander_ms": [600000, 600000]},
		[{"id": 1, "coords": [0, 0], "neighbors": {"right": 2}, "groups": [{"name": "Tofu", "members": [tofu]}]},
		 {"id": 2, "coords": [1, 0], "neighbors": {"left": 1}}])
	return s


class Conn:
	var backend := LocalBackend.new()
	var server: LocalServer
	var events: Array = []

	func _init(p_server: LocalServer, name: String, look := LOOK, account := "local") -> void:
		server = p_server
		backend.account = account # one account holds a few characters only: others pass their own
		backend.server = server
		backend.event.connect(func(ev: Dictionary) -> void: events.append(ev))
		backend.send(Protocol.hello("duo", name, look))
		run(0.1)

	func run(seconds: float, step := 0.05) -> void:
		for i in int(seconds / step):
			server.tick(int(step * 1000.0))
			backend.poll(step)

	func sim() -> WorldSim:
		return backend.sim

	func player() -> PlayerActor:
		return sim().players[backend.player_id]

	func take(type: String) -> Array:
		var out := events.filter(func(e: Dictionary) -> bool: return e["t"] == type)
		events = events.filter(func(e: Dictionary) -> bool: return e["t"] != type)
		return out

	func send(cmd: Dictionary) -> void:
		backend.send(cmd)


## Everyone runs the same time, so that each drains its events.
static func _run(conns: Array, seconds: float) -> void:
	for i in int(seconds / 0.05):
		(conns[0] as Conn).server.tick(50)
		for c: Conn in conns:
			c.backend.poll(0.05)


func _names(actors: Array) -> Array:
	return actors.filter(func(a: Dictionary) -> bool: return a["kind"] == "player").map(func(a: Dictionary) -> String: return str(a["name"]))


func test_a_newcomer_sees_those_present_and_they_see_it() -> void:
	var server := _server()
	var a := Conn.new(server, "Alice")
	var b := Conn.new(server, "Bob", "{1|10,2195||90}")
	_run([a, b], 0.2)
	var enter: Dictionary = b.take(Protocol.MAP_ENTER)[0]
	eq(_names(enter["actors"]).size(), 2, "Bob's map_enter lists Alice and himself")
	var alice: Dictionary = (enter["actors"] as Array).filter(func(x: Dictionary) -> bool: return x["name"] == "Alice")[0]
	eq(alice["looks"], [a.player().character.display_look()], "Alice's look")
	eq(int(alice["level"]), 1)
	eq(int(alice["breed"]), a.player().character.breed, "her class")
	var added: Array = a.take(Protocol.ACTOR_ADD).filter(func(e: Dictionary) -> bool: return e["actor"]["kind"] == "player")
	eq(added.size(), 1, "Alice is told once")
	eq(str(added[0]["actor"]["name"]), "Bob")
	eq(int(added[0]["actor"]["id"]), b.backend.player_id)
	eq(added[0]["actor"]["looks"], [b.player().character.display_look()], "Bob's own look, not Alice's")


func test_walks_are_broadcast_both_ways() -> void:
	var server := _server()
	var a := Conn.new(server, "Alice")
	var b := Conn.new(server, "Bob")
	_run([a, b], 0.2)
	a.events.clear()
	b.events.clear()
	a.send(Protocol.move(320, true))
	_run([a, b], 0.2)
	var seen: Array = b.take(Protocol.ACTOR_MOVE)
	eq(seen.size(), 1, "Bob sees Alice walk")
	eq(int(seen[0]["id"]), a.backend.player_id)
	eq(int(seen[0]["path"][-1]), 320)
	eq(bool(seen[0]["run"]), true)
	eq(a.take(Protocol.ACTOR_MOVE).size(), 1, "and Alice gets her own for the path preview")
	_run([a, b], 4.0)
	b.send(Protocol.move(250))
	_run([a, b], 0.2)
	check(a.take(Protocol.ACTOR_MOVE).any(func(e: Dictionary) -> bool: return int(e["id"]) == b.backend.player_id), "Alice sees Bob walk")
	# a player who arrives while another is walking gets the walk in progress
	var c := Conn.new(server, "Carl")
	var walking: Array = (c.take(Protocol.MAP_ENTER)[0]["actors"] as Array).filter(func(x: Dictionary) -> bool: return x["name"] == "Bob")
	check(walking[0].has("move"), "Bob's walk in progress is in Carl's map_enter")


func test_players_walk_through_each_other() -> void:
	var server := _server()
	var a := Conn.new(server, "Alice")
	var b := Conn.new(server, "Bob")
	a.take(Protocol.ERROR)
	var spot: int = a.player().cell
	b.send(Protocol.move(spot))
	b.run(8.0)
	eq(b.take(Protocol.ERROR).size(), 0, "no refusal: a player's cell is not an obstacle (Dofus)")
	eq(b.player().cell, spot)
	eq(a.player().cell, spot, "both stand on the same cell")


func test_arrival_and_departure_on_a_map_change() -> void:
	var server := _server()
	var a := Conn.new(server, "Alice")
	var b := Conn.new(server, "Bob")
	var c := Conn.new(server, "Carl")
	c.send(Protocol.move(EDGE))
	_run([a, b, c], 12.0)
	b.events.clear()
	a.events.clear()
	c.send(Protocol.change_map("right"))
	_run([a, b, c], 0.2)
	var gone: Array = b.take(Protocol.ACTOR_REMOVE)
	eq(gone.size(), 1, "the ones left behind see Carl leave")
	eq(int(gone[0]["id"]), c.backend.player_id)
	eq(c.player().map_id, 2)
	var d := Conn.new(server, "Dora") # on map 1
	d.send(Protocol.move(EDGE))
	_run([a, b, c, d], 12.0)
	c.events.clear()
	d.send(Protocol.change_map("right"))
	_run([a, b, c, d], 0.2)
	var arrived: Array = c.take(Protocol.ACTOR_ADD)
	eq(arrived.size(), 1, "the ones on the new map see Dora arrive")
	eq(str(arrived[0]["actor"]["name"]), "Dora")
	eq(c.take(Protocol.ACTOR_REMOVE).size(), 0)
	eq(_names(d.take(Protocol.MAP_ENTER)[-1]["actors"]).size(), 2, "and Dora sees Carl and herself")


func test_a_player_in_fight_is_not_on_the_map() -> void:
	var server := _server()
	var a := Conn.new(server, "Alice")
	var b := Conn.new(server, "Bob")
	_run([a, b], 0.2)
	b.events.clear()
	var group: MonsterGroup = a.sim().get_map(1).actors.values().filter(func(x: SimActor) -> bool: return x is MonsterGroup)[0]
	a.send(Protocol.fight_attack(group.id))
	_run([a, b], 0.2)
	var removed := b.take(Protocol.ACTOR_REMOVE).map(func(e: Dictionary) -> int: return int(e["id"]))
	check(removed.has(a.backend.player_id), "Bob sees Alice leave the map for the fight")
	check(removed.has(group.id), "and the group")
	check(not a.sim().get_map(1).actors.has(a.backend.player_id), "Alice is not an actor of the map")
	eq(b.take(Protocol.FIGHT_START).size(), 0, "he gets nothing of the fight")
	var late := Conn.new(server, "Carl")
	eq(_names(late.take(Protocol.MAP_ENTER)[0]["actors"]), ["Bob", "Carl"], "a newcomer does not see her either")
	a.send(Protocol.fight_leave())
	_run([a, b, late], 0.3)
	eq(a.sim().fights.size(), 0)
	var back := b.take(Protocol.ACTOR_ADD).filter(func(e: Dictionary) -> bool: return e["actor"]["name"] == "Alice")
	eq(back.size(), 1, "Alice comes back on the map")


func test_a_disconnection_removes_the_player_for_the_others() -> void:
	var server := _server()
	var a := Conn.new(server, "Alice")
	var b := Conn.new(server, "Bob")
	_run([a, b], 0.2)
	b.events.clear()
	var id := a.backend.player_id
	a.backend.close()
	_run([b], 0.2)
	var gone: Array = b.take(Protocol.ACTOR_REMOVE)
	eq(gone.size(), 1)
	eq(int(gone[0]["id"]), id)
	eq(b.sim().players.size(), 1)


func test_nothing_private_reaches_the_others() -> void:
	var server := _server()
	var a := Conn.new(server, "Alice")
	var b := Conn.new(server, "Bob")
	a.player().character.kamas = 4242
	a.player().character.account = "secret-account"
	a.send(Protocol.move(320))
	_run([a, b], 0.3)
	var seen: Array = []
	for e: Dictionary in b.events:
		if e["t"] in [Protocol.MAP_ENTER, Protocol.ACTOR_ADD]:
			seen.append_array(e["actors"] if e["t"] == Protocol.MAP_ENTER else [e["actor"]])
	check(not seen.is_empty())
	for actor: Dictionary in seen:
		if actor["kind"] != "player":
			continue
		for k: String in actor:
			check(PlayerActor.PUBLIC_KEYS.has(k), "actor field %s is public" % k)
	var mine := b.events.filter(func(e: Dictionary) -> bool: return e["t"] in [Protocol.PLAYER_STATS, Protocol.INVENTORY, Protocol.QUEST_LIST])
	eq(mine.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.PLAYER_STATS).size(), 1, "Bob got one player_stats: his own")
	for e: Dictionary in mine:
		check(not JSON.stringify(e).contains("Alice"), "no event of Bob's holds Alice's data (%s)" % e["t"])
	var wire := JSON.stringify(b.events)
	check(not wire.contains("secret-account") and not wire.contains("4242"), "neither her account nor her kamas travel")


func test_a_worn_item_changes_the_look_for_everyone() -> void:
	var server := _server()
	var a := Conn.new(server, "Alice")
	var b := Conn.new(server, "Bob")
	_run([a, b], 0.2)
	b.events.clear()
	a.player().character.look = "{1|120,2195||56|1@0={1420|||90}}"
	a.sim().items.refresh_look(a.player())
	_run([a, b], 0.2)
	var looks := b.take(Protocol.ACTOR_LOOK)
	eq(looks.size(), 1)
	eq(int(looks[0]["id"]), a.backend.player_id)
