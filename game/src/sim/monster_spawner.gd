## Monster groups of a map, from its subarea (roadmap P1.09). The world's
## monsters.json (tools/extractor/maps.py world_monsters) lists the monsters of
## each subarea (subareas.monsters) with their 5 grades (monsters.grades); the
## sim composes the groups itself, a new composition at each respawn.
## Hand-made worlds may still give fixed groups in the map file ("groups").
## No groups on maps without the ALLOW_MONSTER_RESPAWN capability
## (mapsinformation.m_flags bit 13: zaap maps, the Tavern) nor in subareas
## without monsters.
class_name MonsterSpawner
extends RefCounted

## APPROX(P1.09): how many groups a map holds and how big they are is server
## data (not in the client): 2 to `max_groups` groups of 1 to 4 monsters, each
## at a random grade (1 to 5), like the groups the extractor used to write.
const MIN_GROUPS := 2
const MAX_SIZE := 4

## monster id (String) -> {name_id, race, grades: [member dict of each grade]}
var monsters := {}
## subarea id (String) -> {level, area, monsters: [monster ids]}
var subareas := {}
## dungeon boss id (String) -> same shape as `monsters` (monsters.json `bosses`), drawn only by zones with `bosses`
var bosses := {}
var max_groups := 3


func _init(db := {}, p_max_groups := 3) -> void:
	monsters = db.get("monsters", {})
	subareas = db.get("subareas", {})
	bosses = db.get("bosses", {})
	max_groups = maxi(MIN_GROUPS, p_max_groups)


## The spawn slots of a map: its fixed groups, else one {subarea} slot per group.
func spawns_for(data: MapData, fixed: Array, rng: RandomNumberGenerator) -> Array:
	if not fixed.is_empty():
		return fixed
	if not data.monster_spawn or pool(data.subarea).is_empty():
		return []
	var out: Array = []
	for i in rng.randi_range(MIN_GROUPS, max_groups):
		out.append({"subarea": data.subarea})
	return out


## Monster ids that roam this subarea (bosses and mini-bosses are left out by the extractor).
## A zone with `levels` [lo, hi] keeps the monsters with a grade in that range.
func pool(subarea: int) -> Array:
	var sub: Dictionary = subareas.get(str(subarea), {})
	var lv: Array = sub.get("levels", [])
	return (sub.get("monsters", []) as Array).filter(func(id: Variant) -> bool:
		return monsters.has(str(int(id))) and not _grades_in(monsters[str(int(id))], lv).is_empty())


## The zone's dungeon bosses that may join its groups (`bosses`, known in monsters.json `bosses`).
func boss_pool(subarea: int) -> Array:
	var sub: Dictionary = subareas.get(str(subarea), {})
	return (sub.get("bosses", []) as Array).filter(func(id: Variant) -> bool: return bosses.has(str(int(id))))


## A new group of the subarea: [member dict] (see WorldSim._monster_fighter).
## APPROX(ascension): zones made by a world (Atelier recipe) may give `levels` (only the grades in
## that range are drawn) and `bosses` + `boss_pct` (each member has boss_pct % of chance to be one
## of those dungeon bosses, so a group may hold several). Without them the draws are the usual ones.
func compose(subarea: int, rng: RandomNumberGenerator) -> Array:
	var ids := pool(subarea)
	var out: Array = []
	if ids.is_empty():
		return out
	var sub: Dictionary = subareas.get(str(subarea), {})
	var lv: Array = sub.get("levels", [])
	var boss_ids := boss_pool(subarea) if sub.has("bosses") else []
	var boss_pct := float(sub.get("boss_pct", 0))
	for i in rng.randi_range(1, MAX_SIZE):
		var grades: Array
		if not boss_ids.is_empty() and rng.randf() * 100.0 < boss_pct:
			# a boss with no grade in the range comes at its closest grade
			grades = _grades_in(bosses[str(int(boss_ids[rng.randi_range(0, boss_ids.size() - 1)]))], lv, true)
		else:
			grades = _grades_in(monsters[str(int(ids[rng.randi_range(0, ids.size() - 1)]))], lv)
		out.append((grades[rng.randi_range(0, grades.size() - 1)] as Dictionary).duplicate(true))
	# the leader (first look, the one that sees players) is the highest level
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("level", 1)) > int(b.get("level", 1)))
	return out


## The grades of a monster, those within [lo, hi] when `levels` is given; with `closest`, the
## nearest grade when none is in the range.
static func _grades_in(mo: Dictionary, levels: Array, closest := false) -> Array:
	var grades: Array = mo.get("grades", [])
	if levels.size() < 2:
		return grades
	var lo := int(levels[0])
	var hi := int(levels[1])
	var out := grades.filter(func(g: Dictionary) -> bool: return int(g.get("level", 1)) >= lo and int(g.get("level", 1)) <= hi)
	if out.is_empty() and closest and not grades.is_empty():
		var best: Dictionary = grades[0]
		for g: Dictionary in grades:
			if _gap(int(g.get("level", 1)), lo, hi) < _gap(int(best.get("level", 1)), lo, hi):
				best = g
		out = [best]
	return out


static func _gap(level: int, lo: int, hi: int) -> int:
	return lo - level if level < lo else (level - hi if level > hi else 0)


func area_of(subarea: int) -> int:
	return int((subareas.get(str(subarea), {}) as Dictionary).get("area", 0))
