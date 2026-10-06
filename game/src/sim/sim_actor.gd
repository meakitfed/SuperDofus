## Anything standing on a map in the sim. Position is (cell) or a movement
## (path, t0, run); the arrival time is derived from shared/Movement, so sim
## and client agree on where the actor is at any instant.
class_name SimActor
extends RefCounted

var id := 0
var name := ""
var map_id := 0
## cell at rest, or the cell the current movement started from
var cell := 0
var dir := 1
var looks: PackedStringArray = []
var path: Array = []
var t0 := 0
var run := false


func kind() -> String:
	return "actor"


func is_moving(now: int) -> bool:
	return path.size() >= 2 and now < t0 + Movement.duration_ms(path, run)


## Cell the actor ends up on (current destination, or its cell when idle).
func dest_cell() -> int:
	return path[-1] if path.size() >= 2 else cell


## Settles a finished movement. Called every tick by the map.
func update(now: int) -> void:
	if path.size() >= 2 and not is_moving(now):
		dir = MapGeometry.facing(path[-2], path[-1])
		cell = path[-1]
		path = []


## Stops a movement on the last cell reached (e.g. when a fight starts).
func settle(now: int) -> void:
	if path.size() >= 2:
		var s := Movement.sample(path, t0, run, now)
		cell = path[s["index"]]
		if s["dir"] >= 0:
			dir = s["dir"]
		path = []


func start_move(p_path: Array, p_t0: int, p_run: bool) -> void:
	path = p_path
	t0 = p_t0
	run = p_run
	cell = p_path[0]


func to_dict(now: int) -> Dictionary:
	var d := {"id": id, "kind": kind(), "name": name, "cell": cell, "dir": dir, "looks": Array(looks)}
	if is_moving(now):
		d["move"] = {"path": path, "t0": t0, "run": run}
	return d
