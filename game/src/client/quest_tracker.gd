## Quest tracker, roadmap P2.03 (HUD: U.04): a small panel under the minimap listing the quests under
## way and their current objectives (the Dofus "suivi de quêtes"), with a header that folds it to a
## single line. Read-only: it draws the journal's copy of the quest log (QuestWindow.active) and
## hides when no quest is under way.
class_name QuestTracker
extends PanelContainer

const MAX_QUESTS := 4
const WIDTH := 244

## the header folds the list (remembered for the session)
static var folded := false

var _rows: VBoxContainer
var _head: Button
var _count := 0


func setup(journal: QuestWindow) -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	add_theme_stylebox_override("panel", UiStyle.panel(Color(UiStyle.BG, 0.85), UiStyle.BORDER, 6, 8))
	custom_minimum_size = Vector2(WIDTH, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	add_child(col)
	_head = Button.new()
	_head.flat = true
	_head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_head.focus_mode = Control.FOCUS_NONE
	_head.add_theme_color_override("font_color", UiStyle.TEXT)
	_head.add_theme_font_size_override("font_size", UiStyle.FS_SMALL)
	_head.pressed.connect(toggle_fold)
	col.add_child(_head)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
	col.add_child(_rows)
	journal.changed.connect(func() -> void: refresh(journal.active))
	refresh(journal.active)


func refresh(active: Dictionary) -> void:
	for c: Node in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	visible = not active.is_empty()
	_count = active.size()
	_update_head()
	var shown := 0
	for id: int in active:
		if shown >= MAX_QUESTS:
			break
		shown += 1
		var q: Dictionary = active[id]
		var title := UiStyle.label(QuestTexts.quest_name(int(q["name_id"]), id), UiStyle.GOLD, 13)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.custom_minimum_size = Vector2(WIDTH - 20, 0)
		_rows.add_child(title)
		for o: Dictionary in q["objectives"]:
			if bool(o.get("locked", false)):
				continue
			_rows.add_child(QuestWindow.objective_label(o, 12, WIDTH - 20))
	reset_size.call_deferred()


func toggle_fold() -> void:
	folded = not folded
	_update_head()
	reset_size.call_deferred()


func _update_head() -> void:
	_head.text = "%s Suivi de quêtes (%d)" % ["▸" if folded else "▾", _count]
	_head.tooltip_text = "Déplier" if folded else "Replier"
	_rows.visible = not folded
