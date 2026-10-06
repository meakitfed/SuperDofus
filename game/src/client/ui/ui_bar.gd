## A gauge (XP, HP, pods, job XP…) with an optional centred text.
##   var bar := UiBar.new(UiStyle.XP); bar.set_values(value, max_value, "1 200 / 2 800")
class_name UiBar
extends ProgressBar

var _text: Label


func _init(color := UiStyle.XP, height := 12) -> void:
	show_percentage = false
	custom_minimum_size = Vector2(120, height)
	add_theme_stylebox_override("fill", UiStyle.bar_fill(color))
	add_theme_stylebox_override("background", UiStyle.bar_bg())
	_text = UiStyle.label("", UiStyle.TEXT, maxi(10, height - 2))
	_text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_text.add_theme_constant_override("outline_size", 3)
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_text)


func set_values(v: float, max_v: float, text := "") -> void:
	max_value = maxf(1.0, max_v)
	value = clampf(v, 0.0, max_value)
	_text.text = text
