## Where the fight HUD sits (lot U.05, docs/ui/ADAPTATIF.md 2.3): one pure function from the virtual
## viewport and the size of each part to the position of each part, like HudLayout for exploration.
## The timeline is top centre (and shrinks when there are many fighters), the spell bar bottom
## centre with the fight options above its right end, the challenges under the timeline at the left,
## the short message in the free strip between the bands. FightHud applies the result only when its
## inputs changed (no position set per frame). Pure layout (no Node): tests run it at every window shape.
class_name FightLayout
extends RefCounted

const MARGIN := 12.0
const TOP_GAP := 10.0
const BAND_GAP := 8.0
const OPTIONS_GAP := 6.0
## a tile never gets smaller than this share of its size (still readable)
const MIN_TILE_SCALE := 0.6
const TILE_GAP := 6.0


## Scale of the timeline so that `count` tiles of `tile_w` fit the width of `vp_w` (1.0 when they do).
static func timeline_scale(vp_w: float, count: int, tile_w: float) -> float:
	if count <= 0:
		return 1.0
	var needed := count * tile_w + (count - 1) * TILE_GAP
	return clampf((vp_w - 2.0 * MARGIN) / needed, MIN_TILE_SCALE, 1.0)


## `sizes`: name -> Vector2 of the parts that are shown ("timeline", "bar", "options", "banner",
## "message", already scaled). Returns name -> Vector2 position, for the same names.
## `top` / `bottom` are the bands' heights (see `bands`).
static func place(vp: Vector2, sizes: Dictionary) -> Dictionary:
	var out := {}
	var top := 0.0
	if sizes.has("timeline"):
		var s: Vector2 = sizes["timeline"]
		out["timeline"] = Vector2(maxf(MARGIN, (vp.x - s.x) * 0.5), TOP_GAP)
		top = TOP_GAP + s.y + BAND_GAP
	var bottom := 0.0
	if sizes.has("bar"):
		var s: Vector2 = sizes["bar"]
		out["bar"] = Vector2(maxf(0.0, (vp.x - s.x) * 0.5), vp.y - s.y - MARGIN)
		bottom = MARGIN + s.y + BAND_GAP
		if sizes.has("options"):
			var o: Vector2 = sizes["options"]
			out["options"] = Vector2(maxf(0.0, (out["bar"] as Vector2).x + s.x - o.x), (out["bar"] as Vector2).y - o.y - OPTIONS_GAP)
			bottom += o.y + OPTIONS_GAP
	if sizes.has("banner"):
		out["banner"] = Vector2(MARGIN, top + 4.0)
	if sizes.has("message"):
		var s: Vector2 = sizes["message"]
		var free_h := maxf(1.0, vp.y - top - bottom - s.y)
		out["message"] = Vector2((vp.x - s.x) * 0.5, top + free_h * 0.3)
	return out


## Heights of the top and the bottom band for the same sizes (what the map keeps out of).
static func bands(sizes: Dictionary) -> Vector2:
	var top := 0.0
	if sizes.has("timeline"):
		top = TOP_GAP + (sizes["timeline"] as Vector2).y + BAND_GAP
	var bottom := 0.0
	if sizes.has("bar"):
		bottom = MARGIN + (sizes["bar"] as Vector2).y + BAND_GAP
		if sizes.has("options"):
			bottom += (sizes["options"] as Vector2).y + OPTIONS_GAP
	return Vector2(top, bottom)
