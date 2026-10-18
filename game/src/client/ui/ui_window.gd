## A Dofus-style window: title bar (drag to move), close button, content in
## `body`. Escape closes the top-most open window. Each window has an id and
## remembers where the player left it and how big he made it (user://ui_layout.json,
## client-only preference, never game state; the sim never sees it).
##   var w := UiWindow.new(); w.setup("inventory", "Inventaire"); layer.add_child(w)
##   w.body.add_child(content); w.toggle()
## Lot U.02 (docs/ui/ADAPTATIF.md 2.6): the window always stays inside the safe area of the screen
## (UiScale.safe_rect), whatever the window size or the interface scale; a content taller or wider
## than the screen scrolls; the position is kept as a share of the free space, so it follows a
## change of screen shape; it can be resized by its corner; opening and closing fade a little.
class_name UiWindow
extends PanelContainer

signal closed

const LAYOUT_FILE := "user://ui_layout.json"
const LAYOUT_VERSION := 2
const GRIP := 14.0
const MIN_BODY := 60.0
const OPEN_MS := 0.12
const CLOSE_MS := 0.08
const POP := 0.96

static var _open: Array[UiWindow] = [] # most recently raised last
static var _all: Array[UiWindow] = []
static var _layout := {"v": LAYOUT_VERSION, "windows": {}}
static var _layout_loaded := false
## opening / closing animation (off in headless runs, where tests read `visible` at once)
static var animate := DisplayServer.get_name() != "headless"

var window_id := ""
## where it opens the first time, as a fraction of the free screen space
## (0.5, 0.5 = centred; Dofus puts characteristics left, inventory right)
var default_anchor := Vector2(0.5, 0.5)
## the player may drag the bottom-right corner (not for small dialogs, which have no id)
var resizable := true
var body: VBoxContainer
var title_label: Label
var _header: PanelContainer
var _scroll: ScrollContainer
var _content: MarginContainer
var _grip: Label
var _dragging := false
var _resizing := false
var _drag_offset := Vector2.ZERO
var _resize_start := Vector2.ZERO
var _resize_from := Vector2.ZERO
var _shown := false
var _placed := false
## where the player left it, as a share of the free space; (-1, -1) = default_anchor
var _frac := Vector2(-1.0, -1.0)
## the size the player gave the content area (0 = fit the content)
var _user_size := Vector2.ZERO
var _tween: Tween


func setup(id: String, title: String, icon_path := "") -> void:
	window_id = id
	resizable = id != ""
	theme = ClientTheme.get_theme()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.BG, UiStyle.BORDER_LIGHT, UiStyle.RADIUS, 0))
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
	title_label = UiStyle.title(title)
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
	close.add_theme_color_override("font_hover_color", UiStyle.BAD)
	close.add_theme_color_override("font_pressed_color", UiStyle.BAD)
	close.pressed.connect(close_window)
	bar.add_child(close)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	root.add_child(_scroll)
	_content = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		_content.add_theme_constant_override("margin_" + side, 14)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	_content.add_child(body)
	_grip = Label.new()
	_grip.text = "◢"
	_grip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_grip.add_theme_font_size_override("font_size", 10)
	_grip.add_theme_color_override("font_color", UiStyle.TEXT_MUTED)
	_grip.custom_minimum_size = Vector2(0, GRIP)
	_grip.mouse_filter = Control.MOUSE_FILTER_STOP
	_grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	_grip.visible = resizable
	_grip.gui_input.connect(_on_grip_input)
	root.add_child(_grip)
	# fit the content when it shrinks too (a Container only ever grows); wrapped
	# labels only know their height after a layout pass
	minimum_size_changed.connect(_fit, CONNECT_DEFERRED)
	_content.minimum_size_changed.connect(_fit, CONNECT_DEFERRED)
	if not _all.has(self):
		_all.append(self)


func _enter_tree() -> void:
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_on_screen_changed):
		vp.size_changed.connect(_on_screen_changed)


func _on_screen_changed() -> void:
	if _shown and is_inside_tree():
		_fit_now()


