## Where a world's data comes from. The sim only talks to this interface, so a
## world can be JSON files (JsonWorldSource), built in code (tests), or later the
## real Dofus maps decoded from the client data.
##
## Data layout (see worlds/test for an example):
##   info  {id, name, start_map, start_cell, wander_ms: [min, max]}
##   map   MapData dict + "groups": [{"looks": [look, ...]}]   (fixed spawns, sim-only)
##   monsters  {subareas: {id: {level, area, monsters}}, monsters: {id: {grades}}}
##         (real worlds: the sim composes the groups, MonsterSpawner)
class_name WorldSource
extends RefCounted

var _info := {}
var _maps := {} # map id -> raw dict
var _monsters := {}
var _npcs := {} # map id -> [{npc, cell, dir}]
var _shops := {} # npcs.id -> {items: [items.id]} (P2.02, shops.json)
var _bankers := [] # npcs.id of the bankers (bank.json, P2.08)
var _dialogs := {} # npcs.id -> Dialog tree (hand-written; the others get Dialog.default_for)
var _quests := {} # quest id -> quest (quests.json, P2.03; see QuestEngine)
var _interactives := {} # map id -> [{e, cell, gfx, skill}] (interactives.json, P2.05)
var _coords := {} # "x,y" -> [[map id, world_map, outdoor, priority?]] (find_maps, built on first use)


## Build a world from plain dictionaries (handy for tests and generated worlds).
static func from_dicts(info: Dictionary, maps: Array, monsters := {}) -> WorldSource:
	var s := WorldSource.new()
	s._info = info
	s._monsters = monsters
	for m: Dictionary in maps:
		s._maps[int(m["id"])] = m
	return s


func get_info() -> Dictionary:
	return _info


## An instance of this content (roadmap S.04b): the same data under another world id, so saves and
## lists (which key on `info.id`) are separate; `info.content` names the content it reads.
## The data is shared (read-only), only the info differs.
func instance(p_id: String, p_name := "") -> WorldSource:
	var s: WorldSource = get_script().new()
	for p: Dictionary in get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			s.set(p["name"], get(p["name"]))
	s._info = _info.duplicate()
	s._info["content"] = str(_info.get("content", _info.get("id", "")))
	s._info["id"] = p_id
	s._info["name"] = p_name if p_name != "" else p_id
	return s


func has_map(id: int) -> bool:
	return _maps.has(id) or _load_map(id)


func get_map(id: int) -> MapData:
	if not has_map(id):
		return null
	var m := MapData.from_dict(_maps[id])
	if _interactives.has(id):
		m.interactives = _interactives[id].duplicate(true)
	return m


## Harvestable elements of the maps (tests, generated worlds): {map id: [{e, cell, gfx?, skill}]}.
func set_interactives(by_map: Dictionary) -> void:
	_interactives = {}
	for m: Variant in by_map:
		_interactives[int(m)] = (by_map[m] as Array).map(func(el: Dictionary) -> Dictionary:
			return {"e": int(el["e"]), "cell": int(el["cell"]), "gfx": int(el.get("gfx", 0)), "skill": int(el["skill"])})


## The world's monsters by subarea (monsters.json), {} for hand-made worlds.
func get_monsters() -> Dictionary:
	return _monsters


## Fixed monster groups of a map: [{"looks": [...]}] (hand-made worlds).
func get_spawns(id: int) -> Array:
	return _maps[id].get("groups", []) if has_map(id) else []


## Maps at coordinates (x, y): [[map id, world_map, outdoor, priority?], ...] (admin tp);
## priority = the map the world map shows there (mapsinformation hasPriorityOnWorldmap).
func find_maps(x: int, y: int) -> Array:
	if _coords.is_empty():
		_coords = _coords_index()
	return _coords.get("%d,%d" % [x, y], [])


## Coordinates index of every map of info.maps (small worlds: reads them all).
func _coords_index() -> Dictionary:
	var out := {}
	for id: Variant in _info.get("maps", _maps.keys()):
		var m := get_map(int(id))
		if m != null:
			var key := "%d,%d" % [m.coords.x, m.coords.y]
			var list: Array = out.get(key, [])
			list.append([m.id, m.world_map, m.outdoor])
			out[key] = list
	return out


## The NPCs standing on a map: [{npc, cell, dir}] (npcs.json, P2.01).
func get_npcs(id: int) -> Array:
	return _npcs.get(id, [])


## The hand-written dialog tree of an NPC template, {} when it has none.
func get_dialog(npc_id: int) -> Dictionary:
	return _dialogs.get(npc_id, {})


## What an NPC template sells: {items: [items.id]}, {} when it has no shop (worlds/<id>/shops.json, APPROX(P2.02)).
func get_shop(npc_id: int) -> Dictionary:
	return _shops.get(npc_id, {})


## Is this NPC template a banker (it opens the account chest)? (worlds/<id>/bank.json, P2.08)
func is_banker(npc_id: int) -> bool:
	return _bankers.has(npc_id)


func set_bankers(ids: Array) -> void:
	_bankers = ids.map(func(i: Variant) -> int: return int(i))


## Give NPC templates a shop (tests, generated worlds): {npc id: {items: [items.id]}}.
func set_shops(shops: Dictionary) -> void:
	_shops = {}
	for n: Variant in shops:
		_shops[int(n)] = shops[n]


## Place NPCs (tests, generated worlds): {map id: [{npc, cell, dir}]} and {npc id: Dialog tree}.
func set_npcs(by_map: Dictionary, dialogs := {}) -> void:
	_npcs = {}
	for m: Variant in by_map:
		_npcs[int(m)] = by_map[m]
	_dialogs = {}
	for n: Variant in dialogs:
		_dialogs[int(n)] = dialogs[n]


## The quests of the world {quest id: quest} (worlds/<id>/quests.json, QuestEngine).
func get_quests() -> Dictionary:
	return _quests


func set_quests(quests: Dictionary) -> void:
	_quests = {}
	for q: Variant in quests:
		_quests[int(q)] = quests[q]


## Monster groups mods add to a map (Mods), spawned after its own groups.
func get_mod_spawns(_id: int) -> Array:
	return []


## Lazy loading hook for subclasses (big worlds should not load every map up front).
func _load_map(_id: int) -> bool:
	return false
