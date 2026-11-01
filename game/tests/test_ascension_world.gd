## L'Ascension (worlds/ascension, built by `npm run recipe -- ../worlds_src/ascension/recipe.json` in atelier/): five
## floors of real Dofus maps, each closed on itself (its maps only lead to each other), and on each floor's hub a
## stair keeper whose dialogue goes up and down. Driven through LocalBackend like a client. The world holds data
## taken from Dofus and is never committed: skipped when it is not built on this machine.
extends TestCase

const WORLD := "ascension"
const FLOORS := 5
const MAX_FLOOR_MAPS := 20


class Conn:
	var backend := LocalBackend.new()
	var events: Array = []
	var npcs := {} # npc id -> actor id
	var map := 0

	func _init(server: LocalServer) -> void:
		backend.server = server
		backend.account = "local"
		backend.event.connect(func(ev: Dictionary) -> void:
			events.append(ev)
			if ev["t"] == Protocol.MAP_ENTER:
				map = int(ev["map"]["id"])
				npcs.clear()
				for a: Dictionary in ev["actors"]:
					if a["kind"] == "npc":
						npcs[int(a["npc"])] = int(a["id"]))

	func send(cmd: Dictionary) -> Array:
		events = []
		backend.send(cmd)
		backend.poll(0.0)
		return events

	func take(type: String) -> Array:
		return events.filter(func(e: Dictionary) -> bool: return e["t"] == type)


func _enter() -> bool:
	if not ContentSource.exists("worlds/%s/world.json" % WORLD):
		skip("world %s not built" % WORLD)
		return false
	ContentSource.use_world(WORLD)
	return true


func _leave() -> void:
	ContentSource.use_dev()


## The stair keepers by map: {hub map id: npc id}.
static func keepers() -> Dictionary:
	var out := {}
	var placed: Dictionary = ContentSource.read_json("worlds/%s/npcs.json" % WORLD)["maps"]
	for mid: String in placed:
		for row: Dictionary in placed[mid]:
			out[int(mid)] = int(row["npc"])
	return out


## The maps reached from `start` by walking map edges only.
static func floor_of(start: int) -> Dictionary:
	var seen := {start: true}
	var todo := [start]
	while not todo.is_empty():
		var m: Dictionary = ContentSource.read_json("worlds/%s/maps/%d.json" % [WORLD, todo.pop_back()])
		for to: Variant in (m.get("neighbors", {}) as Dictionary).values():
			if not seen.has(int(to)):
				seen[int(to)] = true
				todo.append(int(to))
	return seen


func test_five_closed_floors() -> void:
	if not _enter():
		return
	var info: Dictionary = ContentSource.read_json("worlds/%s/world.json" % WORLD)
	var hubs := keepers()
	eq(hubs.size(), FLOORS, "one stair keeper per floor")
	check(hubs.has(int(info["start_map"])), "players start on a floor's hub")
	var covered := {}
	for hub: int in hubs:
		var floor := floor_of(hub)
		check(floor.size() <= MAX_FLOOR_MAPS, "floor of %d: %d maps, no bigger than Incarnam" % [hub, floor.size()])
		for other: int in hubs:
			if other != hub:
				check(not floor.has(other), "floor of %d does not walk into the floor of %d" % [hub, other])
		for m: int in floor:
			check(not covered.has(m), "map %d belongs to one floor only" % m)
			covered[m] = true
	eq(covered.size(), (info["maps"] as Array).size(), "every map of the world is on a floor")
	_leave()


func test_the_stair_keeper_goes_up_and_down() -> void:
	if not _enter():
		return
	var c := Conn.new(LocalServer.new())
	var listed := c.send(Protocol.hello(WORLD))
	var chars := listed.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.CHARACTERS)
	check(not chars.is_empty() and not (chars[0]["breeds"] as Array).is_empty(), "the world offers classes")
	if chars.is_empty():
		_leave()
		return
	var breed := int((chars[0]["breeds"] as Array)[0])
	c.send(Protocol.create_character("Kirito", breed))
	c.send(Protocol.hello(WORLD, "Kirito"))
	var hubs := keepers()
	var first := c.map
	check(hubs.has(first), "the character starts on the first floor's hub (%d)" % first)
	var up := _reply(c, hubs[first], "Monter")
	check(up >= 0, "the keeper of the first floor offers to go up")
	if up < 0:
		_leave()
		return
	c.send(Protocol.dialog_reply(up))
	check(hubs.has(c.map) and c.map != first, "going up lands on another floor's hub (%d)" % c.map)
	var down := _reply(c, hubs.get(c.map, 0), "Descendre")
	check(down >= 0, "the keeper of the second floor offers to go down")
	if down >= 0:
		c.send(Protocol.dialog_reply(down))
		eq(c.map, first, "going down leads back to the first floor")
	_leave()


## Talks to the keeper `npc` of the current map; the id of the reply whose text starts with `word`, or -1.
func _reply(c: Conn, npc: int, word: String) -> int:
	if not c.npcs.has(npc):
		fail("keeper %d not on map %d" % [npc, c.map])
		return -1
	c.send(Protocol.npc_talk(c.npcs[npc]))
	var dlg := c.take(Protocol.DIALOG)
	if dlg.is_empty():
		fail("the keeper does not talk (%s)" % [c.events])
		return -1
	for r: Dictionary in dlg[0]["replies"]:
		if str(r.get("text", "")).begins_with(word):
			return int(r["id"])
	return -1