## True from open() to close_window(), even while the closing animation plays.
func is_open() -> bool:
	return _shown


func open() -> void:
	if not _shown:
		_shown = true
		visible = true
		_open.append(self)
		_kill_tween()
		_ensure_loaded()
		_fit_now()
		_fit.call_deferred() # wrapped labels know their height one layout pass later
		_animate_in()
	raise()


func close_window() -> void:
	if not _shown:
		return
	_shown = false
	_open.erase(self)
	_dragging = false
	_resizing = false
	closed.emit()
	if animate and is_inside_tree():
		_kill_tween()
		pivot_offset = size * 0.5
		_tween = create_tween().set_parallel(true)
		_tween.tween_property(self, "modulate:a", 0.0, CLOSE_MS)
		_tween.tween_property(self, "scale", Vector2(POP, POP), CLOSE_MS)
		_tween.chain().tween_callback(_finish_close)
	else:
		visible = false


func _finish_close() -> void:
	if not _shown:
		visible = false
	modulate.a = 1.0
	scale = Vector2.ONE


func _animate_in() -> void:
	if not animate or not is_inside_tree():
		return
	pivot_offset = size * 0.5
	modulate.a = 0.0
	scale = Vector2(POP, POP)
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "modulate:a", 1.0, OPEN_MS)
	_tween.tween_property(self, "scale", Vector2.ONE, OPEN_MS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	modulate.a = 1.0
	scale = Vector2.ONE


func toggle() -> void:
	if _shown:
		close_window()
	else:
		open()


func raise() -> void:
	_open.erase(self)
	if _shown:
		_open.append(self)
	move_to_front()


## Escape: closes the top-most open window (true if one was closed).
static func close_top() -> bool:
	for i in range(_open.size() - 1, -1, -1):
		var w := _open[i]
		if is_instance_valid(w) and w._shown:
			w.close_window()
			return true
		_open.remove_at(i)
	return false


## The screen changed (size, interface scale, safe margin): put every open window back inside it.
static func relayout_all() -> void:
	for i in range(_all.size() - 1, -1, -1):
		var w := _all[i]
		if not is_instance_valid(w):
			_all.remove_at(i)
		elif w._shown and w.is_inside_tree():
			w._fit_now()


## Every live window (tests, tools).
static func all_windows() -> Array[UiWindow]:
	var out: Array[UiWindow] = []
	for w in _all:
		if is_instance_valid(w):
			out.append(w)
	return out


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		raise()


func _on_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_drag_offset = get_global_mouse_position() - global_position
		raise()
		if not _dragging:
			_save_layout()
	elif event is InputEventMouseMotion and _dragging:
		position = _clamped(get_global_mouse_position() - _drag_offset)
		_frac = _fraction_of(position)


func _on_grip_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_resizing = event.pressed
		_resize_start = get_global_mouse_position()
		_resize_from = _scroll.size
		raise()
		if not _resizing:
			_save_layout()
	elif event is InputEventMouseMotion and _resizing:
		_user_size = _resize_from + (get_global_mouse_position() - _resize_start)
		_fit_now()


## Size to the content, then back inside the screen.
func _fit() -> void:
	if _shown:
		_fit_now()


func _fit_now() -> void:
	if not is_inside_tree():
		return
	var safe := UiScale.safe_rect(self)
	var header_h := _header.get_combined_minimum_size().y
	var grip_h := GRIP if resizable else 0.0
	var inner := _content.get_combined_minimum_size()
	var avail_h := maxf(MIN_BODY, safe.size.y - header_h - grip_h)
	var avail_w := maxf(120.0, safe.size.x)
	var want_h := _user_size.y if _user_size.y > 0.0 else inner.y
	var want_w := maxf(_user_size.x, inner.x)
	var bar_w := _scroll.get_v_scroll_bar().get_combined_minimum_size().x
	var h := clampf(want_h, MIN_BODY, avail_h)
	var w := minf(want_w + (bar_w if inner.y > h + 0.5 else 0.0), avail_w)
	_scroll.custom_minimum_size = Vector2(w, h)
	reset_size()
	_place(safe)


func _fraction() -> Vector2:
	return default_anchor if _frac.x < 0.0 else _frac


func _fraction_of(pos: Vector2) -> Vector2:
	var safe := UiScale.safe_rect(self)
	var slack := safe.size - size
	return Vector2(
			clampf((pos.x - safe.position.x) / slack.x, 0.0, 1.0) if slack.x > 1.0 else 0.5,
			clampf((pos.y - safe.position.y) / slack.y, 0.0, 1.0) if slack.y > 1.0 else 0.5)


func _place(safe := Rect2()) -> void:
	if safe.size == Vector2.ZERO:
		safe = UiScale.safe_rect(self)
	if _dragging:
		return
	var slack := (safe.size - size).max(Vector2.ZERO)
	position = _clamped((safe.position + slack * _fraction()).floor(), safe)
	_placed = true


## `pos` pulled back so that the whole window is inside the safe area (its title bar at least).
func _clamped(pos: Vector2, safe := Rect2()) -> Vector2:
	if safe.size == Vector2.ZERO:
		safe = UiScale.safe_rect(self)
	var hi := (safe.end - size).max(safe.position)
	return pos.clamp(safe.position, hi)


func _ensure_loaded() -> void:
	if _placed or window_id == "":
		return
	var saved: Variant = _layout_get(window_id)
	if not saved is Dictionary:
		return
	var d: Dictionary = saved
	if d.has("fx"):
		_frac = Vector2(clampf(float(d["fx"]), 0.0, 1.0), clampf(float(d.get("fy", 0.5)), 0.0, 1.0))
	elif d.has("x"): # layout v1: pixels, taken as the share they were on this screen
		var safe := UiScale.safe_rect(self)
		var slack := (safe.size - size).max(Vector2.ONE)
		_frac = Vector2(clampf((float(d["x"]) - safe.position.x) / slack.x, 0.0, 1.0),
				clampf((float(d.get("y", 0)) - safe.position.y) / slack.y, 0.0, 1.0))
	if d.has("sw"):
		_user_size = Vector2(float(d["sw"]), float(d.get("sh", 0)))


func _save_layout() -> void:
	if window_id == "":
		return
	_layout_get(window_id)
	var entry := {"fx": snappedf(_fraction().x, 0.0001), "fy": snappedf(_fraction().y, 0.0001)}
	if _user_size.x > 0.0 or _user_size.y > 0.0:
		entry["sw"] = roundf(_user_size.x)
		entry["sh"] = roundf(_user_size.y)
	if _layout["windows"].get(window_id) == entry:
		return
	_layout["windows"][window_id] = entry
	var f := FileAccess.open(LAYOUT_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_layout))


## The saved entry of a window; also loads the file (v2, or v1: `id: [x, y]` in pixels).
static func _layout_get(id: String) -> Variant:
	if not _layout_loaded:
		_layout_loaded = true
		_layout = {"v": LAYOUT_VERSION, "windows": {}}
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_FILE)) if FileAccess.file_exists(LAYOUT_FILE) else null
		if data is Dictionary:
			if int((data as Dictionary).get("v", 1)) >= LAYOUT_VERSION and data.get("windows") is Dictionary:
				_layout["windows"] = (data["windows"] as Dictionary).duplicate()
			else:
				for k: Variant in data:
					var v: Variant = data[k]
					if v is Array and (v as Array).size() == 2:
						_layout["windows"][str(k)] = {"x": float(v[0]), "y": float(v[1])}
	return _layout["windows"].get(id)


## Tools and tests: forget saved positions and sizes (deterministic screenshots, "reset the windows").
static func reset_layout() -> void:
	_layout = {"v": LAYOUT_VERSION, "windows": {}}
	_layout_loaded = true
	for w in _all:
		if is_instance_valid(w):
			w._frac = Vector2(-1.0, -1.0)
			w._user_size = Vector2.ZERO
			if w._shown and w.is_inside_tree():
				w._fit_now()
