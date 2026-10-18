## The "where do I store the worlds?" panel (roadmap C.04), opened on the first launch and from the
## launch screen ("Changer…"). The logic is ContentFolder; this only shows the path, the free space,
## the verdict, and offers the old cache (user://worlds) when it holds worlds: move it to the new
## folder, or keep using it where it is.
## `chosen(path)` is emitted once the folder is valid (and the old worlds moved if asked); `cancelled`
## otherwise. The owner remembers and applies the folder.
class_name ContentFolderScreen
extends Control

signal chosen(path: String)
signal cancelled

var current := ""
## false on the first launch: nothing to go back to, "Annuler" is hidden
var can_cancel := true

var _path: LineEdit
var _info: Label
var _notice: UiMenu.Notice
var _legacy_box: VBoxContainer
var _legacy_label: Label
var _move: CheckBox
var _ok: Button
var _legacy: Array[Dictionary] = []


func _ready() -> void:
	theme = ClientTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UiMenu.backdrop())
	var col := UiMenu.card(self, 560)
	UiMenu.header(col, "Dossier des mondes", "Les mondes téléchargés (images, données) sont stockés ici. Cela peut peser plusieurs Go : choisis un disque avec de la place.")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_path = LineEdit.new()
	_path.custom_minimum_size = Vector2(0, UiMenu.FIELD_H)
	_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path.placeholder_text = "D:/Jeux/SuperDofus"
	_path.text = current
	_path.text_changed.connect(func(_t: String) -> void: _refresh())
	_path.text_submitted.connect(func(_t: String) -> void: _confirm())
	row.add_child(_path)
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		var browse := UiMenu.secondary("Parcourir…", 110)
		browse.custom_minimum_size.y = UiMenu.FIELD_H
		browse.pressed.connect(_browse)
		row.add_child(browse)
	col.add_child(row)
	_notice = UiMenu.notice()
	_info = _notice.label
	col.add_child(_notice)
	_legacy_box = VBoxContainer.new()
	_legacy_box.add_theme_constant_override("separation", 6)
	_legacy_label = UiStyle.label("", UiStyle.TEXT, UiStyle.FS_BODY)
	_legacy_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_legacy_box.add_child(_legacy_label)
	_move = CheckBox.new()
	_move.text = "Déplacer ces mondes vers le nouveau dossier (sinon ils restent où ils sont)"
	_move.button_pressed = true
	_legacy_box.add_child(_move)
	col.add_child(_legacy_box)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 12)
	if can_cancel:
		var cancel := UiMenu.secondary("Annuler", 120)
		cancel.pressed.connect(func() -> void: cancelled.emit())
		buttons.add_child(cancel)
	_ok = UiMenu.primary("Valider", 160)
	_ok.pressed.connect(_confirm)
	buttons.add_child(_ok)
	col.add_child(buttons)
	_refresh()


func _browse() -> void:
	var start := ContentFolder.normalize(_path.text)
	DisplayServer.file_dialog_show("Dossier des mondes", start, "", false,
			DisplayServer.FILE_DIALOG_MODE_OPEN_DIR, PackedStringArray(),
			func(status: bool, paths: PackedStringArray, _filter: int) -> void:
				if status and not paths.is_empty():
					_path.text = paths[0]
					_refresh())


func _refresh() -> void:
	var v := ContentFolder.validate(_path.text)
	_ok.disabled = not v["ok"]
	if v["ok"]:
		_notice.say("%s  ·  %s" % [v["path"], ContentFolder.free_text(int(v["free"]))], "ok")
	else:
		_notice.say(str(v["error"]), "error")
	# the old cache is offered only when it is somewhere else than the chosen folder
	_legacy = ContentFolder.legacy_worlds(ContentFolder.legacy_dir(), str(v["path"]))
	_legacy_box.visible = not _legacy.is_empty()
	if not _legacy.is_empty():
		var total := 0
		var names: PackedStringArray = []
		for w in _legacy:
			total += int(w["bytes"])
			names.append(str(w["id"]))
		_legacy_label.text = "Des mondes sont déjà téléchargés dans l'ancien dossier (%s, %s)." % [
				", ".join(names), WorldLoader.format_bytes(total)]


func _confirm() -> void:
	var v := ContentFolder.validate(_path.text)
	if not v["ok"]:
		return
	if _legacy_box.visible and _move.button_pressed:
		var ids: Array = []
		for w in _legacy:
			ids.append(w["id"])
		var r := ContentFolder.migrate(ContentFolder.legacy_dir(), str(v["path"]), ids)
		if not r["ok"]:
			_notice.say(str(r["error"]), "error")
			return
	chosen.emit(str(v["path"]))
