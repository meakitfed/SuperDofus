## World, part 1 (roadmap P1.07, P1.07b): the whole of Incarnam, real exits
## (cellsData.mapChangeData), doors to its interiors (houses, Mine, Tavern: element
## cells from the client maps, destinations from JondoEmu), subarea / area /
## coordinates in map_enter.
extends TestCase

const START := 154010373 # Incarnam, Champs (-1,-5)
const TAVERN_OUT := 153878787 # Route des âmes (0,-3)
const TAVERN := 153357316
const CELLAR := 153358340
const MINE_DOOR_MAP := 153879812 # Pâturages (2,-4): the Mine entrance
const MINE := [153357312, 153357314, 153357318, 153358336, 153358338, 153358342, 153358344]
const SOULS_ROAD := 153880835 # Incarnam, Route des âmes (4,-3): the way down to Astrub
const ASTRUB_TEMPLE := 192416776 # Astrub, Cité (6,-19): the way back up


func _init() -> void:
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()


class Conn:
	var backend := LocalBackend.new()
	var events: Array = []

	func _init(world := "incarnam") -> void:
		backend.server = LocalServer.new()
		backend.event.connect(func(ev: Dictionary) -> void: events.append(ev))
		backend.send(Protocol.hello(world, "Bob"))
		backend.poll(0.0)

	func player() -> PlayerActor:
		return backend.sim.players[backend.player_id]

	func map_id() -> int:
		return player().map_id

	## Tool shortcut (like client_shot goto): stands on `cell` of `map`.
	func put(map: int, cell: int) -> void:
		backend.sim.teleport(player(), map, cell)
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


static func _source() -> JsonWorldSource:
	return JsonWorldSource.for_world("incarnam")


## map id -> MapData of every map of the world.
static func _maps() -> Dictionary:
	var src := _source()
	var out := {}
	for id: Variant in src.get_info()["maps"]:
		out[int(id)] = src.get_map(int(id))
	return out


## Walkable cells of `m` grouped by connectivity: cell -> component index
## (8 directions, no corner cutting, like MapPathfinder).
static func _components(m: MapData) -> Dictionary:
	var comp := {}
	var n := 0
	for start in MapGeometry.CELL_COUNT:
		if comp.has(start) or not m.is_walkable(start):
			continue
		comp[start] = n
		var queue: Array[int] = [start]
		while not queue.is_empty():
			var c: int = queue.pop_front()
			var p := MapGeometry.to_iso(c)
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
					Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
				var nb := MapGeometry.from_iso(p + d)
				if nb < 0 or comp.has(nb) or not m.is_walkable(nb):
					continue
				if d.x != 0 and d.y != 0 and not (m.is_walkable(MapGeometry.from_iso(p + Vector2i(d.x, 0)))
						and m.is_walkable(MapGeometry.from_iso(p + Vector2i(0, d.y)))):
					continue
				comp[nb] = n
				queue.append(nb)
		n += 1
	return comp


## Map moves a player standing anywhere in `cells` can make: [[map, arrival cell]].
static func _moves(maps: Dictionary, m: MapData, cells: Dictionary) -> Array:
	var out := []
	for c: int in cells:
		for dir in m.exit_dirs(c):
			var next: MapData = maps.get(m.neighbor(dir))
			if next != null:
				out.append([next.id, next.arrival_cell(MapGeometry.mirror_cell(c, dir), dir)])
	for door: int in m.triggers: # used from its cell or beside it
		var t := m.trigger_at(door)
		if maps.has(int(t["to_map"])) and m.use_cells(door).any(func(c: int) -> bool: return cells.has(c)):
			var dest: MapData = maps[int(t["to_map"])]
			out.append([dest.id, dest.nearest_walkable(int(t["to_cell"]))])
	return out


