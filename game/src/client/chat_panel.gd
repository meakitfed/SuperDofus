## The chat window (P3.02), bottom left: tabs (Général, Privé, Commerce, Recrutement), the
## messages of each, and the box where one types. Enter opens the box, Escape closes it.
## A line that starts with "/" is a chat command (Chat.parse: /s /b /r /w Bob…, sent as typed:
## the sim parses it) or, for the words of no channel, a GM command (/tp…, CommandLine.parse).
## It shows what the sim sent in `chat_msg`; it keeps no rule of its own except the layout.
class_name ChatPanel
extends PanelContainer

const SIZE := Vector2(430, 190)
const MAX_LINES := 200
## what a GM sees when a command is done (admin_result.args fill the %s)
const ADMIN_TEXTS := {
	"tp": "Téléporté", "give": "%s reçoit l'objet %s x%s", "kamas": "%s a maintenant %s kamas", "level": "%s est niveau %s",
	"heal": "%s est soigné", "say": "Annonce envoyée", "who": "%s joueur(s) : %s", "kick": "%s est expulsé",
	"ban": "%s est banni", "unban": "%s n'est plus banni", "mute": "%s est muet (%s min)", "unmute": "%s peut de nouveau parler",
	"reload": "Données rechargées",
}

var backend: GameBackend
var me := ""
var current := Chat.GENERAL
## the player the private tab answers to (the last one who wrote, or the last one written to)
var reply_to := ""
var _tabs: UiTabs
var _logs := {}      # channel -> RichTextLabel
var _edit: LineEdit
var _prefix: Label


func _ready() -> void:
	theme = ClientTheme.get_theme()
	custom_minimum_size = SIZE
	size = SIZE
	add_theme_stylebox_override("panel", UiStyle.panel(Color(UiStyle.BG, 0.8), UiStyle.BORDER, 6, 6))
	_tabs = UiTabs.new()
	add_child(_tabs)
	for ch: String in Chat.TABS:
		var log := RichTextLabel.new()
		log.bbcode_enabled = true
		log.scroll_following = true
		log.selection_enabled = true
		log.fit_content = false
		log.add_theme_font_size_override("normal_font_size", 13)
		log.add_theme_color_override("default_color", UiStyle.TEXT)
		_logs[ch] = log
		_tabs.add_tab(tab_title(ch), log)
	_tabs.tab_changed.connect(func(i: int) -> void:
		current = Chat.TABS[i]
		_update_prefix())
	var row := HBoxContainer.new()
	_prefix = UiStyle.label("", UiStyle.GOLD, 13)
	row.add_child(_prefix)
	_edit = LineEdit.new()
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.max_length = Chat.MAX_LENGTH
	_edit.placeholder_text = "Entrée pour parler · /b commerce · /r recrutement · /w nom message"
	_edit.add_theme_font_size_override("font_size", 13)
	_edit.text_submitted.connect(func(text: String) -> void:
		submit(text)
		_edit.release_focus())
	_edit.gui_input.connect(func(event: InputEvent) -> void:
		if Shortcuts.pressed(event, "close"):
			_edit.release_focus()
			_edit.accept_event())
	row.add_child(_edit)
	_tabs.add_child(row) # under the pages
	_update_prefix()


static func tab_title(channel: String) -> String:
	return DofusI18n.text(Chat.name_id(channel), str(Chat.FR_NAMES.get(channel, channel)))


## Enter: the box takes the keyboard.
func open() -> void:
	_edit.grab_focus()


func typing() -> bool:
	return _edit != null and _edit.has_focus()


## "Chuchoter": the box opens on "/w <name> " (the contacts window and the player menu).
func whisper(name: String) -> void:
	_edit.text = "/w %s " % name
	_edit.caret_column = _edit.text.length()
	_edit.grab_focus()


