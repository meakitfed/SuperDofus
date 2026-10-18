## The Vertebre world through the network (rule 4: every mechanic also works against a server): a ServerHost on
## 127.0.0.1 hosts worlds/vertebre, a NetBackend client picks one of its classes, walks the hub, talks to the
## keeper of the Black Gate and arrives on the first floor. Every event is validated against Protocol.SCHEMA.
## The world's data overlay is turned on by the host itself (LocalServer.world -> ContentSource.add_overlay).
extends TestCase

const WORLD := "vertebre"
const STEP := 0.05


class Rig:
	var host := ServerHost.new()
	var backend := NetBackend.new()
	var events: Array = []
	var npcs := {}
	var map := 0
	var groups := 0
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
				groups = 0
				for a: Dictionary in ev["actors"]:
					if a["kind"] == "npc":
						npcs[int(a["npc"])] = int(a["id"])
					elif a["kind"] == "monster_group":
						groups += 1)
		backend.connect_to("127.0.0.1:%d" % host.local_port())

	func run(seconds: float, until := Callable()) -> bool:
		var done := 0.0
		while done < seconds:
			ms += int(STEP * 1000.0)
			host.poll(STEP)
			backend.poll(STEP)
			done += STEP
			if until.is_valid() and until.call():
				return true
		return not until.is_valid()

	func has(type: String) -> bool:
		return events.any(func(e: Dictionary) -> bool: return e["t"] == type)

	func take(type: String) -> Array:
		var out := events.filter(func(e: Dictionary) -> bool: return e["t"] == type)
		events = events.filter(func(e: Dictionary) -> bool: return e["t"] != type)
		return out


func test_a_class_of_the_vertebre_plays_through_a_server() -> void:
	if not ContentSource.dir_exists("worlds/%s/data" % WORLD):
		skip("world %s not generated" % WORLD)
		return
	var rig := Rig.new()
	rig.backend.send(Protocol.hello(WORLD))
	check(rig.run(5.0, func() -> bool: return rig.has(Protocol.CHARACTERS)), "the character list arrives")
	var list: Dictionary = rig.take(Protocol.CHARACTERS)[0]
	eq((list["breeds"] as Array).map(func(b: Variant) -> int: return int(b)), [901, 902, 903, 904, 905], "the world offers its five classes only")
	rig.backend.send(Protocol.create_character("Aldo", 904))
	check(rig.run(5.0, func() -> bool: return rig.has(Protocol.CHARACTER_CREATED)), "the character is created")
	eq(int(rig.take(Protocol.CHARACTER_CREATED)[0]["character"]["breed"]), 904)
	rig.backend.send(Protocol.hello(WORLD, "Aldo"))
	check(rig.run(5.0, func() -> bool: return rig.has(Protocol.MAP_ENTER)), "welcome and map_enter arrive")
	eq(rig.map, 9001, "the hub")
	check(rig.npcs.size() >= 8, "the hub NPCs are there (%d)" % rig.npcs.size())
	# the keeper of the Black Gate: the NPC whose first line speaks of the Porte Noire
	var trees: Dictionary = ContentSource.read_json("worlds/%s/dialogs.json" % WORLD)["dialogs"]
	var rows: Array = ContentSource.read_json("worlds/%s/npcs.json" % WORLD)["maps"]["9001"]
	var gate := 0
	var cell := -1
	for row: Dictionary in rows:
		var nodes: Dictionary = (trees.get(str(int(row["npc"])), {}) as Dictionary).get("nodes", {})
		if nodes.has("0") and "Porte Noire" in str(nodes["0"]["text"]):
			gate = int(row["npc"])
			cell = int(row["cell"])
	check(gate != 0, "the keeper of the gate is on the hub")
	rig.backend.send(Protocol.move(MapGeometry.neighbors(cell)[0]))
	rig.run(12.0)
	rig.take(Protocol.ERROR)
	rig.backend.send(Protocol.npc_talk(rig.npcs[gate]))
	check(rig.run(5.0, func() -> bool: return rig.has(Protocol.DIALOG)), "the keeper talks")
	var dlg: Dictionary = rig.take(Protocol.DIALOG)[0]
	rig.backend.send(Protocol.dialog_reply(int((dlg["replies"] as Array)[0]["id"])))
	check(rig.run(5.0, func() -> bool: return rig.map == 9101), "the gate leads to the first floor")
	check(rig.groups >= 2, "the first floor has monster groups (%d)" % rig.groups)
	eq(rig.backend.schema_errors.size(), 0, "every event matches Protocol.SCHEMA: %s" % [rig.backend.schema_errors])
	rig.backend.close()
	rig.run(0.5)
	rig.host.shutdown()
	ContentSource.use_dev()
