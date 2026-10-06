## Static description of one map, as the client receives it (`map_enter`).
## Spawn tables and other server-only data are NOT here (see WorldSource).
class_name MapData
extends RefCounted

var id := 0
var name := ""
## localized name (Dofus i18n id of the subarea), 0 = use `name`
var name_id := 0
## Dofus map whose graphics the client draws (Content/Maps/<visual>.json), 0 = placeholder ground
var visual := 0
## world coordinates of the map (Dofus-style [x, y])
var coords := Vector2i.ZERO
## set of non-walkable cellIds (cellId -> true), roleplay
var blocked := {}
## same in fight, and cells that block line of sight (both default to `blocked`)
var fight_blocked := {}
var los_blocked := {}
## fight placement cells: {"red": [cellId], "blue": [cellId]} (may be empty)
var placement := {"red": [], "blue": []}
## "left"/"right"/"top"/"bottom" -> neighbour map id (missing = no exit)
var neighbors := {}
## subarea / area (Dofus subareas.id, areas.id), 0 = none; false for interiors (mapsinformation.worldMap = -1)
var subarea := 0
var area := 0
## localized area name (i18n id of areas.nameId), 0 = none
var area_name_id := 0
var outdoor := true
## cellsData.mapChangeData: cellId -> bits, bit i = the cell leads out in Dofus
## direction i (0 east, 1 south-east ... 7 north-east, clockwise on screen).
## Empty = every edge cell is an exit (generated worlds).
var map_change := {}
## cell triggers (doors, stairs): cellId -> {"to_map", "to_cell"}. The cell is the
## door's interactive element in the client map (m_interactionId + cellId); where it
## leads is server data: JondoEmu dumps (tools/extractor/jondo.py: Giny 2.68 rows matched
## to the element, else the 2.73 world graph, whose arrival is the door back), or
## worlds/<id>/links.json. Used from the cell or beside it (use_cells).
var triggers := {}
## zaap standing on this map (Dofus waypoints.mapId): its cell, -1 = none.
## APPROX(P1.08): the cell (the interactive's position) is picked on a capture (links.json)
var zaap := -1
## world map this map is drawn on (mapsinformation.worldMap, worldmaps.id), -1 = none (interiors)
var world_map := -1
## map capabilities (mapsinformation.m_flags = Dofus 2 MapPosition.capabilities):
## bit 13 ALLOW_MONSTER_RESPAWN (monster groups spawn here: not on zaap maps, not in
## the Tavern), bit 20 ALLOW_MONSTER_AGRESSION (aggressive groups may attack)
var monster_spawn := true
var monster_aggression := true
## bit 9 ALLOW_TAVERN_REGEN: energy comes back twice as fast when logged out here (Energy)
var tavern := false
## resurrection phoenix standing on this map: its cell, -1 = none (Energy).
## APPROX(P1.10): phoenix positions are server data, absent from the client and
## from the JondoEmu dumps: picked on a capture (links.json)
var phoenix := -1
## harvestable elements (P2.05): [{e: element id, cell, gfx, skill: skills.id}]. Server data
## (worlds/<id>/interactives.json, WorldSource.get_map): the sim sets and shows their state
var interactives: Array = []
## two ground tints (checkerboard) until real map graphics exist
var ground: Array[Color] = [Color("#5a7a4a"), Color("#557245")]


func is_walkable(cell: int) -> bool:
	return MapGeometry.is_valid(cell) and not blocked.has(cell)


func is_fight_walkable(cell: int) -> bool:
	return MapGeometry.is_valid(cell) and not fight_blocked.has(cell)


func blocks_los(cell: int) -> bool:
	return los_blocked.has(cell)


func neighbor(dir: String) -> int:
	return int(neighbors.get(dir, -1))


## Dofus directions leading out through each side (source: cellsData.mapChangeData
## of the Incarnam maps: top row cells carry bits 5-7, left column 3-5, right
## column 7, 0, 1, bottom rows 1-3; a corner cell's bit 5 or 7 is shared by two sides).
const SIDE_BITS := {"right": 0x83, "bottom": 0x0E, "left": 0x38, "top": 0xE0}


