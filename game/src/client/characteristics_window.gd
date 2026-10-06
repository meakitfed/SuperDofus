## Characteristics window (C), roadmap P1.04: identity, XP, HP, then the Dofus 3
## categories (characteristiccategories, in characteristics.order): general
## (AP, MP, range, summons, the six characteristics with base / bonus / total
## and "+", power, critical), secondary (initiative, prospecting, pods, tackle,
## escape, AP/MP dodge and removal, heals), damage and resistances. Capital
## spending (boost_stat: click = 1 point, Shift+click = 10, a click on the name or
## a right click on "+" = ask_points, any number of points at once) and reset
## (reset_stats) are asked to the game; costs and formulas are only shown,
## from the shared StatFormulas. Fed by player_stats.
class_name CharacteristicsWindow
extends UiWindow

const ICONS := "UI/Figma/characteristics/characteristicIcon/1x/"
## characteristics.keyword -> where the character dict has it: a boostable
## stat ("stats"), a derived one ("derived"), or "ap" / "mp"
const SOURCES := {"strength": "stats", "vitality": "stats", "wisdom": "stats", "chance": "stats",
		"agility": "stats", "intelligence": "stats", "actionPoints": "ap", "movementPoints": "mp",
		"range": "derived:range", "maxSummonedCreaturesBoost": "derived:summons", "criticalHit": "derived:crit",
		"damagePercent": "derived:power", "magicFind": "derived:prospecting", "weight": "derived:pods",
		"DodgeApLostProbability": "derived:ap_dodge", "DodgeMpLostProbability": "derived:mp_dodge",
		"apReduction": "derived:ap_attack", "mpReduction": "derived:mp_attack", "tackleBlock": "derived:tackle",
		"tackleEvade": "derived:escape", "initiative": "derived:initiative", "healBonus": "derived:heals",
		"allDamageBonus": "derived:damage"}
## how a derived characteristic is computed (tooltips; StatFormulas)
const FORMULAS := {"tackleBlock": "Agilité / 10 + bonus", "tackleEvade": "Agilité / 10 + bonus",
		"DodgeApLostProbability": "Sagesse / 10 + bonus", "DodgeMpLostProbability": "Sagesse / 10 + bonus",
		"apReduction": "Sagesse / 10 + bonus", "mpReduction": "Sagesse / 10 + bonus",
		"magicFind": "100 + Chance / 10 + bonus", "weight": "1 000 + 5 × Force + métiers + bonus",
		"initiative": "(100 + Force + Intelligence + Chance + Agilité + bonus) × PV / PV max",
		"actionPoints": "6, 7 à partir du niveau 100", "movementPoints": "3",
		"maxSummonedCreaturesBoost": "1 + bonus"}

var backend: GameBackend
var stats := {}
var _name: Label
var _level: Label
var _symbol: TextureRect
var _xp: UiBar
var _hp: UiBar
var _energy: UiBar
var _capital: Label
var _reset: Button
var _pages: Array[VBoxContainer] = []


func setup_window(p_backend: GameBackend) -> void:
	backend = p_backend
	setup("characteristics", "Caractéristiques", "UI/Figma/menuIcons/1x/characteristic")
	custom_minimum_size = Vector2(400, 0)
	default_anchor = Vector2(0.06, 0.3)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	body.add_child(head)
	_symbol = TextureRect.new()
	_symbol.custom_minimum_size = Vector2(44, 44)
	_symbol.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_symbol.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(_symbol)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	head.add_child(names)
	_name = UiStyle.label("", UiStyle.GOLD, 18)
	names.add_child(_name)
	_level = UiStyle.label("", UiStyle.TEXT_MUTED, 13)
	names.add_child(_level)
	_xp = UiBar.new(UiStyle.XP, 14)
	body.add_child(_xp)
	_hp = UiBar.new(UiStyle.HP, 14)
	body.add_child(_hp)
	_energy = UiBar.new(UiStyle.ENERGY, 10)
	body.add_child(_energy)
	var tabs := UiTabs.new()
	body.add_child(tabs)
	var cats: Array = GameData.table("characteristiccategories").values()
	cats.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["order"]) < int(b["order"]))
	for cat: Dictionary in cats:
		if int(cat["id"]) == 6: # "En combat" (erosion): fight only
			continue
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 2)
		page.set_meta("ids", cat["characteristicIds"])
		_pages.append(page)
		var inset := PanelContainer.new()
		inset.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.BG_INSET, UiStyle.BORDER, 4, 8))
		inset.add_child(page)
		tabs.add_tab(UiStyle.plain_text(DofusI18n.text(int(cat["nameId"]), "?")).replace("Caractéristiques ", "").capitalize(), inset)
	var foot := HBoxContainer.new()
	body.add_child(foot)
	_capital = UiStyle.label("", UiStyle.GOLD, 15)
	_capital.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_capital)
	_reset = Button.new()
	_reset.text = "Réinitialiser"
	_reset.focus_mode = Control.FOCUS_NONE
	_reset.tooltip_text = "Remet les caractéristiques à 0 et rend tout le capital dépensé"
	_reset.pressed.connect(func() -> void:
		UiConfirm.ask(get_parent(), "Réinitialiser", "Remettre toutes vos caractéristiques à 0 et récupérer le capital ?",
				"Réinitialiser", func() -> void: backend.send(Protocol.reset_stats())))
	foot.add_child(_reset)