func test_the_world_is_all_of_incarnam() -> void:
	var maps := _maps()
	check(maps.size() >= 50, "%d maps" % maps.size())
	var subareas := {}
	for m: MapData in maps.values():
		eq(m.area, 45, "areas 45 Incarnam: %d" % m.id)
		subareas[m.subarea] = true
	for s: int in [442, 443, 444, 445, 448, 449, 450, 778]: # Lac, Forêt, Champs, Pâturages, Taverne, Cimetière, Route des âmes, Mine
		check(subareas.has(s), "subarea %d" % s)
	check(not maps[TAVERN].outdoor and maps[START].outdoor, "interiors: mapsinformation.worldMap = -1")
	var interiors := maps.values().filter(func(m: MapData) -> bool: return not m.outdoor)
	check(interiors.size() >= 20, "houses, Mine, Tavern: %d interiors" % interiors.size())
	for id: int in MINE:
		check(maps.has(id), "Mine room %d" % id)


## Walks every exit and door from the start: every map is reached, and from
## every arrival cell the player can still go somewhere (no dead end), and back
## to the start.
func test_every_map_is_reachable_without_dead_end() -> void:
	var maps := _maps()
	var comps := {}
	for id: int in maps:
		comps[id] = _components(maps[id])
	var info := _source().get_info()
	var start := int(info["start_map"])
	# nodes = (map, walkable component); edges = exits and doors
	var seen := {}
	var queue := [[start, int(info["start_cell"])]]
	var edges := {} # map -> {map: true}
	while not queue.is_empty():
		var at: Array = queue.pop_front()
		var m: MapData = maps[at[0]]
		if not m.is_walkable(at[1]):
			check(false, "arrival cell %d of map %d not walkable" % at)
			continue
		var comp: Dictionary = comps[at[0]]
		var key := "%d:%d" % [at[0], comp[at[1]]]
		if seen.has(key):
			continue
		seen[key] = true
		var cells := {}
		for c: int in comp:
			if comp[c] == comp[at[1]]:
				cells[c] = true
		var moves := _moves(maps, m, cells)
		check(not moves.is_empty(), "dead end: map %d cell %d" % at)
		for mv: Array in moves:
			edges.get_or_add(at[0], {})[mv[0]] = true
			queue.append(mv)
	var visited := {}
	for k: String in seen:
		visited[int(k.split(":")[0])] = true
	eq(visited.size(), maps.size(), "maps reached from the start, missing %s" % str(maps.keys().filter(func(k: int) -> bool: return not visited.has(k))))
	# back to the start from every map (reverse reachability)
	var back := {start: true}
	var changed := true
	while changed:
		changed = false
		for a: int in edges:
			if not back.has(a) and (edges[a] as Dictionary).keys().any(func(b: int) -> bool: return back.has(b)):
				back[a] = true
				changed = true
	eq(back.size(), maps.size(), "every map leads back to the start, not %s" % str(maps.keys().filter(func(k: int) -> bool: return not back.has(k))))


func test_exit_bits_select_the_side() -> void:
	var m := MapData.from_dict({"id": 1, "neighbors": {"top": 2, "left": 3, "right": 4},
			"map_change": {"0": 216, "13": 32, "2": 224, "167": 2, "196": 8}})
	eq(m.exit_dirs(0), PackedStringArray(["left", "top"]), "corner: bits 3, 4 (left) and 6, 7 (top)")
	eq(m.exit_dirs(13), PackedStringArray(["top"]), "top-right corner, bit 5 = north-west: top only")
	eq(m.exit_dirs(167), PackedStringArray(["right"]), "bit 1 on the right column")
	eq(m.exit_dirs(196), PackedStringArray(["left"]))
	eq(m.exit_dirs(3), PackedStringArray(), "edge cell without mapChangeData: no exit")
	var legacy := MapData.from_dict({"id": 1, "neighbors": {"top": 2}})
	eq(legacy.exit_dirs(3), PackedStringArray(["top"]), "no map_change (generated worlds): every edge cell")
	var back := MapData.from_dict(JSON.parse_string(JSON.stringify(
			MapData.from_dict({"id": 1, "map_change": {"5": 224}, "triggers": [{"cell": 40, "to_map": 9, "to_cell": 41}]}).to_dict())))
	eq(back.map_change, {5: 224}, "JSON round trip")
	eq(back.trigger_at(40), {"to_map": 9, "to_cell": 41})


func test_real_neighbour_without_passage_is_closed() -> void:
	# (0,-1) and (-1,-1) are neighbours in the map data, but no cell leads across (cliff)
	var m: MapData = _source().get_map(153878785)
	eq(m.neighbor("left"), 154010369)
	eq(m.exit_cells("left"), [] as Array[int], "mapChangeData: no left exit")


