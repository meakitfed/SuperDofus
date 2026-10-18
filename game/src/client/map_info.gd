## The place block, top left (the Dofus "mapInfo"): area and sub-area in the title font, the map
## coordinates under it, then a muted status line (world, fps) with a "?" whose tooltip holds the
## controls of the moment. Text only, over the map, so it carries an outline instead of a panel.
class_name MapInfo
extends VBoxContainer

var _title: Label
var _coords: Label
var _status: Label
var _help: Button
var _place_shown := true


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 0)
	_title = _outlined(UiStyle.title("", UiStyle.FS_TITLE))
	add_child(_title)
	_coords = _outlined(UiStyle.label("", UiStyle.TEXT, UiStyle.FS_BODY))
	add_child(_coords)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_help = Button.new()
	_help.text = "?"
	_help.flat = true
	_help.focus_mode = Control.FOCUS_NONE
	_help.custom_minimum_size = Vector2(22, 22)
	_help.add_theme_font_size_override("font_size", UiStyle.FS_SMALL)
	_help.add_theme_color_override("font_color", UiStyle.TEXT_MUTED)
	row.add_child(_help)
	_status = _outlined(UiStyle.label("", UiStyle.TEXT_MUTED, UiStyle.FS_SMALL))
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_status)


static func _outlined(l: Label) -> Label:
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## "Incarnam - Pâturages" and the coordinates; hidden in a fight (the timeline has the top).
func set_place(title: String, coords: Vector2i, shown: bool) -> void:
	_title.text = title
	_coords.text = "%d, %d" % [coords.x, coords.y]
	_place_shown = shown
	_title.visible = shown and title != ""
	_coords.visible = _title.visible


## The status line and the controls of the moment (the tooltip of the "?").
func set_status(text: String, help: String) -> void:
	if _status.text != text:
		_status.text = text
	if _help.tooltip_text != help:
		_help.tooltip_text = help


func place_shown() -> bool:
	return _place_shown
