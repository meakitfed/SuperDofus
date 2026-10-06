## A Dofus-style window: title bar (drag to move), close button, content in
## `body`. Escape closes the top-most open window. Each window has an id and
## remembers where the player left it (user://ui_layout.json, client-only
## preference, never game state).
##   var w := UiWindow.new(); w.setup("inventory", "Inventaire"); layer.add_child(w)
##   w.body.add_child(content); w.toggle()
class_name UiWindow
extends PanelContainer

signal closed

const LAYOUT_FILE := "user://ui_layout.json"

static var _open: Array[UiWindow] = [] # most recently raised last
static var _layout := {}
static var _layout_loaded := false

var window_id := ""
## where it opens the first time, as a fraction of the free screen space
## (0.5, 0.5 = centred; Dofus puts characteristics left, inventory right)
var default_anchor := Vector2(0.5, 0.5)
var body: VBoxContainer
var title_label: Label
var _header: PanelContainer
var _dragging := false
var _drag_offset := Vector2.ZERO
var _placed := false


func setup(id: String, title: String, icon_path := "") -> void:
	window_id = id
	theme = ClientTheme.get_theme()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.BG, UiStyle.BORDER, 6, 0))
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	_header = PanelContainer.new()
	_header.add_theme_stylebox_override("panel", UiStyle.header())
	_header.mouse_filter = Control.MOUSE_FILTER_STOP
	_header.gui_input.connect(_on_header_input)
	_header.mouse_default_cursor_shape = Control.CURSOR_MOVE
	root.add_child(_header)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	_header.add_child(bar)
	if icon_path != "":
		bar.add_child(UiStyle.icon(icon_path, 22, Color.WHITE))
	title_label = UiStyle.label(title, UiStyle.GOLD, 17)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(title_label)
	var close := Button.new()
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = Shortcuts.label("close")
	close.custom_minimum_size = Vector2(28, 28)
	close.text = "×" # the Dofus cross textures are dark glyphs meant for light buttons
	close.add_theme_font_size_override("font_size", 24)
	close.add_theme_color_override("font_color", UiStyle.TEXT_MUTED)
	close.add_theme_color_override("font_hover_color", Color.WHITE)
	close.pressed.connect(close_window)
	bar.add_child(close)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	root.add_child(margin)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	margin.add_child(body)
	# fit the content when it shrinks too (a Container only ever grows); wrapped
	# labels only know their height after a layout pass
	minimum_size_changed.connect(_fit, CONNECT_DEFERRED)


func open() -> void:
	if not visible:
		visible = true
		_open.append(self)
	raise()
	if not _placed:
		_placed = true
		_restore_position.call_deferred()


func close_window() -> void:
	if not visible:
		return
	visible = false
	_open.erase(self)
	closed.emit()


func toggle() -> void:
	if visible:
		close_window()
	else:
		open()


func raise() -> void:
	_open.erase(self)
	_open.append(self)
	move_to_front()


## Escape: closes the top-most open window (true if one was closed).
static func close_top() -> bool:
	for i in range(_open.size() - 1, -1, -1):
		var w := _open[i]
		if is_instance_valid(w) and w.visible:
			w.close_window()
			return true
		_open.remove_at(i)
	return false


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		raise()


func _on_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_drag_offset = get_global_mouse_position() - global_position
		raise()
		if not _dragging:
			_save_position()
	elif event is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() - _drag_offset
		_clamp()


## Size to the content; a window the player never moved stays at its default place.
func _fit() -> void:
	reset_size()
	if _placed and _layout_get(window_id) == null:
		position = ((get_viewport_rect().size - size) * default_anchor).floor()
		_clamp()


func _clamp() -> void:
	var vp := get_viewport_rect().size
	position = position.clamp(Vector2(-size.x + 80, 0), vp - Vector2(80, 40))


func _restore_position() -> void:
	reset_size()
	var saved: Variant = _layout_get(window_id)
	if saved is Array and (saved as Array).size() == 2:
		position = Vector2(float(saved[0]), float(saved[1]))
	else:
		position = ((get_viewport_rect().size - size) * default_anchor).floor()
	_clamp()


func _save_position() -> void:
	if window_id == "":
		return
	_layout[window_id] = [position.x, position.y]
	var f := FileAccess.open(LAYOUT_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_layout))


static func _layout_get(id: String) -> Variant:
	if not _layout_loaded:
		_layout_loaded = true
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_FILE)) if FileAccess.file_exists(LAYOUT_FILE) else null
		_layout = data if data is Dictionary else {}
	return _layout.get(id)


## Tools and tests: forget saved positions (deterministic screenshots).
static func reset_layout() -> void:
	_layout = {}
	_layout_loaded = true
