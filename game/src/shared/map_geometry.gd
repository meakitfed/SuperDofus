## Dofus map geometry, shared by sim and client. Pure static helpers, no nodes.
## A map is 14 x 20 = 560 cells laid out in 40 staggered screen rows of 14:
## cellId = row * 14 + col, odd rows shifted half a cell to the right.
## Each cell also has IsoGrid coords (the diamond lattice), used for screen
## conversion, facing and A*. Row 0 walks +x/-y, each half row adds +x or +y.
class_name MapGeometry
extends RefCounted

const WIDTH := 14
const HEIGHT := 20
const ROWS := 40
const CELL_COUNT := 560
## IsoGrid-space bounding box of the 560 cells (x 0..33, y -13..19)
const ISO_REGION := Rect2i(0, -13, 34, 33)
## map edges, in the order the client tests them
const DIRS: PackedStringArray = ["left", "right", "top", "bottom"]

static var _iso: Array[Vector2i] = []
static var _by_iso: Dictionary = {}


static func _ensure() -> void:
	if not _iso.is_empty():
		return
	var sx := 0
	var sy := 0
	for a in HEIGHT:
		for half in 2:
			for b in WIDTH:
				var p := Vector2i(sx + b, -(sy + b))
				_by_iso[p] = _iso.size()
				_iso.append(p)
			if half == 0:
				sx += 1
			else:
				sy -= 1


static func is_valid(cell: int) -> bool:
	return cell >= 0 and cell < CELL_COUNT


static func row(cell: int) -> int:
	return cell / WIDTH


static func col(cell: int) -> int:
	return cell % WIDTH


static func to_iso(cell: int) -> Vector2i:
	_ensure()
	return _iso[cell]


## -1 if the iso coords are outside the map.
static func from_iso(p: Vector2i) -> int:
	_ensure()
	return _by_iso.get(p, -1)


static func to_screen(cell: int) -> Vector2:
	return IsoGrid.cell_to_world(Vector2(to_iso(cell)))


## -1 if the point is outside every cell.
static func screen_to_cell(p: Vector2) -> int:
	return from_iso(IsoGrid.world_to_cell(p))


## Screen-space rectangle covering the map (cell diamonds included).
static func screen_bounds() -> Rect2:
	var half := Vector2(IsoGrid.CELL_W, IsoGrid.CELL_H) * 0.5
	return Rect2(-half, Vector2((WIDTH - 0.5) * IsoGrid.CELL_W, (ROWS - 1) * IsoGrid.CELL_H * 0.5) + half * 2.0)


## Facing (clockwise from screen-east, = DofusAnimNames.Direction) of a step a -> b.
static func facing(a: int, b: int) -> int:
	return IsoGrid.facing_for_cell_delta(to_iso(b) - to_iso(a))


## Chebyshev distance on the diamond lattice (number of 8-dir steps).
static func distance(a: int, b: int) -> int:
	var d := to_iso(b) - to_iso(a)
	return maxi(absi(d.x), absi(d.y))


static func neighbors(cell: int) -> Array[int]:
	var out: Array[int] = []
	var p := to_iso(cell)
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var n := from_iso(p + Vector2i(dx, dy))
			if n >= 0:
				out.append(n)
	return out


## Edges ("left", "right", "top", "bottom") a cell belongs to. Map changes start from these.
static func edge_dirs(cell: int) -> PackedStringArray:
	var out := PackedStringArray()
	if col(cell) == 0:
		out.append("left")
	if col(cell) == WIDTH - 1:
		out.append("right")
	if row(cell) <= 1:
		out.append("top")
	if row(cell) >= ROWS - 2:
		out.append("bottom")
	return out


static func is_edge(cell: int, dir := "") -> bool:
	var dirs := edge_dirs(cell)
	return not dirs.is_empty() if dir == "" else dirs.has(dir)


static func opposite(dir: String) -> String:
	return {"left": "right", "right": "left", "top": "bottom", "bottom": "top"}.get(dir, "")


## Cell where you arrive on the neighbour map after leaving through `dir` from `cell`.
static func mirror_cell(cell: int, dir: String) -> int:
	var r := row(cell)
	var c := col(cell)
	match dir:
		"left":
			return r * WIDTH + WIDTH - 1
		"right":
			return r * WIDTH
		"top":
			return (r + ROWS - 2) * WIDTH + c
		"bottom":
			return (r - (ROWS - 2)) * WIDTH + c
	return cell