func test_change_map_only_from_an_exit_cell() -> void:
	var c := Conn.new()
	var m: MapData = _source().get_map(START)
	var edge := -1
	for cell in MapGeometry.CELL_COUNT: # a walkable top-edge cell that is not an exit
		if m.is_walkable(cell) and MapGeometry.is_edge(cell, "top") and not m.can_exit(cell, "top"):
			edge = cell
			break
	if edge >= 0:
		c.put(START, edge)
		c.send(Protocol.change_map("top"))
		eq(c.error(), Protocol.E_NO_EXIT, "edge cell %d without mapChangeData" % edge)
		eq(c.map_id(), START)
	var exit := m.exit_cells("top")[0]
	c.put(START, exit)
	c.send(Protocol.change_map("top"))
	eq(c.map_id(), m.neighbor("top"))
	var enter := c.last(Protocol.MAP_ENTER)
	eq(int(enter["map"]["subarea"]), 444, "subarea in map_enter")
	eq(int(enter["map"]["area"]), 45)
	eq(Array(enter["map"]["coords"]).map(func(x: Variant) -> int: return int(x)), [-1, -6])
	var here: MapData = _source().get_map(m.neighbor("top"))
	check(here.can_exit(c.player().cell, "bottom"), "arrived on a cell that leads back (%d)" % c.player().cell)
	c.send(Protocol.change_map("bottom"))
	eq(c.map_id(), START, "and back")


func test_a_door_leads_into_the_tavern_and_its_cellar() -> void:
	var c := Conn.new()
	var out: MapData = _source().get_map(TAVERN_OUT)
	var door := -1
	for cell: int in out.triggers:
		door = cell
	check(door >= 0, "door on the Route des âmes")
	eq(door, 326, "the door element (m_interactionId 489329) stands on cell 326")
	c.put(TAVERN_OUT, out.nearest_walkable(door + 56))
	c.send(Protocol.use_trigger(door))
	eq(c.error(), Protocol.E_NO_EXIT, "too far from the door")
	eq(c.map_id(), TAVERN_OUT)
	c.put(TAVERN_OUT, out.use_cells(door)[0])
	c.send(Protocol.use_trigger(door))
	eq(c.map_id(), TAVERN)
	check(not bool(c.last(Protocol.MAP_ENTER)["map"]["outdoor"]))
	var tavern: MapData = _source().get_map(TAVERN)
	var to_cellar := -1
	var to_out := -1
	for cell: int in tavern.triggers:
		if int(tavern.triggers[cell]["to_map"]) == CELLAR:
			to_cellar = cell
		else:
			to_out = cell
	c.put(TAVERN, tavern.use_cells(to_cellar)[0])
	c.send(Protocol.use_trigger(to_cellar))
	eq(c.map_id(), CELLAR)
	c.put(TAVERN, tavern.use_cells(to_out)[0])
	c.send(Protocol.use_trigger(to_out))
	eq(c.map_id(), TAVERN_OUT, "back outside")


## The Mine: its rooms are linked by doors only (no map-side exits); every
## door of the world leads to a walkable cell of a map of the world.
func test_the_mine_rooms_are_linked_by_doors() -> void:
	var maps := _maps()
	for id: int in MINE:
		check((maps[id] as MapData).map_change.is_empty(), "no side exit in Mine room %d" % id)
	for m: MapData in maps.values():
		for door: int in m.triggers:
			var t := m.trigger_at(door)
			check(maps.has(int(t["to_map"])), "door %d of %d leads into the world" % [door, m.id])
			check(not m.use_cells(door).is_empty(), "door %d of %d can be used" % [door, m.id])
	var c := Conn.new()
	var at: MapData = maps[MINE_DOOR_MAP]
	var room := -1
	for door: int in at.triggers:
		if MINE.has(int(at.triggers[door]["to_map"])):
			room = int(at.triggers[door]["to_map"])
			c.put(MINE_DOOR_MAP, at.use_cells(door)[0])
			c.send(Protocol.use_trigger(door))
	check(room > 0, "a door of the Pâturages leads into the Mine")
	eq(c.map_id(), room)
	var inside: MapData = maps[room]
	var next := -1
	for door: int in inside.triggers:
		var to := int(inside.triggers[door]["to_map"])
		if MINE.has(to) and next < 0:
			next = to
			c.put(room, inside.use_cells(door)[0])
			c.send(Protocol.use_trigger(door))
	eq(c.map_id(), next, "and deeper into the Mine")