## Sides this cell leads out through, toward an existing neighbour map.
func exit_dirs(cell: int) -> PackedStringArray:
	var out := PackedStringArray()
	for dir in MapGeometry.edge_dirs(cell):
		if neighbor(dir) < 0:
			continue
		if map_change.is_empty() or int(map_change.get(cell, 0)) & int(SIDE_BITS[dir]) != 0:
			out.append(dir)
	return out


func can_exit(cell: int, dir: String) -> bool:
	return is_walkable(cell) and exit_dirs(cell).has(dir)


## Cells from which the player may leave through `dir`.
func exit_cells(dir: String) -> Array[int]:
	var out: Array[int] = []
	for c in MapGeometry.CELL_COUNT:
		if can_exit(c, dir):
			out.append(c)
	return out


## Cells from which an interactive element (zaap…) standing on `cell` is used:
## the walkable cells next to it (Dofus walks the player beside the element),
## else the closest walkable cell.
func use_cells(cell: int) -> Array[int]:
	var out: Array[int] = []
	if is_walkable(cell):
		out.append(cell)
	for n in MapGeometry.neighbors(cell):
		if is_walkable(n):
			out.append(n)
	if out.is_empty() and nearest_walkable(cell) >= 0:
		out.append(nearest_walkable(cell))
	return out


## The door (trigger cell) a click on `cell` means: the door's own cell, or a
## blocked cell touching it (the door's sprite covers them), -1 if none.
func door_near(cell: int) -> int:
	if triggers.has(cell):
		return cell
	if is_walkable(cell):
		return -1
	for n in MapGeometry.neighbors(cell):
		if triggers.has(n):
			return n
	return -1


## The harvestable element a click on `cell` means: on its own cell, or on a blocked cell
## touching it (the sprite of a tree covers them); {} if none.
func interactive_near(cell: int) -> Dictionary:
	for el: Dictionary in interactives:
		if int(el["cell"]) == cell:
			return el
	if is_walkable(cell):
		return {}
	for el: Dictionary in interactives:
		if MapGeometry.neighbors(int(el["cell"])).has(cell):
			return el
	return {}


## The harvestable element `e`, {} if none.
func interactive(e: int) -> Dictionary:
	for el: Dictionary in interactives:
		if int(el["e"]) == e:
			return el
	return {}


## The trigger on `cell` ({"to_map", "to_cell"}), {} if none.
func trigger_at(cell: int) -> Dictionary:
	return triggers.get(cell, {})


## Where a player coming from the `dir` side of the previous map arrives
## (entering through the opposite side): the mirrored cell, else the closest
## walkable cell that leads back, else the closest walkable cell.
func arrival_cell(mirrored: int, came_through: String) -> int:
	var back := MapGeometry.opposite(came_through)
	var leads_back := func(c: int) -> bool: return can_exit(c, back)
	if is_walkable(mirrored) and (map_change.is_empty() or neighbor(back) < 0 or leads_back.call(mirrored)):
		return mirrored
	var c := nearest(mirrored, leads_back) if neighbor(back) >= 0 else -1
	return c if c >= 0 else nearest_walkable(mirrored)


## Walkable cell closest to `cell` (breadth-first over the lattice), -1 if none.
func nearest_walkable(cell: int) -> int:
	return nearest(cell, is_walkable)


