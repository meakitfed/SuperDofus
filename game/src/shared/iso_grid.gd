## Isometric diamond lattice (Dofus proportions: 86 x 43 px cells): screen <-> iso coords.
## Cell space: +x goes screen south-east, +y goes screen south-west. MapGeometry maps the
## 560 cells of a map onto it.
class_name IsoGrid
extends RefCounted

const CELL_W := 86.0
const CELL_H := 43.0


static func cell_to_world(c: Vector2) -> Vector2:
	return Vector2((c.x - c.y) * CELL_W * 0.5, (c.x + c.y) * CELL_H * 0.5)


static func world_to_cell(p: Vector2) -> Vector2i:
	var cx := p.x / (CELL_W * 0.5)
	var cy := p.y / (CELL_H * 0.5)
	return Vector2i(roundi((cy + cx) * 0.5), roundi((cy - cx) * 0.5))


## Facing (clockwise from screen-east, numbered like DofusAnimNames.Direction) of a move by `d` cells.
static func facing_for_cell_delta(d: Vector2i) -> int:
	var screen := cell_to_world(Vector2(d))
	var angle := atan2(screen.y, screen.x) # y down: clockwise positive
	return posmod(roundi(angle / (PI / 4.0)), 8)
