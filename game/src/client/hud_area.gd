## What the HUD takes of the screen, for the GameArea (lot U.01): the bands (fight timeline above, bar
## and options below, dock below) and the floating panels that sit over the map. Only the bands move
## the map; the panels are kept clear of the cells in a fight (HudLayout.chat_room).
class_name HudArea
extends RefCounted


## {"top", "bottom", "blocks"} for the current mode.
static func collect(fight: FightView, hud: PlayerHud, panels: Dictionary) -> Dictionary:
	var top := 0.0
	var bottom := 0.0
	var blocks := {}
	if fight != null and fight.hud != null:
		top = fight.hud.reserved_top()
		bottom = fight.hud.reserved_bottom()
		var challenges := fight.hud.banner_rect()
		if challenges.size.y > 0.0:
			blocks["challenges"] = challenges
	elif hud.visible:
		bottom = hud.reserved_bottom()
	for k: String in panels:
		var c: Control = panels[k]
		if c.visible and c.size.x > 0.0 and c.size.y > 0.0 and c.is_visible_in_tree():
			blocks[k] = Rect2(c.position, c.size)
	return {"top": top, "bottom": bottom, "blocks": blocks}


## Screen positions (at the default zoom) of the cells a fighter can stand on.
static func fighter_cells(area: GameArea, vp: Vector2, map: MapData) -> PackedVector2Array:
	var out := PackedVector2Array()
	for cell in MapGeometry.CELL_COUNT:
		if map.is_walkable(cell) and map.is_fight_walkable(cell):
			out.append(area.base_screen(vp, MapGeometry.to_screen(cell)))
	return out


## The room the chat keeps in a fight (HudLayout.chat_room): `at` is the spot of its full size.
static func chat_room(area: GameArea, vp: Vector2, map: MapData, at: Vector2) -> Vector2:
	var pad := Vector4(GameArea.MARGIN.x, GameArea.MARGIN.y, GameArea.FEET, 0.0) * float(area.camera_for_ratio(vp, 1.0)["zoom"])
	return HudLayout.chat_room(at, HudLayout.chat_size(vp), fighter_cells(area, vp, map), pad)
