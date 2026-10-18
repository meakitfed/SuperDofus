## Fight UI: turn timeline (top), your stats + spell bar + ready / end turn
## (bottom), short messages. Reads FightView state, calls back its actions.
class_name FightHud
extends Control

var view: FightView
var _timeline: HBoxContainer
var _bar: PanelContainer
var _hp: UiBar
var _ap: FightPoints
var _mp: FightPoints
var _stats: HBoxContainer
var _timer: Label
var _layout_sig := []
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
var _quit: Button
## The player hid the interface (HudToggles): only the end-turn and quit buttons stay.
var compact := false:
	set(v):
		if v == compact:
			return
		compact = v
		for c: Control in [_timeline, _banner, _stats, _option_box, weapon, spell_bar]:
			if c != null:
				c.visible = not v and not (view.spectator and (c == _option_box or c == weapon or c == spell_bar or c == _stats))
		if view.spectator:
			_stats.visible = true # the timer is all a spectator has
		_bar.reset_size.call_deferred() # the panel shrinks to the buttons that stay (or grows back)
		_layout_sig = []


func setup(p_view: FightView) -> void:
	view = p_view
	theme = ClientTheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_timeline = HBoxContainer.new()
	_timeline.add_theme_constant_override("separation", int(FightLayout.TILE_GAP))
	add_child(_timeline)

	_bar = PanelContainer.new()
	_bar.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.BG, UiStyle.BORDER_LIGHT, UiStyle.RADIUS, 8))
	add_child(_bar)
	var box := VBoxContainer.new()
	_bar.add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	box.add_child(top)
	_stats = top
	_hp = UiBar.new(UiStyle.HP, 18)
	_hp.custom_minimum_size = Vector2(190, 18)
	_hp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hp.tooltip_text = "Points de vie"
	_hp.mouse_filter = Control.MOUSE_FILTER_PASS
	top.add_child(_hp)
	_ap = FightPoints.new("PA", UiStyle.AP)
	top.add_child(_ap)
	_mp = FightPoints.new("PM", UiStyle.MP)
	top.add_child(_mp)
	_timer = UiStyle.label("", UiStyle.TEXT)
	_timer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
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
	_main_button.custom_minimum_size = Vector2(170, 38)
	_main_button.theme_type_variation = UiStyle.V_PRIMARY
	_main_button.pressed.connect(func() -> void: view.end_turn())
	row.add_child(_main_button)
	var quit := Button.new()
	_quit = quit
	quit.text = "Quitter" if view.spectator else "Abandonner"
	quit.focus_mode = Control.FOCUS_NONE
	quit.theme_type_variation = UiStyle.V_DANGER
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
	_message.add_theme_font_override("font", UiStyle.font("title"))
	_message.add_theme_font_size_override("font_size", 22)
	_message.add_theme_color_override("font_outline_color", Color.BLACK)
	_message.add_theme_constant_override("outline_size", 6)
	_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_timeline.scale = Vector2.ONE * FightLayout.timeline_scale(size.x if size.x > 0.0 else get_viewport_rect().size.x, view.order.size(), TimelineTile.SIZE.x)
	_layout_sig = []


## the fight options: key, button text, tooltip (Dofus: lock, group only, block spectators, ask for help)
const OPTIONS := [["locked", "Verrouiller", "Verrouiller le combat : personne ne peut le rejoindre"],
		["party_only", "Groupe seul", "Seul votre groupe peut rejoindre le combat"],
		["secret", "Sans spectateurs", "Bloquer les spectateurs"],
		["help", "Aide", "Demander de l'aide"]]


## The challenges banner: one line per challenge, coloured by state.
func set_challenges() -> void:
	for c: Node in _banner.get_children():
		c.queue_free()
	if not view.challenges.is_empty():
		var title := UiStyle.label("Défis", UiStyle.TEXT_MUTED, 13)
		title.add_theme_color_override("font_outline_color", Color.BLACK)
		title.add_theme_constant_override("outline_size", 4)
		_banner.add_child(title)
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


func _exit_tree() -> void:
	SpellFx.safe = Vector2.ZERO


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
	_timer.add_theme_color_override("font_color", UiStyle.GOLD if view.current == view.you and view.phase != "placement" else UiStyle.TEXT)
	if _message.text != "" and Time.get_ticks_msec() > _msg_until:
		_message.text = ""
	_apply_layout()


