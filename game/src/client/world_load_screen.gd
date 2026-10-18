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
var _rows: VBoxContainer
var _status: Label
var _notice: UiMenu.Notice
var _bar: UiBar
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
	add_child(UiMenu.backdrop())
	var col := UiMenu.card(self, 700)
	UiMenu.header(col, "Choisissez un monde", "Les fichiers d'un monde sont téléchargés une fois, puis gardés sur cet ordinateur.")
	var trail := UiMenu.steps(LaunchScreen.STEPS, 2)
	col.add_child(trail)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	col.add_child(_rows)
	_bar = UiBar.new(UiStyle.XP, 16)
	_bar.visible = false
	col.add_child(_bar)
	_detail = UiStyle.label("", UiStyle.TEXT, UiStyle.FS_BODY)
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_detail)
	_notice = UiMenu.notice()
	_status = _notice.label
	col.add_child(_notice)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	_cancel = UiMenu.secondary("Annuler le téléchargement", 200)
	_cancel.pressed.connect(func() -> void: loader.cancel())
	_retry = UiMenu.primary("Réessayer", 160)
	_retry.pressed.connect(func() -> void: _run_again())
	_back = UiMenu.secondary("Retour", 120)
	_back.pressed.connect(func() -> void: back.emit())
	for b: Button in [_cancel, _retry, _back]:
		buttons.add_child(b)
	col.add_child(buttons)
	_set_buttons(false)
	_refresh()


## The status block: `kind` "info" or "error"; "" hides it.
func _say(text: String, kind := "info") -> void:
	_notice.say(text, kind)


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
	_say("")
	_busy_label = "install"
	_bar.visible = true
	_bar.set_values(0, 1)
	_set_buttons(true)
	for row in _rows.get_children(): # only the world being installed stays: the progress has the room
		row.visible = str(row.get_meta("world", "")) == id
	_thread = Thread.new()
	_thread.start(loader.install.bind(id))


func _refresh() -> void:
	_last = ""
	_busy_label = "list"
	_say("Recherche des mondes du serveur…")
	_set_buttons(true, false)
	_thread = Thread.new()
	_thread.start(loader.refresh)


## "Vérifier": every installed file of the world is hashed again; a damaged one makes the world "partial".
func verify(id: String) -> void:
	if _thread != null or loader == null or _measure != null:
		return
	_last = ""
	_busy_label = "verify"
	_say("Vérification des fichiers…")
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
			_say("Aucun monde sur ce serveur : demande à la personne qui l'héberge de publier le contenu." if loader.worlds.is_empty() else "")
			_set_buttons(false, false)
			if loader.worlds.any(func(e: Dictionary) -> bool: return not bool(e.get("measured", true))):
				_measure = Thread.new()
				_measure.start(loader.measure)
		return
	if op == "verify":
		_show_worlds()
		_say("")
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
	var pct := int(100.0 * loader.done_bytes / maxi(1, loader.total_bytes))
	_bar.set_values(loader.done_bytes, maxi(1, loader.total_bytes), "%d %%" % pct)
	_detail.text = progress_text(loader)


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
	var style := UiStyle.panel(UiStyle.ROW_SELECTED if preferred else UiStyle.BG_RAISED, UiStyle.GOLD if preferred else UiStyle.BORDER, UiStyle.RADIUS, 14)
	style.shadow_size = 0
	panel.add_theme_stylebox_override("panel", style)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	panel.add_child(line)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 3)
	line.add_child(text)
	text.add_child(UiStyle.title(str(e["name"]), 22))
	var players := int(e.get("players", 0))
	var info := "%s · %d fichiers · version %s · %s" % [WorldLoader.format_bytes(int(e["size"])), int(e["files"]),
			str(e["version"]).substr(0, 8), "aucun joueur" if players == 0 else "%d joueur%s" % [players, "s" if players > 1 else ""]]
	var info_label := UiStyle.muted(info)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(info_label)
	text.add_child(UiStyle.label(("✓ " if current else "") + status_text(e), UiStyle.GOOD if current else UiStyle.ENERGY, UiStyle.FS_BODY))
	panel.set_meta("world", str(e["id"]))
	var b := UiMenu.primary(action_text(e), 190) if preferred or not current else UiMenu.secondary(action_text(e), 190)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.disabled = _thread != null or str(e["status"]) == "unavailable"
	b.pressed.connect(func() -> void: pick(str(e["id"])))
	if current: # the files are trusted as written; checking them all is on demand
		var check := UiMenu.secondary("Vérifier", 90)
		check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		check.tooltip_text = "Recalcule l'empreinte de chaque fichier installé"
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
	_say(text, "error")
	_detail.text = ""
	_retry.visible = true


func _save_choice(id: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(LaunchScreen.CONFIG)
	cfg.set_value("server", "world", id)
	cfg.save(LaunchScreen.CONFIG) # best effort
