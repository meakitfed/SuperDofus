## Hides everything outside the window of the map (GameArea.FRAME): the scenery that overflows the
## 14 x 20 grid, the background colour, the empty bands left by a window wider or taller than the
## Dofus ratios. Four opaque black rectangles around the frame, drawn above the map and the
## entities and below the HUD, like the black bars of the Dofus client (DOFUS_UI.md C5, C6).
class_name MapMask
extends Node2D

const FAR := 40000.0
const COLOR := Color.BLACK


func _ready() -> void:
	z_index = 100 # above the y-sorted entities and the foreground of the map
	z_as_relative = false


func _draw() -> void:
	var f := GameArea.frame_world(MapGeometry.screen_bounds())
	draw_rect(Rect2(f.position.x - FAR, f.position.y - FAR, f.size.x + 2.0 * FAR, FAR), COLOR) # above
	draw_rect(Rect2(f.position.x - FAR, f.end.y, f.size.x + 2.0 * FAR, FAR), COLOR) # below
	draw_rect(Rect2(f.position.x - FAR, f.position.y, FAR, f.size.y), COLOR) # left
	draw_rect(Rect2(f.end.x, f.position.y, FAR, f.size.y), COLOR) # right
