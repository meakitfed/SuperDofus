## « Reconnexion… » banner (S.02c): shown at the top-centre while NetBackend tries to get the
## session back after a cut, removed at resume_ok. Display only: the delays come from the
## net_reconnecting event.
class_name ReconnectBanner
extends PanelContainer

var _label: Label
var _until_ms := 0
var _attempt := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var style := UiStyle.panel(Color(UiStyle.BG, 0.94), UiStyle.BAD, 6, 8)
	style.shadow_size = 0
	style.content_margin_left = 18
	style.content_margin_right = 18
	add_theme_stylebox_override("panel", style)
	_label = UiStyle.label("", UiStyle.TEXT, 16)
	add_child(_label)


## The cut was seen: the next try is in `delay_ms`.
func wait(attempt: int, delay_ms: int) -> void:
	_attempt = attempt
	_until_ms = Time.get_ticks_msec() + delay_ms
	visible = true
	_refresh()


func clear() -> void:
	visible = false


func _process(_delta: float) -> void:
	if visible:
		_refresh()


func _refresh() -> void:
	var left := maxi(0, int(ceil((_until_ms - Time.get_ticks_msec()) / 1000.0)))
	_label.text = "Connexion perdue. Reconnexion… (essai %d%s)" % [_attempt, ", dans %d s" % left if left > 0 else ""]
	if not is_inside_tree():
		return
	reset_size()
	position = Vector2((get_viewport_rect().size.x - size.x) / 2.0, 20)
