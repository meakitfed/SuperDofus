## World, part 2 (roadmap P1.08): zaaps (registered on the first visit, paid
## trips), the save point (set at a zaap, used by the recall potion and after a
## lost fight). Real Incarnam zaaps (waypoints 51 and the two others).
extends TestCase

const START := 154010373
const CEMETERY := 153880064 # Cimetière (3,0), waypoints 51
const ROAD := 154010371 # Route des âmes (-1,-3)
const PASTURES := 153879813 # Pâturages (2,-5)


func _init() -> void:
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()


class Conn:
	var backend := LocalBackend.new()
	var events: Array = []

	func _init() -> void:
		backend.server = LocalServer.new()
		backend.event.connect(func(ev: Dictionary) -> void: events.append(ev))
		backend.send(Protocol.hello("incarnam", "Bob"))
		backend.poll(0.0)

	func player() -> PlayerActor:
		return backend.sim.players[backend.player_id]

	func map() -> MapData:
		return backend.sim.get_map(player().map_id).data

	## Tool shortcut: stands on `cell` of `map` (-1 = beside its zaap).
	func put(map_id: int, cell := -1) -> void:
		events.clear()
		var m := backend.sim.get_map(map_id).data
		backend.sim.teleport(player(), map_id, m.use_cells(m.zaap)[0] if cell < 0 else cell)
		backend.poll(0.0)

	func send(cmd: Dictionary) -> void:
		events.clear()
		backend.send(cmd)
		backend.poll(0.0)

	func last(type: String) -> Dictionary:
		var l := events.filter(func(e: Dictionary) -> bool: return e["t"] == type)
		return l[-1] if not l.is_empty() else {}

	func error() -> String:
		return str(last(Protocol.ERROR).get("code", ""))


func test_zaap_price() -> void:
	eq(Travel.zaap_cost(Vector2i(-2, 0), Vector2i(5, 7)), 90, "wiki example: int(sqrt(98)) = 9 maps -> 90 kamas")
	eq(Travel.zaap_cost(Vector2i(-2, 0), Vector2i(5, 7), Travel.INCARNAM_AREA), 22, "divided by 4 from Incarnam")
	eq(Travel.zaap_cost(Vector2i(3, 0), Vector2i(-1, -3), 45), 12, "Cimetière -> Route des âmes: 5 maps, 50 / 4")


func test_the_three_incarnam_zaaps_are_in_the_world() -> void:
	var src := JsonWorldSource.for_world("incarnam")
	for id: int in [CEMETERY, ROAD, PASTURES]:
		var m := src.get_map(id)
		check(m.zaap >= 0, "zaap on %d (waypoints.mapId)" % id)
		check(not m.use_cells(m.zaap).is_empty(), "the zaap of %d can be reached" % id)
	eq(src.get_map(START).zaap, -1)


func test_a_zaap_is_registered_on_the_first_visit() -> void:
	var c := Conn.new()
	eq(c.player().character.known_zaaps, [])
	c.put(CEMETERY)
	eq(int(c.last(Protocol.ZAAP_KNOWN)["map"]), CEMETERY)
	c.put(START, 287)
	c.put(CEMETERY)
	eq(c.last(Protocol.ZAAP_KNOWN), {}, "only once")
	eq(c.player().character.known_zaaps, [CEMETERY])


func test_zaap_list_and_paid_trip() -> void:
	var c := Conn.new()
	c.put(ROAD)
	c.put(PASTURES)
	c.put(CEMETERY, 400)
	c.send(Protocol.use_zaap())
	eq(c.error(), Protocol.E_NOT_AT_ZAAP, "too far from the zaap")
	c.put(CEMETERY)
	c.send(Protocol.use_zaap())
	var list := c.last(Protocol.ZAAP_LIST)
	eq(int(list["zaap"]), CEMETERY)
	var costs := {}
	for d: Dictionary in list["destinations"]:
		costs[int(d["map"])] = int(d["cost"])
	eq(costs, {ROAD: 12, PASTURES: 12}, "known zaaps but this one, Incarnam prices")
	c.send(Protocol.zaap_travel(ROAD))
	eq(c.error(), Protocol.E_NOT_ENOUGH_KAMAS)
	c.send(Protocol.zaap_travel(START))
	eq(c.error(), Protocol.E_UNKNOWN_ZAAP, "no zaap there")
	c.player().character.kamas = 100
	c.send(Protocol.zaap_travel(ROAD))
	eq(c.player().map_id, ROAD)
	eq(c.player().character.kamas, 88)
	check(c.map().use_cells(c.map().zaap).has(c.player().cell), "arrived beside the destination zaap")
	eq(int(c.last(Protocol.PLAYER_STATS)["stats"]["kamas"]), 88)


func test_save_point_at_a_zaap_for_recall_and_defeat() -> void:
	var c := Conn.new()
	c.put(CEMETERY, 400)
	c.send(Protocol.set_save_point())
	eq(c.error(), Protocol.E_NOT_AT_ZAAP)
	c.put(CEMETERY)
	c.send(Protocol.set_save_point())
	eq(c.player().character.save_map, CEMETERY)
	eq(int(c.last(Protocol.PLAYER_STATS)["stats"]["save_map"]), CEMETERY)
	# recall potion
	c.put(START, 287)
	c.backend.sim.give_item(c.player(), 548)
	c.backend.poll(0.0)
	var stack: Dictionary = c.player().character.inventory.items.values().filter(
			func(it: Dictionary) -> bool: return int(it["id"]) == 548).front()
	c.send(Protocol.use_item(int(stack["uid"])))
	eq(c.player().map_id, CEMETERY, "Potion de Rappel -> save point")
	# a lost fight (the player passes every turn) -> save point
	c.put(START, 287)
	var group := -1
	for id: int in c.backend.sim.get_map(START).actors:
		if c.backend.sim.get_map(START).actors[id] is MonsterGroup:
			group = id
	c.send(Protocol.fight_attack(group))
	c.send(Protocol.fight_ready(true))
	var ended := {}
	for i in 600:
		c.backend.send(Protocol.fight_end_turn())
		c.backend.server.tick(500)
		c.backend.poll(0.0)
		var e := c.last(Protocol.FIGHT_END)
		if not e.is_empty():
			ended = e
			break
	eq(str(ended.get("result", "")), "lose")
	eq(c.player().map_id, CEMETERY, "defeat -> save point")
	eq(c.player().character.hp_at(c.backend.sim.now), 1)
