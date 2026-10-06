## World map (M), roadmap P1.08: the real Dofus world map of the current map
## (WorldMapView), the player's position, the known zaaps and the save point.
## Display only: positions come from map_enter and player_stats.
class_name WorldMapWindow
extends UiWindow

var view: WorldMapView
var _legend: Label


func setup_window() -> void:
	setup("worldmap", "Carte du monde", "UI/Figma/menuIcons/1x/map")
	view = WorldMapView.new()
	view.custom_minimum_size = Vector2(820, 540)
	body.add_child(view)
	_legend = UiStyle.label("", UiStyle.TEXT_MUTED, 13)
	body.add_child(_legend)


## The current map (world map id, coordinates, name) and the player's zaaps / save point.
func refresh(map: MapData, map_title: String, stats: Dictionary) -> void:
	var zaaps: Array = stats.get("zaaps", []).filter(func(z: Dictionary) -> bool:
		return z.has("coords") and int(z.get("world_map", map.world_map)) == map.world_map)
	view.zaaps = zaaps
	view.phoenixes = stats.get("phoenixes", []).filter(func(ph: Dictionary) -> bool:
		return int(ph.get("world_map", -1)) == map.world_map)
	view.has_save = false
	for z: Dictionary in zaaps:
		if int(z["map"]) == int(stats.get("save_map", -1)):
			view.has_save = true
			view.save_coords = Vector2i(int(z["coords"][0]), int(z["coords"][1]))
	var shown := view.set_world(map.world_map)
	view.player = map.coords
	if not visible or not shown:
		view.focus(map.coords)
	_legend.text = "%s (%d, %d)  ·  ● vous  ● zaap connu  ◆ point de sauvegarde  ● phénix  ·  molette : zoom, glisser : déplacer" % [
			map_title, map.coords.x, map.coords.y] if shown else "%s : pas de carte ici (intérieur)" % map_title
