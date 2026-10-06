## Dev tool: type/paste any look string (or pick a breed / monster / mount), browse every
## animation and direction, recolour, scrub frames and export PNGs.
extends Control

const PRESETS := {
	"Iop (sample)": "{1|120,2195,4072,4941,3963,5716|1=13418918,2=4077879,3=16022817,4=14386944,5=4275500,6=9904435|56}",
	"Pet": "{1|120,2195,3042,3069,3963|1=16777215,2=15335424,3=15335424,4=16777215,5=0,6=15335424|56|1@0={1420|||90}}",
	"Mount": "{2013|||100|2@0={2|120,2195,3042,3069,3963|1=16777215,2=15335424,3=15335424,4=16777215,5=0,6=15335424|56}}",
	"Aura": "{1|120,2195,3042,3069,3963|1=16777215,2=15335424,3=15335424,4=16777215,5=0,6=15335424|56|4@0={9703|||100},6@0={9702|||100}}",
	"Comte Harebourg": "{2069|||150}",
	"Monster 4907": "{4907|||130}",
}
const DIR_LABELS := ["→ 0", "↘ 1", "↓ 2", "↙ 3", "← 4", "↖ 5", "↑ 6", "↗ 7"]
const PALETTE_SLOTS := 10

var _sprite: DofusSprite
var _stage: Node2D
var _look_edit: LineEdit
var _anim_list: ItemList
var _dir_buttons: Array[Button] = []
var _frame_slider: HSlider
var _info: Label
var _play_button: Button
var _color_buttons: Array[ColorPickerButton] = []
var _zoom := 2.0
var _show_bounds := false
var _updating := false


func _ready() -> void:
	_build_ui()
	_sprite = DofusSprite.new()
	_stage.add_child(_sprite)
	_sprite.look_changed.connect(_on_look_changed)
	_sprite.label_reached.connect(func(label: String, anim: String) -> void: print("label '%s' in %s" % [label, anim]))
	var start: String = PRESETS.values()[0]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("{") or arg.begins_with("["):
			start = arg
	_apply_look(start)


func _process(_delta: float) -> void:
	_stage.position = Vector2(get_viewport_rect().size.x * 0.62, get_viewport_rect().size.y * 0.72)
	_stage.scale = Vector2(_zoom, _zoom)
	if _sprite.get_frame_count() > 0 and not _frame_slider.has_focus():
		_updating = true
		_frame_slider.max_value = _sprite.get_frame_count() - 1
		_frame_slider.value = _sprite.frame
		_updating = false
	_info.text = "%s  %s\nframe %d/%d  %.0f fps\ncache %s" % [
		_sprite.current_animation, "(mirrored)" if _sprite.flipped else "",
		_sprite.frame + 1, _sprite.get_frame_count(), _sprite.get_frame_rate(), DofusContent.stats()]
	_stage.queue_redraw()


# ── actions ────────────────────────────────────────────────────────────────────

func _apply_look(look_string: String) -> void:
	_look_edit.text = look_string
	var t0 := Time.get_ticks_msec()
	_sprite.look_string = look_string
	print("look loaded in %d ms" % (Time.get_ticks_msec() - t0))


func _on_look_changed() -> void:
	_refresh_anim_list()
	_refresh_colors()


func _refresh_anim_list() -> void:
	_anim_list.clear()
	var dirs := _sprite.get_animation_directions()
	var bases := dirs.keys()
	bases.sort()
	for base: String in bases:
		var i := _anim_list.add_item("%s  %s" % [base, dirs[base]])
		_anim_list.set_item_metadata(i, base)
	# bases without a direction suffix (props, FX)
	for anim_name in _sprite.get_animation_names():
		if DofusAnimNames.split(anim_name)[1] < 0:
			var i := _anim_list.add_item(anim_name)
			_anim_list.set_item_metadata(i, anim_name)
	_refresh_dirs()


