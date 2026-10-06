## The harvestable elements of one map and what became of them (P2.05): shared by every
## player on the map (a server keeps one per map, the resources are the same for all).
##   elements  MapData.interactives: [{e: element id, cell, gfx, skill}]
##   until[e]  sim time (ms) a harvested element grows back (absent = ready)
##   busy[e]   the player (actor id) harvesting it right now: nobody else can
class_name InteractiveState
extends RefCounted

var elements := {} # element id -> {e, cell, gfx, skill}
var until := {}
var busy := {}


func _init(list: Array = []) -> void:
	for el: Dictionary in list:
		elements[int(el["e"])] = el


func has(e: int) -> bool:
	return elements.has(e)


func element(e: int) -> Dictionary:
	return elements.get(e, {})


## Ready for `by` to harvest: not grown back yet, or someone else is on it, is not.
func available(e: int, by: int) -> bool:
	return has(e) and not until.has(e) and (not busy.has(e) or busy[e] == by)


func claim(e: int, by: int) -> void:
	busy[e] = by


func release(e: int, by: int) -> void:
	if busy.get(e, -1) == by:
		busy.erase(e)


## Harvested at `now`: gone until it grows back. Returns that time.
func deplete(e: int, now: int) -> int:
	busy.erase(e)
	until[e] = now + Jobs.RESPAWN_MS
	return int(until[e])


## Elements grown back by `now` (they become ready again).
func tick(now: int) -> Array[int]:
	var back: Array[int] = []
	for e: int in until.keys():
		if now >= int(until[e]):
			until.erase(e)
			back.append(e)
	return back


## [{e, until}] of the elements waiting to grow back (what a player entering the map is told).
func depleted() -> Array:
	return until.keys().map(func(e: int) -> Dictionary: return {"e": e, "until": int(until[e])})
