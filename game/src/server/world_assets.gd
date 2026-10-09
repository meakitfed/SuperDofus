## Which assets of `content/` a world really uses (roadmap C.02b): the list a package ships so that
## the light client has its images in cache mode, instead of the 22 GB of the content folder.
##
## The result is a list of logical paths / globs for `WorldPackage` (`worlds/<id>/_content.json`,
## written by tools/world_assets.gd). It is computed from what the renderer and the UI read:
##   maps       Content/Maps/<id>.json of every map of the world, the Gfx textures their layers draw
##              (Maps/Gfx/<g>), the animated props (Animations/Props/<g>/*)
##   entities   the looks of the monsters (monsters.json), NPCs (npcs.json + the npcs table), summons
##              (spells.json), of every playable body / face (breeds, bodies, heads) and of the items the
##              world gives (drops, shops, quests, recipes: items.json `skin`): the bone folders (all the
##              bundles of a family) and the skin folders they name, sub-entities included
##   base       what any world needs: interface, fonts, pictos (spells, items, monsters), world maps,
##              texts (I18n) and the few raw tables the renderer reads in Content/Data
## Folders are listed as `dir/*`; single files (maps, Gfx) as literal paths, so that building the
## package never walks the 62 000 files of Maps/Gfx.
##
## Pure data and file reads under `root` (the folder holding worlds/, data/, content/): no Node, no
## static state of the game, so a test can point it at a tiny fixture. Server side only.
##
## APPROX(C.02b): an item the world never hands out (admin `give`, an item of another world) has no
## skin in the package: the player is drawn without it. Looks the sim builds from nothing (the
## fallback bone 666) are covered by `base`.
class_name WorldAssets
extends RefCounted

const CONTENT := "content/Content"
## where the globs go, next to world.json (leading "_": not shipped as world data, WorldPackage reads it)
const FILE := "_content.json"
## Content/Data tables the renderer / client read raw (not in data/tables): see test_world_assets
## (the trace of a play-through must find nothing outside the package).
const RAW_TABLES: PackedStringArray = ["bodies", "breeds", "skinslotsrules"]
## whole folders every world needs (one glob each)
const BASE_FOLDERS: PackedStringArray = ["Fonts", "UI", "I18n", "Worldmaps", "Picto/Spells", "Picto/Items", "Picto/Monsters"]
const FALLBACK_BONE := "666"
## C.02e: the zone of a playable class is `class_<breeds.id>`
const CLASS_PREFIX := "class_"
## C.02g: the skins of the items leave the base for one zone, and the monsters of a heavy sub-area for
## the zone `<zone>-m` that each block of it requires
const EQUIPMENT_ZONE := "equipment"
const MONSTER_SUFFIX := "-m"
## C.02g: what every block of a sub-area needs alike (the NPCs standing on all its maps...): `<zone>-c<n>`
const COMMON_SUFFIX := "-c"

var root := ""
var world_id := ""
## C.02e: a zone heavier than this (what it adds to the base) is cut into blocks of neighbouring maps
var zone_max_bytes := 150 * 1048576
var _out := {} # glob -> true
## what the last compute found (for the report): {maps, gfx, props, bones, skins, looks, items}
var stats := {}
var missing := PackedStringArray() # referenced but absent from content/ (not an error: extraction is partial)
var _bones := {} # bone name -> true
var _skins := {} # skin id -> true
var _items := {} # item id -> true
var _gathered := {} # C.02g: the items of `_gather_items` (shops, quests, recipes), whose skins go to the equipment zone
var _families: Dictionary = {}
var _looks := {}
# what _load reads once (a zoned compute runs the passes below thousands of times)
var _def: Dictionary = {}
var _monsters: Variant = null
var _npcs: Variant = null
var _npc_table := {}
var _item_skin := {} # item id -> skin id (data/items.json)
var _loaded := false
## C.02e: compute_zoned keeps the class assets out of the passes; `_class_breed` > 0 = the pass of that class
var _split_classes := false
var _class_breed := 0
## C.02g: in a split compute the skins of the gathered items (shops...) stay out of the passes (`_equipment_pass` adds them), and
## `_extra_zones` holds the `-m` / `-c` zones that `_split` hoisted out of the blocks of a sub-area
var _split_equipment := false
var _equipment_pass := false
var _extra_zones := {} # zone id -> entry
var _breed_ids := {}
var _player_bones := {} # bone ids of the breeds' looks (the families that hold class bundles)
var _size_memo := {} # glob -> bytes
var _image_memo := {} # path without extension -> the file that exists ("" = none)


