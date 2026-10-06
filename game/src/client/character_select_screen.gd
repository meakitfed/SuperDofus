## Character selection (roadmap P1.01), shown after hello without a name:
## the account's characters of this world as cards (real class heads), the
## chosen one's sprite, Play / Delete, and a card that opens the creation
## screen (CharacterCreationScreen, P1.02).
## Only displays the `characters` list and sends list / create / delete /
## select commands: every rule (names, limits) is the game's; NameRules is
## shared so the name field can say at once whether a name is valid.
class_name CharacterSelectScreen
extends Control

const CARD := Vector2(172, 236)
const BREED_NAME_FALLBACK := "Pandawa"

var backend: GameBackend
var characters: Array = []
var max_count := 5
var selected := ""
var _world_label: Label
var _cards: HBoxContainer
var _stage: Node2D
var _preview: ActorView
var _preview_look := ""
var _info: Label
var _play: Button
var _delete: Button
## classes the game lets us create (characters.breeds)
var playable_breeds: Array = []
var creation: CharacterCreationScreen
## C.02e: where the files of a class come from in a zoned world (null = all in the base)
var class_gate: ZoneGate
var _last_click := {"name": "", "ms": 0}


func setup(p_backend: GameBackend, p_class_gate: ZoneGate = null) -> void:
	backend = p_backend
	class_gate = p_class_gate
	theme = ClientTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop())
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 10)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(col)
	var title := UiStyle.label("Choisissez votre personnage", UiStyle.GOLD, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	_world_label = UiStyle.label("", UiStyle.TEXT_MUTED, 15)
	_world_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_world_label)
	var stage_box := Control.new() # the chosen character, standing on a disc
	stage_box.custom_minimum_size = Vector2(0, 250)
	stage_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(stage_box)
	_stage = Node2D.new()
	stage_box.add_child(_stage)
	_stage.draw.connect(func() -> void: # the pedestal
		_stage.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.42))
		_stage.draw_circle(Vector2.ZERO, 70, Color(0, 0, 0, 0.35))
		_stage.draw_arc(Vector2.ZERO, 70, 0, TAU, 64, Color(UiStyle.GOLD, 0.45), 2.0, true))
	stage_box.resized.connect(func() -> void: _stage.position = Vector2(stage_box.size.x / 2.0, stage_box.size.y - 20))
	_info = UiStyle.label("", UiStyle.TEXT, 17)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_info)
	var center := CenterContainer.new()
	col.add_child(center)
	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override("separation", 14)
	center.add_child(_cards)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	col.add_child(buttons)
	_delete = Button.new()
	_delete.text = "Supprimer"
	_delete.custom_minimum_size = Vector2(150, 40)
	_delete.pressed.connect(_ask_delete)
	buttons.add_child(_delete)
	_play = gold_button("Jouer")
	_play.tooltip_text = Shortcuts.label("confirm")
	_play.pressed.connect(_play_selected)
	buttons.add_child(_play)


## characters event: {list: [{name, level, breed, sex, look}], max, world}.
func set_characters(ev: Dictionary) -> void:
	characters = ev.get("list", [])
	max_count = int(ev.get("max", 5))
	playable_breeds = ev.get("breeds", [])
	_world_label.text = "Serveur : %s · %d / %d personnages" % [str(ev.get("world", {}).get("name", "")), characters.size(), max_count]
	if not characters.any(func(c: Dictionary) -> bool: return c["name"] == selected):
		selected = str(characters[0]["name"]) if not characters.is_empty() else ""
	_rebuild()
	if characters.is_empty() and visible:
		_open_create()


## character_created: select the new one (the list follows).
func on_created(summary: Dictionary) -> void:
	selected = str(summary.get("name", ""))
	_close_create()


func _rebuild() -> void:
	for c in _cards.get_children():
		c.queue_free()
	for c: Dictionary in characters:
		_cards.add_child(_card(c))
	if characters.size() < max_count:
		_cards.add_child(_new_card())
	var cur := _current()
	_play.disabled = cur.is_empty()
	_delete.disabled = cur.is_empty()
	_info.text = "%s  ·  %s niveau %d" % [cur["name"], breed_name(int(cur["breed"])), int(cur["level"])] if not cur.is_empty() else ""
	_show_preview(str(cur.get("look", "")))


func _current() -> Dictionary:
	for c: Dictionary in characters:
		if c["name"] == selected:
			return c
	return {}


func _card(c: Dictionary) -> Control:
	var is_sel: bool = c["name"] == selected
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.add_theme_stylebox_override("panel", _card_style(is_sel))
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	var head := UiStyle.icon(head_texture(int(c["breed"]), int(c.get("sex", 0))), 128, Color.WHITE)
	v.add_child(head)
	var name := UiStyle.label(str(c["name"]), UiStyle.GOLD if is_sel else UiStyle.TEXT, 18)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name)
	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_child(UiStyle.icon(symbol_texture(int(c["breed"])), 20, Color.WHITE))
	line.add_child(UiStyle.label("Niv. %d" % int(c["level"]), UiStyle.TEXT_MUTED, 14))
	v.add_child(line)
	card.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var now := Time.get_ticks_msec()
			var double: bool = (ev as InputEventMouseButton).double_click or (_last_click["name"] == c["name"] and now - int(_last_click["ms"]) < 400)
			_last_click = {"name": c["name"], "ms": now}
			selected = str(c["name"])
			_rebuild()
			if double:
				_play_selected())
	return card


