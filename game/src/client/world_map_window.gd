## World map (M), roadmap P1.08: the real Dofus world map of the current map
## (WorldMapView), the player's position, the known zaaps and the save point. U.07: a toolbar
## (zoom, back to my position, go to coordinates) and a legend drawn with the kit's map tokens.
## Display only: positions come from map_enter and player_stats.
class_name WorldMapWindow
extends UiWindow

var view: WorldMapView
var _title: Label
var _coords: LineEdit
var _toolbar: HBoxContainer
var _legend: HBoxContainer
var _position := Vector2i.ZERO


func setup_window() -> void:
	setup("worldmap", "Carte du monde", "UI/Figma/menuIcons/1x/map")
	_toolbar = HBoxContainer.new()
	_toolbar.add_theme_constant_override("separation", 6)
	body.add_child(_toolbar)
	_title = UiStyle.heading("")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	_toolbar.add_child(_title)
	_coords = LineEdit.new()
	_coords.placeholder_text = "x, y"
	_coords.custom_minimum_size = Vector2(80, 0)
	_coords.tooltip_text = "Aller à des coordonnées (Entrée)"
	_coords.text_submitted.connect(func(t: String) -> void: go_to(t))
	_toolbar.add_child(_coords)
	_toolbar.add_child(_tool_button("−", "Zoom arrière", func() -> void: view.zoom_by(1 / 1.3)))
	_toolbar.add_child(_tool_button("+", "Zoom avant", func() -> void: view.zoom_by(1.3)))
	_toolbar.add_child(_tool_button("Ma position", "Recentrer sur votre carte", func() -> void: view.focus(_position)))
	view = WorldMapView.new()
	view.custom_minimum_size = Vector2(820, 520)
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(view)
	_legend = HBoxContainer.new()
	_legend.add_theme_constant_override("separation", 14)
	body.add_child(_legend)
	_legend.add_child(_swatch(UiStyle.MAP_PLAYER, "Vous"))
	_legend.add_child(_swatch(UiStyle.MAP_ZAAP, "Zaap connu"))
	_legend.add_child(_swatch(UiStyle.GOLD, "Sauvegarde", true))
	_legend.add_child(_swatch(UiStyle.PHOENIX, "Phénix"))
	var help := UiStyle.label("Molette : zoom · glisser : déplacer", UiStyle.TEXT_MUTED, UiStyle.FS_SMALL)
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_legend.add_child(help)


func _tool_button(text: String, tip: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	UiStyle.compact(b, 30)
	b.pressed.connect(on_press)
	return b


func _swatch(color: Color, text: String, diamond := false) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(11, 11)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var st := StyleBoxFlat.new()
	st.bg_color = color
	st.border_color = UiStyle.MAP_OUTLINE
	st.set_border_width_all(1)
	st.set_corner_radius_all(2 if diamond else 6)
	dot.add_theme_stylebox_override("panel", st)
	box.add_child(dot)
	box.add_child(UiStyle.label(text, UiStyle.TEXT_MUTED, UiStyle.FS_SMALL))
	return box


## "12, -3" (or "12 -3"): centres the view there. False when the text is not two numbers.
func go_to(text: String) -> bool:
	var parts := text.replace(",", " ").split(" ", false)
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return false
	view.focus(Vector2i(parts[0].to_int(), parts[1].to_int()))
	return true


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
	_position = map.coords
	if not visible or not shown:
		view.focus(map.coords)
	_title.text = "%s (%d, %d)" % [map_title, map.coords.x, map.coords.y] if shown else "%s : pas de carte ici (intérieur)" % map_title
	_legend.visible = shown
	_coords.editable = shown