func set_stats(s: Dictionary) -> void:
	stats = s
	var breed := int(s.get("breed", 12))
	_name.text = str(s.get("name", ""))
	_level.text = "Niveau %d · %s" % [int(s["level"]), CharacterSelectScreen.breed_name(breed)]
	_symbol.texture = UiStyle.texture(CharacterSelectScreen.symbol_texture(breed))
	var floor_xp := int(s["xp_floor"])
	_xp.set_values(int(s["xp"]) - floor_xp, int(s["xp_next"]) - floor_xp,
			"%s / %s XP" % [UiStyle.thousands(int(s["xp"])), UiStyle.thousands(int(s["xp_next"]))])
	var energy_name := DofusI18n.text(int(GameData.row("characteristics", 29).get("nameId", 0)), "Énergie")
	_energy.set_values(int(s.get("energy", 0)), int(s.get("max_energy", 1)), "%s / %s %s%s" % [
			UiStyle.thousands(int(s.get("energy", 0))), UiStyle.thousands(int(s.get("max_energy", 0))), energy_name.to_lower(),
			"  ·  fantôme" if int(s.get("life", 0)) == 2 else ""])
	_capital.text = "Capital : %d" % int(s["capital"])
	_reset.disabled = (s["stats"] as Dictionary).values().all(func(v: Variant) -> bool: return int(v) == 0)
	for page in _pages:
		_fill(page)


func set_hp(hp: int, max_hp: int) -> void:
	_hp.set_values(hp, max_hp, "%d / %d PV" % [hp, max_hp])


func _fill(page: VBoxContainer) -> void:
	for c: Node in page.get_children():
		c.queue_free()
	var rows: Array = (page.get_meta("ids") as Array).map(func(id: Variant) -> Dictionary: return GameData.row("characteristics", int(id)))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("order", 0)) < int(b.get("order", 0)))
	var boostable := rows.filter(func(r: Dictionary) -> bool: return SOURCES.get(r.get("keyword", ""), "") == "stats")
	var others := rows.filter(func(r: Dictionary) -> bool: return SOURCES.get(r.get("keyword", ""), "") != "stats")
	if not boostable.is_empty():
		var grid := GridContainer.new()
		grid.columns = 6
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 3)
		page.add_child(grid)
		grid.add_child(Control.new())
		for t: String in ["", "Base", "Bonus", "Total", ""]:
			var l := UiStyle.label(t, UiStyle.TEXT_MUTED, 12)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(l)
		for r: Dictionary in boostable:
			_boost_row(grid, r)
		page.add_child(HSeparator.new())
	var list := GridContainer.new()
	list.columns = 6 # two columns of icon, name, value
	list.add_theme_constant_override("h_separation", 8)
	list.add_theme_constant_override("v_separation", 3)
	page.add_child(list)
	for r: Dictionary in others:
		var key := str(r.get("keyword", ""))
		list.add_child(UiStyle.icon(ICONS + str(r.get("asset", "")), 20, Color.WHITE))
		var n := UiStyle.label(_name_of(r), UiStyle.TEXT, 13)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.custom_minimum_size = Vector2(120, 0)
		n.mouse_filter = Control.MOUSE_FILTER_STOP
		n.tooltip_text = FORMULAS.get(key, "")
		list.add_child(n)
		var v := UiStyle.label(str(_value(key)), UiStyle.TEXT, 13)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.custom_minimum_size = Vector2(52, 0)
		list.add_child(v)


