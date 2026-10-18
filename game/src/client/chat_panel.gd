## The chat window (P3.02), bottom left: tabs (Général, Privé, Commerce, Recrutement), the
## messages of each, and the box where one types. Enter opens the box, Escape closes it.
## A line that starts with "/" is a chat command (Chat.parse: /s /b /r /w Bob…, sent as typed:
## the sim parses it) or, for the words of no channel, a GM command (/tp…, CommandLine.parse).
## It shows what the sim sent in `chat_msg`; it keeps no rule of its own except the layout.
class_name ChatPanel
extends PanelContainer

const SIZE := Vector2(430, 190)
const MAX_LINES := 200
## background opacity the player picks (the button of the tab row): clear, light, normal, solid
const OPACITIES := [0.25, 0.55, 0.82, 0.97]
## idle (not typed in, not hovered, nothing new for a while) the background fades to this share
## of its opacity so that the map shows through; the text never fades (outlined, always readable)
const IDLE_SHARE := 0.3
const FRESH_MS := 6000
const SETTINGS_FILE := "user://chat_settings.json"
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
var _logs := {}      # channel -> ChatLog
var _edit: LineEdit
var _prefix: Label
var _last_msg_ms := -FRESH_MS
var _bg: StyleBoxFlat
var _opacity_level := 2
var _opacity_button: Button
var _more: Button # "new messages": shown when the log is scrolled up and a line arrives
var _unread := {} # channel -> lines written in a tab that is not the one shown
var _bg_alpha := 0.0


func _ready() -> void:
	theme = ClientTheme.get_theme()
	custom_minimum_size = SIZE
	size = SIZE
	_load_settings()
	_bg = UiStyle.panel(Color(UiStyle.BG, OPACITIES[_opacity_level]), UiStyle.BORDER, 6, 6)
	add_theme_stylebox_override("panel", _bg)
	_bg_alpha = OPACITIES[_opacity_level]
	_tabs = UiTabs.new()
	add_child(_tabs)
	for ch: String in Chat.TABS:
		var log := ChatLog.new()
		log.scroll_following = true
		log.selection_enabled = true
		log.fit_content = false
		log.add_theme_font_size_override("normal_font_size", 13)
		log.add_theme_color_override("default_color", UiStyle.TEXT)
		log.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		log.add_theme_constant_override("outline_size", 3)
		log.add_theme_constant_override("line_separation", 2)
		_logs[ch] = log
		_tabs.add_tab(tab_title(ch), log)
	_tabs.set_compact()
	_tabs.tab_changed.connect(func(i: int) -> void:
		current = Chat.TABS[i]
		_unread.erase(current)
		_refresh_titles()
		_update_more()
		_update_prefix())
	_opacity_button = Button.new() # at the right end of the tab row
	_opacity_button.text = "◐"
	_opacity_button.flat = true
	_opacity_button.focus_mode = Control.FOCUS_NONE
	_opacity_button.pressed.connect(cycle_opacity)
	_tabs.add_to_bar(_opacity_button)
	_update_opacity_tip()
	_more = Button.new()
	_more.text = "▼ Nouveaux messages"
	_more.flat = true
	_more.focus_mode = Control.FOCUS_NONE
	_more.add_theme_font_size_override("font_size", UiStyle.FS_SMALL)
	_more.add_theme_color_override("font_color", UiStyle.GOLD)
	_more.visible = false
	_more.pressed.connect(scroll_to_end)
	_tabs.add_child(_more)
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


## The chat takes its share of the window (HudLayout.chat_size); a no-op when it already has it.
func fit(vp: Vector2) -> void:
	var s := HudLayout.chat_size(vp)
	if custom_minimum_size != s:
		custom_minimum_size = s
		size = s


func _process(delta: float) -> void:
	var fresh := Time.get_ticks_msec() - _last_msg_ms < FRESH_MS
	var active := typing() or fresh or get_global_rect().has_point(get_global_mouse_position())
	var target: float = OPACITIES[_opacity_level] * (1.0 if active else IDLE_SHARE)
	if not is_equal_approx(_bg_alpha, target):
		_bg_alpha = move_toward(_bg_alpha, target, delta * 2.0)
		_bg.bg_color.a = _bg_alpha
		_bg.border_color.a = clampf(_bg_alpha * 1.6, 0.0, 1.0)
	_edit.modulate.a = move_toward(_edit.modulate.a, 1.0 if active else 0.55, delta * 4.0)
	if _more.visible and _at_end():
		_update_more()


## Next background opacity (clear, light, normal, solid, clear...), remembered.
func cycle_opacity() -> void:
	_opacity_level = (_opacity_level + 1) % OPACITIES.size()
	_update_opacity_tip()
	_save_settings()


func opacity() -> float:
	return OPACITIES[_opacity_level]


func _update_opacity_tip() -> void:
	_opacity_button.tooltip_text = "Transparence du fond : %d %%" % int(round(float(OPACITIES[_opacity_level]) * 100.0))


func _load_settings() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_FILE)) if FileAccess.file_exists(SETTINGS_FILE) else null
	if data is Dictionary:
		_opacity_level = clampi(int(data.get("opacity", _opacity_level)), 0, OPACITIES.size() - 1)


func _save_settings() -> void:
	var f := FileAccess.open(SETTINGS_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"opacity": _opacity_level}))


## The tab titles with the lines unread in the others: "Privé (2)".
func _refresh_titles() -> void:
	for i in Chat.TABS.size():
		var ch: String = Chat.TABS[i]
		var n := int(_unread.get(ch, 0))
		_tabs.set_title(i, tab_title(ch) + (" (%d)" % n if n > 0 else ""))
		_tabs.set_alert(i, n > 0)