## Sends a line of the box (and clears it): chat, or a GM command if no channel has that word.
func submit(text: String) -> void:
	_edit.clear()
	var line := text.strip_edges()
	if line == "":
		return
	if line.to_lower() == "/help":
		on_help()
		return
	var contact := ContactsModel.parse_command(line) # /friend Bob, /ignore Bob…
	if not contact.is_empty():
		backend.send(contact)
		return
	if line.begins_with("/") and Chat.channel_of(line.split(" ")[0]) == "":
		var cmd := CommandLine.parse(line)
		if not cmd.is_empty():
			backend.send(cmd)
		return
	backend.send(Protocol.chat_send(current, line, reply_to))


## One chat_msg: written in its tab (the world channels and general each have one).
func on_message(ev: Dictionary) -> void:
	var channel := str(ev["channel"])
	var log: RichTextLabel = _logs.get(channel)
	if log == null:
		return
	if channel == Chat.PRIVATE:
		reply_to = str(ev["to"]) if str(ev["from"]) == me else str(ev["from"])
		_update_prefix()
	log.append_text(line_for(ev, me) + "\n")
	while log.get_paragraph_count() > MAX_LINES:
		log.remove_paragraph(0)


## The usage of every GM command, in the General tab (/help).
func on_help() -> void:
	var log: RichTextLabel = _logs[Chat.GENERAL]
	for usage: String in ProtocolAdmin.USAGE.values():
		log.append_text("[color=#%s]%s[/color]\n" % [UiStyle.TEXT_MUTED.to_html(false), usage.replace("[", "[lb]")])


## admin_result (a GM command was done) and announce (a GM spoke to everyone): a line of the
## General tab. The sim sends values, the words are ours (ADMIN_TEXTS).
func on_admin(ev: Dictionary) -> void:
	var log: RichTextLabel = _logs[Chat.GENERAL]
	var text := ""
	var color := UiStyle.GOOD
	if str(ev["t"]) == ProtocolAdmin.ANNOUNCE:
		text = "[Annonce] %s : %s" % [str(ev["from"]), str(ev["text"])]
		color = UiStyle.KAMAS
	else:
		text = admin_line(str(ev["cmd"]), ev["args"])
	log.append_text("[color=#%s]%s[/color]\n" % [color.to_html(false), text.replace("[", "[lb]")])


static func admin_line(cmd: String, args: Array) -> String:
	var shown: Array = args.map(func(x: Variant) -> String: return str(int(x)) if x is float else str(x)) # JSON numbers are floats
	var fmt: String = ADMIN_TEXTS.get(cmd, "")
	if cmd == "who":
		return fmt % [shown.size(), ", ".join(shown)]
	if fmt == "" or fmt.count("%s") > shown.size():
		return "/%s : fait" % cmd
	return fmt % shown.slice(0, fmt.count("%s"))


## "[heure] Alice : salut", "De Bob : salut", "À Bob : salut" with the colour of the channel.
static func line_for(ev: Dictionary, me_name: String) -> String:
	var text := str(ev["text"]).replace("[", "[lb]") # a player's text never becomes BBCode
	var who := str(ev["from"])
	var head := who
	if str(ev["channel"]) == Chat.PRIVATE:
		head = "À %s" % str(ev["to"]) if who == me_name else "De %s" % who
	return "[color=#%s]%s : %s[/color]" % [channel_color(str(ev["channel"])).to_html(false), head, text]


static func channel_color(channel: String) -> Color:
	match channel:
		Chat.PRIVATE:
			return UiStyle.XP
		Chat.COMMERCE:
			return UiStyle.KAMAS
		Chat.RECRUITMENT:
			return UiStyle.GOOD
	return UiStyle.TEXT


func text_of(channel: String) -> String:
	return (_logs[channel] as RichTextLabel).get_parsed_text() if _logs.has(channel) else ""


func _update_prefix() -> void:
	var sc := Chat.shortcut(current)
	_prefix.text = ("%s %s " % [sc, reply_to] if current == Chat.PRIVATE and reply_to != "" else sc + " ") if sc != "" else ""