## The sizes of the parts as they sit on screen (the timeline may be scaled down).
func _sizes() -> Dictionary:
	var out := {"bar": _bar.get_combined_minimum_size()}
	if not compact:
		out["timeline"] = _timeline.get_combined_minimum_size() * _timeline.scale
	if not view.spectator and not compact:
		out["options"] = _option_box.get_combined_minimum_size()
	var banner := _banner.get_combined_minimum_size()
	if banner.y > 0.0 and not compact:
		out["banner"] = banner
	if _message.text != "":
		out["message"] = _message.get_combined_minimum_size()
	return out


## Puts the parts where FightLayout says, only when the window or a part changed size
## (a Control under a CanvasLayer has no parent rect to anchor to, so it is done here, not per frame).
func _apply_layout() -> void:
	var vp := get_viewport_rect().size
	var sizes := _sizes()
	var sig: Array = [vp, sizes, _timeline.scale]
	if sig == _layout_sig:
		return
	_layout_sig = sig
	size = vp
	var scale := FightLayout.timeline_scale(vp.x, view.order.size(), TimelineTile.SIZE.x)
	if not is_equal_approx(scale, _timeline.scale.x):
		_timeline.scale = Vector2.ONE * scale
		if sizes.has("timeline"):
			sizes["timeline"] = _timeline.get_combined_minimum_size() * _timeline.scale
	var at := FightLayout.place(vp, sizes)
	_timeline.position = at.get("timeline", Vector2.ZERO)
	_bar.position = at.get("bar", Vector2.ZERO)
	_option_box.position = at.get("options", Vector2.ZERO)
	_banner.position = at.get("banner", Vector2(FightLayout.MARGIN, 120))
	_message.position = at.get("message", Vector2.ZERO)
	var b := FightLayout.bands(sizes)
	SpellFx.safe = b
	_layout_sig = [vp, _sizes(), _timeline.scale]


## Height of the top band (the timeline): the map is fitted under it (GameArea).
func reserved_top() -> float:
	return FightLayout.bands(_sizes()).x


## Height of the bottom band (the bar and its option buttons).
func reserved_bottom() -> float:
	return FightLayout.bands(_sizes()).y


## The timeline and the bar with its options, floating over the map: name -> screen Rect2.
func overlay_rects() -> Dictionary:
	var out := {}
	var sizes := _sizes()
	for k: String in ["timeline", "bar", "options"]:
		if sizes.has(k):
			var c: Control = {"timeline": _timeline, "bar": _bar, "options": _option_box}[k]
			out[k] = Rect2(c.position, sizes[k])
	return out


## The challenge banner, a panel at the top left: the map keeps out of it.
func banner_rect() -> Rect2:
	var s := _banner.get_combined_minimum_size()
	return Rect2(_banner.position, s) if s.y > 0.0 and not compact else Rect2()


func refresh() -> void:
	var me := view.me()
	if not me.is_empty():
		_refresh_mine(me)
	_refresh_tiles()


## Your own numbers, buttons and spell slots (nothing of it when watching).
func _refresh_mine(me: Dictionary) -> void:
	var shield := view.buff_total(view.you, "shield")
	_hp.set_values(int(me["hp"]), int(me["max_hp"]), "%d / %d%s" % [int(me["hp"]), int(me["max_hp"]), "  +%d" % shield if shield > 0 else ""])
	_ap.set_value(int(me["ap"]))
	_mp.set_value(int(me["mp"]))
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
		slot.note = _why_text(why, view.is_my_turn())


## Why a spell cannot be cast now, in words (the tooltip of its slot); "" when it can.
static func _why_text(why: String, my_turn: bool) -> String:
	if not my_turn:
		return "Ce n'est pas votre tour"
	if why == "":
		return ""
	if why.is_valid_int():
		return "Relance : encore %d tour%s" % [int(why), "s" if int(why) > 1 else ""]
	return {"PA": "Pas assez de PA", "max": "Plus de lancers ce tour", "état": "Un état vous en empêche", "sim": "Pas encore disponible", "?": "Sort inconnu"}.get(why, why)


func _refresh_tiles() -> void:
	for id: int in view.order:
		if not _tiles.has(id):
			continue
		var f: Dictionary = view.fighters[id]
		var t: TimelineTile = _tiles[id]
		t.is_you = id == view.you
		t.tip = {"name": view.fighter_name(id), "level": int(f.get("level", 1)), "hp": int(f["hp"]), "max_hp": int(f["max_hp"]),
				"ap": int(f["ap"]), "mp": int(f["mp"]), "buffs": view.buff_lines(id),
				"ready": view.phase == "placement" and bool(f.get("ready", false)), "team": int(f["team"]), "alive": bool(f["alive"])}
		t.update(f, id == view.current)