func _init(p_root: String, p_world: String) -> void:
	root = p_root.replace("\\", "/").trim_suffix("/")
	world_id = p_world


## Sorted globs of the world (everything in one list), [] when the world is unknown.
func compute() -> PackedStringArray:
	missing = PackedStringArray()
	if not _load():
		return PackedStringArray()
	_reset()
	_maps_of(_def.get("maps", []))
	if _monsters is Dictionary:
		for m: Dictionary in (_monsters.get("monsters", {}) as Dictionary).values():
			_monster(m)
	if _npcs is Dictionary:
		for list: Array in (_npcs.get("maps", {}) as Dictionary).values():
			_npc_list(list)
	_world_wide()
	return _finish()


## C.02c: the same assets split by zone, for a client that downloads only what it walks to.
## `world.json` `zone_key` names the field of `worlds/<id>/maps/<map>.json` that groups the maps
## ("subarea"); without it the world is not zoned and {} comes back. Result:
##   {base: globs (what every client needs, with the zone of start_map),
##    start_zone: id,
##    zones: {id: {maps: [ids], files: {dir: [names]}, dirs: [globs], bytes}}}
## A zone lists every file its maps need that the base does not hold, even a file another zone also
## needs (the client downloads each distinct file once). Files are grouped by folder (`files`), which
## keeps the list of 17 000 maps small. With `zone_key` "subarea", monsters.json `subareas` gives the
## monsters of a zone and npcs.json the NPCs of its maps.
## C.02e: (1) a zone heavier than `zone_max_bytes` is cut into blocks of neighbouring maps (ids
## `<zone>-<n>`, see `_split`); the block holding start_map is the one the base carries. (2) the
## skeletons and creation skins of each playable class leave the base: zone `class_<breed>`
## (`CLASS_PREFIX`, no map), downloaded when a character of that class is shown.
## C.02g: (1) the skins of the items the world gives leave the base for the zone `equipment` (`skins` lists
## their ids: the client asks for it when it sees one worn). (2) when the monsters weigh more than half
## of a zone that has to be cut, they go to `<zone>-m` (no map) and each block `requires` it.
func compute_zoned() -> Dictionary:
	missing = PackedStringArray()
	if not _load():
		return {}
	var key := str(_def.get("zone_key", ""))
	if key == "":
		return {}
	_split_classes = true
	_split_equipment = true
	_class_breed = 0
	_extra_zones = {}
	var by_zone := _zone_maps(key)
	var start_map := int(_def.get("start_map", -1))
	var start := ""
	for z: String in by_zone:
		if (by_zone[z] as Array).has(start_map):
			start = z
	# the base without any zone: what the start zone is measured against
	_reset()
	_world_wide()
	var base0 := _set_of(_finish())
	var blocks := {} # zone -> [[block id, maps]]
	var start_block := ""
	var start_maps: Array = []
	if start != "":
		blocks[start] = _split(key, start, by_zone[start], base0, false)
		for b: Array in blocks[start]:
			if (b[1] as Array).has(start_map):
				start_block = str(b[0])
				start_maps = b[1]
	_reset()
	_world_wide()
	if start_block != "":
		_zone_pass(key, start, start_maps)
	var base := _finish()
	var base_set := _set_of(base)
	var ids := by_zone.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return (int(a) < int(b)) if a.is_valid_int() and b.is_valid_int() else a < b)
	var zones := {}
	var worst := 0
	for z: String in ids:
		var list: Array = blocks[z] if blocks.has(z) else _split(key, z, by_zone[z], base_set)
		for b: Array in list:
			var id := str(b[0])
			if id == start_block:
				zones[id] = {"maps": b[1], "files": {}, "dirs": [], "bytes": 0}
				continue
			var e := _zone_entry(key, z, b[1], _ref_with(base_set, b[2]))
			e["maps"] = b[1]
			if not (b[2] as Array).is_empty():
				e["requires"] = b[2]
			worst = maxi(worst, int(e["bytes"]))
			zones[id] = e
	for id: String in _extra_zones:
		zones[id] = _extra_zones[id]
	var eq := _equipment_entry(base_set)
	if int(eq["bytes"]) > 0:
		zones[EQUIPMENT_ZONE] = eq
	var classes := 0
	var breeds_ids := _table("breeds").keys()
	breeds_ids.sort()
	for b: Variant in breeds_ids:
		if not str(b).is_valid_int():
			continue
		var e := _class_entry(int(b), base_set)
		if int(e["bytes"]) > 0:
			zones[CLASS_PREFIX + str(int(b))] = e
			classes += 1
	_split_classes = false
	_split_equipment = false
	_extra_zones = {}
	_class_breed = 0
	stats["zones"] = zones.size()
	stats["class_zones"] = classes
	stats["monster_zones"] = zones.keys().filter(func(k: String) -> bool: return k.ends_with(MONSTER_SUFFIX)).size()
	stats["common_zones"] = zones.keys().filter(func(k: String) -> bool: return k.contains(COMMON_SUFFIX)).size()
	stats["equipment_bytes"] = int(eq["bytes"])
	stats["largest_zone_bytes"] = worst
	return {"base": base, "start_zone": start_block, "zones": zones}


