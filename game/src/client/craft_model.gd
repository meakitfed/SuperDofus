## State of the workshop window (P2.06b), without any Node so a test can drive it: what craft_state says
## (skill, slots, job, ingredients put down, result, how many times, recipe book) and the messages the
## window sends. The sim decides everything (recipes, slots, ingredients); this only keeps what is shown.
class_name CraftModel
extends RefCounted

var skill := 0
var slots := 0
## the job view of the skill ({job, level, xp, ...}, Protocol job_xp.view)
var job: Dictionary = {}
## [{item, qty}] put down, as the sim last confirmed them
var ingredients: Array = []
## the item the ingredients make (0 = no recipe)
var result := 0
## how many times the bag holds those ingredients
var max_count := 0
## the recipe book [{item, level, ingredients: [{item, qty}]}]
var book: Array = []
var is_open := false


## craft_state event. The book only comes with the first one after craft_open.
func apply_state(ev: Dictionary) -> void:
	if not is_open or int(ev["skill"]) != skill:
		skill = int(ev["skill"])
		book = []
		is_open = true
	slots = int(ev["slots"])
	job = ev["view"]
	ingredients = ev["ingredients"]
	result = int(ev["result"])
	max_count = int(ev["max"])
	var given: Array = ev.get("book", [])
	if not given.is_empty():
		book = given


func close() -> void:
	is_open = false
	skill = 0
	ingredients = []
	result = 0
	max_count = 0
	book = []


func qty_of(item: int) -> int:
	for g: Dictionary in ingredients:
		if int(g["item"]) == item:
			return int(g["qty"])
	return 0


## True when one more kind of ingredient still fits in the slots.
func has_room_for(item: int) -> bool:
	return qty_of(item) > 0 or ingredients.size() < slots


## Message that puts `qty` more of `item` down (null if the slots are full).
func add(item: int, qty: int) -> Variant:
	if qty < 1 or not has_room_for(item):
		return null
	var list := ingredients.duplicate(true)
	var found := false
	for g: Dictionary in list:
		if int(g["item"]) == item:
			g["qty"] = int(g["qty"]) + qty
			found = true
	if not found:
		list.append({"item": item, "qty": qty})
	return Protocol.craft_set(list)


## Message that takes an ingredient off (all of it).
func remove(item: int) -> Dictionary:
	return Protocol.craft_set(ingredients.filter(func(g: Dictionary) -> bool: return int(g["item"]) != item))


## Message that puts down the ingredients of a book recipe.
func fill_from(recipe: Dictionary) -> Dictionary:
	return Protocol.craft_set(recipe["ingredients"])


func can_craft() -> bool:
	return is_open and result != 0 and max_count > 0


## Message that makes `count` items (clamped to what the bag holds), null when nothing can be made.
func make(count: int) -> Variant:
	if not can_craft():
		return null
	return Protocol.craft_do(clampi(count, 1, max_count))
