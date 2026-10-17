## What the achievements window shows (P2.12b), without any Node: the definitions (data/achievements.json, read
## through DataFiles like every static table) and the state of the character (achievement_list / achievement_unlocked).
## The sim decides what is obtained; this only sorts and counts. Categories: the top ones (parent 0) group their
## sub-categories; an achievement lists in the category of its `category` field.
class_name AchievementsModel
extends RefCounted

static var _defs := {}
static var _cats := {}
static var _loaded := false

var points := 0
var total := 0
var done := {}     # achievement id -> day
var progress := {} # achievement id -> [objective ids true]


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var data: Variant = DataFiles.read_json("data/achievements.json")
	if data is Dictionary:
		set_defs((data as Dictionary).get("achievements", {}), (data as Dictionary).get("categories", {}))


## Replaces the definitions (tests); keys may be strings (JSON).
static func set_defs(defs: Dictionary, cats: Dictionary) -> void:
	_loaded = true
	_defs = {}
	for k: Variant in defs:
		_defs[int(k)] = defs[k]
	_cats = {}
	for k: Variant in cats:
		_cats[int(k)] = cats[k]


static func reset() -> void:
	_loaded = false
	_defs = {}
	_cats = {}


func apply_list(ev: Dictionary) -> void:
	points = int(ev["points"])
	total = int(ev["total"])
	done = {}
	for d: Dictionary in ev["done"]:
		done[int(d["id"])] = int(d["day"])
	progress = {}
	for p: Dictionary in ev["progress"]:
		progress[int(p["id"])] = (p["objectives"] as Array).map(func(o: Variant) -> int: return int(o))


func apply_unlocked(ev: Dictionary) -> void:
	var id := int(ev["achievement"])
	if not done.has(id):
		done[id] = -1
	progress.erase(id)
	points = int(ev["total_points"])


static func name_of(id: int) -> String:
	_load()
	var a: Dictionary = _defs.get(id, {})
	return UiStyle.plain_text(DofusI18n.text(int(a.get("name_id", 0)), "Succès %d" % id))


## The line of the toast when `ev` (achievement_unlocked) arrives.
static func unlocked_text(ev: Dictionary) -> String:
	return "Succès obtenu : %s (+%d points)" % [UiStyle.plain_text(DofusI18n.text(int(ev["name_id"]), "Succès %d" % int(ev["achievement"]))), int(ev["points"])]


func _top_of(cat: int) -> int:
	var seen := 0
	while _cats.has(cat) and int(_cats[cat].get("parent", 0)) != 0 and seen < 8:
		cat = int(_cats[cat]["parent"])
		seen += 1
	return cat


## The top categories that hold achievements, by `order`: [{id, name, done, count, points}].
func categories() -> Array:
	_load()
	var by := {}
	for id: int in _defs:
		var top := _top_of(int(_defs[id].get("category", 0)))
		if not by.has(top):
			by[top] = {"id": top, "name": "", "done": 0, "count": 0, "points": 0}
		var c: Dictionary = by[top]
		c["count"] = int(c["count"]) + 1
		if done.has(id):
			c["done"] = int(c["done"]) + 1
			c["points"] = int(c["points"]) + int(_defs[id].get("points", 0))
	var out := by.values()
	for c: Dictionary in out:
		c["name"] = UiStyle.plain_text(DofusI18n.text(int(_cats.get(int(c["id"]), {}).get("name_id", 0)), "Divers"))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var oa := int(_cats.get(int(a["id"]), {}).get("order", 999))
		var ob := int(_cats.get(int(b["id"]), {}).get("order", 999))
		return oa < ob or (oa == ob and int(a["id"]) < int(b["id"])))
	return out


## The achievements of a top category (sub-categories included): obtained first, then the others, each by order.
## [{id, name, desc, points, done, day, level, order, objectives: [{name, done}]}]
func rows(top: int) -> Array:
	_load()
	var out := []
	for id: int in _defs:
		var a: Dictionary = _defs[id]
		if _top_of(int(a.get("category", 0))) != top:
			continue
		var objs := []
		var got: Array = progress.get(id, [])
		for o: Dictionary in a.get("objectives", []):
			objs.append({"name": UiStyle.plain_text(DofusI18n.text(int(o.get("name_id", 0)), "")),
					"done": done.has(id) or got.has(int(o["id"]))})
		out.append({"id": id, "name": name_of(id), "desc": UiStyle.plain_text(DofusI18n.text(int(a.get("desc_id", 0)), "")),
				"points": int(a.get("points", 0)), "done": done.has(id), "day": int(done.get(id, -1)),
				"level": int(a.get("level", 0)), "order": int(a.get("order", 0)), "objectives": objs})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a["done"]) != bool(b["done"]):
			return bool(a["done"])
		return int(a["order"]) < int(b["order"]) or (int(a["order"]) == int(b["order"]) and int(a["id"]) < int(b["id"])))
	return out
