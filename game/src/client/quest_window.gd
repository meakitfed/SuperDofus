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
var _search: LineEdit
var _list: VBoxContainer
var _detail: VBoxContainer


func setup_window(p_backend: GameBackend = null) -> void:
	backend = p_backend
	setup("quests", UiStyle.plain_text(DofusI18n.text(QuestTexts.JOURNAL, "Quêtes")), "UI/Figma/menuIcons/1x/quest")
	default_anchor = Vector2(0.06, 0.3) # left, clear of the character (the map centre)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	body.add_child(row)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	row.add_child(left)
	_search = UiSearch.field("Rechercher une quête", _fill, 200)
	left.add_child(_search)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(240, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
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
	var q := _search.text
	var shown := 0
	for id: int in active:
		var title := QuestTexts.quest_name(int(active[id]["name_id"]), id)
		if UiSearch.matches(title, q):
			shown += 1
			_list.add_child(_entry(id, title, id == _selected, UiStyle.TEXT))
	var done: Array = finished.filter(func(f: Dictionary) -> bool:
		return UiSearch.matches(QuestTexts.quest_name(int(f["name_id"]), int(f["id"])), q))
	if not done.is_empty():
		_list.add_child(UiStyle.label("Terminées (%d)" % done.size(), UiStyle.TEXT_MUTED, 12))
		for f: Dictionary in done:
			shown += 1
			_list.add_child(_entry(int(f["id"]), QuestTexts.quest_name(int(f["name_id"]), int(f["id"])), false, UiStyle.TEXT_MUTED))
	if shown == 0 and not (active.is_empty() and finished.is_empty()):
		_list.add_child(UiStyle.label("Aucune quête ne correspond.", UiStyle.TEXT_MUTED, 13))
	if active.has(_selected):
		_show(active[_selected])
	else:
		_detail.add_child(UiStyle.label("Choisissez une quête dans la liste." if not active.is_empty() else "", UiStyle.TEXT_MUTED, 13))


## A quest of the list: a row that lights up, gold edge when chosen (the finished ones are not clickable).
func _entry(id: int, text: String, selected: bool, color: Color) -> UiRow:
	var row := UiRow.new(active.has(id))
	row.selected = selected
	row.set_meta("quest", id)
	var l := UiStyle.label(text, color, UiStyle.FS_BODY)
	l.clip_text = true
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.tooltip_text = text
	row.h.add_child(l)
	if active.has(id):
		row.activated.connect(func() -> void:
			_selected = id
			_fill())
	else:
		row.h.add_child(UiStyle.label("✓", UiStyle.GOOD, UiStyle.FS_BODY))
	return row


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
		give_up.theme_type_variation = UiStyle.V_DANGER
		give_up.pressed.connect(func() -> void:
			UiConfirm.ask(self, "Abandonner la quête",
					"Abandonner « %s » ? Votre progression dans cette quête sera perdue." % QuestTexts.quest_name(int(q["name_id"]), int(q["id"])),
					"Abandonner", func() -> void: backend.send(Protocol.quest_abandon(int(q["id"])))))
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
