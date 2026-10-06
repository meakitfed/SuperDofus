## « Chargement de la zone… » panel (C.02d): shown at the centre while a map_enter waits for the
## files of its zone, with a bar (bytes of the zone) and, after a failed download, the error and the
## next try. Display only: ZoneGate owns the state.
class_name ZoneIndicator
extends PanelContainer

var _label: Label
var _bar: ProgressBar
var _detail: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var style := UiStyle.panel(Color(UiStyle.BG, 0.96), UiStyle.BORDER, 6, 12)
	style.content_margin_left = 22
	style.content_margin_right = 22
	add_theme_stylebox_override("panel", style)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	_label = UiStyle.label("", UiStyle.TEXT, 18)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_label)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(360, 18)
	_bar.show_percentage = false
	_bar.add_theme_stylebox_override("background", UiStyle.bar_bg())
	_bar.add_theme_stylebox_override("fill", UiStyle.bar_fill(UiStyle.XP))
	col.add_child(_bar)
	_detail = UiStyle.label("", UiStyle.TEXT_MUTED, 14)
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_detail)


## The text and bar for the gate's state (static: the tests and the capture read it too).
static func text_for(state: String, error: String, done: int, total: int) -> Dictionary:
	var out := {"title": "Chargement de la zone…", "detail": "", "value": 0.0, "color": UiStyle.TEXT}
	if state == "indexing":
		out["title"] = "Connexion au contenu du monde…"
	elif total > 0:
		out["detail"] = "%s / %s" % [WorldLoader.format_bytes(done), WorldLoader.format_bytes(total)]
		out["value"] = clampf(float(done) / float(total), 0.0, 1.0)
	if state == "failed":
		out["title"] = "Zone indisponible"
		out["detail"] = "%s. Nouvel essai en cours…" % error
		out["color"] = UiStyle.BAD
	return out


func update(gate: ZoneGate) -> void:
	visible = gate.waiting()
	if not visible:
		return
	var t := text_for(gate.state, gate.error, gate.done_bytes, gate.total_bytes)
	_label.text = str(t["title"])
	_label.add_theme_color_override("font_color", t["color"])
	_bar.value = float(t["value"]) * 100.0
	_bar.visible = gate.state == "loading"
	_detail.text = str(t["detail"])
	_detail.visible = _detail.text != ""
	if is_inside_tree():
		reset_size()
		position = (get_viewport_rect().size - size) / 2.0
