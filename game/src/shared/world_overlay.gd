## Data a world brings with it, merged over the global data (data/) without touching it:
##   worlds/<id>/data/items.json          {"items": [...], "sets": [...]}  (GameData)
##   worlds/<id>/data/spells.json         {"classes", "grades", "spells", "summons"}  (SpellBook)
##   worlds/<id>/data/tables/<name>.json  {"objectsById": {...}}  (GameData.table: breeds, skills, jobs...)
##   worlds/<id>/Content/...              bones, icons, maps, Content/I18n/extra_<lang>.json (ContentSourceProvider layer)
## and settings of worlds/<id>/world.json:
##   "breeds": [ids]       the classes this world offers (a world without the key offers every breed no other world claims)
##   "default_breed": id   the class a character without one gets (default 12)
## Everything only ADDS: an id already in the global data is never replaced, so the overlays of several worlds
## (a server hosting them all, ContentSource.add_overlay) live side by side: ids are disjoint. The overlay of a
## downloaded world travels in its package (worlds/<id>/**), so a world is complete on its own.
class_name WorldOverlay
extends RefCounted

const DEFAULT_BREED := 12


## Parsed worlds/<id>/<rel_path> of every world whose overlay is active (Dictionaries only), in activation order.
static func read_all(rel_path: String) -> Array:
	var out: Array = []
	for id in ContentSource.overlays():
		var d: Variant = ContentSource.read_json("worlds/%s/%s" % [id, rel_path])
		if d is Dictionary:
			out.append(d)
	return out


static func _world_json(world_id: String) -> Dictionary:
	if world_id == "":
		return {}
	var d: Variant = ContentSource.read_json("worlds/%s/world.json" % world_id)
	return d if d is Dictionary else {}


## The world the interface shows: the one being played (client), else the last overlay of the process.
static func ui_world() -> String:
	if ContentSource.world() != "":
		return ContentSource.world()
	var all := ContentSource.overlays()
	return all[all.size() - 1] if not all.is_empty() else ""


## May a character of `world_id` be of class `breed`? A world that lists its classes offers those; any other
## offers every class that no active world claims for itself.
static func allowed_breed(world_id: String, breed: int) -> bool:
	var own := _world_json(world_id).get("breeds", []) as Array
	if not own.is_empty():
		return own.has(breed) or own.has(float(breed))
	for id in ContentSource.overlays():
		var claimed := _world_json(id).get("breeds", []) as Array
		if claimed.has(breed) or claimed.has(float(breed)):
			return false
	return true


static func default_breed(world_id: String) -> int:
	return int(_world_json(world_id).get("default_breed", DEFAULT_BREED))
