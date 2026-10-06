## Zaap window, roadmap P1.08: opened by zaap_list (the player used the zaap
## of the map). One row per known destination with its price (the sim's,
## Travel.zaap_cost), "Voyager" sends zaap_travel; "Sauvegarder" makes this
## zaap the save point. The sim checks everything (kamas, known zaap, distance).
class_name ZaapWindow
extends UiWindow

var backend: GameBackend
var _rows: VBoxContainer
var _save: Button
var _save_label: Label
var _zaap := -1


func setup_window(p_backend: GameBackend) -> void:
	backend = p_backend
	setup("zaap", "Zaap", "UI/Figma/menuIcons/1x/map")
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	body.add_child(top)
	_save_label = UiStyle.label("", UiStyle.TEXT_MUTED, 13)
	_save_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_save_label)
	_save = Button.new()
	_save.text = "Sauvegarder"
	_save.tooltip_text = "Faire de ce zaap votre point de sauvegarde (potion de rappel, défaite)"
	_save.pressed.connect(func() -> void: backend.send(Protocol.set_save_point()))
	top.add_child(_save)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(460, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 4)
	scroll.add_child(_rows)


## zaap_list event; `kamas` = the player's, to grey out what they cannot pay.
func show_list(ev: Dictionary, kamas: int) -> void:
	_zaap = int(ev["zaap"])
	var here_saved := int(ev["save_map"]) == _zaap
	_save.disabled = here_saved
	_save_label.text = "Ce zaap est votre point de sauvegarde" if here_saved else "Point de sauvegarde ailleurs"
	for c: Node in _rows.get_children():
		c.queue_free()
	var dests: Array = (ev["destinations"] as Array).duplicate()
	dests.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _name(a) < _name(b))
	if dests.is_empty():
		_rows.add_child(UiStyle.label("Aucune autre destination connue : visitez d'autres zaaps.", UiStyle.TEXT_MUTED, 13))
	for d: Dictionary in dests:
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.BG_INSET, UiStyle.BORDER, 4, 6))
		_rows.add_child(row)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		row.add_child(h)
		var name := UiStyle.label(_name(d), UiStyle.TEXT, 14)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(name)
		var c: Array = d.get("coords", [0, 0])
		h.add_child(UiStyle.label("%d, %d" % [int(c[0]), int(c[1])], UiStyle.TEXT_MUTED, 13))
		var cost := int(d["cost"])
		h.add_child(UiStyle.label("%s K" % UiStyle.thousands(cost), UiStyle.KAMAS if cost <= kamas else UiStyle.BAD, 14))
		var go := Button.new()
		go.text = "Voyager"
		go.disabled = cost > kamas
		var map := int(d["map"])
		go.pressed.connect(func() -> void:
			backend.send(Protocol.zaap_travel(map))
			close_window())
		h.add_child(go)
	open()


## After set_save_point (player_stats): the button follows.
func set_save_map(save_map: int) -> void:
	if visible and _zaap >= 0:
		_save.disabled = save_map == _zaap
		_save_label.text = "Ce zaap est votre point de sauvegarde" if save_map == _zaap else "Point de sauvegarde ailleurs"


static func _name(d: Dictionary) -> String:
	var sub := DofusI18n.text(int(d.get("name_id", 0)), "Map %d" % int(d["map"]))
	var area := DofusI18n.text(int(d.get("area_name_id", 0)), "")
	return "%s - %s" % [area, sub] if area != "" and area != sub else sub
