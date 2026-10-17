## Jobs window (P2.05c, key P): one card per job practised with its level, XP gauge and harvesting
## skills (resource icon, level needed, XP per harvest; greyed while the level is too low).
## All numbers are the sim's: this only shows a JobsModel.
class_name JobsWindow
extends UiWindow

var model := JobsModel.new()
var _rows: VBoxContainer


func setup_window() -> void:
	setup("jobs", "Métiers", "UI/Figma/menuIcons/1x/job")
	default_anchor = Vector2(0.9, 0.3)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, 320)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_rows)
	refresh()


func set_stats(stats: Dictionary) -> void:
	model.apply_stats(stats)
	refresh()


func on_xp(ev: Dictionary) -> void:
	model.apply_xp(ev)
	refresh()


func refresh() -> void:
	for c: Node in _rows.get_children():
		c.queue_free()
	var rows := model.rows()
	if rows.is_empty():
		_rows.add_child(UiStyle.label("Aucun métier pratiqué : récoltez une ressource pour commencer.", UiStyle.TEXT_MUTED, 13))
	for r: Dictionary in rows:
		_rows.add_child(_card(r))


func _card(r: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.BG_INSET, UiStyle.BORDER, 4, 8))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var name := UiStyle.label(str(r["name"]), UiStyle.GOLD, 15)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name)
	head.add_child(UiStyle.label("Niveau %d" % int(r["level"]), UiStyle.TEXT, 14))
	var bar := UiBar.new(UiStyle.XP, 12)
	var span := int(r["xp_next"]) - int(r["xp_floor"])
	bar.set_values(int(r["xp"]) - int(r["xp_floor"]), span, "%s / %s" % [UiStyle.thousands(int(r["xp"]) - int(r["xp_floor"])), UiStyle.thousands(span)])
	v.add_child(bar)
	var skills := GridContainer.new()
	skills.columns = 2
	skills.add_theme_constant_override("h_separation", 16)
	v.add_child(skills)
	for s: Dictionary in r["skills"]:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		var slot := ItemSlot.new(int(s["item"]), 0)
		slot.custom_minimum_size = Vector2(32, 32)
		slot.modulate = Color(1, 1, 1, 0.4) if bool(s["locked"]) else Color.WHITE
		line.add_child(slot)
		var txt := "%s\nniv. %d · +%d XP" % [UiTooltips.item_name(int(s["item"])), int(s["level"]), int(s["xp"])]
		line.add_child(UiStyle.label(txt, UiStyle.TEXT_MUTED if bool(s["locked"]) else UiStyle.TEXT, 11))
		skills.add_child(line)
	return card
