## « Reconnexion… » banner (S.02c): shown at the top-centre while NetBackend tries to get the
## session back after a cut, removed at resume_ok. Display only: the delays come from the
## net_reconnecting event. A thin bar drains until the next attempt, so the wait is visible.
class_name ReconnectBanner
extends PanelContainer

const WIDTH := 380

var _label: Label
var _hint: Label
var _bar: UiBar
var _until_ms := 0
var _delay_ms := 1
var _attempt := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	custom_minimum_size = Vector2(WIDTH, 0)
	var style := UiStyle.panel(UiStyle.BG_RAISED, UiStyle.BAD, UiStyle.RADIUS, 12)
	style.border_width_left = 4
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	_label = UiStyle.heading("")
	box.add_child(_label)
	_bar = UiBar.new(UiStyle.BAD, 6)
	_bar.max_value = 1.0
	box.add_child(_bar)
	_hint = UiStyle.muted("Le jeu reprend tout seul dès que le serveur répond.")
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_hint)


## The cut was seen: the next try is in `delay_ms`.
func wait(attempt: int, delay_ms: int) -> void:
	_attempt = attempt
	_delay_ms = maxi(1, delay_ms)
	_until_ms = Time.get_ticks_msec() + delay_ms
	visible = true
	_refresh()


func clear() -> void:
	visible = false


func _process(_delta: float) -> void:
	if visible:
		_refresh()


func _refresh() -> void:
	var left_ms := maxi(0, _until_ms - Time.get_ticks_msec())
	var left := int(ceil(left_ms / 1000.0))
	_label.text = "Connexion perdue. Reconnexion… (essai %d%s)" % [_attempt, ", dans %d s" % left if left > 0 else ""]
	_bar.value = 1.0 - float(left_ms) / float(_delay_ms)
	if not is_inside_tree():
		return
	reset_size()
	position = Vector2((get_viewport_rect().size.x - size.x) / 2.0, 20)
