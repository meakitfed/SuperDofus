## Interface scale and safe area (docs/ui/ADAPTATIF.md 2.1, 2.2, 2.4; lot U.02).
## The project stretches `canvas_items` / `expand` from a 1280x720 design viewport: the HUD is laid
## out in "virtual" pixels (get_viewport_rect), the engine does the scaling. This adds the player's
## choice on top (user://ui_settings.json: client-only preference, never game state) and a safe
## margin for screens that crop their edges.
class_name UiScale
extends RefCounted

const SETTINGS_FILE := "user://ui_settings.json"
const BASE := Vector2(1280.0, 720.0)
## smallest window the game accepts (stretch factor 0.8)
const MIN_WINDOW := Vector2i(1024, 576)
## the product stretch x choice never goes under this (text stays readable)
const MIN_TOTAL := 0.75
const MAX_TOTAL := 3.0
## "auto" is 0.0
const CHOICES := [0.0, 0.75, 1.0, 1.25, 1.5]
const MAX_SAFE_SHARE := 0.05

static var _loaded := false
static var _choice := 0.0 # 0 = auto
static var _safe_share := 0.0


## The stretch factor the engine applies for a window of `window_px` (aspect "expand").
static func stretch(window_px: Vector2) -> float:
	return minf(window_px.x / BASE.x, window_px.y / BASE.y)


## The factor on top of the stretch. Auto keeps 1.0, except on very large windows (4K and more) where the
## stretch alone would pass MAX_TOTAL; a choice is clamped so that stretch x factor stays readable.
static func factor_for(window_px: Vector2, choice: float) -> float:
	var s := maxf(0.01, stretch(window_px))
	if choice <= 0.0:
		return minf(1.0, MAX_TOTAL / s) if s > MAX_TOTAL else 1.0
	return clampf(choice, MIN_TOTAL / s, MAX_TOTAL / s)


## The size of the virtual viewport (what the HUD lays out in) for a window and a choice.
static func virtual_for(window_px: Vector2, choice: float) -> Vector2:
	return window_px / (stretch(window_px) * factor_for(window_px, choice))


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_FILE)) if FileAccess.file_exists(SETTINGS_FILE) else null
	if data is Dictionary:
		_choice = _valid_choice(float(data.get("scale", 0.0)))
		_safe_share = clampf(float(data.get("safe_margin", 0.0)), 0.0, MAX_SAFE_SHARE)


static func _valid_choice(v: float) -> float:
	return v if CHOICES.has(v) else 0.0


static func _save() -> void:
	var f := FileAccess.open(SETTINGS_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"scale": _choice, "safe_margin": _safe_share}))


## The player's choice: 0.0 (auto) or one of CHOICES.
static func choice() -> float:
	_load()
	return _choice


## The factor really applied on this window.
static func ui_scale(window: Window) -> float:
	_load()
	return factor_for(Vector2(window.size), _choice)


## Reads the preferences and applies them (scale factor, minimum window size). Idempotent.
static func apply(window: Window) -> void:
	_load()
	if window == null:
		return
	window.min_size = MIN_WINDOW
	window.content_scale_factor = ui_scale(window)
	UiWindow.relayout_all()


## Sets and remembers the choice (0.0 = auto), then applies it.
static func set_choice(window: Window, c: float) -> void:
	_load()
	_choice = _valid_choice(c)
	_save()
	apply(window)


## The next choice up (+1) or down (-1) in CHOICES, for the shortcut.
static func step(window: Window, dir: int) -> void:
	_load()
	var cur := ui_scale(window)
	var best := CHOICES[1] as float
	var steps: Array[float] = [0.75, 1.0, 1.25, 1.5]
	if dir > 0:
		for v in steps:
			if v > cur + 0.001:
				best = v
				break
			best = v
	else:
		best = steps[0]
		for v in steps:
			if v < cur - 0.001:
				best = v
	set_choice(window, best)


## Ctrl+PageUp / PageDown / Home (Shortcuts): interface size up, down, windows back to their places.
static func handle_key(event: InputEvent, window: Window) -> bool:
	if not (event is InputEventKey and (event as InputEventKey).ctrl_pressed):
		return false
	if Shortcuts.pressed(event, "ui_scale_up"):
		step(window, 1)
	elif Shortcuts.pressed(event, "ui_scale_down"):
		step(window, -1)
	elif Shortcuts.pressed(event, "ui_reset"):
		UiWindow.reset_layout()
	else:
		return false
	return true


## Margin kept free around the screen, in virtual pixels.
static func safe_margin(node: Node) -> float:
	_load()
	return virtual_size(node).x * _safe_share


static func set_safe_share(window: Window, share: float) -> void:
	_load()
	_safe_share = clampf(share, 0.0, MAX_SAFE_SHARE)
	_save()
	UiWindow.relayout_all()


## The one access to the virtual screen size.
static func virtual_size(node: Node) -> Vector2:
	return node.get_viewport().get_visible_rect().size


## The virtual screen minus the safe margin: where windows and panels may go.
static func safe_rect(node: Node) -> Rect2:
	var v := virtual_size(node)
	var m := safe_margin(node)
	return Rect2(Vector2(m, m), (v - Vector2(m, m) * 2.0).max(Vector2.ONE))


## Tests: forget the loaded preferences.
static func reset_for_tests() -> void:
	_loaded = true
	_choice = 0.0
	_safe_share = 0.0