func _boost_row(grid: GridContainer, r: Dictionary) -> void:
	var stat := str(r["keyword"])
	var base := int((stats["stats"] as Dictionary).get(stat, 0))
	# bonus: scrolls (additional) + items (P1.06)
	var bonus := int((stats.get("additional", {}) as Dictionary).get(stat, 0)) + int((stats.get("bonus", {}) as Dictionary).get(stat, 0))
	var breed := int(stats.get("breed", 12))
	var cost := StatFormulas.point_cost(breed, stat, base)
	grid.add_child(UiStyle.icon(ICONS + str(r.get("asset", "")), 22, Color.WHITE))
	var n := UiStyle.label(_name_of(r))
	n.custom_minimum_size = Vector2(110, 0)
	n.mouse_filter = Control.MOUSE_FILTER_STOP
	n.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	n.tooltip_text = "Clic : répartir plusieurs points"
	n.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			ask_points(stat)
			n.accept_event())
	grid.add_child(n)
	for v: int in [base, bonus, base + bonus]:
		var l := UiStyle.label(str(v), UiStyle.TEXT if v != bonus or bonus != 0 else UiStyle.TEXT_MUTED)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.custom_minimum_size = Vector2(44, 0)
		grid.add_child(l)
	var b := Button.new()
	b.text = "+"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(30, 0)
	b.disabled = int(stats["capital"]) < cost
	var tiers := PackedStringArray(StatFormulas.tiers(breed, stat).map(func(t: Array) -> String:
		return "dès %d : %d" % [int(t[0]), int(t[1])]))
	b.tooltip_text = "%d capital par point (%s)\nMaj+clic : 10 points · clic droit : répartir plusieurs points" % [cost, ", ".join(tiers)]
	b.gui_input.connect(func(ev: InputEvent) -> void:
		if not (ev is InputEventMouseButton and ev.pressed):
			return
		var button := (ev as InputEventMouseButton).button_index
		if button == MOUSE_BUTTON_LEFT:
			_send_points(stat, 10 if ev.shift_pressed else 1)
			b.accept_event()
		elif button == MOUSE_BUTTON_RIGHT:
			ask_points(stat)
			b.accept_event())
	grid.add_child(b)


## Asks the game for `points` more points of `stat`: the capital they cost (StatFormulas tiers).
func _send_points(stat: String, points: int) -> void:
	var breed := int(stats.get("breed", 12))
	var base := int((stats["stats"] as Dictionary).get(stat, 0))
	backend.send(Protocol.boost_stat(stat, StatFormulas.capital_for(breed, stat, base + points) - StatFormulas.capital_for(breed, stat, base)))


## The batch spending window of `stat`: how many points (up to what the capital buys), their
## cost and the capital left, "Max", then one boost_stat for all of them.
func ask_points(stat: String) -> void:
	var breed := int(stats.get("breed", 12))
	var base := int((stats["stats"] as Dictionary).get(stat, 0))
	var capital := int(stats["capital"])
	var most := int(StatFormulas.boost(breed, stat, base, capital)[0])
	var row_data := {}
	for r: Dictionary in GameData.table("characteristics").values():
		if str(r.get("keyword", "")) == stat:
			row_data = r
	var title := _name_of(row_data) if not row_data.is_empty() else stat
	var modal := Control.new()
	modal.name = "PointsDialog"
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal.add_child(dim)
	var w := UiWindow.new()
	w.setup("", "Répartir : %s" % title)
	w.custom_minimum_size = Vector2(340, 0)
	modal.add_child(w)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	w.body.add_child(line)
	line.add_child(UiStyle.icon(ICONS + str(row_data.get("asset", "")), 22, Color.WHITE))
	line.add_child(UiStyle.label("Points à ajouter"))
	var spin := SpinBox.new()
	spin.min_value = 0 if most == 0 else 1
	spin.max_value = most
	spin.value = most
	spin.rounded = true
	spin.custom_minimum_size = Vector2(90, 0)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(spin)
	var max_b := Button.new()
	max_b.text = "Max"
	max_b.focus_mode = Control.FOCUS_NONE
	max_b.pressed.connect(func() -> void: spin.value = most)
	line.add_child(max_b)
	var info := UiStyle.label("", UiStyle.TEXT_MUTED, 13)
	w.body.add_child(info)
	var ok := Button.new()
	var refresh := func(v: float) -> void:
		var pts := int(v)
		var cost := StatFormulas.capital_for(breed, stat, base + pts) - StatFormulas.capital_for(breed, stat, base)
		info.text = "%d → %d  ·  coût : %d capital  ·  reste : %d" % [base, base + pts, cost, capital - cost]
		ok.disabled = pts <= 0
	spin.value_changed.connect(refresh)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	w.body.add_child(buttons)
	var no := Button.new()
	no.text = "Annuler"
	no.pressed.connect(w.close_window)
	buttons.add_child(no)
	ok.text = "Investir"
	ok.add_theme_color_override("font_color", UiStyle.GOOD)
	ok.pressed.connect(func() -> void:
		_send_points(stat, int(spin.value))
		modal.queue_free())
	buttons.add_child(ok)
	refresh.call(spin.value)
	w.closed.connect(modal.queue_free)
	get_parent().add_child(modal)
	w.open()


func _value(keyword: String) -> int:
	var src := str(SOURCES.get(keyword, ""))
	if src == "ap" or src == "mp":
		return int(stats.get(src, 0))
	if src.begins_with("derived:"):
		return int((stats.get("derived", {}) as Dictionary).get(src.substr(8), 0))
	return int((stats.get("bonus", {}) as Dictionary).get(keyword, 0))


static func _name_of(r: Dictionary) -> String:
	return DofusI18n.text(int(r.get("nameId", 0)), str(r.get("keyword", "")))