## Cell closest to `cell` (breadth-first over the lattice) for which `ok` is true, -1 if none.
func nearest(cell: int, ok: Callable) -> int:
	if ok.call(cell):
		return cell
	var seen := {cell: true}
	var queue: Array[int] = [cell]
	while not queue.is_empty():
		var c: int = queue.pop_front()
		for n in MapGeometry.neighbors(c):
			if seen.has(n):
				continue
			if ok.call(n):
				return n
			seen[n] = true
			queue.append(n)
	return -1


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"name_id": name_id,
		"visual": visual,
		"coords": [coords.x, coords.y],
		"blocked": _sorted(blocked),
		"fight_blocked": _sorted(fight_blocked),
		"los_blocked": _sorted(los_blocked),
		"placement": placement.duplicate(true),
		"neighbors": neighbors.duplicate(),
		"subarea": subarea,
		"area": area,
		"area_name_id": area_name_id,
		"outdoor": outdoor,
		"map_change": _str_keys(map_change),
		"zaap": zaap,
		"world_map": world_map,
		"monster_spawn": monster_spawn,
		"monster_aggression": monster_aggression,
		"tavern": tavern,
		"phoenix": phoenix,
		"triggers": _str_keys(triggers),
		"interactives": interactives.duplicate(true),
		"ground": [ground[0].to_html(false), ground[1].to_html(false)],
	}


## Accepts JSON-parsed data (numbers may be floats).
static func from_dict(d: Dictionary) -> MapData:
	var m := MapData.new()
	m.id = int(d.get("id", 0))
	m.name = str(d.get("name", ""))
	m.name_id = int(d.get("name_id", d.get("subarea_name_id", 0)))
	m.visual = int(d.get("visual", 0))
	var c: Array = d.get("coords", [0, 0])
	m.coords = Vector2i(int(c[0]), int(c[1]))
	for cell: Variant in d.get("blocked", []):
		m.blocked[int(cell)] = true
	for cell: Variant in d.get("fight_blocked", d.get("blocked", [])):
		m.fight_blocked[int(cell)] = true
	for cell: Variant in d.get("los_blocked", d.get("blocked", [])):
		m.los_blocked[int(cell)] = true
	var p: Dictionary = d.get("placement", {})
	for team: String in ["red", "blue"]:
		m.placement[team] = (p.get(team, []) as Array).map(func(x: Variant) -> int: return int(x))
	var n: Dictionary = d.get("neighbors", {})
	for dir: String in n:
		m.neighbors[dir] = int(n[dir])
	m.subarea = int(d.get("subarea", 0))
	m.area = int(d.get("area", 0))
	m.area_name_id = int(d.get("area_name_id", 0))
	m.outdoor = bool(d.get("outdoor", true))
	m.zaap = int(d.get("zaap", -1))
	m.world_map = int(d.get("world_map", -1))
	m.monster_spawn = bool(d.get("monster_spawn", true))
	m.monster_aggression = bool(d.get("monster_aggression", true))
	m.tavern = bool(d.get("tavern", false))
	m.phoenix = int(d.get("phoenix", -1))
	var mc: Dictionary = d.get("map_change", {})
	for cell: Variant in mc:
		m.map_change[int(cell)] = int(mc[cell])
	var tr: Variant = d.get("triggers", [])
	# a list [{cell, to_map, to_cell}] (world files) or a dict cell -> {to_map, to_cell} (to_dict)
	var entries: Array = tr if tr is Array else (tr as Dictionary).keys().map(
			func(k: Variant) -> Dictionary: return (tr[k] as Dictionary).merged({"cell": k}))
	for t: Dictionary in entries:
		m.triggers[int(t["cell"])] = {"to_map": int(t["to_map"]), "to_cell": int(t["to_cell"])}
	for el: Dictionary in d.get("interactives", []):
		m.interactives.append({"e": int(el["e"]), "cell": int(el["cell"]), "gfx": int(el.get("gfx", 0)), "skill": int(el["skill"])})
	var g: Array = d.get("ground", [])
	if g.size() >= 2:
		m.ground = [Color(str(g[0])), Color(str(g[1]))]
	return m


static func _str_keys(d: Dictionary) -> Dictionary:
	var out := {}
	for k: Variant in d:
		out[str(k)] = d[k].duplicate() if d[k] is Dictionary else d[k]
	return out


static func _sorted(set: Dictionary) -> Array:
	var out := set.keys()
	out.sort()
	return out