func _refresh_dirs() -> void:
	var base := DofusAnimNames.split(_sprite.current_animation)[0] as String
	var available: Array = _sprite.get_animation_directions().get(base, [])
	for d in 8:
		_dir_buttons[d].disabled = not available.has(d)
		_dir_buttons[d].button_pressed = d == _sprite.direction


func _refresh_colors() -> void:
	_updating = true
	for i in _color_buttons.size():
		_color_buttons[i].color = _sprite.look.get_color(i + 1) if _sprite.look != null else Color.WHITE
	_updating = false


func _export_png() -> void:
	var img := get_viewport().get_texture().get_image()
	var dir := "user://exports"
	DirAccess.make_dir_recursive_absolute(dir)
	var path := "%s/%s_f%d.png" % [dir, _sprite.current_animation, _sprite.frame]
	img.save_png(path)
	print("exported ", ProjectSettings.globalize_path(path))


func _load_catalog(kind: String, id: int) -> void:
	var table := {"monster": "monstersdataroot", "mount": "mountsdataroot"}[kind] as String
	var data: Variant = DofusContent.get_provider().read_json("Content/Data/%s.json" % table)
	if data is Dictionary and (data["objectsById"] as Dictionary).has(str(id)):
		_apply_look(str(data["objectsById"][str(id)]["look"]))
	else:
		push_warning("%s %d not found (extract data with --data)" % [kind, id])


func _load_breed(breed: int, female: bool) -> void:
	var gd := DofusContent.get_game_data()
	var b: Dictionary = gd.breeds.get(breed, {})
	if b.is_empty():
		return
	var look := DofusLook.parse(b["femaleLook" if female else "maleLook"])
	# add the first head of this breed/gender so the character is complete
	var heads: Variant = DofusContent.get_provider().read_json("Content/Data/headsdataroot.json")
	if heads is Dictionary and look.skins.size() == 1:
		for h: Dictionary in (heads["objectsById"] as Dictionary).values():
			if int(h["breed"]) == breed and int(h["gender"]) == int(female):
				look.skins.append(str(h["skins"]).to_int())
				break
	_apply_look(str(look))


