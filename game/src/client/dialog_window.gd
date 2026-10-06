## NPC dialog window, roadmap P2.01: opened by `dialog` (the NPC speaks: its text,
## and the replies the sim offers this character), replaced by the next `dialog`,
## closed by `dialog_end`. Replies send dialog_reply; closing the window sends
## dialog_close. The texts are the client's own i18n (text_id); a hand-made world
## sends a literal `text`.
class_name DialogWindow
extends UiWindow

var backend: GameBackend
var _text: Label
var _replies: VBoxContainer
var _ending := false


func setup_window(p_backend: GameBackend) -> void:
	backend = p_backend
	setup("dialog", "PNJ")
	default_anchor = Vector2(0.5, 0.7)
	_text = UiStyle.label("", UiStyle.TEXT, 15)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(440, 0)
	body.add_child(_text)
	_replies = VBoxContainer.new()
	_replies.add_theme_constant_override("separation", 4)
	body.add_child(_replies)
	closed.connect(func() -> void:
		if not _ending:
			backend.send(Protocol.dialog_close()))


## `npc_name` = the NPC's name (the title bar).
func show_dialog(ev: Dictionary, npc_name: String) -> void:
	title_label.text = npc_name if npc_name != "" else "PNJ"
	_text.text = line(ev)
	for c: Node in _replies.get_children():
		c.queue_free()
	for r: Dictionary in ev["replies"]:
		_add_button(reply_line(r), func() -> void: backend.send(Protocol.dialog_reply(int(r["id"]))))
	_add_button("Fermer", close_window)
	open()


## dialog_end: the sim closed it (final reply, walked away).
func end_dialog() -> void:
	_ending = true
	close_window()
	_ending = false


## The text of a message or reply: its i18n id, else the literal text.
static func line(d: Dictionary) -> String:
	if d.has("text_id"):
		return UiStyle.plain_text(DofusI18n.text(int(d["text_id"]), str(d.get("text", ""))))
	return str(d.get("text", ""))


## A reply's label; a quest the NPC offers reads "Nouvelle quête : <name>" (the client's own text).
static func reply_line(r: Dictionary) -> String:
	if r.has("quest"):
		return QuestTexts.headline(QuestTexts.NEW_QUEST, "Nouvelle quête : $quest{0}", line(r))
	return line(r)


func _add_button(label: String, on_press: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.pressed.connect(on_press)
	_replies.add_child(b)
