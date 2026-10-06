## Quest journal, roadmap P2.03 (Q): the quests under way on the left (then the finished ones), the
## chosen quest on the right: its step, the description of the step and its objectives.
## It also holds the client's copy of the quest log, fed by quest_list / quest_start / quest_update /
## quest_complete; the tracker (QuestTracker) reads it. The sim decides everything.
class_name QuestWindow
extends UiWindow

signal changed

## quest id -> view (Protocol quest_start)
var active := {}
## [{id, name_id}] in completion order
var finished: Array = []
var backend: GameBackend
var _selected := -1
var _list: VBoxContainer
var _detail: VBoxContainer


func setup_window(p_backend: GameBackend = null) -> void:
	backend = p_backend
	setup("quests", UiStyle.plain_text(DofusI18n.text(QuestTexts.JOURNAL, "Quêtes")), "UI/Figma/menuIcons/1x/quest")
	default_anchor = Vector2(0.4, 0.35)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	body.add_child(row)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(220, 340)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 3)
	scroll.add_child(_list)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.BG_INSET, UiStyle.BORDER, 4, 10))
	panel.custom_minimum_size = Vector2(340, 340)
	row.add_child(panel)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 6)
	panel.add_child(_detail)
	_fill()


# ── the events ─────────────────────────────────────────────────────────────────

func set_list(ev: Dictionary) -> void:
	active.clear()
	for q: Dictionary in ev["active"]:
		active[int(q["id"])] = q
	finished = (ev["finished"] as Array).duplicate()
	_changed()


func quest_started(q: Dictionary) -> void:
	active[int(q["id"])] = q
	_selected = int(q["id"])
	_changed()


func quest_updated(q: Dictionary) -> void:
	active[int(q["id"])] = q
	_changed()


func quest_done(id: int, name_id: int) -> void:
	active.erase(id)
	if not finished.any(func(f: Dictionary) -> bool: return int(f["id"]) == id):
		finished.append({"id": id, "name_id": name_id})
	if _selected == id:
		_selected = -1
	_changed()


func _changed() -> void:
	_fill()
	changed.emit()


# ── drawing ────────────────────────────────────────────────────────────────────

func _fill() -> void:
	if _list == null:
		return
	for c: Node in _list.get_children():
		c.queue_free()
	for c: Node in _detail.get_children():
		c.queue_free()
	if _selected < 0 and not active.is_empty():
		_selected = int(active.keys()[0])
	if active.is_empty() and finished.is_empty():
		_list.add_child(UiStyle.label("Aucune quête. Parlez aux habitants.", UiStyle.TEXT_MUTED, 13))
	for id: int in active:
		_list.add_child(_entry(id, QuestTexts.quest_name(int(active[id]["name_id"]), id), id == _selected, UiStyle.GOLD))
	if not finished.is_empty():
		_list.add_child(UiStyle.label("Terminées", UiStyle.TEXT_MUTED, 12))
		for f: Dictionary in finished:
			_list.add_child(_entry(int(f["id"]), QuestTexts.quest_name(int(f["name_id"]), int(f["id"])), false, UiStyle.TEXT_MUTED))
	if active.has(_selected):
		_show(active[_selected])
	else:
		_detail.add_child(UiStyle.label("", UiStyle.TEXT_MUTED, 13))


func _entry(id: int, text: String, selected: bool, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.toggle_mode = false
	b.add_theme_color_override("font_color", color if not selected else Color.WHITE)
	b.set_meta("quest", id)
	if active.has(id):
		b.pressed.connect(func() -> void:
			_selected = id
			_fill())
	return b


func _show(q: Dictionary) -> void:
	var title := UiStyle.label(QuestTexts.quest_name(int(q["name_id"]), int(q["id"])), UiStyle.GOLD, 17)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(title)
	var step_name := UiStyle.plain_text(DofusI18n.text(int(q.get("step_name_id", 0)), ""))
	if step_name != "" and step_name != QuestTexts.quest_name(int(q["name_id"]), int(q["id"])):
		var step := UiStyle.label("%s (%d/%d)" % [step_name, int(q["step"]) + 1, int(q["steps"])] if int(q["steps"]) > 1 else step_name, UiStyle.TEXT, 14)
		step.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(step)
	var desc := UiStyle.plain_text(DofusI18n.text(int(q.get("desc_id", 0)), ""))
	if desc != "":
		var d := UiStyle.label(desc, UiStyle.TEXT_MUTED, 13)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(d)
	_detail.add_child(UiStyle.label("Objectifs", UiStyle.GOLD, 14))
	for o: Dictionary in q["objectives"]:
		_detail.add_child(objective_label(o, 13))
	_detail.add_child(UiStyle.label("Niveau conseillé : %d" % int(q.get("level", 1)), UiStyle.TEXT_MUTED, 12))
	if backend != null: # P2.04: the sim gives the quest up and sends quest_list again
		var give_up := Button.new()
		give_up.text = "Abandonner"
		give_up.pressed.connect(func() -> void: backend.send(Protocol.quest_abandon(int(q["id"]))))
		_detail.add_child(give_up)


## A line for an objective: done = crossed in green, to do = white, waiting for the previous ones = muted.
static func objective_label(o: Dictionary, size: int, width := 300) -> Label:
	var done := bool(o["done"])
	var locked := bool(o.get("locked", false))
	var l := UiStyle.label(("✓ " if done else "• ") + QuestTexts.objective(o),
			UiStyle.GOOD if done else (UiStyle.TEXT_MUTED if locked else UiStyle.TEXT), size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0)
	return l
