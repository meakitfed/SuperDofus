## Short messages at the top-centre of the screen that fade out (refused
## actions, notices). Several stack; the oldest go first.
class_name Toast
extends VBoxContainer

const SHOW_MS := 2500
const FADE_MS := 400
const IN_MS := 140
const MAX_SHOWN := 4


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_text(text: String, color := UiStyle.GOLD) -> void:
	# the same message twice in a row only restarts its timer
	if get_child_count() > 0:
		var last: PanelContainer = get_child(get_child_count() - 1)
		if last.get_meta("text", "") == text:
			last.set_meta("born", Time.get_ticks_msec())
			last.modulate.a = 1.0
			return
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := UiStyle.panel(UiStyle.BG_RAISED, UiStyle.BORDER_LIGHT, UiStyle.RADIUS, 6)
	style.border_width_left = 4 # the accent of the message
	style.border_color = color
	style.shadow_size = 8
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.theme = ClientTheme.get_theme()
	label.text = text
	label.add_theme_color_override("font_color", color)
	panel.add_child(label)
	panel.set_meta("text", text)
	panel.set_meta("born", Time.get_ticks_msec())
	add_child(panel)
	while get_child_count() > MAX_SHOWN:
		var old := get_child(0)
		remove_child(old)
		old.queue_free()
	_place()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	for panel: Control in get_children():
		var age := now - int(panel.get_meta("born", now))
		if age > SHOW_MS + FADE_MS:
			panel.queue_free()
		elif age > SHOW_MS:
			panel.modulate.a = 1.0 - float(age - SHOW_MS) / FADE_MS
		elif age < IN_MS:
			panel.modulate.a = float(age) / IN_MS # eases in
	_place()


func _place() -> void:
	if not is_inside_tree():
		return
	reset_size()
	position = Vector2((get_viewport_rect().size.x - size.x) / 2.0, 70)
