## Moving around (WorldSim handler): walking, map exits, doors (P1.07), zaaps and the
## save point (P1.08), the GM teleport (S.06).
class_name WorldTravel
extends WorldHandler


func on_move(p: PlayerActor, map: MapInstance, target: int, run: bool) -> void:
	if not map.data.is_walkable(target):
		p.outbox.append(Protocol.error(Protocol.E_BAD_CELL, "cell %d not walkable" % target, Protocol.MOVE))
		return
	var r := Movement.replan(p.path, p.t0, p.run, p.cell, sim.now, target, map.pathfinder)
	if r["path"].is_empty():
		if p.dest_cell() != target:
			p.outbox.append(Protocol.error(Protocol.E_UNREACHABLE, "no path to %d" % target, Protocol.MOVE))
		return
	map.move_actor(p, r["path"], r["t0"], run)


func on_change_map(p: PlayerActor, map: MapInstance, dir: String) -> void:
	# accepted once the player stands on (or is walking to) an exit cell of that side
	# (cellsData.mapChangeData: MapData.can_exit)
	var cell := p.dest_cell()
	var next_id := map.data.neighbor(dir)
	if not map.data.can_exit(cell, dir):
		p.outbox.append(Protocol.error(Protocol.E_NO_EXIT, "cannot leave through %s from cell %d" % [dir, cell], Protocol.CHANGE_MAP))
		return
	var next := sim.get_map(next_id)
	if next == null:
		p.outbox.append(Protocol.error(Protocol.E_NO_EXIT, "map %d missing" % next_id, Protocol.CHANGE_MAP))
		return
	sim.teleport(p, next.data.id, next.data.arrival_cell(MapGeometry.mirror_cell(cell, dir), dir))


## use_trigger: the door / stairs on `cell` (MapData.triggers), used like any
## interactive element from the cell itself or a cell beside it (MapData.use_cells).
func on_use_trigger(p: PlayerActor, map: MapInstance, cell: int) -> void:
	var t := map.data.trigger_at(cell)
	if t.is_empty() or not map.data.use_cells(cell).has(p.dest_cell()) or sim.get_map(int(t["to_map"])) == null:
		p.outbox.append(Protocol.error(Protocol.E_NO_EXIT, "no trigger on cell %d" % cell, Protocol.USE_TRIGGER))
		return
	var dest := sim.get_map(int(t["to_map"]))
	sim.teleport(p, dest.data.id, dest.data.nearest_walkable(int(t["to_cell"])))


# ── zaaps (P1.08) ──────────────────────────────────────────────────────────────

## "" when the player stands next to the zaap of `map` (MapData.use_cells), else the error.
func at_zaap(p: PlayerActor, map: MapInstance) -> String:
	if map.data.zaap < 0 or not map.data.use_cells(map.data.zaap).has(p.dest_cell()):
		return Protocol.E_NOT_AT_ZAAP
	return ""


## The known zaaps a player can travel to from the zaap of `here`, with their price.
func zaap_destinations(c: Character, here: MapData) -> Array:
	var out := []
	for id: int in c.known_zaaps:
		if id == here.id or not sim.source.has_map(id):
			continue
		var m := sim.get_map(id).data
		out.append({"map": id, "name_id": m.name_id, "area_name_id": m.area_name_id, "coords": [m.coords.x, m.coords.y],
				"cost": Travel.zaap_cost(here.coords, m.coords, here.area)})
	return out


func on_use_zaap(p: PlayerActor, map: MapInstance) -> void:
	var err := at_zaap(p, map)
	if err != "":
		p.outbox.append(Protocol.error(err, "", Protocol.USE_ZAAP))
		return
	p.outbox.append(Protocol.zaap_list(map.data.id, zaap_destinations(p.character, map.data), p.character.save_map))


func on_zaap_travel(p: PlayerActor, map: MapInstance, dest_id: int) -> void:
	var err := at_zaap(p, map)
	var dest: Dictionary = {}
	for d: Dictionary in zaap_destinations(p.character, map.data):
		if int(d["map"]) == dest_id:
			dest = d
	if err == "" and dest.is_empty():
		err = Protocol.E_UNKNOWN_ZAAP
	if err == "" and p.character.kamas < int(dest["cost"]):
		err = Protocol.E_NOT_ENOUGH_KAMAS
	if err != "":
		p.outbox.append(Protocol.error(err, "", Protocol.ZAAP_TRAVEL))
		return
	p.character.kamas -= int(dest["cost"])
	var to := sim.get_map(dest_id).data
	sim.teleport(p, dest_id, to.nearest_walkable(to.zaap))
	p.outbox.append(Protocol.player_stats(p.character.public_dict(sim.now)))


