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


## Where the map goes: {"zoom": float, "rect": Rect2 (the whole map on screen)}.
## The whole map (cells and the scenery around them) is fitted in the strip between the bands and
## centred on the screen's width; the panels (chat, minimap, tracker) float over it, they never push
## the map. Nothing is hidden outside it (the light blur of MapFrame is all there is).
func place(vp: Vector2, bounds: Rect2) -> Dictionary:
	var free := rect(vp)
	var z := maxf(0.01, minf(vp.x / bounds.size.x, free.size.y / bounds.size.y))
	var size := bounds.size * z
	return {"zoom": z, "rect": Rect2(Vector2((vp.x - size.x) * 0.5, free.position.y + (free.size.y - size.y) * 0.5), size)}


func _hits(r: Rect2) -> bool:
	for k: Variant in blocks:
		if r.intersects(blocks[k]):
			return true
	return false


## The player's zoom, as a share of the fitting zoom: 1 = the whole map (the minimum, so the void
## around the map is never shown), MAX_RATIO = a close look. Kept when the layout moves.
const MAX_RATIO := 2.5
const WHEEL := 1.1
var ratio := 1.0
## the world point the zoomed view is centred on (the player; the map's centre when unset)
var focus := Vector2.INF
## world points that must stay in the free strip, clear of the panels (the fighters of a fight)
var must_show: Array[Vector2] = []
const MARGIN := Vector2(45.0, 140.0) # world pixels kept left/right and above a fighter's feet (body, name tag)
const FEET := 30.0 # and below


## One wheel notch: `dir` > 0 zooms in. Returns true when the ratio changed.
func zoom_step(dir: int) -> bool:
	var old := ratio
	ratio = clampf(ratio * (WHEEL if dir > 0 else 1.0 / WHEEL), 1.0, MAX_RATIO)
	if absf(ratio - 1.0) < 0.02:
		ratio = 1.0
	return ratio != old


func reset_zoom() -> void:
	ratio = 1.0


## The transform for `vp`: {"zoom", "position"} of the camera, ratio applied and limited by must_show.
func camera_for(vp: Vector2) -> Dictionary:
	var bounds := MapGeometry.screen_bounds()
	var p := place(vp, bounds)
	var z0: float = p["zoom"]
	var r: Rect2 = p["rect"]
	var base := {"zoom": z0, "position": bounds.get_center() - (r.get_center() - vp * 0.5) / z0}
	if ratio <= 1.0:
		return base
	var t := ratio
	while t > 1.0:
		var c := _zoomed(vp, bounds, r, z0, t)
		if _shows_all(c, vp):
			return c
		t = maxf(1.0, t * 0.97)
		if t < 1.005:
			break
	return base


func _zoomed(vp: Vector2, bounds: Rect2, r: Rect2, z0: float, t: float) -> Dictionary:
	var z := z0 * t
	var free := rect(vp)
	var f := focus if focus.is_finite() else bounds.get_center()
	f = f.clamp(bounds.position, bounds.end)
	if not must_show.is_empty():
		var box := Rect2(must_show[0], Vector2.ZERO)
		for q in must_show:
			box = box.expand(q)
		f = box.get_center()
	var pos := f - (free.get_center() - vp * 0.5) / z
	var axes := [0, 1]
	for a in axes: # the map keeps covering the free strip: no empty edge
		var size: float = bounds.size[a] * z
		if size >= free.size[a]:
			var lo: float = bounds.end[a] - (free.end[a] - vp[a] * 0.5) / z # camera so the map's far edge meets the strip's
			var hi: float = bounds.position[a] - (free.position[a] - vp[a] * 0.5) / z
			pos[a] = clampf(pos[a], minf(lo, hi), maxf(lo, hi))
		else:
			pos[a] = bounds.get_center()[a] - (r.get_center()[a] - vp[a] * 0.5) / z
	return {"zoom": z, "position": pos}


func _shows_all(c: Dictionary, vp: Vector2) -> bool:
	var free := rect(vp)
	var z: float = c["zoom"]
	var pos: Vector2 = c["position"]
	for q in must_show:
		var box := Rect2((q - pos) * z + vp * 0.5 - MARGIN * z, Vector2(MARGIN.x * 2.0, MARGIN.y + FEET) * z)
		if not free.encloses(box) or _hits(box):
			return false
	return true


## Screen position of a world point with the player's zoom left out (ratio 1): where the map sits
## by default, for the panels that must keep clear of the cells.
func base_screen(vp: Vector2, world: Vector2) -> Vector2:
	var c := camera_for_ratio(vp, 1.0)
	return (world - (c["position"] as Vector2)) * float(c["zoom"]) + vp * 0.5


func camera_for_ratio(vp: Vector2, r: float) -> Dictionary:
	var old := ratio
	ratio = r
	var c := camera_for(vp)
	ratio = old
	return c


## Zoom and position the camera so that the map sits in `place`.
func fit(camera: Camera2D, vp: Vector2) -> void:
	var c := camera_for(vp)
	var z: float = c["zoom"]
	camera.zoom = Vector2(z, z)
	camera.position = c["position"]
