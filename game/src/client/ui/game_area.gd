## The part of the screen the map may use (docs/ui/ADAPTATIF.md 2.5, lot U.01).
## The HUD declares what it takes: a band at the top (fight timeline), a band at the bottom
## (spell bar, fight bar and its options), and floating panels (chat, minimap, quest tracker,
## fight challenges) as rectangles. `fit` then puts the whole map in the largest spot that
## touches none of them, so no cell, no monster and no player is ever behind the UI.
## Pure layout (no Node): the session feeds it and applies the result to its Camera2D.
class_name GameArea
extends RefCounted

## the layout changed (a band or a panel moved, appeared or went away): fit the camera again
signal changed

## the smallest zoom tried, as a share of the zoom that fills the free band
const MIN_SHARE := 0.35
const ZOOM_STEP := 0.97
const GRID := 16

var top := 0.0
var bottom := 0.0
var blocks := {} # name -> Rect2


## Sets the bands and the panels at once; emits `changed` only when something moved by more than a pixel.
func set_layout(p_top: float, p_bottom: float, p_blocks: Dictionary) -> void:
	if absf(top - p_top) <= 1.0 and absf(bottom - p_bottom) <= 1.0 and _same_blocks(p_blocks):
		return
	top = p_top
	bottom = p_bottom
	blocks = p_blocks.duplicate()
	changed.emit()


func _same_blocks(other: Dictionary) -> bool:
	if other.size() != blocks.size():
		return false
	for k: Variant in other:
		if not blocks.has(k):
			return false
		var a: Rect2 = blocks[k]
		var b: Rect2 = other[k]
		if a.position.distance_to(b.position) > 1.0 or a.size.distance_to(b.size) > 1.0:
			return false
	return true


## The strip between the two bands.
func rect(vp: Vector2) -> Rect2:
	return Rect2(0.0, top, vp.x, maxf(1.0, vp.y - top - bottom))


## Where the map goes: {"zoom": float, "rect": Rect2 (the map's bounds on screen)}.
## The largest zoom for which a position exists that overlaps no panel, the nearest one to the
## centre of the screen (the panels sit in the corners, so the map slides away from them).
func place(vp: Vector2, bounds: Rect2) -> Dictionary:
	var free := rect(vp)
	var z0 := maxf(0.01, minf(free.size.x / bounds.size.x, free.size.y / bounds.size.y))
	var z := z0
	while z >= z0 * MIN_SHARE:
		var size := bounds.size * z
		var spot := _spot(free, size, vp)
		if spot.size.x > 0.0:
			return {"zoom": z, "rect": spot}
		z *= ZOOM_STEP
	var size0 := bounds.size * z0 # nothing fits (tiny window): the whole strip, panels or not
	return {"zoom": z0, "rect": Rect2(free.position + (free.size - size0) * 0.5, size0)}


## A rect of `size` inside `free` clear of every block, nearest to the centre; size 0 when none.
func _spot(free: Rect2, size: Vector2, vp: Vector2) -> Rect2:
	var slack := free.size - size
	if slack.x < -0.5 or slack.y < -0.5:
		return Rect2()
	var ideal := Vector2(clampf((vp.x - size.x) * 0.5, free.position.x, free.position.x + slack.x),
			free.position.y + slack.y * 0.5)
	var xs := _candidates(ideal.x, free.position.x, maxf(0.0, slack.x))
	var ys := _candidates(ideal.y, free.position.y, maxf(0.0, slack.y))
	for y: float in ys:
		for x: float in xs:
			var r := Rect2(x, y, size.x, size.y)
			if not _hits(r):
				return r
	return Rect2()


func _hits(r: Rect2) -> bool:
	for k: Variant in blocks:
		if r.intersects(blocks[k]):
			return true
	return false


## The ideal coordinate, then a regular scan of [from, from + span], nearest to the ideal first.
static func _candidates(ideal: float, from: float, span: float) -> Array[float]:
	var out: Array[float] = [ideal]
	for i in GRID + 1:
		out.append(from + span * i / GRID)
	out.sort_custom(func(a: float, b: float) -> bool: return absf(a - ideal) < absf(b - ideal))
	return out


## Zoom and position the camera so that the map sits in `place`.
func fit(camera: Camera2D, vp: Vector2) -> void:
	var bounds := MapGeometry.screen_bounds()
	var p := place(vp, bounds)
	var z: float = p["zoom"]
	var r: Rect2 = p["rect"]
	camera.zoom = Vector2(z, z)
	camera.position = bounds.get_center() - (r.get_center() - vp * 0.5) / z