## Save point = this zaap (the cell beside it where zaap trips arrive).
func on_set_save_point(p: PlayerActor, map: MapInstance) -> void:
	var err := at_zaap(p, map)
	if err != "":
		p.outbox.append(Protocol.error(err, "", Protocol.SET_SAVE_POINT))
		return
	p.character.save_map = map.data.id
	p.character.save_cell = map.data.nearest_walkable(map.data.zaap)
	p.outbox.append(Protocol.player_stats(p.character.public_dict(sim.now)))
	sim.save_player(p)


## The save point [map id, cell]: Character.save_map, else the world's start.
func save_point(c: Character) -> Array:
	if c.save_map >= 0 and sim.source.has_map(c.save_map):
		var m := sim.get_map(c.save_map)
		return [c.save_map, m.data.nearest_walkable(c.save_cell)]
	var start := sim.get_map(int(sim.info.get("start_map", 0)))
	return [start.data.id, start.data.nearest_walkable(int(sim.info.get("start_cell", 0)))]


## What the client shows of a known zaap (world map markers).
func add_zaap_info(c: Character, id: int) -> void:
	if not sim.source.has_map(id):
		return
	var m := sim.source.get_map(id)
	c.zaap_info[id] = {"map": id, "coords": [m.coords.x, m.coords.y], "name_id": m.name_id,
			"area_name_id": m.area_name_id, "world_map": m.world_map}


# ── GM command tp (roadmap S.06; the other GM commands: WorldAdmin, A1.01) ─────

## tp <map id> [cell] | <x> <y> [world_map]: "" when done, else the error code ("detail" in `sim.admin.detail`).
func admin_tp(p: PlayerActor, args: Array) -> String:
	var n: Array[int] = []
	for a: Variant in args:
		if not str(a).strip_edges().is_valid_int():
			sim.admin.detail = "not a number: %s" % str(a)
			return Protocol.E_BAD_MESSAGE
		n.append(int(str(a)))
	var dest := tp_destination(p, n)
	if dest.is_empty():
		sim.admin.detail = "no map %s" % str(n)
		return Protocol.E_UNKNOWN_MAP
	var m := sim.get_map(dest[0])
	var cell := m.data.nearest_walkable(dest[1])
	p.settle(sim.now)
	sim.teleport(p, m.data.id, cell if cell >= 0 else dest[1])
	return ""


## tp arguments -> [map id, cell] or []: [map id, cell?] (a map id is far above any
## coordinate), or [x, y, world_map?]. Several maps share coordinates (worlds,
## interiors, old maps): the given world_map, else the current map's, else Amakna (1);
## then the map the world map shows there (priority), outdoor maps, the smallest id.
func tp_destination(p: PlayerActor, n: Array[int]) -> Array:
	const CENTRE := 300
	if n.size() in [1, 2] and absi(n[0]) > 10000:
		return [n[0], n[1] if n.size() > 1 else CENTRE] if sim.source.has_map(n[0]) else []
	if n.size() not in [2, 3]:
		return []
	var here := sim.get_map(p.map_id)
	var worlds: Array = [n[2]] if n.size() > 2 else [here.data.world_map if here != null else 1, 1]
	var found: Array = sim.source.find_maps(n[0], n[1])
	for w: Variant in worlds + [null]:
		var list := found.filter(func(c: Array) -> bool: return w == null or int(c[1]) == int(w))
		if n.size() > 2 and w == null:
			break
		if list.is_empty():
			continue
		list.sort_custom(func(a: Array, b: Array) -> bool:
			var pa := a.size() > 3 and bool(a[3])
			var pb := b.size() > 3 and bool(b[3])
			if pa != pb:
				return pa
			if bool(a[2]) != bool(b[2]):
				return bool(a[2])
			return int(a[0]) < int(b[0]))
		if sim.source.has_map(int(list[0][0])):
			return [int(list[0][0]), CENTRE]
	return []
