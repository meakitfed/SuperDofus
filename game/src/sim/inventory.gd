## A character's items (roadmap P1.05). An item instance is a JSON-safe dict
## {uid, id, qty, effects, pos, reserve} (reserve: the forgemagie puits, in hundredths, absent = 0; effects: ItemEffects format; pos: the
## Equipment slot it is worn in, -1 in the bag). Instances of the same item with
## the same effects stack in the bag; uids come from Persistence.next_uid, unique
## across the whole game (the server's database later).
class_name Inventory
extends RefCounted

const BAG := -1

var items := {} # uid -> instance


## The stack `id` + `effects` (+ forgemagie `reserve`) would join (0 = a new one).
func find_stack(id: int, effects: Array, reserve := 0) -> int:
	for uid: int in items:
		var it: Dictionary = items[uid]
		if int(it["id"]) == id and it["effects"] == effects and int(it.get("pos", BAG)) == BAG 				and int(it.get("reserve", 0)) == reserve:
			return uid
	return 0


## Adds `qty` items; `new_uid` is called when a new stack is needed. Returns the stack.
func add(id: int, qty: int, effects: Array, new_uid: Callable, reserve := 0) -> Dictionary:
	var uid := find_stack(id, effects, reserve)
	if uid == 0:
		uid = int(new_uid.call())
		items[uid] = {"uid": uid, "id": id, "qty": 0, "effects": effects.duplicate(true), "pos": BAG}
		if reserve != 0:
			items[uid]["reserve"] = reserve
	items[uid]["qty"] = int(items[uid]["qty"]) + qty
	return items[uid]


## Removes `qty` of a stack: the stack left, or {} when it is gone.
func remove(uid: int, qty: int) -> Dictionary:
	var it: Dictionary = items[uid]
	it["qty"] = int(it["qty"]) - qty
	if int(it["qty"]) <= 0:
		items.erase(uid)
		return {}
	return it


func get_item(uid: int) -> Dictionary:
	return items.get(uid, {})


## Total weight (items.realWeight × quantity), in pods.
func weight() -> int:
	var w := 0
	for it: Dictionary in items.values():
		w += int(GameData.item(int(it["id"])).get("weight", 1)) * int(it["qty"])
	return w


## The worn instances: slot -> instance.
func worn() -> Dictionary:
	var out := {}
	for it: Dictionary in items.values():
		if int(it.get("pos", BAG)) != BAG:
			out[int(it["pos"])] = it
	return out


## How many of an item the bag holds (worn ones excluded).
func bag_count(id: int) -> int:
	var n := 0
	for it: Dictionary in items.values():
		if int(it["id"]) == id and int(it.get("pos", BAG)) == BAG:
			n += int(it["qty"])
	return n


## Takes `qty` of an item from the bag stacks (lowest uid first). Returns [{uid, left: the stack, {} when gone}].
func take(id: int, qty: int) -> Array:
	var out := []
	var uids := items.keys()
	uids.sort()
	for uid: int in uids:
		var it: Dictionary = items[uid]
		if qty <= 0:
			break
		if int(it["id"]) != id or int(it.get("pos", BAG)) != BAG:
			continue
		var n := mini(qty, int(it["qty"]))
		qty -= n
		out.append({"uid": uid, "left": remove(uid, n)})
	return out


func count(id: int) -> int:
	var n := 0
	for it: Dictionary in items.values():
		if int(it["id"]) == id:
			n += int(it["qty"])
	return n


## Instances sorted by uid (JSON-safe copies).
func to_array() -> Array:
	var uids := items.keys()
	uids.sort()
	return uids.map(func(u: int) -> Dictionary: return items[u].duplicate(true))


static func from_array(a: Array) -> Inventory:
	var inv := Inventory.new()
	for it: Dictionary in a:
		var uid := int(it.get("uid", 0))
		inv.items[uid] = {"uid": uid, "id": int(it["id"]), "qty": int(it["qty"]), "pos": int(it.get("pos", BAG)),
				"effects": (it.get("effects", []) as Array).map(func(e: Array) -> Array: return e.map(func(x: Variant) -> int: return int(x)))}
		if int(it.get("reserve", 0)) != 0:
			inv.items[uid]["reserve"] = int(it["reserve"])
	return inv
