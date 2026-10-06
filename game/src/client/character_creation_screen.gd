## Character creation (roadmap P1.02): class, sex, body, face, colors and
## name, with the animated character built live by the shared LookBuilder
## (the very function the game uses to validate the creation).
##   left: the classes (breeds, Dofus order), their description and roles
##   centre: the character on its pedestal (turn it with the arrows), name, Create
##   right: sex, body, face, colors
## Classes the game cannot create yet (`breeds` of the characters event) are shown dimmed.
class_name CharacterCreationScreen
extends Control

signal cancelled

const THUMB := 56

var backend: GameBackend
var playable: Array = [] # breeds.id the game accepts
var breed := 12
var sex := 0
var body := 0
var face := 0
var colors: Array = [] # one int per breed color, -1 = default
var _dir := 1
var _stage: Node2D
var _preview: ActorView
## C.02e: the zones of the classes come on demand (null = all in the base); the preview waits for its class
var class_gate: ZoneGate
var _breed_buttons := {} # breed id -> Button
var _breed_title: Label
var _breed_roles: HBoxContainer
var _breed_desc: Label
var _sex_buttons: Array[Button] = []
var _bodies: HBoxContainer
var _faces: GridContainer
var _colors: HBoxContainer
var _name_edit: LineEdit
var _name_hint: Label
var _create: Button
var _locked: Label


func setup(p_backend: GameBackend, p_playable: Array) -> void:
	backend = p_backend
	playable = p_playable.map(func(b: Variant) -> int: return int(b))
	theme = ClientTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(CharacterSelectScreen.backdrop())
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	margin.add_child(row)
	row.add_child(_left_panel())
	row.add_child(_centre())
	row.add_child(_right_panel())
	var first := breed if breed in playable or playable.is_empty() else int(playable[0])
	_select_breed(first)


# --- left: classes -----------------------------------------------------------------

func _left_panel() -> Control:
	var panel := _panel(300)
	var v: VBoxContainer = panel.get_child(0)
	v.add_child(UiStyle.label("Classe", UiStyle.GOLD, 18))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	for row: Dictionary in LookBuilder.breeds():
		var id := int(row["id"])
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.icon = UiStyle.texture(CharacterSelectScreen.symbol_texture(id))
		b.expand_icon = true
		b.custom_minimum_size = Vector2(50, 50)
		b.tooltip_text = CharacterSelectScreen.breed_name(id) + ("" if id in playable else " (bientôt)")
		if not id in playable:
			b.modulate = Color(1, 1, 1, 0.4)
		b.pressed.connect(func() -> void: _select_breed(id))
		grid.add_child(b)
		_breed_buttons[id] = b
	_breed_title = UiStyle.label("", UiStyle.GOLD, 24)
	v.add_child(_breed_title)
	_breed_roles = HBoxContainer.new()
	_breed_roles.add_theme_constant_override("separation", 6)
	v.add_child(_breed_roles)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_breed_desc = UiStyle.label("", UiStyle.TEXT_MUTED, 14)
	_breed_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_breed_desc.custom_minimum_size = Vector2(268, 0)
	scroll.add_child(_breed_desc)
	return panel


func _on_class_installed(installed: int) -> void:
	if installed == breed and is_inside_tree():
		_refresh_preview()


func _select_breed(id: int) -> void:
	breed = id
	body = 0
	face = 0
	colors = []
	for b: int in _breed_buttons:
		(_breed_buttons[b] as Button).button_pressed = b == id
	_breed_title.text = CharacterSelectScreen.breed_name(id)
	var row := GameData.row("breeds", id)
	_breed_desc.text = UiStyle.plain_text(DofusI18n.text(int(row.get("descriptionId", 0)), ""))
	for c in _breed_roles.get_children():
		c.queue_free()
	var roles: Array = (row.get("breedRoles", []) as Array).filter(func(r: Dictionary) -> bool: return int(r.get("order", -1)) >= 1)
	roles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["order"]) < int(b["order"]))
	for r: Dictionary in roles:
		var role := GameData.row("breedroles", int(r["roleId"]))
		var chip := UiStyle.label(DofusI18n.text(int(role.get("nameId", 0)), "Rôle"), Color.hex((int(role.get("color", 0xAAAAAA)) << 8) | 0xFF), 13)
		chip.tooltip_text = UiStyle.plain_text(DofusI18n.text(int(r.get("descriptionId", 0)), ""))
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		_breed_roles.add_child(chip)
	_locked.visible = not id in playable
	_refresh_choices()


