## The social window (P3.05b, F): three tabs (friends, enemies, ignored), a green dot for the
## friends who are online, the name box to add, a button to remove and, for a friend online, to
## whisper. It only shows the lists the sim sent and asks the sim for every change.
class_name ContactsWindow
extends UiWindow

signal whisper(name: String)

var model := ContactsModel.new()
var backend: GameBackend
var _tabs: UiTabs
var _pages := {}
var _edit: LineEdit
var _kind := Contacts.FRIEND


func setup_window(p_backend: GameBackend = null) -> void:
	backend = p_backend
	setup("contacts", "Amis", "UI/Figma/menuIcons/1x/friends")
	default_anchor = Vector2(0.3, 0.2)
	_tabs = UiTabs.new()
	for kind: String in Contacts.KINDS:
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(340, 230)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 3)
		scroll.add_child(box)
		_pages[kind] = box
		_tabs.add_tab(ContactsModel.KIND_TITLES[kind], scroll)
	_tabs.tab_changed.connect(func(i: int) -> void: _kind = Contacts.KINDS[i])
	body.add_child(_tabs)
	var row := HBoxContainer.new()
	_edit = LineEdit.new()
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.placeholder_text = "Nom du personnage"
	_edit.max_length = 30
	_edit.text_submitted.connect(func(_t: String) -> void: add_typed())
	row.add_child(_edit)
	var add := Button.new()
	add.text = "Ajouter"
	add.pressed.connect(add_typed)
	row.add_child(add)
	body.add_child(row)
	_fill()


func open() -> void:
	super.open()
	if backend != null:
		backend.send(ProtocolContacts.get_lists()) # fresh online marks


func set_lists(ev: Dictionary) -> void:
	model.apply(ev)
	_fill()


func refresh() -> void:
	_fill()


func add_typed() -> void:
	var name := _edit.text.strip_edges()
	_edit.clear()
	if name != "" and backend != null:
		backend.send(ProtocolContacts.add(_kind, name))


func _fill() -> void:
	if _pages.is_empty():
		return
	for kind: String in Contacts.KINDS:
		var box: VBoxContainer = _pages[kind]
		for c: Node in box.get_children():
			box.remove_child(c)
			c.queue_free()
		var list: Array = model.lists[kind]
		if list.is_empty():
			box.add_child(UiStyle.label("Personne pour l'instant.", UiStyle.TEXT_MUTED, 13))
		for e: Dictionary in list:
			box.add_child(_row(kind, e))


func _row(kind: String, e: Dictionary) -> Control:
	var name := str(e["name"])
	var online := bool(e.get("online", false))
	var row := HBoxContainer.new()
	row.set_meta("contact", name)
	if kind != Contacts.IGNORED:
		var dot := UiStyle.label("●", UiStyle.GOOD if online else UiStyle.TEXT_MUTED, 14)
		dot.tooltip_text = "En ligne" if online else "Hors ligne"
		row.add_child(dot)
	var text := name
	if online:
		text += "  ·  niveau %d · %s" % [int(e["level"]), CharacterSelectScreen.breed_name(int(e["breed"]))]
		if str(e.get("playing", "")) not in ["", name]:
			text += "  (%s)" % str(e["playing"])
	var l := UiStyle.label(text, UiStyle.TEXT if online or kind == Contacts.IGNORED else UiStyle.TEXT_MUTED, 13)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	row.add_child(l)
	if online and kind != Contacts.IGNORED:
		var w := Button.new()
		w.text = "Chuchoter"
		w.pressed.connect(func() -> void: whisper.emit(str(e.get("playing", name))))
		row.add_child(w)
	var rm := Button.new()
	rm.text = "×"
	rm.tooltip_text = "Retirer de la liste"
	rm.pressed.connect(func() -> void:
		if backend != null:
			backend.send(ProtocolContacts.remove(kind, name)))
	row.add_child(rm)
	return row
