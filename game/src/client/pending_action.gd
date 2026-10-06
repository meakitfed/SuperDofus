## The one action the player waits to do once the character has walked beside its
## target (like the Dofus client): leave through an edge cell, use a door, a zaap or
## the phoenix, talk to an NPC, harvest an element. At most one at a time, a new click
## replaces it (ClientSession._try_pending).
class_name PendingAction
extends RefCounted

enum Kind { NONE, EXIT, TRIGGER, ZAAP, PHOENIX, NPC, INTERACTIVE }

var kind := Kind.NONE
## EXIT: the side to leave through ("left" / "right" / "top" / "bottom")
var exit := ""
## TRIGGER: the door's cell · NPC: the NPC's actor id · INTERACTIVE: the element id
var target := -1


func is_set() -> bool:
	return kind != Kind.NONE


func clear() -> void:
	kind = Kind.NONE
	exit = ""
	target = -1


## Wait to use `kind` (ZAAP / PHOENIX need no target); replaces the previous action.
func set_to(p_kind: Kind, p_target := -1) -> void:
	clear()
	kind = p_kind
	target = p_target


## Wait to leave through `dir`; "" (not an exit cell) waits for nothing.
func set_exit(dir: String) -> void:
	clear()
	if dir != "":
		kind = Kind.EXIT
		exit = dir


## Exit direction of a clicked edge cell ("" if none): the side of the map
## closest to the click when the cell lies on a corner.
static func exit_for(map: MapData, cell: int, p: Vector2) -> String:
	var best := ""
	var best_d := INF
	var b := MapGeometry.screen_bounds()
	var dist := {"left": p.x - b.position.x, "right": b.end.x - p.x, "top": p.y - b.position.y, "bottom": b.end.y - p.y}
	for dir in map.exit_dirs(cell):
		if dist[dir] < best_d:
			best = dir
			best_d = dist[dir]
	return best
