## Spell book (S), roadmap P1.03: the class's spell pairs (Dofus 3 variants)
## in spell book order, each with its two spells; learnt ones are lit, the
## used one of each pair is framed. The right panel details the selected spell
## (description, grade, costs, effects) and lets the player use it instead of
## its pair (choose_variant). Used spells are dragged to the spell bar.
## Fed by player_stats; every rule (level, variants) is the game's: the window
## only reads the static spell data (SpellBook) to show them.
class_name SpellBookWindow
extends UiWindow

var backend: GameBackend
var stats := {}
var _selected := 0 # spells.id shown on the right
var _rows: VBoxContainer
var _detail: VBoxContainer


func setup_window(p_backend: GameBackend) -> void:
	backend = p_backend
	setup("spells", "Sorts", "UI/Figma/menuIcons/1x/spells")
	default_anchor = Vector2(0.5, 0.4)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	body.add_child(h)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(330, 470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	h.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 3)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)
	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.BG_INSET, UiStyle.BORDER, 5, 12))
	right.custom_minimum_size = Vector2(360, 470)
	h.add_child(right)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 8)
	right.add_child(_detail)


func set_stats(s: Dictionary) -> void:
	stats = s
	if SpellBook.pair_of(_breed(), _selected).is_empty(): # first stats, or another character
		var pairs := SpellBook.pairs(_breed())
		_selected = int(pairs[0][0]) if not pairs.is_empty() else 0
	_fill()


func _breed() -> int:
	return int(stats.get("breed", 12))


func _level() -> int:
	return int(stats.get("level", 1))


## spells.id used by the character (from its castable ids).
func _used() -> Array:
	return (stats.get("spells", []) as Array).map(func(id: Variant) -> int: return int(SpellBook.get_spell(int(id)).get("spell", 0)))


func _fill() -> void:
	for c: Node in _rows.get_children():
		c.queue_free()
	var used := _used()
	for pair: Array in SpellBook.pairs(_breed()):
		_rows.add_child(_row(pair, used))
	_fill_detail()


func _row(pair: Array, used: Array) -> Control:
	var in_pair := pair.filter(func(s: int) -> bool: return used.has(s))
	var shown: int = in_pair[0] if not in_pair.is_empty() else pair[0]
	var panel := PanelContainer.new()
	var sel := pair.has(_selected)
	panel.add_theme_stylebox_override("panel", UiStyle.panel(Color(0.2, 0.18, 0.13, 0.9) if sel else Color(0, 0, 0, 0.18),
			UiStyle.GOLD if sel else Color(0, 0, 0, 0), 4, 4))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	panel.add_child(h)
	for sid: int in pair:
		var learnt := SpellBook.unlock_level(sid) <= _level()
		var slot := SpellSlot.new(SpellBook.grade_for(sid, _level()) if learnt else SpellBook.grade_ids(sid)[0], 40)
		slot.dimmed = not learnt
		slot.selected = used.has(sid)
		slot.draggable = used.has(sid)
		slot.overlay = "" if learnt else str(SpellBook.unlock_level(sid))
		slot.clicked.connect(func(_s: SpellSlot, button: int) -> void:
			if button == MOUSE_BUTTON_LEFT:
				_selected = sid
				_fill())
		h.add_child(slot)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var learnt_shown := SpellBook.unlock_level(shown) <= _level()
	v.add_child(UiStyle.label(spell_name(shown), UiStyle.TEXT if learnt_shown else UiStyle.TEXT_MUTED, 14))
	v.add_child(UiStyle.label("Niv. %d · variante niv. %d" % [SpellBook.unlock_level(pair[0]), SpellBook.unlock_level(pair[1])],
			UiStyle.TEXT_MUTED, 11))
	return panel


static func spell_name(sid: int) -> String:
	var s := SpellBook.get_spell(SpellBook.grade_ids(sid)[0]) if not SpellBook.grade_ids(sid).is_empty() else {}
	return DofusI18n.text(int(s.get("name_id", 0)), str(s.get("name", "?")))


func _fill_detail() -> void:
	for c: Node in _detail.get_children():
		c.queue_free()
	if _selected == 0:
		return
	var level := _level()
	var learnt := SpellBook.unlock_level(_selected) <= level
	var grades := SpellBook.grade_ids(_selected)
	var castable := SpellBook.grade_for(_selected, level) if learnt else int(grades[0])
	var s := SpellBook.get_spell(castable)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_detail.add_child(head)
	var big := SpellSlot.new(castable, 64)
	big.dimmed = not learnt
	big.draggable = _used().has(_selected)
	head.add_child(big)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	names.add_child(UiStyle.label(spell_name(_selected), UiStyle.GOLD, 19))
	var grade_levels := PackedStringArray(grades.map(func(g: int) -> String: return str(int(SpellBook.get_spell(g).get("level", 1)))))
	names.add_child(UiStyle.label(("Grade %d / %d" % [int(s.get("grade", 1)), grades.size()]) if learnt
			else "Appris au niveau %d" % SpellBook.unlock_level(_selected), UiStyle.TEXT if learnt else UiStyle.BAD, 13))
	names.add_child(UiStyle.label("Grades aux niveaux " + ", ".join(grade_levels), UiStyle.TEXT_MUTED, 12))
	var desc := Label.new()
	desc.text = UiStyle.plain_text(DofusI18n.text(int(s.get("description_id", 0)), ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(330, 0)
	desc.add_theme_color_override("font_color", UiStyle.TEXT_MUTED)
	desc.add_theme_font_size_override("font_size", 13)
	_detail.add_child(desc)
	_detail.add_child(HSeparator.new())
	_detail.add_child(UiTooltips.spell(s))
	if s.has("partial"):
		var note := Label.new()
		note.text = ("Aucun effet de ce sort n'est encore simulé : il ne peut pas être lancé." if (s.get("effects", []) as Array).is_empty()
				else "Certains effets de ce sort (invocation, glyphe, porter…) ne sont pas encore simulés.")
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size = Vector2(330, 0)
		note.add_theme_color_override("font_color", UiStyle.BAD)
		note.add_theme_font_size_override("font_size", 12)
		_detail.add_child(note)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.add_child(spacer)
	var use := CharacterSelectScreen.gold_button("Utiliser ce sort")
	use.custom_minimum_size = Vector2(0, 38)
	use.add_theme_font_size_override("font_size", 16)
	var in_use := _used().has(_selected)
	use.disabled = in_use or not learnt
	use.text = "Sort utilisé" if in_use else ("Utiliser ce sort" if learnt else "Pas encore appris")
	use.tooltip_text = "Remplace l'autre sort de la paire (hors combat)"
	var sid := _selected
	use.pressed.connect(func() -> void: backend.send(Protocol.choose_variant(sid)))
	_detail.add_child(use)
