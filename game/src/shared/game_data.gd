## Game tables shared by sim and client, generated from Dofus 3
## (tools/extractor/gamedata.py):
##   data/experience.json  {levels: [total XP of level 1, 2, ...]}
##   data/items.json       {items: [{id, name_id, name, icon, type, level, weight}]}
##
## Any Dofus 3 table, generically and lazily (docs/data_catalog.md):
##   GameData.table("breeds")      {id (String) -> row}, {} when unavailable
##   GameData.row("breeds", 1)     one row, {} when missing
## Logical paths (ContentSource: res:// in dev, the downloaded cache otherwise).
## Searched in ROOTS order: first the light derived copies shipped with the
## game (data/tables/<name>.json, `gamedata.py table <name>`), then the
## raw extracted content (content/Content/Data/<name>dataroot.json,
## never committed, heavy: fine for tools and dev, not for the server).
class_name GameData
extends RefCounted

const EXPERIENCE := "data/experience.json"
const ITEMS := "data/items.json"
const DEFAULT_ROOTS: PackedStringArray = ["data/tables", "content/Content/Data"]

## Where tables are looked up (tests point it at fixtures).
static var roots: PackedStringArray = DEFAULT_ROOTS
static var _levels: Array = []
static var _items := {}
static var _sets := {}
static var _tables := {} # name -> {id: row}


static func table(name: String) -> Dictionary:
	if not _tables.has(name):
		_tables[name] = _load_table(name)
	return _tables[name]


static func row(name: String, id: Variant) -> Dictionary:
	return table(name).get(str(id), {})


static func has_table(name: String) -> bool:
	return not table(name).is_empty()


## Forget loaded tables (after changing roots, in tests).
static func clear_cache() -> void:
	_tables.clear()
	_levels.clear()
	_items.clear()
	_sets.clear()


static func _load_table(name: String) -> Dictionary:
	for root in roots:
		for file in [name + ".json", name + "dataroot.json"]:
			var data: Variant = DataFiles.read_json(root.path_join(file))
			if data is Dictionary and data.get("objectsById") is Dictionary:
				return data["objectsById"]
	return {}


static func max_level() -> int:
	_ensure()
	return _levels.size()


## Total XP needed to be `level` (level 1 = 0).
static func xp_floor(level: int) -> int:
	_ensure()
	return int(_levels[clampi(level, 1, _levels.size()) - 1])


## Total XP needed for the next level (= xp_floor(level) at the max level).
static func xp_next(level: int) -> int:
	return xp_floor(mini(level + 1, max_level()))


static func level_for_xp(xp: int) -> int:
	_ensure()
	var lv := 1
	while lv < _levels.size() and xp >= int(_levels[lv]):
		lv += 1
	return lv


static func item(id: int) -> Dictionary:
	_ensure()
	return _items.get(id, {})


## Every item id the game knows (items.json), sorted.
static func item_ids() -> Array:
	_ensure()
	var ids := _items.keys()
	ids.sort()
	return ids


## An item set (items.json "sets": {id, name_id, items, effects: [bonus for n items worn,
## index n - 1]}), {} if none.
static func item_set(id: int) -> Dictionary:
	_ensure()
	return _sets.get(id, {})


static func _ensure() -> void:
	if not _levels.is_empty():
		return
	var xp: Variant = DataFiles.read_json(EXPERIENCE)
	_levels = xp.get("levels", []) if xp is Dictionary else []
	if _levels.is_empty(): # no generated table: a simple quadratic curve
		for lv in 200:
			_levels.append(lv * lv * 110)
	var items: Variant = DataFiles.read_json(ITEMS)
	if items is Dictionary:
		for it: Dictionary in items.get("items", []):
			it["id"] = int(it["id"])
			_items[it["id"]] = it
		for st: Dictionary in items.get("sets", []):
			_sets[int(st["id"])] = st
