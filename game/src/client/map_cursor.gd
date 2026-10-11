## The mouse cursor over the map, like the Dofus client: an arrow towards the next map over
## an exit cell, a hand over what can be used (door, zaap, phoenix, resource, NPC). Arrows
## are drawn once (gold, dark outline, UiStyle). Changed only when the kind changes.
class_name MapCursor
extends RefCounted

const SIZE := 32
## "" = the normal cursor
const KINDS := ["", "top", "bottom", "left", "right", "use"]

static var _arrows := {} # side -> ImageTexture
static var _current := ""


## Shows the cursor of `kind` (KINDS).
static func show(kind: String) -> void:
	if kind == _current:
		return
	_current = kind
	if kind in ["top", "bottom", "left", "right"]:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		Input.set_custom_mouse_cursor(arrow(kind), Input.CURSOR_ARROW, Vector2(SIZE, SIZE) * 0.5)
		return
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if kind == "use" else Input.CURSOR_ARROW)


static func current() -> String:
	return _current


## A chevron arrow pointing to `side`.
static func arrow(side: String) -> ImageTexture:
	if not _arrows.has(side):
		var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		# pointing up: a filled triangle (tip at the top) over a short stem; then rotated
		var tri := PackedVector2Array([Vector2(16, 3), Vector2(28, 17), Vector2(4, 17)])
		var stem := Rect2(11, 17, 10, 11)
		for y in SIZE:
			for x in SIZE:
				var p := Vector2(x + 0.5, y + 0.5)
				if Geometry2D.is_point_in_polygon(p, tri) or stem.has_point(p):
					img.set_pixel(x, y, UiStyle.GOLD)
		var out := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8) # a dark outline around the shape
		for y in SIZE:
			for x in SIZE:
				if img.get_pixel(x, y).a > 0.0:
					out.set_pixel(x, y, img.get_pixel(x, y))
				elif _touches(img, x, y):
					out.set_pixel(x, y, Color(0, 0, 0, 0.9))
		match side:
			"bottom":
				out.flip_y()
			"right":
				out.rotate_90(CLOCKWISE)
			"left":
				out.rotate_90(COUNTERCLOCKWISE)
		_arrows[side] = ImageTexture.create_from_image(out)
	return _arrows[side]


static func _touches(img: Image, x: int, y: int) -> bool:
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		var q := Vector2i(x, y) + d
		if q.x >= 0 and q.y >= 0 and q.x < SIZE and q.y < SIZE and img.get_pixelv(q).a > 0.0:
			return true
	return false
