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
var _search: LineEdit
var _kind := Contacts.FRIEND


func setup_window(p_backend: GameBackend = null) -> void:
	backend = p_backend
	setup("contacts", "Amis", "UI/Figma/menuIcons/1x/social")
	default_anchor = Vector2(0.94, 0.25) # right, clear of the map centre
	_search = UiSearch.field("Rechercher un nom", _fill, 200)
	body.add_child(_search)
	_tabs = UiTabs.new()
	for kind: String in Contacts.KINDS:
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(360, 230)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 4)
		scroll.add_child(box)
		_pages[kind] = box
		_tabs.add_tab(ContactsModel.KIND_TITLES[kind], scroll)
	_tabs.tab_changed.connect(func(i: int) -> void: _kind = Contacts.KINDS[i])
	body.add_child(_tabs)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_edit = LineEdit.new()
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.placeholder_text = "Nom du personnage"
	_edit.max_length = 30
	_edit.text_submitted.connect(func(_t: String) -> void: add_typed())
	row.add_child(_edit)
	var add := Button.new()
	add.text = "Ajouter"
	add.theme_type_variation = UiStyle.V_PRIMARY
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
	for i in Contacts.KINDS.size():
		var kind: String = Contacts.KINDS[i]
		var box: VBoxContainer = _pages[kind]
		for c: Node in box.get_children():
			box.remove_child(c)
			c.queue_free()
		var list: Array = model.lists[kind]
		var shown := list.filter(func(e: Dictionary) -> bool: return UiSearch.matches(str(e["name"]), _search.text))
		var online := shown.filter(func(e: Dictionary) -> bool: return bool(e.get("online", false)))
		shown = online + shown.filter(func(e: Dictionary) -> bool: return not bool(e.get("online", false))) # who is there first
		_tabs.set_title(i, _tab_title(kind, list))
		if list.is_empty():
			box.add_child(UiStyle.label("Personne pour l'instant.", UiStyle.TEXT_MUTED, 13))
		elif shown.is_empty():
			box.add_child(UiStyle.label("Aucun nom ne correspond.", UiStyle.TEXT_MUTED, 13))
		for e: Dictionary in shown:
			box.add_child(_row(kind, e))


## "Amis (2/5)": who is online out of how many (friends only; the other lists just count).
static func _tab_title(kind: String, list: Array) -> String:
	var title: String = ContactsModel.KIND_TITLES[kind]
	if list.is_empty():
		return title
	if kind == Contacts.FRIEND:
		var n := list.filter(func(e: Dictionary) -> bool: return bool(e.get("online", false))).size()
		return "%s (%d/%d)" % [title, n, list.size()]
	return "%s (%d)" % [title, list.size()]


func _row(kind: String, e: Dictionary) -> Control:
	var name := str(e["name"])
	var online := bool(e.get("online", false))
	var row := UiRow.new()
	row.set_meta("contact", name)
	if kind != Contacts.IGNORED:
		var dot := UiStyle.label("●", UiStyle.GOOD if online else UiStyle.TEXT_MUTED, 14)
		dot.tooltip_text = "En ligne" if online else "Hors ligne"
		row.h.add_child(dot)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.h.add_child(texts)
	var l := UiStyle.label(name, UiStyle.TEXT if online or kind == Contacts.IGNORED else UiStyle.TEXT_MUTED, UiStyle.FS_BODY)
	l.clip_text = true
	texts.add_child(l)
	if online:
		var sub := "niveau %d · %s" % [int(e["level"]), CharacterSelectScreen.breed_name(int(e["breed"]))]
		if str(e.get("playing", "")) not in ["", name]:
			sub += "  (%s)" % str(e["playing"])
		texts.add_child(UiStyle.label(sub, UiStyle.TEXT_MUTED, UiStyle.FS_SMALL))
	if online and kind != Contacts.IGNORED:
		var w := Button.new()
		w.text = "Chuchoter"
		w.pressed.connect(func() -> void: whisper.emit(str(e.get("playing", name))))
		row.h.add_child(w)
	var rm := Button.new()
	rm.text = "×"
	rm.tooltip_text = "Retirer de la liste"
	UiStyle.compact(rm)
	rm.pressed.connect(func() -> void:
		if backend != null:
			backend.send(ProtocolContacts.remove(kind, name)))
	row.h.add_child(rm)
	return row
