## Generates the "test" world: 3 x 3 Dofus-geometry maps, seeded obstacles,
## monster groups picked by race among the monsters whose bone is extracted.
##   godot --headless --path game -s res://tools/gen_test_world.gd
## Output: res://worlds/test/world.json + maps/<id>.json (committed, hand-editable).
extends SceneTree

## every test monster hits with "Béco du Tofu" (a real monster spell of data/spells.json)
const DEFAULT_SPELL := 1001001
const OUT := ContentSource.DEV_ROOT + "worlds/test" # tool: writes in the project, reads go through ContentSource
const SEED := 7
const MAX_LEVEL := 15 # a beginner zone: keeps test fights short
const EXITS := {"left": Vector2i.LEFT, "right": Vector2i.RIGHT, "top": Vector2i.UP, "bottom": Vector2i.DOWN}
const FALLBACK_MEMBERS := [
	{"monster": 0, "name": "Monstre", "look": "{4907|||130}", "level": 5, "hp": 40, "ap": 5, "mp": 3, "spells": [DEFAULT_SPELL]},
	{"monster": 0, "name": "Monstre", "look": "{2069|||100}", "level": 5, "hp": 40, "ap": 5, "mp": 3, "spells": [DEFAULT_SPELL]},
]
const GROUNDS := [
	["#5f7f45", "#5a7841"], ["#6d8a4c", "#678346"], ["#4f7448", "#4a6d43"],
	["#7a8a52", "#73824c"], ["#5b8150", "#557a4b"], ["#86865a", "#7f7f54"],
	["#4d6b52", "#48654d"], ["#6c7b58", "#667452"], ["#8a7d55", "#83764f"],
]

var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = SEED
	var families := _monster_families()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "/maps"))
	var ids := {}
	for y in range(-1, 2):
		for x in range(-1, 2):
			ids[Vector2i(x, y)] = 100 + (y + 1) * 3 + (x + 1)
	for coords: Vector2i in ids:
		var id: int = ids[coords]
		var neighbors := {}
		for dir: String in EXITS:
			var n: Vector2i = coords + EXITS[dir]
			if ids.has(n):
				neighbors[dir] = ids[n]
		var family: Array = families[rng.randi() % families.size()]
		var groups: Array = []
		for g in rng.randi_range(2, 3):
			var members: Array = []
			for m in rng.randi_range(1, 4):
				members.append(family[rng.randi() % family.size()])
			groups.append({"name": "Groupe %d" % (g + 1), "members": members})
		var map := {
			"id": id,
			"name": "Plaine [%d,%d]" % [coords.x, coords.y],
			"coords": [coords.x, coords.y],
			"neighbors": neighbors,
			"ground": GROUNDS[id - 100],
			"blocked": _obstacles(),
			"groups": groups,
		}
		_write("%s/maps/%d.json" % [OUT, id], map)
	_write(OUT + "/world.json", {
		"id": "test",
		"name": "Monde de test",
		"start_map": ids[Vector2i.ZERO],
		"start_cell": 300,
		"wander_ms": [6000, 15000],
		"maps": ids.values(),
	})
	print("test world written to ", ProjectSettings.globalize_path(OUT))
	quit()


## Small rock clusters away from the edges (edges stay free: they are the exits).
func _obstacles() -> Array:
	var blocked := {}
	for cluster in rng.randi_range(8, 12):
		var c := rng.randi_range(0, MapGeometry.CELL_COUNT - 1)
		for i in rng.randi_range(1, 5):
			if not MapGeometry.is_edge(c) and MapGeometry.row(c) > 3 and MapGeometry.row(c) < MapGeometry.ROWS - 4:
				blocked[c] = true
			var n := MapGeometry.neighbors(c)
			c = n[rng.randi() % n.size()]
	var out := blocked.keys()
	out.sort()
	return out


## Monsters grouped by race (only races with >= 2 extracted bones), with the
## fight stats of their first grade: {monster, name, look, level, hp, ap, mp}.
func _monster_families() -> Array:
	var provider := DofusContent.get_provider()
	var data: Variant = provider.read_json("Content/Data/monstersdataroot.json")
	var by_race := {}
	if data is Dictionary:
		for m: Dictionary in (data["objectsById"] as Dictionary).values():
			var look := DofusLook.parse(str(m.get("look", "")))
			if look.bone <= 1 or not look.sub_entities.is_empty():
				continue
			if not provider.exists("Content/Characters/Bones/%d/bone.json" % look.bone):
				continue
			var race := str(m.get("race", "0"))
			if not by_race.has(race):
				by_race[race] = []
			var grades: Array = m.get("grades", [])
			if grades.is_empty() or by_race[race].size() >= 6:
				continue
			var gr: Dictionary = grades[0]
			var hp := int(gr.get("lifePoints", 0))
			if int(gr.get("level", 1)) > MAX_LEVEL or hp < 20 or hp > 400 or int(gr.get("actionPoints", 0)) <= 0: # skips summons, bosses, props
				continue
			by_race[race].append({
				"monster": int(m["id"]), "name": "Monstre %d" % int(m["id"]), "look": str(m["look"]),
				"level": int(gr.get("level", 1)), "hp": hp,
				"ap": int(gr.get("actionPoints", 5)), "mp": int(gr.get("movementPoints", 3)),
				"spells": [DEFAULT_SPELL],
			})
	var out: Array = []
	var races := by_race.keys()
	races.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for race: String in races:
		if by_race[race].size() >= 2:
			out.append(by_race[race])
	if out.is_empty():
		out.append(FALLBACK_MEMBERS)
	print("%d monster families available" % out.size())
	return out


func _write(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t", false))
