## The bonus drops of a Temporis-like server (S.06, WorldRates.bonus_drops): a system
## apart from the normal drops. For each player and each monster killed, a chance of
## WorldRates.bonus_rate % × prospecting / 100 (no drop rate, no stars, no challenge) to
## get one equipment: from the sets tied to the monsters killed (share bonus_set_share),
## else a craftable equipment without a set within ± bonus_range levels of the group's
## highest monster. The pools: data/bonus_drops.json (tools/extractor/gamedata.py
## bonus_drops). APPROX(S.06): the official Temporis tables (monsters.temporisDrops) are
## empty in the Dofus 3 data; the sets are tied to the monsters through the recipes.
class_name BonusDrops
extends RefCounted

const PATH := "data/bonus_drops.json"

static var _loaded := false
static var _monster_sets := {} # monster id -> [set id]
static var _sets := {} # set id -> [item id]
static var _equipment: Array = [] # [[item id, level]] sorted by level


## player fighter id -> {item id: qty}. Rolled on fight.rng, after the normal drops.
static func roll(fight: Fight, players: Array, dead: Array, monsters: Array, prospecting: Dictionary, rates: WorldRates) -> Dictionary:
	_ensure()
	var out := {}
	var max_level := 1
	for m: Fighter in monsters:
		max_level = maxi(max_level, m.level)
	var set_pool := set_items(dead.map(func(m: Fighter) -> int: return m.monster))
	var free_pool := equipment_between(max_level - rates.bonus_range, max_level + rates.bonus_range)
	for p: Fighter in players:
		var items := {}
		if not set_pool.is_empty() or not free_pool.is_empty():
			for _m: Fighter in dead:
				var chance := minf(100.0, rates.bonus_rate * int(prospecting[p.id]) / 100.0)
				if fight.rng.randf() * 100.0 >= chance:
					continue
				var from_sets := not set_pool.is_empty() and (free_pool.is_empty() or fight.rng.randf() < rates.bonus_set_share)
				var pool := set_pool if from_sets else free_pool
				var item := int(pool[fight.rng.randi_range(0, pool.size() - 1)])
				items[item] = int(items.get(item, 0)) + 1
		out[p.id] = items
	return out


## The items of the sets tied to these monsters (each item once).
static func set_items(monster_ids: Array) -> Array:
	_ensure()
	var seen := {}
	var out: Array = []
	for mid: int in monster_ids:
		for sid: int in _monster_sets.get(mid, []):
			for item: int in _sets.get(sid, []):
				if not seen.has(item):
					seen[item] = true
					out.append(item)
	return out


## The craftable equipment without a set whose level is in [lo, hi].
static func equipment_between(lo: int, hi: int) -> Array:
	_ensure()
	var out: Array = []
	var i := _equipment.bsearch_custom(lo, func(e: Array, v: int) -> bool: return int(e[1]) < v)
	while i < _equipment.size() and int(_equipment[i][1]) <= hi:
		out.append(int(_equipment[i][0]))
		i += 1
	return out


static func sets_of(monster_id: int) -> Array:
	_ensure()
	return _monster_sets.get(monster_id, [])


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var d: Variant = DataFiles.read_json(PATH)
	if not d is Dictionary:
		return
	var ms: Dictionary = d.get("monster_sets", {})
	for k: String in ms:
		_monster_sets[int(k)] = (ms[k] as Array).map(func(s: Variant) -> int: return int(s))
	var sets: Dictionary = d.get("sets", {})
	for k: String in sets:
		_sets[int(k)] = (sets[k] as Array).map(func(s: Variant) -> int: return int(s))
	# only the items the game knows (data/items.json)
	for e: Array in d.get("equipment", []):
		if not GameData.item(int(e[0])).is_empty():
			_equipment.append([int(e[0]), int(e[1])])
	for sid: int in _sets:
		_sets[sid] = (_sets[sid] as Array).filter(func(i: int) -> bool: return not GameData.item(i).is_empty())
