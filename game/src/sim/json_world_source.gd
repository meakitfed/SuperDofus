## World stored as JSON files: <root>/world.json + <root>/maps/<id>.json
## (+ <root>/monsters.json and <root>/npcs.json for real worlds).
## Maps are read lazily, on first access.
class_name JsonWorldSource
extends WorldSource

var root := ""
var _mod_groups := {} # map id -> [spawn] (Mods)


func _init(p_root := "") -> void:
	root = p_root.trim_suffix("/")
	if root == "":
		return
	var info: Variant = _read(root + "/world.json")
	if info is Dictionary:
		_info = info
	else:
		push_error("JsonWorldSource: no world.json in " + root)
	var monsters: Variant = _read(root + "/monsters.json")
	if monsters is Dictionary:
		_monsters = monsters
	var npcs: Variant = _read(root + "/npcs.json")
	if npcs is Dictionary:
		set_npcs(npcs.get("maps", {}), npcs.get("dialogs", {}))
	var shops: Variant = _read(root + "/shops.json")
	if shops is Dictionary:
		set_shops(shops.get("shops", {}))
	var bank: Variant = _read(root + "/bank.json")
	if bank is Dictionary:
		set_bankers(bank.get("bankers", []))
		for m: Variant in bank.get("placed", {}): # bankers the real data does not place in this world (APPROX(P2.08))
			var list: Array = _npcs.get(int(m), [])
			list.append_array(bank["placed"][m])
			_npcs[int(m)] = list
	var quests: Variant = _read(root + "/quests.json")
	if quests is Dictionary:
		set_quests(quests.get("quests", {}))
	var interactives: Variant = _read(root + "/interactives.json")
	if interactives is Dictionary:
		set_interactives(interactives.get("maps", {}))
	_merge_mods()


## Mods add monsters (never over existing ids) and groups on given maps.
func _merge_mods() -> void:
	for mod: Dictionary in Mods.read_all("worlds/%s/monsters.json" % str(_info.get("id", ""))):
		if not _monsters.has("monsters"):
			_monsters["monsters"] = {}
		var db: Dictionary = _monsters["monsters"]
		var add: Dictionary = mod.get("monsters", {})
		for mid: String in add:
			if not db.has(mid):
				db[mid] = add[mid]
		var groups: Dictionary = mod.get("groups", {})
		for map_id: String in groups:
			var list: Array = _mod_groups.get(int(map_id), [])
			list.append_array(groups[map_id])
			_mod_groups[int(map_id)] = list


func get_mod_spawns(id: int) -> Array:
	return _mod_groups.get(id, [])


static func for_world(world_id: String) -> JsonWorldSource:
	return JsonWorldSource.new("worlds/" + world_id)


## Big worlds ship <root>/coords.json (maps.py full) instead of reading every map.
func _coords_index() -> Dictionary:
	var c: Variant = _read(root + "/coords.json")
	return c if c is Dictionary else super()


func _load_map(id: int) -> bool:
	var m: Variant = _read("%s/maps/%d.json" % [root, id])
	if m is Dictionary:
		_maps[id] = m
		return true
	return false


static func _read(path: String) -> Variant:
	return DataFiles.read_json(path)