func _set_of(globs: PackedStringArray) -> Dictionary:
	var out := {}
	for g in globs:
		out[g] = true
	return out


## What a zone (or a block of it) adds to the base: {files: {dir: [names]}, dirs: [globs], bytes}.
func _zone_entry(key: String, zone: String, maps: Array, base_set: Dictionary) -> Dictionary:
	_reset()
	_zone_pass(key, zone, maps)
	return _diff(_finish(), base_set)


## The assets of the class `breed` that the base does not hold (its skeletons, its creation skins).
func _class_entry(breed: int, base_set: Dictionary) -> Dictionary:
	_reset()
	_class_breed = breed
	_players()
	var e := _diff(_finish(), base_set)
	_class_breed = 0
	e["maps"] = []
	return e


## C.02g: the skins of the items the world gives (shops, quests, recipes: what `_gather_items` lists) that
## the base does not hold. The skins of what a monster drops stay in the zone of that monster. `skins` = their ids, for the client.
func _equipment_entry(base_set: Dictionary) -> Dictionary:
	_reset()
	_equipment_pass = true
	_gather_items()
	var worn := {}
	for id: int in _items:
		if _item_skin.has(id):
			worn[_item_skin[id]] = true
	var e := _diff(_finish(), base_set)
	_equipment_pass = false
	var ids: Array = worn.keys()
	ids.sort()
	e["skins"] = ids
	e["maps"] = []
	return e


## C.02g: what the monsters of the sub-area `zone` add to `ref` (the weight of `<zone>-m`).
func _monsters_entry(key: String, zone: String, ref: Dictionary) -> Dictionary:
	_reset()
	_zone_monsters(key, zone)
	return _diff(_finish(), ref)


func _diff(globs: PackedStringArray, base_set: Dictionary) -> Dictionary:
	var files := {}
	var dirs: Array = []
	var bytes := 0
	for g in globs:
		if base_set.has(g):
			continue
		bytes += _glob_size(g)
		if g.contains("*"):
			dirs.append(g)
		else:
			files.get_or_add(g.get_base_dir(), []).append(g.get_file())
	return {"files": files, "dirs": dirs, "bytes": bytes}


