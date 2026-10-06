## A* over one map's cells (8 directions, no corner cutting). Same code on sim
## (authoritative path) and client (follower placement, prediction).
class_name MapPathfinder
extends RefCounted

var map: MapData
var _astar := AStarGrid2D.new()


func _init(p_map: MapData) -> void:
	map = p_map
	_astar.region = MapGeometry.ISO_REGION
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()
	_astar.fill_solid_region(_astar.region, true)
	for cell in MapGeometry.CELL_COUNT:
		if map.is_walkable(cell):
			_astar.set_point_solid(MapGeometry.to_iso(cell), false)


## cellIds from `from` to `to`, both included. Empty if unreachable.
func find_path(from: int, to: int) -> Array:
	var out: Array = []
	if not map.is_walkable(from) or not map.is_walkable(to):
		return out
	for p in _astar.get_id_path(MapGeometry.to_iso(from), MapGeometry.to_iso(to)):
		out.append(MapGeometry.from_iso(p))
	return out
