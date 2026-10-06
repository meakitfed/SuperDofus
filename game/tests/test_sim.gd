## Game logic scenarios, driven exactly like the client does: commands in,
## events out, through a LocalBackend (JSON-serialized messages).
extends TestCase

const LOOK := "{1|120,2195||56}"


## 2 x 1 world, no obstacles, one monster group on map 1.
static func _tiny_world() -> WorldSource:
	return WorldSource.from_dicts(
		{"id": "tiny", "name": "Tiny", "start_map": 1, "start_cell": 300, "wander_ms": [500, 1000]},
		[{"id": 1, "coords": [0, 0], "neighbors": {"right": 2}, "groups": [{"looks": ["{4907|||130}", "{4907|||130}"]}]},
		 {"id": 2, "coords": [1, 0], "neighbors": {"left": 1}, "blocked": [14 * 20]}])


class Client:
	var backend := LocalBackend.new()
	var events: Array = []
	var you := -1

	func _init(world: String, source: WorldSource) -> void:
		if source != null:
			backend.sources[world] = source
		backend.event.connect(func(ev: Dictionary) -> void:
			events.append(ev)
			if ev["t"] == Protocol.WELCOME:
				you = int(ev["you"]))
		backend.send(Protocol.hello(world, "Tester", LOOK))

	func run(seconds: float, step := 0.05) -> void:
		for i in int(seconds / step):
			backend.poll(step)

	func take(type: String) -> Array:
		var out := events.filter(func(e: Dictionary) -> bool: return e["t"] == type)
		events = events.filter(func(e: Dictionary) -> bool: return e["t"] != type)
		return out

	func me() -> PlayerActor:
		return backend.sim.players[you]


func test_hello_enters_start_map() -> void:
	var c := Client.new("tiny", _tiny_world())
	c.run(0.1)
	check(c.you > 0, "welcome received")
	var enter := c.take(Protocol.MAP_ENTER)
	eq(enter.size(), 1)
	eq(int(enter[0]["map"]["id"]), 1)
	var kinds := (enter[0]["actors"] as Array).map(func(a: Dictionary) -> String: return a["kind"])
	check(kinds.has("player") and kinds.has("monster_group"), "self and monsters listed: %s" % [kinds])


func test_move_arrives_on_time() -> void:
	var c := Client.new("tiny", _tiny_world())
	c.run(0.1)
	c.take(Protocol.ACTOR_MOVE)
	c.backend.send(Protocol.move(304))
	c.run(0.05)
	var moves := c.take(Protocol.ACTOR_MOVE).filter(func(e: Dictionary) -> bool: return int(e["id"]) == c.you)
	eq(moves.size(), 1, "player move broadcast")
	var path: Array = moves[0]["path"]
	eq(int(path[-1]), 304)
	var dur := Movement.duration_ms(path.map(func(x: Variant) -> int: return int(x)), false)
	c.run(dur / 1000.0 + 0.1)
	eq(c.me().cell, 304, "arrived")
	check(not c.me().is_moving(c.backend.time_ms()))


func test_move_to_blocked_cell_is_refused() -> void:
	var c := Client.new("tiny", _tiny_world())
	c.run(0.1)
	c.backend.send(Protocol.move(9999))
	c.run(0.05)
	eq(c.take(Protocol.ERROR).size(), 1)


func test_change_map_from_edge() -> void:
	var c := Client.new("tiny", _tiny_world())
	c.run(0.1)
	var edge := 20 * 14 + 13 # right edge, row 20
	c.backend.send(Protocol.move(edge))
	c.run(15.0)
	eq(c.me().cell, edge)
	c.take(Protocol.MAP_ENTER)
	c.backend.send(Protocol.change_map("right"))
	c.run(0.05)
	var enter := c.take(Protocol.MAP_ENTER)
	eq(enter.size(), 1, "entered neighbour map")
	eq(int(enter[0]["map"]["id"]), 2)
	# mirror cell 20*14 is blocked on map 2 -> nearest walkable
	eq(c.me().map_id, 2)
	check(c.me().cell != 20 * 14 and MapGeometry.distance(c.me().cell, 20 * 14) == 1, "nearest free mirror cell")


func test_change_map_refused_off_edge() -> void:
	var c := Client.new("tiny", _tiny_world())
	c.run(0.1)
	c.backend.send(Protocol.change_map("right"))
	c.run(0.05)
	eq(c.take(Protocol.ERROR).size(), 1)
	c.backend.send(Protocol.change_map("left"))
	c.run(0.05)
	eq(c.take(Protocol.ERROR).size(), 1, "no map on the left")


func test_monster_groups_wander_on_walkable_cells() -> void:
	var c := Client.new("test", null) # the committed test world
	c.run(0.1)
	var map := MapData.from_dict(c.take(Protocol.MAP_ENTER)[0]["map"])
	var groups := {}
	for a: Dictionary in c.backend.sim.maps[map.id].actors_dicts(0):
		if a["kind"] == "monster_group":
			groups[int(a["id"])] = true
	check(groups.size() >= 2, "test map has monster groups")
	c.run(40.0, 0.1)
	var moves := c.take(Protocol.ACTOR_MOVE).filter(func(e: Dictionary) -> bool: return groups.has(int(e["id"])))
	check(moves.size() >= groups.size(), "groups moved (%d moves)" % moves.size())
	for m: Dictionary in moves:
		var p: Array = m["path"]
		for i in p.size():
			check(map.is_walkable(int(p[i])), "walkable cell %s" % p[i])
			if i > 0:
				eq(MapGeometry.distance(int(p[i - 1]), int(p[i])), 1, "adjacent step")


func test_events_are_json_safe_without_serialization() -> void:
	var c := Client.new("tiny", _tiny_world())
	c.backend.serialize_messages = false
	c.run(0.1)
	c.backend.send(Protocol.move(310))
	c.run(3.0)
	check(not c.events.is_empty())
	for ev: Dictionary in c.events:
		check(Protocol.is_json_safe(ev), "json-safe %s" % ev["t"])


func test_sim_is_deterministic() -> void:
	var a := Client.new("tiny", _tiny_world())
	var b := Client.new("tiny", _tiny_world())
	a.run(20.0)
	b.run(20.0)
	eq(JSON.stringify(a.events), JSON.stringify(b.events))


func test_monster_groups_show_members_but_not_their_stats() -> void:
	var c := Client.new("test", null)
	c.run(0.1)
	var groups := (c.take(Protocol.MAP_ENTER)[0]["actors"] as Array).filter(
			func(a: Dictionary) -> bool: return a["kind"] == "monster_group")
	check(not groups.is_empty())
	for g: Dictionary in groups:
		eq((g["members"] as Array).size(), (g["looks"] as Array).size(), "one entry per member")
		for m: Dictionary in g["members"]:
			check(m.has("name") and m.has("level"), "name and level (group tooltip)")
			check(not m.has("hp") and not m.has("drops"), "fight stats and loot stay in the sim")
