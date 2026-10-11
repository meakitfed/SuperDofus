## Dungeon rules (roadmap P4.01), pure: a definition is a Dictionary
## {id, name, level, min_level, difficulty, maps: [rooms in order], entrance_map, exit_map,
##  keys: [{item, qty}], bosses: [monster ids]} (dungeons.* table fields, ints after JSON).
## Nothing here knows a world: the sim feeds it the definition and the monster pool.
class_name Dungeon
extends RefCounted

## APPROX(P4.01): the real group compositions of dungeon rooms are server data (absent).
const MIN_GROUPS := 2
const MAX_GROUPS := 3
const MAX_SIZE := 5


## dungeons.maps (the rooms, in order).
static func room_count(def: Dictionary) -> int:
	return (def.get("maps", []) as Array).size()


## Map id of room `idx`, -1 out of bounds.
static func room_map(def: Dictionary, idx: int) -> int:
	var maps: Array = def.get("maps", [])
	return int(maps[idx]) if idx >= 0 and idx < maps.size() else -1


## Index of a map in the room list, -1 when it is not a room.
static func room_index(def: Dictionary, map_id: int) -> int:
	var maps: Array = def.get("maps", [])
	for i in maps.size():
		if int(maps[i]) == map_id:
			return i
	return -1


static func is_last(def: Dictionary, idx: int) -> bool:
	return idx >= 0 and idx == room_count(def) - 1


## idx + 1, or -1 after the last room (and out of bounds).
static func next_room(def: Dictionary, idx: int) -> int:
	return idx + 1 if idx >= 0 and idx < room_count(def) - 1 else -1


## "" when the player may enter; "level" (dungeons.min_level, APPROX(P4.01): checked on the
## character level) or "key" (dungeons.keys: item and quantity); `items` is {item id: count}.
static func check_entry(def: Dictionary, level: int, items: Dictionary) -> String:
	if level < int(def.get("min_level", 0)):
		return "level"
	for k: Dictionary in keys_to_consume(def):
		if _count(items, int(k["item"])) < int(k["qty"]):
			return "key"
	return ""


## The keys taken at the door: [{item, qty}] (dungeons.keys). APPROX(P4.01): all are consumed on entry.
static func keys_to_consume(def: Dictionary) -> Array:
	var out: Array = []
	for k: Dictionary in def.get("keys", []):
		out.append({"item": int(k.get("item", 0)), "qty": maxi(1, int(k.get("qty", 1)))})
	return out


## A room is cleared when no monster is left alive (APPROX(P4.01): the door opens then).
static func room_cleared(monsters_alive: int) -> bool:
	return monsters_alive <= 0


## The boss room is the last one (dungeons.maps order).
static func boss_room(def: Dictionary) -> int:
	return room_count(def) - 1


static func has_boss(def: Dictionary, idx: int) -> bool:
	return idx >= 0 and idx == boss_room(def) and not (def.get("bosses", []) as Array).is_empty()


## Groups of room `idx`: [{members: [member dict + monster, grade]}], the member dicts being
## those of MonsterSpawner.compose (the `pool` fiches are {id, grades: [member dict per grade]}).
## APPROX(P4.01): 2-3 groups, bigger with the room index; the last room is one group of the
## `bosses` (grade closest to def.level) with an escort of the pool.
static func compose_room(def: Dictionary, idx: int, rng: RandomNumberGenerator, pool: Array) -> Array:
	var out: Array = []
	if idx < 0 or idx >= room_count(def):
		return out
	var level := int(def.get("level", 1))
	if has_boss(def, idx):
		var members: Array = []
		for b: Variant in def["bosses"]:
			members.append(_member(_fiche(pool, int(b)), int(b), true, level, rng))
		if not pool.is_empty():
			for i in rng.randi_range(1, 2):
				var f: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
				members.append(_member(f, int(f["id"]), false, level, rng))
		out.append({"members": members})
		return out
	if pool.is_empty():
		return out
	var progress := float(idx) / maxf(1.0, float(room_count(def) - 1))
	var max_size := clampi(2 + int(round(progress * (MAX_SIZE - 2))), 2, MAX_SIZE)
	for g in rng.randi_range(MIN_GROUPS, MAX_GROUPS):
		var members: Array = []
		for i in rng.randi_range(maxi(1, max_size - 1), max_size):
			var f: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
			members.append(_member(f, int(f["id"]), false, level, rng))
		members.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("level", 1)) > int(b.get("level", 1)))
		out.append({"members": members})
	return out


static func _count(items: Dictionary, item: int) -> int:
	return int(items.get(item, items.get(str(item), 0)))


static func _fiche(pool: Array, id: int) -> Dictionary:
	for f: Dictionary in pool:
		if int(f.get("id", -1)) == id:
			return f
	return {"id": id}


## A member: the grade's dict (copy) + "monster" and "grade" (1-based). Bosses take the grade whose
## level is closest to the dungeon level (APPROX(P4.01)); escort picks a random grade.
static func _member(fiche: Dictionary, id: int, boss: bool, level: int, rng: RandomNumberGenerator) -> Dictionary:
	var grades: Array = fiche.get("grades", [])
	var grade := 1
	if not grades.is_empty():
		if boss:
			var best := 1 << 30
			for i in grades.size():
				var d := absi(int((grades[i] as Dictionary).get("level", 1)) - level)
				if d < best:
					best = d
					grade = i + 1
		else:
			grade = rng.randi_range(1, grades.size())
	var m: Dictionary = (grades[grade - 1] as Dictionary).duplicate(true) if not grades.is_empty() else {}
	m["monster"] = id
	m["grade"] = grade
	return m