## C.02e: cuts the maps of a zone into blocks that each weigh at most `zone_max_bytes` (what the
## block adds to `ref`). Returns [[block id, maps]]: a zone that fits keeps its own id. A block is cut
## in two along its larger side (world coordinates, `_cut`) until it fits, holds one map, or cutting
## no longer lightens it (a monster's files that every block repeats).
## APPROX(C.02e): the sizes count what each block downloads alone; two blocks that share a texture
## download it once, so the sum over a zone overstates the real total.
func _split(key: String, zone: String, maps: Array, ref: Dictionary, monster_zone := true) -> Array:
	var whole := int(_zone_entry(key, zone, maps, ref)["bytes"])
	if whole <= zone_max_bytes or maps.size() <= 1:
		return [[zone, maps, []]]
	var requires: Array = []
	var ref2 := ref
	if monster_zone:
		var mon := _monsters_entry(key, zone, ref)
		# C.02g: the monsters weigh most of it, or more than half a block (every block would repeat them): their own zone
		if int(mon["bytes"]) * 2 > whole or int(mon["bytes"]) * 2 > zone_max_bytes:
			var id := zone + MONSTER_SUFFIX
			mon["maps"] = []
			_extra_zones[id] = mon
			requires = [id]
			ref2 = _ref_with(ref, requires)
			whole = int(_zone_entry(key, zone, maps, ref2)["bytes"])
	var leaves: Array = []
	_split_into(key, zone, maps, ref2, whole, leaves, requires, monster_zone)
	if leaves.size() == 1:
		return [[zone, maps, leaves[0][1]]]
	var out: Array = []
	for i in leaves.size():
		out.append(["%s-%d" % [zone, i + 1], leaves[i][0], leaves[i][1]])
	return out


## `leaves`: [[maps, requires]]. `common` = the zone may hoist what both halves share (not for the start zone,
## whose assets are in the base).
func _split_into(key: String, zone: String, maps: Array, ref: Dictionary, bytes: int, leaves: Array, requires: Array, common := true) -> void:
	if bytes <= zone_max_bytes or maps.size() <= 1:
		leaves.append([maps, requires])
		return
	var halves := _cut(maps)
	var sizes: Array = []
	for h: Array in halves:
		sizes.append(int(_zone_entry(key, zone, h, ref)["bytes"]))
	if mini(sizes[0], sizes[1]) >= int(bytes * 0.95):
		# both halves weigh as much as the whole (a half that stays heavy while the other is light is cut again): what every block needs alike (the same NPCs on all the maps...) goes to a zone
		# of its own that the blocks require, and the maps are cut again without it
		if common and requires.size() < 4:
			var shared := _shared_entry(key, zone, halves, ref)
			if int(shared["bytes"]) * 4 > bytes: # at least a quarter of the zone: worth a download of its own
				var id := "%s%s%d" % [zone, COMMON_SUFFIX, _extra_zones.size() + 1]
				shared["maps"] = []
				_extra_zones[id] = shared
				var req2 := requires.duplicate()
				req2.append(id)
				var ref2 := _ref_with(ref, [id])
				var lighter := int(_zone_entry(key, zone, maps, ref2)["bytes"])
				if lighter < bytes * 0.95:
					_split_into(key, zone, maps, ref2, lighter, leaves, req2, common)
					return
				_extra_zones.erase(id)
		leaves.append([maps, requires]) # nothing more to hoist: the block stays heavy
		return
	for i in 2:
		_split_into(key, zone, halves[i], ref, sizes[i], leaves, requires, common)


## The files both halves need that `ref` does not hold: {files, dirs, bytes}.
func _shared_entry(key: String, zone: String, halves: Array, ref: Dictionary) -> Dictionary:
	_reset()
	_zone_pass(key, zone, halves[0])
	var a := _finish()
	_reset()
	_zone_pass(key, zone, halves[1])
	var b := _set_of(_finish())
	var both := PackedStringArray()
	for g in a:
		if b.has(g):
			both.append(g)
	return _diff(both, ref)