# --- centre: preview, name --------------------------------------------------------

func _centre() -> Control:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	var title := UiStyle.label("Création de personnage", UiStyle.GOLD, 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var stage_box := Control.new()
	stage_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(stage_box)
	_stage = Node2D.new()
	stage_box.add_child(_stage)
	_stage.draw.connect(func() -> void:
		_stage.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.42))
		_stage.draw_circle(Vector2.ZERO, 90, Color(0, 0, 0, 0.35))
		_stage.draw_arc(Vector2.ZERO, 90, 0, TAU, 64, Color(UiStyle.GOLD, 0.45), 2.0, true))
	stage_box.resized.connect(func() -> void: _stage.position = Vector2(stage_box.size.x / 2.0, stage_box.size.y - 30))
	var turn := HBoxContainer.new()
	turn.alignment = BoxContainer.ALIGNMENT_CENTER
	turn.add_theme_constant_override("separation", 120)
	v.add_child(turn)
	for step in [-1, 1]:
		var b := Button.new()
		b.text = "⟲" if step < 0 else "⟳"
		b.tooltip_text = "Tourner le personnage"
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(44, 36)
		b.pressed.connect(func() -> void:
			_dir = posmod(_dir + step * 2, 8) # the 4 diagonal directions Dofus shows
			if _preview != null:
				_preview.face(_dir))
		turn.add_child(b)
	_locked = UiStyle.label("Cette classe arrive avec ses sorts : son apparence est déjà disponible ici.", UiStyle.TEXT_MUTED, 14)
	_locked.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_locked)
	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 10)
	v.add_child(name_row)
	_name_edit = LineEdit.new()
	_name_edit.max_length = 20
	_name_edit.placeholder_text = "Nom du personnage"
	_name_edit.custom_minimum_size = Vector2(300, 42)
	_name_edit.add_theme_font_size_override("font_size", 18)
	_name_edit.text_changed.connect(func(_t: String) -> void: _refresh_create())
	_name_edit.text_submitted.connect(func(_t: String) -> void: _submit())
	name_row.add_child(_name_edit)
	_name_hint = UiStyle.label("", UiStyle.TEXT_MUTED, 13)
	_name_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_name_hint)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	v.add_child(buttons)
	var back := Button.new()
	back.text = "Retour"
	back.tooltip_text = Shortcuts.label("close")
	back.custom_minimum_size = Vector2(150, 44)
	back.pressed.connect(func() -> void: cancelled.emit())
	buttons.add_child(back)
	_create = CharacterSelectScreen.gold_button("Créer")
	_create.pressed.connect(_submit)
	buttons.add_child(_create)
	return v


func _refresh_preview() -> void:
	if _preview != null:
		_preview.queue_free()
		_preview = null
	if class_gate != null and not class_gate.want_class(breed):
		if not class_gate.class_installed.is_connected(_on_class_installed):
			class_gate.class_installed.connect(_on_class_installed)
		return # the class files are downloading: the preview comes with class_installed
	_preview = ActorView.new()
	_stage.add_child(_preview)
	_preview.setup(LookBuilder.build(breed, sex, body, face, colors), 0, _dir)
	_preview.position = Vector2.ZERO
	_preview.scale = Vector2(3.0, 3.0)


func _refresh_create() -> void:
	var n := _name_edit.text
	var ok := NameRules.is_valid(n)
	_create.disabled = not ok or not breed in playable
	if n == "":
		_name_hint.text = "Une majuscule puis des minuscules, 2 à 20 lettres, jusqu'à deux tirets."
		_name_hint.add_theme_color_override("font_color", UiStyle.TEXT_MUTED)
	else:
		_name_hint.text = "Nom valide" if ok else "Une majuscule puis des minuscules, 2 à 20 lettres, jusqu'à deux tirets (ex. Jean-Luc)."
		_name_hint.add_theme_color_override("font_color", UiStyle.GOOD if ok else UiStyle.BAD)


func _submit() -> void:
	if not _create.disabled:
		backend.send(Protocol.create_character(_name_edit.text, breed, sex, body, face, colors))


func focus_name(text := "") -> void:
	_name_edit.text = text
	_refresh_create()
	_name_edit.grab_focus.call_deferred()


# --- right: sex, body, face, colors -------------------------------------------------

