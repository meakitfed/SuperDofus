## The loading screen (roadmap C.03), shown after the login on a server: the worlds the server
## offers (name, version, what is left to download), a progress bar while the missing files come
## in, then the world starts from the local cache. All the logic is WorldLoader (a model without
## Node); this screen runs its blocking calls in a thread and displays its fields.
##
## `world_ready(id)` is emitted when the cache of the chosen world is complete and active
## (ContentSource.use_world): the owner then starts the game. `back` = leave the server.
class_name WorldLoadScreen
extends Control

signal world_ready(world: String)
signal back

## captures and tests: slows the download down (chunks per poll, pause per poll in ms)
static var throttle_chunks := 64
static var throttle_delay_ms := 0

var loader: WorldLoader
var _title: Label
var _rows: VBoxContainer
var _status: Label
var _bar: ProgressBar
var _detail: Label
var _cancel: Button
var _retry: Button
var _back: Button
var _thread: Thread
## what "Réessayer" repeats: "" (the list) or a world id
var _last := ""
var _busy_label := ""
var _preferred := ""
## the exact sizes of the updates, measured behind the rows already shown (C.07)
var _measure: Thread


## `loader`: already pointed at the server's content API. `preferred`: world id to highlight.
func setup(p_loader: WorldLoader, preferred := "") -> void:
	loader = p_loader
	_preferred = preferred
	loader.client.chunks_per_poll = throttle_chunks
	loader.client.poll_delay_ms = throttle_delay_ms


func _ready() -> void:
	theme = ClientTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(CharacterSelectScreen.backdrop())
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 12)
	add_child(col)
	var title := UiStyle.label("Choisissez un monde", UiStyle.GOLD, 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	_title = UiStyle.label("", UiStyle.TEXT_MUTED, 15)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)
	_rows = VBoxContainer.new()
	_rows.custom_minimum_size = Vector2(560, 0)
	_rows.add_theme_constant_override("separation", 8)
	col.add_child(_centered(_rows))
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(560, 22)
	_bar.show_percentage = false
	_bar.add_theme_stylebox_override("background", UiStyle.bar_bg())
	_bar.add_theme_stylebox_override("fill", UiStyle.bar_fill(UiStyle.XP))
	_bar.visible = false
	col.add_child(_centered(_bar))
	_detail = UiStyle.label("", UiStyle.TEXT, 14)
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_detail)
	_status = UiStyle.label("", UiStyle.TEXT_MUTED, 16)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(560, 0)
	col.add_child(_centered(_status))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	_cancel = CharacterSelectScreen.gold_button("Annuler")
	_cancel.pressed.connect(func() -> void: loader.cancel())
	_retry = CharacterSelectScreen.gold_button("Réessayer")
	_retry.pressed.connect(func() -> void: _run_again())
	_back = CharacterSelectScreen.gold_button("Retour")
	_back.pressed.connect(func() -> void: back.emit())
	for b: Button in [_cancel, _retry, _back]:
		buttons.add_child(b)
	col.add_child(_centered(buttons))
	_title.text = "Les fichiers d'un monde sont téléchargés une fois, puis gardés sur cet ordinateur."
	_set_buttons(false)
	_refresh()


func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		loader.cancel()
		_thread.wait_to_finish()
	if _measure != null and _measure.is_started():
		_measure.wait_to_finish()


func _process(_delta: float) -> void:
	if _measure != null and not _measure.is_alive():
		_measure.wait_to_finish()
		_measure = null
		if _thread == null:
			_show_worlds() # the exact sizes
	if _thread == null:
		return
	if _thread.is_alive():
		_show_progress()
		return
	_thread.wait_to_finish()
	_thread = null
	_finished()


## Starts the download of `id` (or launches it when its cache is current): what a click on a row does.
func pick(id: String) -> void:
	if _thread != null or loader == null:
		return
	var e := loader.entry(id)
	if e.is_empty() or e["status"] == "unavailable" or _measure != null:
		return
	_last = id
	if e["status"] == "current":
		_launch(id)
		return
	_status.text = ""
	_busy_label = "install"
	_bar.visible = true
	_bar.value = 0
	_set_buttons(true)
	_thread = Thread.new()
	_thread.start(loader.install.bind(id))


func _refresh() -> void:
	_last = ""
	_busy_label = "list"
	_status.text = "Recherche des mondes du serveur…"
	_status.add_theme_color_override("font_color", UiStyle.TEXT_MUTED)
	_set_buttons(true, false)
	_thread = Thread.new()
	_thread.start(loader.refresh)


## "Vérifier": every installed file of the world is hashed again; a damaged one makes the world "partial".
func verify(id: String) -> void:
	if _thread != null or loader == null or _measure != null:
		return
	_last = ""
	_busy_label = "verify"
	_status.text = "Vérification des fichiers…"
	_status.add_theme_color_override("font_color", UiStyle.TEXT_MUTED)
	_set_buttons(true, false)
	_thread = Thread.new()
	_thread.start(loader.repair.bind(id))


func _run_again() -> void:
	if _last == "":
		_refresh()
	else:
		pick(_last)


func _finished() -> void:
	var op := _busy_label
	_busy_label = ""
	_bar.visible = loader.state == "downloading" or (op == "install" and loader.state == "cancelled")
	if op == "list":
		_show_worlds()
		if loader.state == "failed":
			_show_error(loader.error)
			_set_buttons(false)
		else:
			_status.text = "Aucun monde sur ce serveur." if loader.worlds.is_empty() else ""
			_set_buttons(false, false)
			if loader.worlds.any(func(e: Dictionary) -> bool: return not bool(e.get("measured", true))):
				_measure = Thread.new()
				_measure.start(loader.measure)
		return
	if op == "verify":
		_show_worlds()
		_status.text = ""
		_set_buttons(false, false)
		return
	_show_worlds()
	if loader.state == "done":
		_launch(_last)
		return
	_bar.visible = loader.state == "cancelled"
	_show_error(loader.error)
	_set_buttons(false)


