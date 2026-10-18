## The player's zoom on the map (GameArea does the maths): wheel, "recentre" shortcut, and what the
## zoomed view must keep in sight. Back to the whole map on a change of mode (exploration / fight)
## or of map; during a fight the zoom is held back so no fighter leaves the free strip or goes
## behind the UI.
class_name MapZoom
extends RefCounted

var _in_fight := false


## One wheel notch (dir > 0 zooms in). True when the view must be fitted again.
func wheel(area: GameArea, dir: int) -> bool:
	return area.zoom_step(dir)


## Zoom back to 1 and recentre. True when something changed.
func recentre(area: GameArea) -> bool:
	var changed := area.ratio != 1.0
	area.reset_zoom()
	return changed


## Called every frame: feeds the area with the fighters / the player. True when the camera must be refitted.
func track(area: GameArea, fight: FightView, views: Dictionary, you: int) -> bool:
	var changed := false
	var fighting := fight != null and fight.hud != null
	if fighting != _in_fight:
		_in_fight = fighting
		changed = recentre(area)
	var pts: Array[Vector2] = []
	var focus := Vector2.INF
	if fighting:
		for id: int in fight.views:
			var n: Node2D = fight.views[id]
			if is_instance_valid(n):
				pts.append(n.position)
	elif views.has(you):
		focus = (views[you] as Node2D).position
	if area.ratio > 1.0 and (pts != area.must_show or focus != area.focus):
		changed = true
	area.must_show = pts
	area.focus = focus
	return changed
