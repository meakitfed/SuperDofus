## Where the exploration HUD sits (lot U.04, docs/ui/ADAPTATIF.md 2.3): one pure function from the
## virtual viewport and the size of each part to the position of each part, like the corners of the
## Dofus banner. Place names top left, the group under them, the minimap and the quest tracker top
## right, the dungeon widget top centre, the chat bottom left above the bottom band. The session
## applies the result only when its inputs changed (no position set per frame).
## Pure layout (no Node), so the tests run it at every window shape.
class_name HudLayout
extends RefCounted

const MARGIN := 12.0
const GAP := 8.0
## the chat keeps this share of the screen, between a floor (readable) and a ceiling (never a wall of text)
const CHAT_MIN := Vector2(440.0, 150.0)
const CHAT_MAX := Vector2(520.0, 280.0)
const CHAT_SHARE := Vector2(0.36, 0.27)
## the minimum height kept free above the bottom band for the chat
const BAND_FLOOR := 96.0


## Chat size for a viewport: a third of the width and a quarter of the height, within bounds.
static func chat_size(vp: Vector2) -> Vector2:
	return Vector2(clampf(vp.x * CHAT_SHARE.x, CHAT_MIN.x, CHAT_MAX.x), clampf(vp.y * CHAT_SHARE.y, CHAT_MIN.y, CHAT_MAX.y))


## Width of the side panels (minimap, tracker): narrower on a narrow window.
static func side_width(vp: Vector2) -> float:
	return clampf(vp.x * 0.19, 200.0, 260.0)


## `sizes`: name -> Vector2 of the parts that are shown ("mapinfo", "party", "minimap", "tracker",
## "dungeon", "chat"); `band`: the bottom band (spell bar, fight bar) the chat sits above.
## Returns name -> Vector2 position, for the same names.
static func place(vp: Vector2, sizes: Dictionary, band: float) -> Dictionary:
	var out := {}
	var left_y := MARGIN
	if sizes.has("mapinfo"):
		out["mapinfo"] = Vector2(MARGIN + 2.0, MARGIN - 4.0)
		left_y = (out["mapinfo"] as Vector2).y + (sizes["mapinfo"] as Vector2).y + GAP
	if sizes.has("party"):
		out["party"] = Vector2(MARGIN, left_y)
	var right_y := MARGIN
	if sizes.has("minimap"):
		var s: Vector2 = sizes["minimap"]
		out["minimap"] = Vector2(vp.x - s.x - MARGIN, MARGIN)
		right_y += s.y + GAP
	if sizes.has("tracker"):
		var s: Vector2 = sizes["tracker"]
		out["tracker"] = Vector2(vp.x - s.x - MARGIN, right_y)
	if sizes.has("dungeon"):
		var s: Vector2 = sizes["dungeon"]
		out["dungeon"] = Vector2((vp.x - s.x) * 0.5, MARGIN)
	if sizes.has("chat"):
		var s: Vector2 = sizes["chat"]
		out["chat"] = Vector2(MARGIN, vp.y - s.y - maxf(BAND_FLOOR, band))
	return out


## During a fight the chat shrinks (never moves the map) so that it stays clear of every cell a
## fighter can stand on: `cells` are those cells' screen positions (feet), `pad` what a fighter takes
## around its feet (left/right, above, below). The chat keeps its bottom left corner (`at`: its
## position for the size `want`); returns the largest size, at most `want`, whose rectangle touches
## no fighter, or Vector2.ZERO when not even CHAT_FLOOR fits (the chat is folded away for the fight).
const CHAT_FLOOR := Vector2(260.0, 90.0)


static func chat_room(at: Vector2, want: Vector2, cells: PackedVector2Array, pad: Vector4) -> Vector2:
	var bottom := at.y + want.y
	var best := Vector2.ZERO
	var w := want.x
	while w >= CHAT_FLOOR.x:
		var h := want.y
		while h >= CHAT_FLOOR.y:
			if w * h > best.x * best.y and _clear(Rect2(at.x, bottom - h, w, h), cells, pad):
				best = Vector2(w, h)
				break # a smaller h only loses area at this width
			h -= 10.0
		w -= 12.0
	return best


static func _clear(r: Rect2, cells: PackedVector2Array, pad: Vector4) -> bool:
	for c in cells:
		if r.intersects(Rect2(c.x - pad.x, c.y - pad.y, pad.x * 2.0, pad.y + pad.z)):
			return false
	return true