# ── UI ─────────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.18, 0.22)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_stage = Node2D.new()
	_stage.draw.connect(_draw_stage)
	add_child(_stage)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(390, 0)
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	box.add_child(_label("Look string"))
	_look_edit = LineEdit.new()
	_look_edit.text_submitted.connect(_apply_look)
	box.add_child(_look_edit)

	var presets := OptionButton.new()
	presets.add_item("— presets —")
	for name: String in PRESETS:
		presets.add_item(name)
	presets.item_selected.connect(func(i: int) -> void:
		if i > 0:
			_apply_look(PRESETS.values()[i - 1]))
	box.add_child(presets)

	var breed_row := HBoxContainer.new()
	var breed_spin := _spin(1, 20, 8)
	var female := CheckBox.new()
	female.text = "F"
	var breed_btn := Button.new()
	breed_btn.text = "Breed"
	breed_btn.pressed.connect(func() -> void: _load_breed(int(breed_spin.value), female.button_pressed))
	breed_row.add_child(breed_btn)
	breed_row.add_child(breed_spin)
	breed_row.add_child(female)
	box.add_child(breed_row)

	var cat_row := HBoxContainer.new()
	var cat_spin := _spin(1, 99999, 31)
	for kind in ["monster", "mount"]:
		var b := Button.new()
		b.text = kind.capitalize()
		b.pressed.connect(func() -> void: _load_catalog(kind, int(cat_spin.value)))
		cat_row.add_child(b)
	cat_row.add_child(cat_spin)
	box.add_child(cat_row)

	var skin_row := HBoxContainer.new()
	var skin_spin := _spin(1, 99999, 709)
	var add_skin := Button.new()
	add_skin.text = "+ skin"
	add_skin.pressed.connect(func() -> void:
		var l := _sprite.look.duplicate_look()
		l.skins.append(int(skin_spin.value))
		_apply_look(str(l)))
	var pop_skin := Button.new()
	pop_skin.text = "- last"
	pop_skin.pressed.connect(func() -> void:
		var l := _sprite.look.duplicate_look()
		if l.skins.size() > 2:
			l.skins.remove_at(l.skins.size() - 1)
		_apply_look(str(l)))
	skin_row.add_child(add_skin)
	skin_row.add_child(skin_spin)
	skin_row.add_child(pop_skin)
	box.add_child(skin_row)

	box.add_child(_label("Animations (base  [directions])"))
	_anim_list = ItemList.new()
	_anim_list.custom_minimum_size = Vector2(0, 220)
	_anim_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_anim_list.item_selected.connect(func(i: int) -> void:
		_sprite.play_animation(_anim_list.get_item_metadata(i), _sprite.direction, _sprite.looping)
		_refresh_dirs())
	box.add_child(_anim_list)

	var dirs := GridContainer.new()
	dirs.columns = 4
	for d in 8:
		var b := Button.new()
		b.text = DIR_LABELS[d]
		b.toggle_mode = true
		b.pressed.connect(func() -> void:
			_sprite.direction = d
			_refresh_dirs())
		dirs.add_child(b)
		_dir_buttons.append(b)
	box.add_child(dirs)

	var play_row := HBoxContainer.new()
	_play_button = Button.new()
	_play_button.text = "Pause"
	_play_button.pressed.connect(func() -> void:
		_sprite.playing = not _sprite.playing
		_play_button.text = "Pause" if _sprite.playing else "Play")
	play_row.add_child(_play_button)
	var loop := CheckBox.new()
	loop.text = "Loop"
	loop.button_pressed = true
	loop.toggled.connect(func(on: bool) -> void: _sprite.play_animation(_sprite.animation, _sprite.direction, on))
	play_row.add_child(loop)
	var bounds := CheckBox.new()
	bounds.text = "Bounds"
	bounds.toggled.connect(func(on: bool) -> void: _show_bounds = on)
	play_row.add_child(bounds)
	var export := Button.new()
	export.text = "PNG"
	export.pressed.connect(_export_png)
	play_row.add_child(export)
	box.add_child(play_row)

	_frame_slider = HSlider.new()
	_frame_slider.step = 1
	_frame_slider.value_changed.connect(func(v: float) -> void:
		if not _updating:
			_sprite.playing = false
			_play_button.text = "Play"
			_sprite.seek(int(v)))
	box.add_child(_frame_slider)

	var speed := HSlider.new()
	speed.min_value = 0.1
	speed.max_value = 3.0
	speed.step = 0.1
	speed.value = 1.0
	speed.value_changed.connect(func(v: float) -> void: _sprite.speed_scale = v)
	box.add_child(_label("Speed / zoom"))
	box.add_child(speed)
	var zoom := HSlider.new()
	zoom.min_value = 0.5
	zoom.max_value = 6.0
	zoom.step = 0.1
	zoom.value = _zoom
	zoom.value_changed.connect(func(v: float) -> void: _zoom = v)
	box.add_child(zoom)

	box.add_child(_label("Colours"))
	var colors := GridContainer.new()
	colors.columns = 5
	for i in PALETTE_SLOTS:
		var c := ColorPickerButton.new()
		c.custom_minimum_size = Vector2(56, 28)
		c.tooltip_text = "slot %d" % (i + 1)
		c.color_changed.connect(func(col: Color) -> void:
			if not _updating:
				_sprite.set_color(i + 1, col)
				_look_edit.text = _sprite.get_look_string())
		colors.add_child(c)
		_color_buttons.append(c)
	box.add_child(colors)

	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_info)


func _draw_stage() -> void:
	_stage.draw_line(Vector2(-40, 0), Vector2(40, 0), Color(1, 1, 1, 0.25), 1.0 / _zoom)
	_stage.draw_line(Vector2(0, -8), Vector2(0, 8), Color(1, 1, 1, 0.25), 1.0 / _zoom)
	if _show_bounds and _sprite != null:
		_stage.draw_rect(_sprite.get_frame_rect(), Color(1, 0.8, 0.2, 0.8), false, 1.0 / _zoom)


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _spin(lo: int, hi: int, value: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = value
	return s
