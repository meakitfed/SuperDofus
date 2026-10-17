## Achievements window (P2.12b, key U): the points of the character, the top categories on the left (done / total),
## the achievements of the chosen one on the right with their objectives (ticked when true). Opening it asks the
## sim for the state (achievement_open); everything shown comes from AchievementsModel.
class_name AchievementsWindow
extends UiWindow

var model := AchievementsModel.new()
var backend: GameBackend
var _selected := -1
var _points: Label
var _cats: VBoxContainer
var _list: VBoxContainer


func setup_window(p_backend: GameBackend = null) -> void:
	backend = p_backend
	setup("achievements", "Succès", "UI/Figma/menuIcons/1x/success")
	default_anchor = Vector2(0.5, 0.3)
	_points = UiStyle.label("", UiStyle.GOLD, 14)
	body.add_child(_points)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	body.add_child(row)
	var left := ScrollContainer.new()
	left.custom_minimum_size = Vector2(200, 360)
	left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(left)
	_cats = VBoxContainer.new()
	_cats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cats.add_theme_constant_override("separation", 3)
	left.add_child(_cats)
	var right := ScrollContainer.new()
	right.custom_minimum_size = Vector2(380, 360)
	right.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(right)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	right.add_child(_list)
	refresh()


func open() -> void:
	super.open()
	if backend != null:
		backend.send(ProtocolAchievement.open())


func on_event(t: String, ev: Dictionary) -> void:
	if t == ProtocolAchievement.LIST:
		model.apply_list(ev)
	elif t == ProtocolAchievement.UNLOCKED:
		model.apply_unlocked(ev)
	refresh()


func select(top: int) -> void:
	_selected = top
	refresh()


func refresh() -> void:
	for c: Node in _cats.get_children():
		c.queue_free()
	for c: Node in _list.get_children():
		c.queue_free()
	_points.text = "%s points sur %s" % [UiStyle.thousands(model.points), UiStyle.thousands(model.total)]
	var cats := model.categories()
	if cats.is_empty():
		_list.add_child(UiStyle.label("Aucun succès dans ce monde.", UiStyle.TEXT_MUTED, 13))
		return
	if _selected == -1 or not cats.any(func(c: Dictionary) -> bool: return int(c["id"]) == _selected):
		_selected = int(cats[0]["id"])
	for c: Dictionary in cats:
		var b := Button.new()
		b.text = "%s  %d/%d" % [c["name"], int(c["done"]), int(c["count"])]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.button_pressed = int(c["id"]) == _selected
		b.pressed.connect(select.bind(int(c["id"])))
		_cats.add_child(b)
	for r: Dictionary in model.rows(_selected):
		_list.add_child(_card(r))


func _card(r: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.BG_INSET, UiStyle.GOOD if bool(r["done"]) else UiStyle.BORDER, 4, 8))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	card.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var name := UiStyle.label(str(r["name"]), UiStyle.GOLD if bool(r["done"]) else UiStyle.TEXT, 14)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(name)
	head.add_child(UiStyle.label("%d pts" % int(r["points"]), UiStyle.TEXT_MUTED, 12))
	if str(r["desc"]) != "":
		var d := UiStyle.label(str(r["desc"]), UiStyle.TEXT_MUTED, 11)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(d)
	for o: Dictionary in r["objectives"]:
		if str(o["name"]) == "":
			continue
		var l := UiStyle.label("%s %s" % ["[x]" if bool(o["done"]) else "[ ]", o["name"]], UiStyle.GOOD if bool(o["done"]) else UiStyle.TEXT, 11)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
	return card