## `ref` plus every glob of the zones `ids` (their entries are in `_extra_zones`).
func _ref_with(ref: Dictionary, ids: Array) -> Dictionary:
	if ids.is_empty():
		return ref
	var out := ref.duplicate()
	for id: Variant in ids:
		var e: Dictionary = _extra_zones.get(str(id), {})
		for g: Variant in e.get("dirs", []):
			out[str(g)] = true
		for dir: String in e.get("files", {}):
			for n: Variant in e["files"][dir]:
				out[dir + "/" + str(n)] = true
	return out


## Two halves of `maps` by number: apart by world map, else along the larger side of the box of
## their coordinates (worlds/<id>/maps/<map>.json `world_map`, `coords`); a map without coordinates
## sorts by id.
func _cut(maps: Array) -> Array:
	var info := {} # id -> [world_map, x, y]
	var wms := {}
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for id: Variant in maps:
		var f := root.path_join("worlds/%s/maps/%d.json" % [world_id, int(id)])
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(f)) if FileAccess.file_exists(f) else null
		var wm := 0
		var c := Vector2i(int(id), 0)
		if d is Dictionary:
			wm = int(d.get("world_map", 0))
			var xy: Variant = d.get("coords")
			if xy is Array and xy.size() >= 2:
				c = Vector2i(int(xy[0]), int(xy[1]))
		info[int(id)] = [wm, c.x, c.y]
		wms[wm] = true
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var order := [1, 2, 0] if hi.x - lo.x >= hi.y - lo.y else [2, 1, 0]
	if wms.size() > 1:
		order = [0, 1, 2]
	var sorted := maps.duplicate()
	sorted.sort_custom(func(a: Variant, b: Variant) -> bool:
		var ia: Array = info[int(a)]
		var ib: Array = info[int(b)]
		for k: int in order:
			if ia[k] != ib[k]:
				return ia[k] < ib[k]
		return int(a) < int(b))
	var mid := sorted.size() / 2
	return [sorted.slice(0, mid), sorted.slice(mid)]


## Writes `worlds/<id>/_content.json` (what WorldPackage reads). Returns "" or an error.
## `zoned` = the result of compute_zoned (C.02c): `globs` is then the base and the zones go in
## `zones` (compact: no indentation, the zone lists are long).
func save(globs: PackedStringArray, zoned := {}) -> String:
	var path := root.path_join("worlds/%s/%s" % [world_id, FILE])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "cannot write " + path
	var doc := {"_doc": "Generated by tools/world_assets.gd (C.02b, C.02c): the assets of content/ this world uses (globs = the base, zones = what is downloaded on demand). Read by WorldPackage; do not edit.",
			"stats": stats, "bytes": size_of(globs), "globs": Array(globs)}
	if not zoned.is_empty():
		doc["start_zone"] = zoned["start_zone"]
		doc["zones"] = zoned["zones"]
	f.store_string(JSON.stringify(doc, "\t" if zoned.is_empty() else ""))
	f.close()
	return ""


## Total bytes of the files the globs select (what a client downloads for the content part).
func size_of(globs: PackedStringArray) -> int:
	var total := 0
	for g in globs:
		total += _glob_size(g)
	return total


## Bytes of one glob (remembered: zones share most of their folders).
func _glob_size(g: String) -> int:
	if _size_memo.has(g):
		return _size_memo[g]
	var total := 0
	if not g.contains("*"):
		total = maxi(0, _size(root.path_join(g)))
	else:
		for f in _files_under(ContentManifest.glob_base(g)):
			if ContentManifest.glob_matches(g, f):
				total += maxi(0, _size(root.path_join(f)))
	_size_memo[g] = total
	return total


