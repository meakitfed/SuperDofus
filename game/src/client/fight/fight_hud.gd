## Fight UI: turn timeline (top), your stats + spell bar + ready / end turn
## (bottom), short messages. Reads FightView state, calls back its actions.
class_name FightHud
extends Control

const COL_HP := Color(0.95, 0.35, 0.35)
const COL_AP := Color(0.4, 0.7, 1.0)
const COL_MP := Color(0.45, 0.9, 0.45)

var view: FightView
var _timeline: HBoxContainer
var _bar: PanelContainer
var _hp: Label
var _ap: Label
var _mp: Label
var _timer: Label
## the turn's chrono (P1.15), the challenge banner and the option buttons
var _chrono: UiBar
var _banner: VBoxContainer
var _option_box: HBoxContainer
var _option_buttons := {}
var _message: Label
var _main_button: Button
var spell_bar: SpellBar
## the weapon hit (or Coup de poing), left of the bar
var weapon: SpellSlot
var _tiles := {} # fighter id -> TimelineTile
var _msg_until := 0


func setup(p_view: FightView) -> void:
	view = p_view
	theme = ClientTheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_timeline = HBoxContainer.new()
	_timeline.add_theme_constant_override("separation", 6)
	add_child(_timeline)

	_bar = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.085, 0.08, 0.88)
	style.border_color = Color(0.45, 0.38, 0.26)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	_bar.add_theme_stylebox_override("panel", style)
	add_child(_bar)
	var box := VBoxContainer.new()
	_bar.add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 22)
	box.add_child(top)
	_hp = _stat_label(top, COL_HP)
	_ap = _stat_label(top, COL_AP)
	_mp = _stat_label(top, COL_MP)
	_timer = Label.new()
	top.add_child(_timer)
	_chrono = UiBar.new(UiStyle.GOOD, 14)
	_chrono.custom_minimum_size = Vector2(150, 14)
	_chrono.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_chrono)
	var row: BoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	weapon = SpellSlot.new(0, 44)
	weapon.draggable = false
	weapon.clicked.connect(func(s: SpellSlot, button: int) -> void:
		if button == MOUSE_BUTTON_LEFT and s.spell_id != 0:
			view.select_spell(s.spell_id))
	row.add_child(weapon)
	spell_bar = SpellBar.new()
	spell_bar.pressed.connect(func(id: int) -> void: view.select_spell(id))
	spell_bar.moved.connect(func(spell: int, slot: int) -> void: view.backend.send(Protocol.move_spell(spell, slot)))
	row.add_child(spell_bar)
	set_bar()
	var buttons := VBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(buttons)
	row = buttons
	_main_button = Button.new()
	_main_button.focus_mode = Control.FOCUS_NONE
	_main_button.custom_minimum_size = Vector2(150, 0)
	_main_button.pressed.connect(func() -> void: view.end_turn())
	row.add_child(_main_button)
	var quit := Button.new()
	quit.text = "Quitter" if view.spectator else "Abandonner"
	quit.focus_mode = Control.FOCUS_NONE
	quit.pressed.connect(func() -> void: view.leave())
	row.add_child(quit)

	_banner = VBoxContainer.new()
	_banner.add_theme_constant_override("separation", 2)
	add_child(_banner)
	_option_box = HBoxContainer.new()
	_option_box.add_theme_constant_override("separation", 4)
	add_child(_option_box)
	for o: Array in OPTIONS:
		var b := Button.new()
		b.text = o[1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = o[2]
		b.toggled.connect(func(on: bool) -> void:
			if on != bool(view.options.get(o[0], false)):
				view.set_option(o[0], on))
		_option_box.add_child(b)
		_option_buttons[o[0]] = b

	if view.spectator: # watching: the timer and the way out, nothing to play with
		for c: Control in [_hp, _ap, _mp, weapon, spell_bar, _main_button, _option_box]:
			c.visible = false
	_message = Label.new()
	_message.add_theme_font_size_override("font_size", 22)
	_message.add_theme_color_override("font_outline_color", Color.BLACK)
	_message.add_theme_constant_override("outline_size", 6)
	add_child(_message)
	rebuild_timeline()
	refresh()


## Your bar (FightView.bar), keeping only the spells your fighter has; test
## worlds without a bar (old spell files) show the known spells in order.
func set_bar() -> void:
	var known: Array = (view.me().get("spells", []) as Array).map(func(x: Variant) -> int: return int(x))
	var b: Array = view.bar.map(func(x: Variant) -> int: return int(x) if known.has(int(x)) else 0)
	# the weapon hit / Coup de poing: the fighter spell not in any spell book pair
	var hit := known.filter(func(id: int) -> bool: return id == Equipment.WEAPON_SPELL or SpellBook.grade_ids(0).has(id))
	known = known.filter(func(id: int) -> bool: return not hit.has(id))
	if b.is_empty() or b.max() == 0:
		b = known
	spell_bar.set_bar(b)
	if not hit.is_empty():
		var own: Dictionary = view.spell_of(int(hit[0]))
		if int(hit[0]) == Equipment.WEAPON_SPELL:
			weapon.set_spell_dict(own)
		else:
			weapon.set_spell(int(hit[0]))
	if _main_button != null: # not during setup
		refresh()


func show_message(text: String, seconds := 2.0) -> void:
	_message.text = text
	_msg_until = Time.get_ticks_msec() + int(seconds * 1000)


func rebuild_timeline() -> void:
	for t: Node in _tiles.values():
		t.queue_free()
	_tiles.clear()
	for id: int in view.order:
		var tile := TimelineTile.new()
		_timeline.add_child(tile)
		tile.setup(view.fighters[id])
		_tiles[id] = tile


## the fight options: key, button text, tooltip (Dofus: lock, group only, block spectators, ask for help)
const OPTIONS := [["locked", "Verrouiller", "Verrouiller le combat : personne ne peut le rejoindre"],
		["party_only", "Groupe seul", "Seul votre groupe peut rejoindre le combat"],
		["secret", "Sans spectateurs", "Bloquer les spectateurs"],
		["help", "Aide", "Demander de l'aide"]]


## The challenges banner: one line per challenge, coloured by state.
func set_challenges() -> void:
	for c: Node in _banner.get_children():
		c.queue_free()
	for c: Dictionary in view.challenges:
		var state := str(c["state"])
		var color := UiStyle.GOOD if state == "success" else (UiStyle.BAD if state == "failed" else UiStyle.GOLD)
		var mark := "✔ " if state == "success" else ("✘ " if state == "failed" else "◆ ")
		var text := mark + DofusI18n.text(int(c["name_id"]), "?")
		if int(c.get("target", -1)) >= 0:
			text += " (%s)" % view.fighter_name(int(c["target"]))
		var l := UiStyle.label(text, color, 16)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 5)
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		l.tooltip_text = "%s
+%d %% d'XP et de butin si réussi" % [UiStyle.plain_text(DofusI18n.text(int(c["desc_id"]), "")), roundi(float(c["bonus"]) * 100.0)]
		_banner.add_child(l)


