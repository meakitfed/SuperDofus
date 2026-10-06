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
var _legacy_box: VBoxContainer
var _legacy_label: Label
var _move: CheckBox
var _ok: Button
var _legacy: Array[Dictionary] = []


func _ready() -> void:
	theme = ClientTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(CharacterSelectScreen.backdrop())
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 12)
	add_child(col)
	var title := UiStyle.label("Dossier des mondes", UiStyle.GOLD, 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var help := UiStyle.label("Les mondes téléchargés (images, données) sont stockés ici.\nCela peut peser plusieurs Go : choisissez un disque avec de la place.", UiStyle.TEXT_MUTED, 15)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(help)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_path = LineEdit.new()
	_path.custom_minimum_size = Vector2(430, 36)
	_path.placeholder_text = "D:/Jeux/SuperDofus"
	_path.text = current
	_path.text_changed.connect(func(_t: String) -> void: _refresh())
	_path.text_submitted.connect(func(_t: String) -> void: _confirm())
	row.add_child(_path)
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		var browse := Button.new()
		browse.text = "Parcourir…"
		browse.pressed.connect(_browse)
		row.add_child(browse)
	col.add_child(_centered(row))
	_info = UiStyle.label("", UiStyle.TEXT_MUTED, 15)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_info)
	_legacy_box = VBoxContainer.new()
	_legacy_label = UiStyle.label("", UiStyle.TEXT, 15)
	_legacy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_legacy_box.add_child(_legacy_label)
	_move = CheckBox.new()
	_move.text = "Déplacer ces mondes vers le nouveau dossier (sinon ils restent où ils sont)"
	_move.button_pressed = true
	_legacy_box.add_child(_centered(_move))
	col.add_child(_legacy_box)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	_ok = CharacterSelectScreen.gold_button("Valider")
	_ok.pressed.connect(_confirm)
	buttons.add_child(_ok)
	if can_cancel:
		var cancel := Button.new()
		cancel.text = "Annuler"
		cancel.pressed.connect(func() -> void: cancelled.emit())
		buttons.add_child(cancel)
	col.add_child(_centered(buttons))
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
		_info.text = "%s  ·  %s" % [v["path"], ContentFolder.free_text(int(v["free"]))]
		_info.add_theme_color_override("font_color", UiStyle.TEXT_MUTED)
	else:
		_info.text = str(v["error"])
		_info.add_theme_color_override("font_color", UiStyle.BAD)
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
			_info.text = str(r["error"])
			_info.add_theme_color_override("font_color", UiStyle.BAD)
			return
	chosen.emit(str(v["path"]))


func _centered(c: Control) -> CenterContainer:
	var box := CenterContainer.new()
	box.add_child(c)
	return box
