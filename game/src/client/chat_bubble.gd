## The speech bubble over a character when it speaks on the general channel (P3.02).
class_name ChatBubble
extends RefCounted

const SHOW_MS := 5000
const MAX_CHARS := 120


## Puts `text` over `view` (an actor's sprite), replacing the previous bubble; it fades after SHOW_MS.
static func show_over(view: Node2D, text: String) -> void:
	var old := view.get_node_or_null("Bubble")
	if old != null:
		old.free()
	var panel := PanelContainer.new()
	panel.name = "Bubble"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.theme = ClientTheme.get_theme()
	panel.add_theme_stylebox_override("panel", UiStyle.panel(Color(UiStyle.BG, 0.9), UiStyle.BORDER_LIGHT, 8, 5))
	var label := UiStyle.label(text.substr(0, MAX_CHARS), UiStyle.TEXT, 13)
	label.custom_minimum_size.x = minf(label.get_minimum_size().x, 180.0) # measured before wrapping
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(label)
	view.add_child(panel)
	panel.reset_size()
	panel.position = Vector2(-panel.size.x / 2.0, -175.0 - panel.size.y)
	panel.z_index = 50
	var tween := panel.create_tween()
	tween.tween_interval(SHOW_MS / 1000.0)
	tween.tween_property(panel, "modulate:a", 0.0, 0.4)
	tween.tween_callback(panel.queue_free)
