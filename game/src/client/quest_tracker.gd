## Quest tracker, roadmap P2.03: a small panel under the minimap listing the quests under way and
## their current objectives (the Dofus "suivi de quêtes"). Read-only: it draws the journal's copy
## of the quest log (QuestWindow.active) and hides when no quest is under way.
class_name QuestTracker
extends PanelContainer

const MAX_QUESTS := 4
const WIDTH := 250

var _rows: VBoxContainer


func setup(journal: QuestWindow) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UiStyle.panel(Color(UiStyle.BG, 0.8), UiStyle.BORDER, 6, 8))
	custom_minimum_size = Vector2(WIDTH, 0)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
	add_child(_rows)
	journal.changed.connect(func() -> void: refresh(journal.active))
	refresh(journal.active)


func refresh(active: Dictionary) -> void:
	for c: Node in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	visible = not active.is_empty()
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
