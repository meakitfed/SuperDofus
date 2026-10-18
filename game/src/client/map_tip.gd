## The small tooltip over the map (what the mouse points at: resource, door, NPC, player) and the
## name plate over a sprite. One look for all of them (kit tokens), placed so it never hides the
## thing pointed at nor leaves the screen: it sits at the lower right of the mouse, flips to the
## left / above when it would overflow, and stays inside the free strip of the game area.
class_name MapTip
extends RefCounted

const GAP := 18.0
const MARGIN := 4.0


## A tooltip panel: gold title, then `detail` (muted when `muted`).
static func build(title: String, detail := "", muted := false) -> PanelContainer:
	var tip := PanelContainer.new()
	tip.theme = ClientTheme.get_theme()
	tip.add_theme_stylebox_override("panel", ClientTheme.get_theme().get_stylebox("panel", "TooltipPanel"))
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_child(UiStyle.label(title, UiStyle.GOLD, 14))
	if detail != "":
		box.add_child(UiStyle.label(detail, UiStyle.TEXT_MUTED if muted else UiStyle.TEXT, 12))
	tip.add_child(box)
	return tip


## Where a tip of `size` goes for a mouse at `at` in a screen of `vp`: right/below, else left/above, then clamped.
static func position_for(at: Vector2, size: Vector2, vp: Vector2) -> Vector2:
	var p := at + Vector2(GAP, GAP)
	if p.x + size.x > vp.x - MARGIN:
		p.x = at.x - GAP - size.x
	if p.y + size.y > vp.y - MARGIN:
		p.y = at.y - GAP - size.y
	return p.clamp(Vector2(MARGIN, MARGIN), (vp - size - Vector2(MARGIN, MARGIN)).max(Vector2(MARGIN, MARGIN)))


## Puts `tip` next to the mouse (its real size, even on the frame it was created).
static func place(tip: Control, at: Vector2, vp: Vector2) -> void:
	tip.position = position_for(at, tip.get_combined_minimum_size().max(tip.size), vp)


## A name over a sprite, on a small dark pill so it reads on any decor (the outline alone vanished on dark maps).
static func add_plate(view: Node2D, text: String, color: Color, y := -135.0, node_name := "Plate") -> PanelContainer:
	var old := view.get_node_or_null(node_name)
	if old != null:
		old.free()
	var plate := PanelContainer.new()
	plate.name = node_name
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := UiStyle.panel(Color(UiStyle.BG, 0.62), Color(UiStyle.BORDER, 0.0), 8, 2)
	style.content_margin_left = 7
	style.content_margin_right = 7
	style.shadow_size = 0
	plate.add_theme_stylebox_override("panel", style)
	var label := UiStyle.label(text, color, 13)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	plate.add_child(label)
	view.add_child(plate)
	plate.reset_size()
	plate.position = Vector2(-plate.size.x / 2.0, y)
	return plate


## What the camera's zoom does to what hangs over a sprite (plate, quest mark, bubble): the whole
## map zoomed out to fit the free strip would shrink the names to a few pixels, so they grow back
## (up to MAX_GROW) around their bottom centre, the point over the sprite's head.
const OVERLAYS := ["Plate", "Tag", "QuestMark", "Bubble"]
const MAX_GROW := 2.0


static func grow_for(zoom: float) -> float:
	return clampf(1.0 / maxf(zoom, 0.01), 1.0, MAX_GROW)


static func keep_readable(view: Node2D, zoom: float) -> void:
	var k := grow_for(zoom)
	for n: String in OVERLAYS:
		var c := view.get_node_or_null(n) as Control
		if c == null:
			continue
		var tail := ChatBubble.TAIL if n == "Bubble" else 0.0
		c.pivot_offset = Vector2(c.size.x / 2.0, c.size.y + tail)
		c.scale = Vector2(k, k)