## The files of `paths` (logical, as ContentSource.trace_stop gives them) that exist under `root` but that
## the package of the world would not hold: `globs` plus worlds/<world>/ and data/.
func uncovered(globs: PackedStringArray, paths: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for p in paths:
		if not FileAccess.file_exists(root.path_join(p)):
			continue # a probe (png vs webp, an optional mod layer): nothing to ship
		if p.begins_with("data/") or p.begins_with("worlds/%s/" % world_id):
			continue
		var covered := false
		for g in globs:
			if g == p or (g.contains("*") and ContentManifest.glob_matches(g, p)):
				covered = true
				break
		if not covered:
			out.append(p)
	return out


# --- maps -------------------------------------------------------------------------------------

func _maps_of(ids: Array) -> void:
	var gfx := {}
	var props := {}
	var count := 0
	for id: Variant in ids:
		var path := "%s/Maps/%d.json" % [CONTENT, int(id)]
		var m: Variant = _json(path)
		if not m is Dictionary:
			missing.append(path)
			continue
		count += 1
		_add(path)
		var layers: Dictionary = m.get("layers", {})
		for layer: String in layers:
			for e: Variant in layers[layer]:
				gfx[int(e["g"])] = true
		for e: Variant in m.get("animated", []):
			props[int(e["g"])] = true
	for g in gfx:
		_add_image("%s/Maps/Gfx/%d" % [CONTENT, g])
	for p in props:
		_add_folder("%s/Animations/Props/%d" % [CONTENT, p])
	stats["maps"] = int(stats.get("maps", 0)) + count
	stats["gfx"] = int(stats.get("gfx", 0)) + gfx.size()
	stats["props"] = int(stats.get("props", 0)) + props.size()


# --- entities ---------------------------------------------------------------------------------

func _monster(m: Dictionary) -> void:
	for g: Dictionary in m.get("grades", []):
		_look(str(g.get("look", "")))
		for d: Dictionary in g.get("drops", []):
			_items[int(d.get("item", 0))] = true


func _npc_list(list: Array) -> void:
	for n: Dictionary in list:
		if n.has("look"):
			_look(str(n["look"]))
		_look(str(_npc_table.get(str(int(n.get("npc", 0))), {}).get("look", "")))


## What no map or zone owns: summons, every playable look, what shops, quests and recipes give.
func _world_wide() -> void:
	var spells: Variant = _json("data/spells.json")
	if spells is Dictionary:
		for s: Dictionary in (spells.get("summons", {}) as Dictionary).values():
			_look(str(s.get("look", "")))
	_players()
	_gather_items()


## The assets of one zone: its maps, the monsters of the sub-area, the NPCs standing on its maps.
func _zone_pass(key: String, zone: String, maps: Array) -> void:
	_maps_of(maps)
	_zone_monsters(key, zone)
	if _npcs is Dictionary:
		for id: Variant in maps:
			_npc_list((_npcs.get("maps", {}) as Dictionary).get(str(int(id)), []))


## The monsters of the sub-area `zone` (monsters.json `subareas`).
func _zone_monsters(key: String, zone: String) -> void:
	if key == "subarea" and _monsters is Dictionary:
		var sub: Variant = (_monsters.get("subareas", {}) as Dictionary).get(zone)
		var all: Dictionary = _monsters.get("monsters", {})
		if sub is Dictionary:
			for mid: Variant in sub.get("monsters", []):
				if all.has(str(int(mid))):
					_monster(all[str(int(mid))])


## {zone: [map ids]}: the field `key` of each map's sim file (worlds/<id>/maps/<map>.json), read
## from its first bytes (17 000 files). A map without a file or field goes to zone "0".
func _zone_maps(key: String) -> Dictionary:
	var re := RegEx.create_from_string('"%s":(-?\\d+)' % key)
	var out := {}
	for id: Variant in _def.get("maps", []):
		var zone := "0"
		var f := FileAccess.open(root.path_join("worlds/%s/maps/%d.json" % [world_id, int(id)]), FileAccess.READ)
		if f != null:
			var head := f.get_buffer(400).get_string_from_utf8()
			var hit := re.search(head)
			if hit == null: # the field is further than the first bytes: parse the whole file
				f.seek(0)
				var d: Variant = JSON.parse_string(f.get_as_text())
				if d is Dictionary and d.has(key):
					zone = str(int(d[key]))
			else:
				zone = hit.get_string(1)
		out.get_or_add(zone, []).append(int(id))
	return out


func _load() -> bool:
	if _loaded:
		return true
	var def: Variant = _json("worlds/%s/world.json" % world_id)
	if not def is Dictionary:
		missing.append("worlds/%s/world.json" % world_id)
		return false
	_def = def
	var fam: Variant = _json(CONTENT + "/Characters/Bones/families.json")
	_families = fam if fam is Dictionary else {}
	_monsters = _json("worlds/%s/monsters.json" % world_id)
	_npcs = _json("worlds/%s/npcs.json" % world_id)
	_npc_table = _table("npcs")
	var items: Variant = _json("data/items.json")
	if items is Dictionary:
		for it: Dictionary in items.get("items", []):
			if int(it.get("skin", 0)) > 0:
				_item_skin[int(it.get("id", 0))] = int(it["skin"])
	for b: Dictionary in _table("breeds").values():
		_breed_ids[int(b.get("id", 0))] = true
		for key in ["maleLook", "femaleLook"]:
			_player_bones[str(DofusLook.parse(str(b.get(key, ""))).bone)] = true
	_loaded = true
	return true


func _reset() -> void:
	_out.clear()
	_bones.clear()
	_skins.clear()
	_items.clear()
	_gathered.clear()
	_looks.clear()
	stats = {}


## Adds what every pass ends with (skins of the items, base folders, raw tables, bones, skins) and
## returns the sorted globs.
func _finish() -> PackedStringArray:
	if not _families.is_empty():
		_add(CONTENT + "/Characters/Bones/families.json")
	_skins_of_items()
	for folder in BASE_FOLDERS:
		_add_folder(CONTENT + "/" + folder)
	for t in RAW_TABLES:
		_add(CONTENT + "/Data/%sdataroot.json" % t)
	for id in _bones:
		_add_bone(str(id))
	for id in _skins:
		_add_folder(CONTENT + "/Characters/Skins/" + str(id))
	stats["bones"] = _bones.size()
	stats["skins"] = _skins.size()
	stats["looks"] = _looks.size()
	stats["items"] = _items.size()
	var out := PackedStringArray(_out.keys())
	out.sort()
	return out


## Every look a player can be created with (LookBuilder: breeds.maleLook / femaleLook, the bodies and
## faces available at creation). C.02e: in a split pass (`compute_zoned`) the base keeps only the fallback
## bone and `_class_breed` > 0 adds the looks and the creation skins of that class.
func _players() -> void:
	_bones[FALLBACK_BONE] = true
	if _split_classes and _class_breed == 0:
		for bone: String in _player_bones: # the generic bundles stay in the base, `_add_bone` leaves the class ones out
			_bones[bone] = true
		return
	var breeds := _table("breeds")
	var bodies := _table("bodies").values()
	var heads := _table("heads").values()
	for b: Dictionary in breeds.values():
		if _class_breed > 0 and int(b.get("id", 0)) != _class_breed:
			continue
		for key in ["maleLook", "femaleLook"]:
			_look(str(b.get(key, "")))
	for rows in [bodies, heads]:
		for r: Dictionary in rows:
			if _class_breed > 0 and int(r.get("breed", 0)) != _class_breed:
				continue
			if int(r.get("availableAtCreation", 0)) == 1 and int(r.get("payable", 0)) == 0:
				for s in str(r.get("skins", "")).split(",", false):
					if s.is_valid_int():
						_skins[int(s)] = true


## Items the world hands out: drops (already collected), shops, quest rewards, recipe results.
func _gather_items() -> void:
	var shops: Variant = _json("worlds/%s/shops.json" % world_id)
	if shops is Dictionary:
		for s: Dictionary in (shops.get("shops", {}) as Dictionary).values():
			for i: Variant in s.get("items", []):
				_gather(int(i))
	var quests: Variant = _json("worlds/%s/quests.json" % world_id)
	if quests is Dictionary:
		for q: Dictionary in (quests.get("quests", {}) as Dictionary).values():
			for step: Dictionary in q.get("steps", []):
				for r: Dictionary in step.get("rewards", []):
					for it: Variant in r.get("items", []):
						_gather(int(it[0]))
	for r: Dictionary in _table("recipes").values():
		_gather(int(r.get("resultId", 0)))


func _gather(id: int) -> void:
	_items[id] = true
	_gathered[id] = true


func _skins_of_items() -> void:
	for id: int in _items:
		if _split_equipment and not _equipment_pass and _gathered.has(id):
			continue
		if _item_skin.has(id):
			_skins[_item_skin[id]] = true


# --- looks ------------------------------------------------------------------------------------

func _look(look: String) -> void:
	if look == "" or _looks.has(look):
		return
	_looks[look] = true
	_use_look(DofusLook.parse(look))


func _use_look(l: DofusLook) -> void:
	if l.bone > 0:
		_bones[str(l.bone)] = true
	for s in l.skins:
		_skins[int(s)] = true
	for category: Variant in l.sub_entities:
		for sub: Variant in (l.sub_entities[category] as Dictionary).values():
			_use_look(sub)


## Bone folders of a bone id: the bone itself, or every bundle of its family (a split bone such as
## the player's: 1-static, 1-12-combat...).
func _add_bone(name: String) -> void:
	var dir := "%s/Characters/Bones/" % CONTENT
	if _families.has(name):
		for bundle: String in _families[name]:
			var cls := _bundle_class(name, bundle)
			if _split_classes and cls > 0 and cls != _class_breed:
				continue # C.02e: the bundle of another class (or of a class zone, in a map pass)
			_add_folder(dir + bundle)
	else:
		_add_folder(dir + name)


## The class a bundle of a player's bone belongs to (`1-12-combat` of bone 1 = class 12), 0 for the others
## (`1-combat`, a monster's bundle).
func _bundle_class(bone: String, bundle: String) -> int:
	if not _player_bones.has(bone) or not bundle.begins_with(bone + "-"):
		return 0
	var part := bundle.substr(bone.length() + 1).split("-")[0]
	return int(part) if part.is_valid_int() and _breed_ids.has(int(part)) else 0


# --- files ------------------------------------------------------------------------------------

func _add(path: String) -> void:
	if FileAccess.file_exists(root.path_join(path)):
		_out[path] = true
	else:
		missing.append(path)


func _add_image(path_without_ext: String) -> void:
	if not _image_memo.has(path_without_ext):
		_image_memo[path_without_ext] = ""
		for ext in ContentSource.IMAGE_EXTENSIONS:
			if FileAccess.file_exists(root.path_join("%s.%s" % [path_without_ext, ext])):
				_image_memo[path_without_ext] = "%s.%s" % [path_without_ext, ext]
				break
		if _image_memo[path_without_ext] == "":
			missing.append(path_without_ext + ".*")
	if _image_memo[path_without_ext] != "":
		_out[_image_memo[path_without_ext]] = true


func _add_folder(dir: String) -> void:
	if DirAccess.dir_exists_absolute(root.path_join(dir)):
		_out[dir + "/*"] = true
	else:
		missing.append(dir + "/")


func _files_under(rel_dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(root.path_join(rel_dir)):
		out.append(rel_dir + "/" + f)
	for d in DirAccess.get_directories_at(root.path_join(rel_dir)):
		out.append_array(_files_under(rel_dir + "/" + d))
	return out


func _size(abs_path: String) -> int:
	return maxi(0, FileHash.size_of(abs_path))


func _json(rel: String) -> Variant:
	var path := root.path_join(rel)
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## A Dofus table {id: row}: the light copy (data/tables) first, else the raw one.
func _table(name: String) -> Dictionary:
	for rel in ["data/tables/%s.json" % name, "%s/Data/%sdataroot.json" % [CONTENT, name]]:
		var d: Variant = _json(rel)
		if d is Dictionary and d.get("objectsById") is Dictionary:
			return d["objectsById"]
	return {}
