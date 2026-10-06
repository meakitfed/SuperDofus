## Crafting (P2.06): the recipes, shared by the sim and the client.
##
## Data: `recipes` (light copy in data/tables, `gamedata.py table recipes`): one row per crafted item
## (key = result item id) {resultId, resultLevel, ingredientIds, quantities, jobId, skillId}. A skill that
## appears as `recipes.skillId` is a craft skill (the workshop verb of a job: Forger, Coudre, Cuisiner...).
##
## What the client does not give is marked APPROX(P2.06) below.
class_name Crafting
extends RefCounted

## APPROX(P2.06): ingredient slots of a job level = 2, +1 every 20 levels, at most 8
## (Dofus 2 rule; `items.recipeSlots` gives what a recipe needs, 1 to 8).
const MIN_SLOTS := 2
const MAX_SLOTS := 8
const LEVELS_PER_SLOT := 20
## APPROX(P2.06): XP of one craft = BASE + the level of the item (items.craftXpRatio is -1 for 96 % of the recipes
## and its unit is unknown, so it is ignored), like the harvest XP (Jobs.XP_BASE).
const XP_BASE := 10

static var _source := {} # the table the indexes were built from (GameData.clear_cache swaps it)
static var _by_signature := {} # skill id -> {signature: recipe row}
static var _by_skill := {} # skill id -> [recipe rows], sorted by level then id


static func recipe(item_id: int) -> Dictionary:
	return GameData.row("recipes", item_id)


static func clear_cache() -> void:
	_by_signature.clear()
	_by_skill.clear()


## A skill that crafts (some recipe uses it).
static func is_craft_skill(skill_id: int) -> bool:
	_index()
	return _by_skill.has(skill_id)


## Every craft skill (the workshops a player can open), sorted by id.
static func craft_skills() -> Array:
	_index()
	var out := _by_skill.keys()
	out.sort()
	return out


static func job_of(skill_id: int) -> int:
	return Jobs.job_of(skill_id)


## Ingredient slots a job level offers. APPROX(P2.06).
static func slots_for_level(job_level: int) -> int:
	return clampi(MIN_SLOTS + job_level / LEVELS_PER_SLOT, MIN_SLOTS, MAX_SLOTS)


## [{item, qty}] of a recipe, in the data order.
static func ingredients(r: Dictionary) -> Array:
	var out := []
	var ids: Array = r.get("ingredientIds", [])
	var qs: Array = r.get("quantities", [])
	for i in ids.size():
		out.append({"item": int(ids[i]), "qty": int(qs[i])})
	return out


## The recipe the ingredients [{item, qty}] make with `skill` exactly (every item and quantity as written), {} if none.
static func match_recipe(skill_id: int, given: Array) -> Dictionary:
	_index()
	var by_sig: Dictionary = _by_signature.get(skill_id, {})
	return by_sig.get(_signature(given), {})


## The recipes of a skill that fit `slots` slots, as the recipe book shows them: [{item, level, ingredients}].
static func book(skill_id: int, slots: int) -> Array:
	_index()
	var out := []
	for r: Dictionary in _by_skill.get(skill_id, []):
		if (r["ingredientIds"] as Array).size() <= slots:
			out.append({"item": int(r["resultId"]), "level": int(r.get("resultLevel", 1)), "ingredients": ingredients(r)})
	return out


## How many times the bag holds the ingredients of a recipe (items: item id -> count in the bag).
static func times_available(r: Dictionary, bag_count: Callable) -> int:
	var n := 1 << 30
	for ing: Dictionary in ingredients(r):
		n = mini(n, int(bag_count.call(int(ing["item"]))) / maxi(1, int(ing["qty"])))
	return n


## XP of crafting `count` times. APPROX(P2.06).
static func xp_gain(r: Dictionary, count: int) -> int:
	return (XP_BASE + int(r.get("resultLevel", 1))) * count


static func _signature(given: Array) -> String:
	var parts := PackedStringArray()
	var sorted := given.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["item"]) < int(b["item"]))
	for g: Dictionary in sorted:
		parts.append("%d:%d" % [int(g["item"]), int(g["qty"])])
	return ",".join(parts)


static func _index() -> void:
	var table := GameData.table("recipes")
	if _source == table and not _by_skill.is_empty():
		return
	_source = table
	_by_skill.clear()
	_by_signature.clear()
	for r: Dictionary in table.values():
		var skill := int(r.get("skillId", 0))
		if not _by_skill.has(skill):
			_by_skill[skill] = []
			_by_signature[skill] = {}
		_by_skill[skill].append(r)
		_by_signature[skill][_signature(ingredients(r))] = r
	for skill: int in _by_skill:
		(_by_skill[skill] as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var la := int(a.get("resultLevel", 1))
			var lb := int(b.get("resultLevel", 1))
			return la < lb or (la == lb and int(a["resultId"]) < int(b["resultId"])))
