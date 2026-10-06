## A Dofus world map (roadmap P1.08): the real texture tiles
## (Content/Worldmaps/<id>/1/<n>, maps.py worldmap; 1024 px, row-major from 1)
## laid out with the `worldmaps` table (origineX/Y = pixel of map 0,0,
## mapWidth/Height = pixels per map), and markers: the player's map, the
## known zaaps, the save point. Used by the world map window (M) and the
## minimap. Wheel = zoom, drag = pan (when `interactive`).
class_name WorldMapView
extends Control

signal clicked

const TILE := 1024.0

var world_map := -1
## screen px per texture px
var zoom := 0.5
var min_zoom := 0.25
var max_zoom := 1.0
## texture pixel shown at the centre of the control
var center := Vector2.ZERO
var interactive := true
## the player's map coordinates
var player := Vector2i.ZERO
## [{coords: [x, y], name}] known zaaps
var zaaps: Array = []
var save_coords := Vector2i.ZERO
var has_save := false
## [{coords: [x, y]}] resurrection phoenixes
var phoenixes: Array = []
## a quest offer / objective is on the player's map (P2.04b: map_markers only covers the current map)
var quest_mark := false
var _info := {}
var _drag := false
var _hover := Vector2i(1 << 20, 0)

static var _tiles := {} # "id/n" -> Texture2D


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func() -> void:
		_hover = Vector2i(1 << 20, 0)
		queue_redraw())


## Shows `id` (worldmaps.id); false when the world has no world map (interiors: -1).
func set_world(id: int) -> bool:
	if id != world_map:
		world_map = id
		_info = GameData.row("worldmaps", id) if id >= 0 else {}
		if not _info.is_empty():
			min_zoom = float(_info.get("minScale", 0.25))
			max_zoom = float(_info.get("maxScale", 1.0))
			if interactive:
				zoom = float(_info.get("startScale", zoom))
	queue_redraw()
	return not _info.is_empty()


## Centres the view on map coordinates.
func focus(coords: Vector2i) -> void:
	center = map_rect(coords).get_center()
	queue_redraw()


## Texture-pixel rectangle of one map.
func map_rect(c: Vector2i) -> Rect2:
	var w := float(_info.get("mapWidth", 69.0))
	var h := float(_info.get("mapHeight", 50.0))
	return Rect2(float(_info.get("origineX", 0)) + c.x * w, float(_info.get("origineY", 0)) + c.y * h, w, h)


func coords_at(screen: Vector2) -> Vector2i:
	var p := (screen - size * 0.5) / zoom + center
	var w := float(_info.get("mapWidth", 69.0))
	var h := float(_info.get("mapHeight", 50.0))
	return Vector2i(floori((p.x - float(_info.get("origineX", 0))) / w), floori((p.y - float(_info.get("origineY", 0))) / h))


func _to_screen(p: Vector2) -> Vector2:
	return (p - center) * zoom + size * 0.5


static func _tile(id: int, n: int) -> Texture2D:
	var key := "%d/%d" % [id, n]
	if not _tiles.has(key):
		var img := DofusContent.get_provider().load_image("Content/Worldmaps/%d/1/%d" % [id, n])
		_tiles[key] = ImageTexture.create_from_image(img) if img != null else null
	return _tiles[key]


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.08))
	if _info.is_empty():
		return
	var cols := ceili(float(_info["totalWidth"]) / TILE)
	var rows := ceili(float(_info["totalHeight"]) / TILE)
	var view := Rect2(Vector2.ZERO, size)
	for n in cols * rows:
		var at := Vector2((n % cols) * TILE, (n / cols) * TILE)
		var r := Rect2(_to_screen(at), Vector2(TILE, TILE) * zoom)
		if not view.intersects(r):
			continue
		var tex := _tile(world_map, n + 1)
		if tex != null:
			draw_texture_rect(tex, Rect2(r.position, tex.get_size() * zoom), false)
	var font := get_theme_default_font()
	if _hover.x != 1 << 20 and interactive:
		var hr := _screen_rect(_hover)
		draw_rect(hr, Color(1, 1, 1, 0.8), false, 1.5)
	for z: Dictionary in zaaps:
		var c: Array = z["coords"]
		var zr := _screen_rect(Vector2i(int(c[0]), int(c[1])))
		_marker(zr.position + zr.size * Vector2(0.75, 0.3), Color(0.3, 0.95, 0.85), 5)
	for ph: Dictionary in phoenixes:
		var c: Array = ph["coords"]
		var fr := _screen_rect(Vector2i(int(c[0]), int(c[1])))
		_marker(fr.position + fr.size * Vector2(0.5, 0.7), UiStyle.PHOENIX, 5)
	if has_save:
		var sr := _screen_rect(save_coords)
		var sc := sr.position + sr.size * Vector2(0.25, 0.3)
		draw_colored_polygon(PackedVector2Array([sc + Vector2(0, -6), sc + Vector2(6, 0), sc + Vector2(0, 6), sc + Vector2(-6, 0)]), UiStyle.GOLD)
	var pr := _screen_rect(player)
	draw_rect(pr, Color(1, 1, 1, 0.18))
	draw_rect(pr, Color.BLACK, false, 4.0)
	draw_rect(pr, Color.WHITE, false, 2.0)
	_marker(pr.get_center(), Color(1, 0.35, 0.25), 6)
	if quest_mark:
		var qa := pr.position + Vector2(pr.size.x, 0)
		draw_circle(qa, 8, Color.BLACK)
		draw_circle(qa, 6.5, UiStyle.GOLD)
		draw_string(font, qa + Vector2(-3, 5), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.BLACK)
	if interactive and _hover.x != 1 << 20:
		var t := "%d, %d" % [_hover.x, _hover.y]
		var at := get_local_mouse_position() + Vector2(14, -6)
		draw_string_outline(font, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color.BLACK)
		draw_string(font, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiStyle.TEXT)


func _screen_rect(c: Vector2i) -> Rect2:
	var r := map_rect(c)
	return Rect2(_to_screen(r.position), r.size * zoom)


func _marker(at: Vector2, color: Color, radius: float) -> void:
	draw_circle(at, radius + 2, Color.BLACK)
	draw_circle(at, radius, color)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var b := event as InputEventMouseButton
		if not interactive:
			if b.button_index == MOUSE_BUTTON_LEFT:
				clicked.emit()
			return
		match b.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				var before := (b.position - size * 0.5) / zoom + center
				zoom = clampf(zoom * (1.15 if b.button_index == MOUSE_BUTTON_WHEEL_UP else 1 / 1.15), min_zoom, max_zoom)
				center = before - (b.position - size * 0.5) / zoom
				queue_redraw()
				accept_event()
			MOUSE_BUTTON_LEFT:
				_drag = true
	elif event is InputEventMouseButton and not event.pressed:
		_drag = false
	elif event is InputEventMouseMotion:
		if _drag and interactive:
			center -= (event as InputEventMouseMotion).relative / zoom
		_hover = coords_at((event as InputEventMouseMotion).position)
		queue_redraw()
