## The dungeon widget (P4.01), top centre: on an entrance map, the dungeons offered (minimum level,
## "Entrer"); inside a dungeon, its name, "Salle 2/5" / "Salle du boss" and "Quitter le donjon".
## It shows what DungeonModel keeps; every action goes back as a ProtocolDungeon message.
class_name DungeonIndicator
extends PanelContainer

var backend: GameBackend
var model := DungeonModel.new()
var _box: VBoxContainer


func setup(p_backend: GameBackend) -> void:
	backend = p_backend
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UiStyle.panel(Color(UiStyle.BG, 0.85), UiStyle.BORDER, 6, 8))
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 4)
	add_child(_box)
	refresh()


## A map_enter: the entrances of the map.
func on_map(map: Dictionary) -> void:
	model.on_map(map)
	refresh()


## dungeon_room / dungeon_end.
func on_event(t: String, ev: Dictionary, toast: Toast) -> void:
	var text := model.on_event(t, ev)
	if text != "" and toast != null:
		toast.show_text(text, UiStyle.GOOD if model.last_reason == ProtocolDungeon.REASON_WON else UiStyle.TEXT)
	refresh()


func enter(id: int) -> void:
	backend.send(ProtocolDungeon.enter(id))


func leave() -> void:
	backend.send(ProtocolDungeon.leave())


## Hidden with the rest of the interface (HudToggles).
var user_hidden := false:
	set(v):
		user_hidden = v
		if model != null:
			refresh()


func refresh() -> void:
	for c: Node in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	visible = (model.inside or not model.entrances.is_empty()) and not user_hidden
	if model.inside:
		_box.add_child(UiStyle.label(model.dungeon_name(), UiStyle.GOLD, 13))
		_box.add_child(UiStyle.label(model.room_text(), UiStyle.BAD if model.boss else UiStyle.TEXT, 14))
		if model.room_name != "" and model.room_name != model.dungeon_name():
			_box.add_child(UiStyle.label(model.room_name, UiStyle.TEXT_MUTED, 11))
		var quit := Button.new()
		quit.text = "Quitter le donjon"
		quit.pressed.connect(leave)
		_box.add_child(quit)
	else:
		for d: Dictionary in model.entrances:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var col := VBoxContainer.new()
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			col.add_child(UiStyle.label(str(d["name"]), UiStyle.GOLD, 13))
			col.add_child(UiStyle.label("Niveau %d minimum" % int(d["min_level"]), UiStyle.TEXT_MUTED, 11))
			row.add_child(col)
			var go := Button.new()
			go.text = "Entrer"
			var id := int(d["id"])
			go.pressed.connect(func() -> void: enter(id))
			row.add_child(go)
			_box.add_child(row)
	reset_size.call_deferred()
