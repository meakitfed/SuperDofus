## Isometric diamond grid (Dofus proportions: 86 x 43 px cells) + A* pathfinding.
## Cell space: +x goes screen south-east, +y goes screen south-west.
class_name IsoGrid
extends RefCounted

const CELL_W := 86.0
const CELL_H := 43.0

var size: Vector2i
var _astar := AStarGrid2D.new()


func _init(p_size: Vector2i) -> void:
	size = p_size
	_astar.region = Rect2i(Vector2i.ZERO, size)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()


static func cell_to_world(c: Vector2) -> Vector2:
	return Vector2((c.x - c.y) * CELL_W * 0.5, (c.x + c.y) * CELL_H * 0.5)


static func world_to_cell(p: Vector2) -> Vector2i:
	var cx := p.x / (CELL_W * 0.5)
	var cy := p.y / (CELL_H * 0.5)
	return Vector2i(roundi((cy + cx) * 0.5), roundi((cy - cx) * 0.5))


## Facing (GameEntity.Facing, clockwise from screen-east) of a move by `d` cells.
static func facing_for_cell_delta(d: Vector2i) -> int:
	var screen := cell_to_world(Vector2(d))
	var angle := atan2(screen.y, screen.x) # y down: clockwise positive
	return posmod(roundi(angle / (PI / 4.0)), 8)


func in_bounds(c: Vector2i) -> bool:
	return _astar.is_in_boundsv(c)


func set_blocked(c: Vector2i, blocked: bool) -> void:
	if in_bounds(c):
		_astar.set_point_solid(c, blocked)


func is_blocked(c: Vector2i) -> bool:
	return not in_bounds(c) or _astar.is_point_solid(c)


func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not in_bounds(from) or not in_bounds(to) or is_blocked(to):
		return out
	for p in _astar.get_id_path(from, to):
		out.append(p)
	return out