func _right_panel() -> Control:
	var panel := _panel(330)
	var v: VBoxContainer = panel.get_child(0)
	v.add_child(UiStyle.label("Sexe", UiStyle.GOLD, 16))
	var sexes := HBoxContainer.new()
	sexes.add_theme_constant_override("separation", 8)
	v.add_child(sexes)
	for s in 2:
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.text = "Masculin" if s == 0 else "Féminin"
		b.custom_minimum_size = Vector2(145, 40)
		b.pressed.connect(func() -> void:
			sex = s
			body = 0
			face = 0
			colors = []
			_refresh_choices())
		sexes.add_child(b)
		_sex_buttons.append(b)
	v.add_child(UiStyle.label("Corps", UiStyle.GOLD, 16))
	_bodies = HBoxContainer.new()
	_bodies.add_theme_constant_override("separation", 6)
	v.add_child(_bodies)
	v.add_child(UiStyle.label("Visage", UiStyle.GOLD, 16))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 3 * (THUMB + 6))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_faces = GridContainer.new()
	_faces.columns = 5
	_faces.add_theme_constant_override("h_separation", 6)
	_faces.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_faces)
	var color_title := HBoxContainer.new()
	v.add_child(color_title)
	var ct := UiStyle.label("Couleurs", UiStyle.GOLD, 16)
	ct.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_title.add_child(ct)
	var reset := Button.new()
	reset.text = "Par défaut"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(func() -> void:
		colors = []
		_refresh_choices())
	color_title.add_child(reset)
	_colors = HBoxContainer.new()
	_colors.add_theme_constant_override("separation", 6)
	v.add_child(_colors)
	return panel


## Rebuilds the choice buttons of the current class and sex, then the preview.
func _refresh_choices() -> void:
	for i in _sex_buttons.size():
		_sex_buttons[i].button_pressed = i == sex
	for c in _bodies.get_children() + _faces.get_children() + _colors.get_children():
		c.queue_free()
	var bs := LookBuilder.bodies(breed, sex)
	for b: Dictionary in bs:
		_bodies.add_child(_thumb("UI/cosmetics/bodies/" + str(b["assetId"]), int(b["id"]), body if body != 0 else int(bs[0]["id"]), DofusI18n.text(int(b.get("nameId", 0)), str(b.get("label", ""))),
				func(id: int) -> void:
					body = id
					_refresh_choices(), Vector2(THUMB, THUMB * 1.6)))
	var fs := LookBuilder.faces(breed, sex)
	for h: Dictionary in fs:
		_faces.add_child(_thumb("UI/cosmetics/faces/" + str(h["assetId"]), int(h["id"]), face if face != 0 else int(fs[0]["id"]),
				DofusI18n.text(int(h.get("nameId", 0)), "Visage " + str(h.get("label", ""))),
				func(id: int) -> void:
					face = id
					_refresh_choices(), Vector2(THUMB, THUMB)))
	var defaults := LookBuilder.default_colors(breed, sex)
	for i in defaults.size():
		var pick := ColorPickerButton.new()
		pick.custom_minimum_size = Vector2(40, 40)
		pick.focus_mode = Control.FOCUS_NONE
		pick.edit_alpha = false
		pick.tooltip_text = "Couleur %d" % (i + 1)
		var value := int(colors[i]) if i < colors.size() and int(colors[i]) >= 0 else int(defaults[i])
		pick.color = Color.hex((value << 8) | 0xFF)
		pick.popup_closed.connect(func() -> void:
			while colors.size() < defaults.size():
				colors.append(-1)
			colors[i] = pick.color.to_rgba32() >> 8
			_refresh_preview())
		_colors.add_child(pick)
	_refresh_preview()
	_refresh_create()


func _thumb(texture: String, id: int, current: int, tip: String, on_pick: Callable, size: Vector2) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.icon = UiStyle.texture(texture)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = size
	b.tooltip_text = tip
	b.button_pressed = id == current
	b.pressed.connect(func() -> void: on_pick.call(id))
	return b


func _panel(width: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(width, 0)
	p.add_theme_stylebox_override("panel", UiStyle.panel(Color(UiStyle.BG, 0.85), UiStyle.BORDER, 8, 14))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	return p


func _unhandled_input(event: InputEvent) -> void:
	if visible and Shortcuts.pressed(event, "close"):
		cancelled.emit()
		get_viewport().set_input_as_handled()
