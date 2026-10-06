## Movement timing, shared by sim (when does an actor arrive?) and client
## (where to draw it now?). A movement is (path of cellIds, t0 in ms, run).
## Step durations are the Dofus ones: screen-horizontal, screen-vertical, diagonal.
class_name Movement
extends RefCounted

const WALK := {"h": 510, "v": 425, "d": 480}
const RUN := {"h": 255, "v": 150, "d": 170}


static func step_ms(a: int, b: int, run: bool) -> int:
	var s := IsoGrid.cell_to_world(Vector2(MapGeometry.to_iso(b) - MapGeometry.to_iso(a)))
	var t: Dictionary = RUN if run else WALK
	if is_zero_approx(s.y):
		return t["h"]
	if is_zero_approx(s.x):
		return t["v"]
	return t["d"]


static func duration_ms(path: Array, run: bool) -> int:
	var total := 0
	for i in range(1, path.size()):
		total += step_ms(path[i - 1], path[i], run)
	return total


## Time at which path[index] is reached.
static func arrival_ms(path: Array, t0: int, run: bool, index: int) -> int:
	var t := t0
	for i in range(1, mini(index, path.size() - 1) + 1):
		t += step_ms(path[i - 1], path[i], run)
	return t


## State of a movement at `now`:
##   pos    IsoGrid coords (float) to draw at
##   index  last path index reached
##   dir    facing of the current (or last) step
##   moving false before t0 and after arrival
static func sample(path: Array, t0: int, run: bool, now: int) -> Dictionary:
	if path.size() < 2 or now <= t0:
		var d0 := MapGeometry.facing(path[0], path[1]) if path.size() >= 2 else -1
		return {"pos": Vector2(MapGeometry.to_iso(path[0])), "index": 0, "dir": d0, "moving": false}
	var t := t0
	for i in range(1, path.size()):
		var step := step_ms(path[i - 1], path[i], run)
		if now < t + step:
			var a := Vector2(MapGeometry.to_iso(path[i - 1]))
			var b := Vector2(MapGeometry.to_iso(path[i]))
			return {"pos": a.lerp(b, float(now - t) / step), "index": i - 1,
					"dir": MapGeometry.facing(path[i - 1], path[i]), "moving": true}
		t += step
	var last := path.size() - 1
	return {"pos": Vector2(MapGeometry.to_iso(path[last])), "index": last,
			"dir": MapGeometry.facing(path[last - 1], path[last]), "moving": false}


## New movement towards `target` that continues smoothly from the current one:
## an actor mid-step keeps walking to the next cell, then follows the new route.
## Returns {"path": [...], "t0": ms}, or an empty path if unreachable / already there.
static func replan(cur_path: Array, cur_t0: int, cur_run: bool, rest_cell: int, now: int,
		target: int, finder: MapPathfinder, start_delay_ms := 0) -> Dictionary:
	var s := sample(cur_path, cur_t0, cur_run, now) if cur_path.size() >= 2 else {"moving": false}
	if s["moving"]:
		var idx: int = s["index"]
		var rest := finder.find_path(cur_path[idx + 1], target)
		if rest.is_empty():
			return {"path": [], "t0": now}
		return {"path": [cur_path[idx]] + rest, "t0": arrival_ms(cur_path, cur_t0, cur_run, idx)}
	var p := finder.find_path(rest_cell, target)
	return {"path": p if p.size() >= 2 else [], "t0": now + start_delay_ms}