func refresh_options() -> void:
	for key: String in _option_buttons:
		(_option_buttons[key] as Button).set_pressed_no_signal(bool(view.options.get(key, false)))


func _process(_delta: float) -> void:
	var secs := ceili(view.time_left_ms() / 1000.0)
	_chrono.set_values(view.time_left_ms(), view.timer_total)
	_chrono.modulate = Color.WHITE if view.time_left_ms() > 5000 else UiStyle.BAD
	if view.phase == "placement":
		_timer.text = "Placement · %d s" % secs
	elif view.current == view.you:
		_timer.text = "À vous · %d s" % secs
	else:
		_timer.text = "Tour de %s · %d s" % [view.fighter_name(view.current), secs]
	if _message.text != "" and Time.get_ticks_msec() > _msg_until:
		_message.text = ""
	# manual layout (a Control under a CanvasLayer has no parent rect to anchor to)
	size = get_viewport_rect().size
	_timeline.position = Vector2((size.x - _timeline.get_combined_minimum_size().x) * 0.5, 58)
	_bar.position = Vector2((size.x - _bar.size.x) * 0.5, size.y - _bar.size.y - 12)
	_message.position = (size - _message.size) * Vector2(0.5, 0.35)
	_banner.position = Vector2(12, 120)
	_option_box.position = Vector2(_bar.position.x + _bar.size.x - _option_box.get_combined_minimum_size().x, _bar.position.y - _option_box.get_combined_minimum_size().y - 6)


func refresh() -> void:
	var me := view.me()
	if not me.is_empty():
		_refresh_mine(me)
	_refresh_tiles()


## Your own numbers, buttons and spell slots (nothing of it when watching).
func _refresh_mine(me: Dictionary) -> void:
	_hp.text = "♥ %d / %d" % [int(me["hp"]), int(me["max_hp"])]
	var shield := view.buff_total(view.you, "shield")
	if shield > 0:
		_hp.text += "  +%d" % shield
	_ap.text = "★ %d PA" % int(me["ap"])
	_mp.text = "➜ %d PM" % int(me["mp"])
	if view.phase == "placement":
		_main_button.text = "Pas prêt" if bool(me.get("ready", false)) else "Prêt (Espace)"
		_main_button.disabled = false
	else:
		_main_button.text = "Fin du tour (Espace)"
		_main_button.disabled = view.current != view.you
	for slot: SpellSlot in spell_bar.slots + [weapon]:
		var id := slot.spell_id
		if id == 0:
			continue
		var why := view.spell_block(id)
		slot.selected = view.selected_spell == id
		slot.dimmed = not view.is_my_turn() or why != ""
		slot.overlay = why if why.is_valid_int() else ""


func _refresh_tiles() -> void:
	for id: int in view.order:
		if not _tiles.has(id):
			continue
		var f: Dictionary = view.fighters[id]
		var t: TimelineTile = _tiles[id]
		t.update(f, id == view.current)
		var lines: Array = ["%s (niv. %d)" % [view.fighter_name(id), int(f.get("level", 1))],
				"%d / %d PV · %d PA · %d PM" % [int(f["hp"]), int(f["max_hp"]), int(f["ap"]), int(f["mp"])]]
		lines.append_array(view.buff_lines(id))
		if view.phase == "placement" and bool(f.get("ready", false)):
			lines.append("Prêt")
		t.tooltip_text = "\n".join(lines)


func _stat_label(parent: Control, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 17)
	parent.add_child(l)
	return l

