## A fight point counter (AP or MP): a coloured disc with the number, then its name. Read at a
## glance from the bar; the colours are the kit's (UiStyle.AP / MP).
class_name FightPoints
extends Control

var value := 0
var caption := ""
var color := UiStyle.AP


func _init(p_caption := "PA", p_color := UiStyle.AP) -> void:
	caption = p_caption
	color = p_color
	custom_minimum_size = Vector2(76, 32)
	mouse_filter = Control.MOUSE_FILTER_PASS
	tooltip_text = "Points d'action" if p_caption == "PA" else "Points de mouvement"


func set_value(v: int) -> void:
	if v == value:
		return
	value = v
	queue_redraw()


func _draw() -> void:
	var c := Vector2(16, size.y * 0.5)
	draw_circle(c, 15.0, UiStyle.BG_INSET)
	draw_arc(c, 14.0, 0.0, TAU, 32, color, 2.0, true)
	draw_circle(c, 11.5, color)
	var font := UiStyle.font("title")
	var text := str(value)
	var fs := 17
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(c.x - w * 0.5, c.y + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiStyle.TEXT_ON_ACCENT)
	draw_string(UiStyle.font("heading"), Vector2(36, c.y + 5.0), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.FS_BODY, color)
