## L'Ascension through the network (rule 4): a ServerHost on 127.0.0.1 hosts worlds/ascension, a NetBackend client
## creates a character, talks to the stair keeper of the first floor and goes up. Every event is validated against
## Protocol.SCHEMA. Skipped when the world is not built on this machine (it is never committed).
extends TestCase

const WORLD := "ascension"
const STEP := 0.05


class Rig:
	var host := ServerHost.new()
	var backend := NetBackend.new()
	var events: Array = []
	var npcs := {}
	var map := 0
	var ms := 0

	func _init() -> void:
		host.listen(0, "127.0.0.1")
		backend.validate_events = true
		backend.ticks = func() -> int: return ms
		backend.event.connect(func(ev: Dictionary) -> void:
			events.append(ev)
			if ev["t"] == Protocol.MAP_ENTER:
				map = int(ev["map"]["id"])
				npcs.clear()
				for a: Dictionary in ev["actors"]:
					if a["kind"] == "npc":
						npcs[int(a["npc"])] = int(a["id"]))
		backend.connect_to("127.0.0.1:%d" % host.local_port())

	func run(seconds: float, until: Callable) -> bool:
		var done := 0.0
		while done < seconds:
			ms += int(STEP * 1000.0)
			host.poll(STEP)
			backend.poll(STEP)
			done += STEP
			if until.call():
				return true
		return false

	func has(type: String) -> bool:
		return events.any(func(e: Dictionary) -> bool: return e["t"] == type)

	func take(type: String) -> Array:
		var out := events.filter(func(e: Dictionary) -> bool: return e["t"] == type)
		events = events.filter(func(e: Dictionary) -> bool: return e["t"] != type)
		return out


func test_going_up_a_floor_through_a_server() -> void:
	if not ContentSource.exists("worlds/%s/world.json" % WORLD):
		skip("world %s not built" % WORLD)
		return
	var rig := Rig.new()
	rig.backend.send(Protocol.hello(WORLD))
	check(rig.run(5.0, func() -> bool: return rig.has(Protocol.CHARACTERS)), "the character list arrives")
	var breeds: Array = rig.take(Protocol.CHARACTERS)[0]["breeds"]
	check(not breeds.is_empty(), "the world offers classes")
	rig.backend.send(Protocol.create_character("Asuna", int(breeds[0])))
	check(rig.run(5.0, func() -> bool: return rig.has(Protocol.CHARACTER_CREATED)), "the character is created")
	rig.backend.send(Protocol.hello(WORLD, "Asuna"))
	check(rig.run(5.0, func() -> bool: return rig.has(Protocol.MAP_ENTER)), "welcome and map_enter arrive")
	var hubs := _keepers()
	var first := rig.map
	check(hubs.has(first), "the character starts on a hub (%d)" % first)
	if not hubs.has(first) or not rig.npcs.has(hubs[first]):
		fail("no stair keeper on the start map")
	else:
		rig.backend.send(Protocol.npc_talk(rig.npcs[hubs[first]]))
		check(rig.run(5.0, func() -> bool: return rig.has(Protocol.DIALOG)), "the keeper talks")
		var up := -1
		for r: Dictionary in rig.take(Protocol.DIALOG)[0]["replies"]:
			if str(r.get("text", "")).begins_with("Monter"):
				up = int(r["id"])
		check(up >= 0, "the keeper offers to go up")
		rig.backend.send(Protocol.dialog_reply(up))
		check(rig.run(5.0, func() -> bool: return rig.map != first and hubs.has(rig.map)), "the stairs lead to the next floor's hub")
	eq(rig.backend.schema_errors.size(), 0, "every event matches Protocol.SCHEMA: %s" % [rig.backend.schema_errors])
	rig.backend.close()
	rig.run(0.5, func() -> bool: return false)
	rig.host.shutdown()
	ContentSource.use_dev()


## The stair keepers by map: {hub map id: npc id}.
static func _keepers() -> Dictionary:
	var out := {}
	var placed: Dictionary = ContentSource.read_json("worlds/%s/npcs.json" % WORLD)["maps"]
	for mid: String in placed:
		for row: Dictionary in placed[mid]:
			out[int(mid)] = int(row["npc"])
	return out