func unread(channel: String) -> int:
	return int(_unread.get(channel, 0))


func _log() -> ChatLog:
	return _logs[current]


## The scroll is at the bottom (or there is nothing to scroll).
func _at_end() -> bool:
	var bar := _log().get_v_scroll_bar()
	return bar.value + bar.page >= bar.max_value - 4.0


func _update_more() -> void:
	_more.visible = not _at_end()


func scroll_to_end() -> void:
	_log().scroll_to_line(maxi(0, _log().get_line_count() - 1))
	_more.visible = false


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
	if line.to_lower().begins_with("/e ") or line.to_lower() == "/e":
		var id := emote_id(line.substr(3))
		if id != 0:
			backend.send(ProtocolEmote.emote(id))
		else:
			var log: ChatLog = _logs[Chat.GENERAL]
			log.append_text("[color=#%s]Émote inconnue : %s[/color]
" % [UiStyle.TEXT_MUTED.to_html(false), line.substr(3).replace("[", "[lb]")])
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
	_last_msg_ms = Time.get_ticks_msec()
	var channel := str(ev["channel"])
	var log: ChatLog = _logs.get(channel)
	if log == null:
		return
	if channel == Chat.PRIVATE:
		reply_to = str(ev["to"]) if str(ev["from"]) == me else str(ev["from"])
		_update_prefix()
	log.append_text(line_for(ev, me) + "\n")
	while log.get_paragraph_count() > MAX_LINES:
		log.remove_paragraph(0)
	if channel != current:
		_unread[channel] = int(_unread.get(channel, 0)) + 1
		_refresh_titles()
	elif not _at_end():
		_more.visible = true


## The usage of every GM command, in the General tab (/help).
func on_help() -> void:
	var log: RichTextLabel = _logs[Chat.GENERAL]
	for usage: String in ProtocolAdmin.USAGE.values():
		log.append_text("[color=#%s]%s[/color]\n" % [UiStyle.TEXT_MUTED.to_html(false), usage.replace("[", "[lb]")])


## The server's rates (S.06, welcome.world.rates), in the General tab when a character arrives.
func on_rates(rates: Dictionary) -> void:
	if rates.is_empty():
		return
	var log: RichTextLabel = _logs[Chat.GENERAL]
	log.append_text("[color=#%s]%s[/color]\n" % [UiStyle.GOLD.to_html(false), rates_line(rates)])


static func rates_line(rates: Dictionary) -> String:
	var num := func(v: Variant) -> String: return str(int(v)) if float(v) == floorf(float(v)) else str(snappedf(float(v), 0.01))
	var text := "Taux du serveur : XP x%s, butin x%s, kamas x%s, métiers x%s" % [num.call(rates.get("xp", 1)),
			num.call(rates.get("drop", 1)), num.call(rates.get("kamas", 1)), num.call(rates.get("job_xp", 1))]
	if bool(rates.get("bonus_drops", false)):
		text += ", drops bonus : %s %% par monstre (équipements à ±%d niveaux)" % [num.call(rates.get("bonus_rate", 0)), int(rates.get("bonus_range", 0))]
	if bool(rates.get("free_keys", false)):
		text += ", trousseau de clés infini"
	return text


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
	for id: Variant in ev.get("links", []): # {item:id} -> the item's name (P3.02b)
		text = text.replace("{item:%d}" % int(id), "[lb]%s]" % item_name(int(id)))
	for id: Variant in ev.get("smileys", []): # {smiley:id} -> a face (the art is the smileys.gfxId icon, not drawn yet)
		text = text.replace("{smiley:%d}" % int(id), "☺")
	var who := str(ev["from"])
	var head := who
	if str(ev["channel"]) == Chat.PRIVATE:
		head = "À %s" % str(ev["to"]) if who == me_name else "De %s" % who
	return "[color=#%s]%s : %s[/color]" % [channel_color(str(ev["channel"])).to_html(false), head, text]


## `/e <word>`: the emoticons.id whose name or shortcut is `word` (or a bare id), 0 if none.
static func emote_id(word: String) -> int:
	var w := word.strip_edges().to_lower().trim_prefix("/")
	if w.is_valid_int():
		return int(w) if not GameData.row("emoticons", int(w)).is_empty() else 0
	if w == "":
		return 0
	for k: Variant in GameData.table("emoticons"):
		var row: Dictionary = GameData.table("emoticons")[k]
		for key: String in ["shortcutId", "nameId"]:
			var text := DofusI18n.text(int(str(row.get(key, "0"))), "").to_lower().trim_prefix("/")
			if text == w:
				return int(row["id"])
	return 0


## The text of a message without its markers (the bubble over the head): "☺" for a smiley, "[name]" for an item.
static func plain_text(ev: Dictionary) -> String:
	var out := ""
	for piece: Dictionary in ChatLog.pieces(str(ev["text"]), ev.get("links", []), ev.get("smileys", [])):
		out += "☺" if piece.has("smiley") else ("[%s]" % item_name(int(piece["item"])) if piece.has("item") else str(piece["text"]))
	return out


static func item_name(id: int) -> String:
	return DofusI18n.text(int(GameData.item(id).get("nameId", 0)), "#%d" % id)


static func channel_color(channel: String) -> Color:
	match channel:
		Chat.GROUP:
			return UiStyle.GOLD
		Chat.TEAM:
			return UiStyle.GOOD
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