func _new_card() -> Control:
	var card := Button.new()
	card.custom_minimum_size = CARD
	card.focus_mode = Control.FOCUS_NONE
	card.text = "+\nCréer un\npersonnage"
	card.add_theme_font_size_override("font_size", 18)
	card.add_theme_stylebox_override("normal", _card_style(false, true))
	card.add_theme_stylebox_override("hover", _card_style(true, true))
	card.add_theme_stylebox_override("pressed", _card_style(true, true))
	card.add_theme_color_override("font_color", UiStyle.TEXT_MUTED)
	card.add_theme_color_override("font_hover_color", UiStyle.GOLD)
	card.pressed.connect(_open_create)
	return card


func _show_preview(look: String) -> void:
	if look == _preview_look:
		return
	_preview_look = look
	if _preview != null:
		_preview.queue_free()
		_preview = null
	if look == "":
		return
	_preview = ActorView.new()
	_stage.add_child(_preview)
	_preview.setup(look, 0, 1)
	_preview.position = Vector2.ZERO
	_preview.scale = Vector2(2.4, 2.4)


func _play_selected() -> void:
	if selected != "" and creation == null:
		backend.send(Protocol.select_character(selected))


func _ask_delete() -> void:
	if selected == "":
		return
	var name := selected
	UiConfirm.ask(self, "Supprimer un personnage",
			"Supprimer définitivement %s ? Son niveau, ses objets et ses kamas seront perdus." % name, "Supprimer",
			func() -> void: backend.send(Protocol.delete_character(name)))


# --- creation ------------------------------------------------------------------

## Opens the creation screen (P1.02) over the selection.
func _open_create() -> void:
	if creation != null:
		return
	creation = CharacterCreationScreen.new()
	add_child(creation)
	creation.class_gate = class_gate
	creation.setup(backend, playable_breeds)
	creation.cancelled.connect(_close_create)
	creation.focus_name()


func _close_create() -> void:
	if creation != null:
		creation.queue_free()
		creation = null


func _unhandled_input(event: InputEvent) -> void:
	if visible and Shortcuts.pressed(event, "confirm") and creation == null:
		_play_selected()
		get_viewport().set_input_as_handled()


# --- look ------------------------------------------------------------------------

## breeds.shortNameId in the player's language.
static func breed_name(breed: int) -> String:
	var row := GameData.row("breeds", breed)
	return DofusI18n.text(int(str(row.get("shortNameId", "0"))), BREED_NAME_FALLBACK if breed == 12 else "Classe %d" % breed)


## Content/UI/classes (tools/extractor/ui.py classes): head per breed and sex.
static func head_texture(breed: int, sex: int) -> String:
	return "UI/classes/heads/big/Head_%d" % (breed * 10 + sex)


static func symbol_texture(breed: int) -> String:
	return "UI/classes/symbol_%d" % breed


static func _card_style(active: bool, dashed := false) -> StyleBoxFlat:
	var s := UiStyle.panel(Color(0.08, 0.08, 0.09, 0.92) if not dashed else Color(0.06, 0.06, 0.07, 0.6),
			UiStyle.GOLD if active else UiStyle.BORDER, 8, 10)
	s.set_border_width_all(2 if active else 1)
	return s


## The main action of a screen (Jouer, Créer): gold, dark text.
static func gold_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(220, 46)
	b.add_theme_font_size_override("font_size", 20)
	for st: String in ["normal", "hover", "pressed", "disabled"]:
		var col := {"normal": Color(0.93, 0.74, 0.33), "hover": Color(1.0, 0.82, 0.42), "pressed": Color(0.85, 0.66, 0.28),
				"disabled": Color(0.35, 0.3, 0.2)}[st] as Color
		b.add_theme_stylebox_override(st, UiStyle.panel(col, Color(0.55, 0.4, 0.15), 6, 8))
	b.add_theme_color_override("font_color", Color(0.12, 0.09, 0.03))
	b.add_theme_color_override("font_hover_color", Color.BLACK)
	b.add_theme_color_override("font_pressed_color", Color.BLACK)
	b.add_theme_color_override("font_disabled_color", Color(0.6, 0.55, 0.45))
	return b


## Full-screen background of the menus (the world is not loaded yet): warm
## light in the middle, dark edges.
static func backdrop() -> TextureRect:
	var bg := TextureRect.new()
	var grad := GradientTexture2D.new()
	grad.fill = GradientTexture2D.FILL_RADIAL
	grad.fill_from = Vector2(0.5, 0.42)
	grad.fill_to = Vector2(1.05, 1.0)
	grad.gradient = Gradient.new()
	grad.gradient.set_color(0, Color(0.16, 0.14, 0.10))
	grad.gradient.set_color(1, Color(0.025, 0.027, 0.033))
	bg.texture = grad
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return bg