## GM command tp (roadmap S.06): by map id (+ cell) or by coordinates; an outdoor
## map wins over an interior at the same coordinates (the Tavern is at (0,-3) too).
func test_admin_tp_by_map_id_and_by_coordinates() -> void:
	var c := Conn.new()
	c.send(Protocol.admin_cmd("tp", [str(MINE_DOOR_MAP), "300"]))
	eq(c.map_id(), MINE_DOOR_MAP, "tp <map id> <cell>")
	eq(int(c.last(Protocol.MAP_ENTER)["map"]["id"]), MINE_DOOR_MAP, "map_enter sent")
	c.send(Protocol.admin_cmd("tp", ["0", "-3"]))
	eq(c.map_id(), TAVERN_OUT, "tp <x> <y>: the outdoor map")
	c.send(Protocol.admin_cmd("tp", ["-1", "-5"]))
	eq(c.map_id(), START, "tp back to the Champs")
	check(c.backend.sim.get_map(START).data.is_walkable(c.player().cell), "lands on a walkable cell")


func test_admin_tp_refusals() -> void:
	var c := Conn.new()
	c.send(Protocol.admin_cmd("tp", ["123456789"]))
	eq(c.error(), Protocol.E_UNKNOWN_MAP, "no such map id")
	c.send(Protocol.admin_cmd("tp", ["500", "500"]))
	eq(c.error(), Protocol.E_UNKNOWN_MAP, "no map at these coordinates")
	c.send(Protocol.admin_cmd("tp", ["a", "b"]))
	eq(c.error(), Protocol.E_BAD_MESSAGE, "not numbers")
	c.send(Protocol.admin_cmd("fly", []))
	eq(c.error(), Protocol.E_UNKNOWN_COMMAND, "unknown GM command")
	eq(c.map_id(), START, "still at the start")
	c.player().gm = false
	c.send(Protocol.admin_cmd("tp", [str(TAVERN_OUT)]))
	eq(c.error(), Protocol.E_NOT_GM, "a command refused without the role")
	eq(c.map_id(), START, "not moved")


func test_command_line_parses_slash_commands() -> void:
	eq(CommandLine.parse("/tp 5,-18"), Protocol.admin_cmd("tp", ["5", "-18"]), "coordinates with a comma")
	eq(CommandLine.parse("  TP 153879812 300 "), Protocol.admin_cmd("tp", ["153879812", "300"]), "no slash, spaces")
	eq(CommandLine.parse("   "), {}, "empty line")


## Leaving Incarnam (world "dofus"): the element of the Route des âmes (4,-3) takes
## the player down to Astrub (6,-19) and the one there back up (JondoEmu routes,
## the way down: client world graph, the way up: Giny 2.68).
func test_down_to_astrub_and_back_up() -> void:
	var src := JsonWorldSource.for_world("dofus")
	var road: MapData = src.get_map(SOULS_ROAD)
	var temple: MapData = src.get_map(ASTRUB_TEMPLE)
	eq(int(road.trigger_at(174).get("to_map", 0)), ASTRUB_TEMPLE, "cell 174 of the Route des âmes leads to Astrub")
	eq(int(temple.trigger_at(455).get("to_map", 0)), SOULS_ROAD, "cell 455 of Astrub leads back to Incarnam")
	var c := Conn.new("dofus")
	c.put(SOULS_ROAD, road.use_cells(174)[0])
	c.send(Protocol.use_trigger(174))
	eq(c.map_id(), ASTRUB_TEMPLE, "down to Astrub")
	eq(int(c.last(Protocol.MAP_ENTER)["map"]["area"]), 18, "area 18: Astrub")
	c.put(ASTRUB_TEMPLE, temple.use_cells(455)[0])
	c.send(Protocol.use_trigger(455))
	eq(c.map_id(), SOULS_ROAD, "back up to Incarnam")