func _launch(id: String) -> void:
	if loader.launch(id):
		_save_choice(id)
		world_ready.emit(id)
	else:
		_show_error("Le contenu de ce monde n'est pas complet.")
		_set_buttons(false)


func _show_progress() -> void:
	if _busy_label != "install":
		return
	_bar.max_value = maxi(1, loader.total_bytes)
	_bar.value = loader.done_bytes
	_detail.text = progress_text(loader)
	_status.text = "Téléchargement de « %s »…" % str(loader.entry(loader.world_id).get("name", loader.world_id))
	_status.add_theme_color_override("font_color", UiStyle.TEXT_MUTED)


## "Fichier 3 / 12 · 4,2 Mo / 14 Mo · 1,2 Mo/s" (no Node: testable)
static func progress_text(l: WorldLoader) -> String:
	var speed := l.speed()
	if l.phase == "plan":
		return "Comparaison avec les fichiers déjà installés…"
	var text := "Fichier %d / %d  ·  %s / %s" % [mini(l.done_files, l.total_files), l.total_files,
			WorldLoader.format_bytes(l.done_bytes), WorldLoader.format_bytes(l.total_bytes)]
	if speed > 0.0:
		text += "  ·  %s/s" % WorldLoader.format_bytes(int(speed))
		var left := l.eta()
		if left > 0:
			text += "  ·  %s restantes" % format_duration(left)
	return text


## "45 s", "3 min 20 s", "1 h 05 min"
static func format_duration(seconds: int) -> String:
	if seconds >= 3600:
		return "%d h %02d min" % [seconds / 3600, (seconds % 3600) / 60]
	if seconds >= 60:
		return "%d min %02d s" % [seconds / 60, seconds % 60]
	return "%d s" % seconds


## The label of a world's action button.
static func action_text(e: Dictionary) -> String:
	var size := ("" if bool(e.get("measured", true)) else "≤ ") + WorldLoader.format_bytes(int(e["todo_bytes"]))
	match str(e["status"]):
		"current":
			return "Jouer"
		"partial":
			return "Reprendre (%s)" % size
		"update":
			return "Mettre à jour (%s)" % size
		"unavailable":
			return "Indisponible"
	return "Télécharger (%s)" % size


## "À jour", "Pas encore téléchargé"…
static func status_text(e: Dictionary) -> String:
	match str(e["status"]):
		"current":
			return "À jour · gardé sur cet ordinateur"
		"partial":
			return "Téléchargement interrompu"
		"update":
			return "Nouvelle version disponible"
		"unavailable":
			return "Indisponible sur le serveur : " + str(e.get("note", ""))
	return "Pas encore téléchargé"


func _show_worlds() -> void:
	for c in _rows.get_children():
		c.queue_free()
	for e in loader.worlds:
		_rows.add_child(_row(e))


func _row(e: Dictionary) -> Control:
	var current: bool = e["status"] == "current"
	var panel := PanelContainer.new()
	var preferred: bool = str(e["id"]) == _preferred
	panel.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.BG, UiStyle.GOLD if preferred else UiStyle.BORDER, 6, 12))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	panel.add_child(line)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(text)
	text.add_child(UiStyle.label(str(e["name"]), UiStyle.TEXT, 22))
	var players := int(e.get("players", 0))
	var info := "%s · %d fichiers · version %s · %s" % [WorldLoader.format_bytes(int(e["size"])), int(e["files"]),
			str(e["version"]).substr(0, 8), "aucun joueur" if players == 0 else "%d joueur%s" % [players, "s" if players > 1 else ""]]
	text.add_child(UiStyle.label(info, UiStyle.TEXT_MUTED, 13))
	text.add_child(UiStyle.label(status_text(e), UiStyle.GOOD if current else UiStyle.ENERGY, 14))
	var b := CharacterSelectScreen.gold_button(action_text(e))
	b.custom_minimum_size = Vector2(230, 46)
	b.disabled = _thread != null or str(e["status"]) == "unavailable"
	b.pressed.connect(func() -> void: pick(str(e["id"])))
	if current: # the files are trusted as written; checking them all is on demand
		var check := CharacterSelectScreen.gold_button("Vérifier")
		check.custom_minimum_size = Vector2(110, 46)
		check.disabled = _thread != null
		check.pressed.connect(func() -> void: verify(str(e["id"])))
		line.add_child(check)
	line.add_child(b)
	return panel


func _set_buttons(busy: bool, can_cancel := true) -> void:
	_cancel.visible = busy and can_cancel
	_retry.visible = not busy and _status.text != "" and loader.state in ["failed", "cancelled"]
	_back.visible = not busy
	for row in _rows.get_children():
		for b in row.find_children("*", "Button", true, false):
			(b as Button).disabled = busy


func _show_error(text: String) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", UiStyle.BAD)
	_detail.text = ""
	_retry.visible = true


func _save_choice(id: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(LaunchScreen.CONFIG)
	cfg.set_value("server", "world", id)
	cfg.save(LaunchScreen.CONFIG) # best effort


func _centered(c: Control) -> CenterContainer:
	var box := CenterContainer.new()
	box.add_child(c)
	return box
