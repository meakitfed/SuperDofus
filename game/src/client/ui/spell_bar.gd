## The spell shortcut bar (roleplay and fight): the first slots of the
## player's bar (player_stats.bar, arranged by the game), two rows of ten.
## Keys 1…0 cast the first row (Shortcuts "spell_slot_N"). Spells are dragged
## between slots or from the spell book: `moved` asks the game (move_spell).
class_name SpellBar
extends GridContainer

signal pressed(spell_id: int)
signal moved(spell: int, slot: int)

const COLUMNS := 10
const ROWS := 2

var slots: Array[SpellSlot] = []


func _init(slot_size := 44) -> void:
	columns = COLUMNS
	add_theme_constant_override("h_separation", 3)
	add_theme_constant_override("v_separation", 3)
	for i in COLUMNS * ROWS:
		var s := SpellSlot.new(0, slot_size)
		s.drop_slot = i
		if i < COLUMNS:
			s.key_text = Shortcuts.label_key("spell_slot_%d" % (i + 1))
		s.clicked.connect(func(slot: SpellSlot, button: int) -> void:
			if button == MOUSE_BUTTON_LEFT and slot.spell_id != 0:
				pressed.emit(slot.spell_id))
		s.dropped.connect(func(spell: int, slot: int) -> void: moved.emit(spell, slot))
		add_child(s)
		slots.append(s)


## bar: castable id or 0 per slot (player_stats.bar).
func set_bar(bar: Array) -> void:
	for i in slots.size():
		slots[i].set_spell(int(bar[i]) if i < bar.size() else 0)


## The castable id bound to a key event (first row), 0 if none.
func spell_for_key(event: InputEvent) -> int:
	for i in COLUMNS:
		if Shortcuts.pressed(event, "spell_slot_%d" % (i + 1)):
			return slots[i].spell_id
	return 0
