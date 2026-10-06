## Draws the current map's cells (placeholder ground until real map graphics),
## obstacles, exits, the hovered cell and the path preview.
class_name MapView
extends Node2D

var map: MapData
var hover := -1
## placeholder ground (no extracted Dofus map); with a real map only overlays are drawn
var draw_ground := true
## highlight the hovered cell (fight); off in roleplay like the Dofus client
var show_hover := true
## tools: outline every walkable cell, exits in green, doors in blue, cell ids
var debug := false
var preview: Array = []
## the player is a ghost: the phoenix is shown more (Energy)
var ghost := false
## cellId -> Color drawn over the ground (fight ranges, reachable cells…)
var overlays := {}


func set_map(p_map: MapData) -> void:
	map = p_map
	hover = -1
	preview = []
	overlays = {}
	queue_redraw()


func _draw() -> void:
	if map == null:
		return
	for c in (MapGeometry.CELL_COUNT if draw_ground else 0):
		var iso := MapGeometry.to_iso(c)
		var fill: Color = map.ground[posmod(iso.x + iso.y, 2)]
		if not map.is_walkable(c):
			fill = fill.darkened(0.55)
		elif not map.exit_dirs(c).is_empty():
			fill = fill.lightened(0.12)
		draw_colored_polygon(_diamond(c, 1.0), fill)
		if not map.is_walkable(c):
			draw_colored_polygon(_diamond(c, 0.55, Vector2(0, -10)), fill.darkened(0.3))
	for c: int in overlays:
		draw_colored_polygon(_diamond(c, 0.92), overlays[c])
	for c in preview:
		draw_colored_polygon(_diamond(int(c), 0.5), Color(1, 1, 1, 0.25))
	if map.phoenix >= 0: # the phoenix: the statue is server data, its place glows
		for c: int in map.use_cells(map.phoenix) + [map.phoenix]:
			draw_colored_polygon(_diamond(c, 0.9), Color(UiStyle.PHOENIX, 0.28 if ghost else 0.12))
	if debug:
		_draw_debug()
	var passage := hover >= 0 and is_passage(hover)
	if hover >= 0 and (show_hover or draw_ground or passage):
		var outline := _diamond(hover, 1.0)
		outline.append(outline[0])
		var ok := map.is_walkable(hover)
		var col := Color(1, 1, 1, 0.8) if ok else Color(1, 0.3, 0.3, 0.8)
		if passage and not show_hover: # roleplay: only exits and doors light up, like the Dofus map-change cursor
			col = UiStyle.GOLD
			draw_colored_polygon(_diamond(hover, 1.0), Color(UiStyle.GOLD, 0.25))
		draw_polyline(outline, col, 2.0)


## A cell that leads to another map (edge exit, door and the blocked cells its
## sprite covers) or the zaap.
func is_passage(cell: int) -> bool:
	if map == null:
		return false
	if (map.zaap >= 0 and is_zaap(cell)) or is_phoenix(cell) or map.door_near(cell) >= 0:
		return true
	return map.is_walkable(cell) and not map.exit_dirs(cell).is_empty()


## The zaap's cell or a blocked cell touching it (the arch covers them).
func is_zaap(cell: int) -> bool:
	return map != null and map.zaap >= 0 and (cell == map.zaap or (not map.is_walkable(cell) and MapGeometry.distance(cell, map.zaap) <= 1))


## The phoenix's cell or a blocked cell touching it.
func is_phoenix(cell: int) -> bool:
	return map != null and map.phoenix >= 0 and (cell == map.phoenix or (not map.is_walkable(cell) and MapGeometry.distance(cell, map.phoenix) <= 1))


func _draw_debug() -> void:
	var font := ThemeDB.fallback_font
	for c in MapGeometry.CELL_COUNT:
		if not map.is_walkable(c) and c != map.zaap and map.trigger_at(c).is_empty():
			continue
		var outline := _diamond(c, 1.0)
		outline.append(outline[0])
		var col := Color(1, 1, 1, 0.25)
		if c == map.zaap:
			col = Color(0.3, 1.0, 0.9, 0.9)
		elif not map.trigger_at(c).is_empty():
			col = Color(0.3, 0.6, 1.0, 0.9)
			draw_colored_polygon(_diamond(c, 1.0), Color(0.3, 0.6, 1.0, 0.35))
		elif not map.exit_dirs(c).is_empty():
			col = Color(0.4, 1.0, 0.4, 0.9)
		draw_polyline(outline, col, 1.0)
		draw_string(font, MapGeometry.to_screen(c) + Vector2(-9, 4), str(c), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.8))


func _diamond(cell: int, scale: float, offset := Vector2.ZERO) -> PackedVector2Array:
	var c := MapGeometry.to_screen(cell) + offset
	var w := IsoGrid.CELL_W * 0.5 * scale
	var h := IsoGrid.CELL_H * 0.5 * scale
	return PackedVector2Array([c + Vector2(0, -h), c + Vector2(w, 0), c + Vector2(0, h), c + Vector2(-w, 0)])
