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
var max_groups := 3


func _init(db := {}, p_max_groups := 3) -> void:
	monsters = db.get("monsters", {})
	subareas = db.get("subareas", {})
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
func pool(subarea: int) -> Array:
	var sub: Dictionary = subareas.get(str(subarea), {})
	return (sub.get("monsters", []) as Array).filter(func(id: Variant) -> bool: return monsters.has(str(int(id))))


## A new group of the subarea: [member dict] (see WorldSim._monster_fighter).
func compose(subarea: int, rng: RandomNumberGenerator) -> Array:
	var ids := pool(subarea)
	var out: Array = []
	if ids.is_empty():
		return out
	for i in rng.randi_range(1, MAX_SIZE):
		var mo: Dictionary = monsters[str(int(ids[rng.randi_range(0, ids.size() - 1)]))]
		var grades: Array = mo["grades"]
		out.append((grades[rng.randi_range(0, grades.size() - 1)] as Dictionary).duplicate(true))
	# the leader (first look, the one that sees players) is the highest level
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("level", 1)) > int(b.get("level", 1)))
	return out


func area_of(subarea: int) -> int:
	return int((subareas.get(str(subarea), {}) as Dictionary).get("area", 0))
