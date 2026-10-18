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
var _save_map := -1
var _dests: Array = []
var _kamas := 0
var _search: LineEdit
var _by_price: CheckBox
var _kamas_label: Label
var _scroll_list: ScrollContainer


func setup_window(p_backend: GameBackend) -> void:
	backend = p_backend
	setup("zaap", "Zaap", "UI/Figma/menuIcons/1x/map")
	default_anchor = Vector2(0.06, 0.3) # left, clear of the map centre
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
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	body.add_child(bar)
	_search = UiSearch.field("Rechercher une destination", _fill, 200)
	bar.add_child(_search)
	_by_price = CheckBox.new()
	_by_price.text = "Moins chers d'abord"
	_by_price.toggled.connect(func(_on: bool) -> void: _fill())
	bar.add_child(_by_price)
	_kamas_label = UiStyle.label("", UiStyle.KAMAS, 15)
	bar.add_child(_kamas_label)
	var scroll := ScrollContainer.new()
	_scroll_list = scroll
	scroll.custom_minimum_size = Vector2(500, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 4)
	scroll.add_child(_rows)


## zaap_list event; `kamas` = the player's, to grey out what they cannot pay.
func show_list(ev: Dictionary, kamas: int) -> void:
	_zaap = int(ev["zaap"])
	_save_map = int(ev["save_map"])
	_dests = (ev["destinations"] as Array).duplicate()
	_kamas = kamas
	_search.clear()
	_save.disabled = _save_map == _zaap
	_save_label.text = "Ce zaap est votre point de sauvegarde" if _save_map == _zaap else "Point de sauvegarde ailleurs"
	_fill()
	open()


func _fill() -> void:
	if _rows == null:
		return
	_kamas_label.text = "%s K" % UiStyle.thousands(_kamas)
	for c: Node in _rows.get_children():
		_rows.remove_child(c)
		c.free()
	var dests: Array = _dests.filter(func(d: Dictionary) -> bool: return UiSearch.matches(_name(d), _search.text))
	dests.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if _by_price.button_pressed and int(a["cost"]) != int(b["cost"]):
			return int(a["cost"]) < int(b["cost"])
		return _name(a) < _name(b))
	if _dests.is_empty():
		_rows.add_child(UiStyle.label("Aucune autre destination connue : visitez d'autres zaaps.", UiStyle.TEXT_MUTED, 13))
	elif dests.is_empty():
		_rows.add_child(UiStyle.label("Aucune destination ne correspond.", UiStyle.TEXT_MUTED, 13))
	for d: Dictionary in dests:
		var map := int(d["map"])
		var cost := int(d["cost"])
		var row := UiRow.new(cost <= _kamas)
		row.activated.connect(func() -> void: _go(map))
		_rows.add_child(row)
		var name := UiStyle.label(_name(d), UiStyle.TEXT if cost <= _kamas else UiStyle.TEXT_MUTED, 14)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.h.add_child(name)
		if map == _save_map:
			var tag := UiStyle.label("Sauvegarde", UiStyle.GOLD, UiStyle.FS_SMALL)
			tag.tooltip_text = "Votre point de sauvegarde"
			row.h.add_child(tag)
		var c: Array = d.get("coords", [0, 0])
		row.h.add_child(UiStyle.label("%d, %d" % [int(c[0]), int(c[1])], UiStyle.TEXT_MUTED, 13))
		row.h.add_child(UiStyle.label("%s K" % UiStyle.thousands(cost), UiStyle.KAMAS if cost <= _kamas else UiStyle.BAD, 14))
		var go := Button.new()
		go.text = "Voyager"
		go.theme_type_variation = UiStyle.V_PRIMARY
		go.disabled = cost > _kamas
		go.tooltip_text = "Vous n'avez pas assez de kamas" if go.disabled else ""
		go.pressed.connect(func() -> void: _go(map))
		row.h.add_child(go)
	# the list is as tall as its rows (a few, not a 300 px void), up to 300 px then it scrolls
	_scroll_list.custom_minimum_size.y = clampf(_rows.get_combined_minimum_size().y + 4.0, 60.0, 300.0)


func _go(map: int) -> void:
	backend.send(Protocol.zaap_travel(map))
	close_window()


## After set_save_point (player_stats): the button follows.
func set_save_map(save_map: int) -> void:
	_save_map = save_map
	if visible and _zaap >= 0:
		_fill()
		_save.disabled = save_map == _zaap
		_save_label.text = "Ce zaap est votre point de sauvegarde" if save_map == _zaap else "Point de sauvegarde ailleurs"


static func destination_name(d: Dictionary) -> String:
	return _name(d)


static func _name(d: Dictionary) -> String:
	var sub := DofusI18n.text(int(d.get("name_id", 0)), "Map %d" % int(d["map"]))
	var area := DofusI18n.text(int(d.get("area_name_id", 0)), "")
	return "%s - %s" % [area, sub] if area != "" and area != sub else sub
