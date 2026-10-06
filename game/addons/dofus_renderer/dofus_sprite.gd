## Displays a Dofus entity (character, monster, pet, mount, map prop) from a look string.
##
##     var s := DofusSprite.new()
##     s.look_string = "{1|10,2195,3042||100}"
##     s.play_animation("AnimMarche", DofusAnimNames.Direction.DOWN_RIGHT)
##
## The node origin is the entity's ground anchor (feet), so it y-sorts naturally.
## `modulate` tints the whole entity. Gameplay code should talk to it through a
## presentation layer (see src/presentation/entity_view.gd), not directly.
class_name DofusSprite
extends Node2D

signal animation_finished(anim_name: String)
## Emitted when playback enters a frame carrying a label (e.g. hit / sound markers).
signal label_reached(label: String, anim_name: String)
signal look_changed

@export_multiline var look_string := "":
	set(value):
		look_string = value
		set_look(DofusLook.parse(value) if value.strip_edges() != "" else null)
## Animation base name ("AnimMarche", "AnimAttaque0"…). Empty = the bone's idle.
@export var animation := "":
	set(value):
		animation = value
		if not _suspend:
			_resolve_and_play()
@export_range(0, 7) var direction := 1:
	set(value):
		direction = wrapi(value, 0, 8)
		if not _suspend:
			_resolve_and_play()
@export var playing := true
@export var looping := true
@export_range(0.0, 8.0, 0.05) var speed_scale := 1.0
## Map prop animation instead of a character bone.
@export var is_prop := false
## Force a bone bundle (e.g. "1-combat"); empty = automatic from the look.
@export var bone_name := ""
## Fill missing colours with the breed defaults (like the game).
@export var inject_default_colors := true
## Stencil masks (some spell FX) use Godot clip groups. Godot draws clip groups as opaque
## black over a *transparent* background (e.g. a transparent SubViewport portrait): use
## HIDE_MASKED there. IGNORE draws masked content unclipped (debug).
@export var mask_mode: DofusSpriteInstance.MaskMode = DofusSpriteInstance.MaskMode.CLIP:
	set(value):
		mask_mode = value
		if _instance != null:
			_instance.mask_mode = value
			_render()

var look: DofusLook
## Resolved animation actually played (e.g. "AnimMarche_1") and whether it is mirrored.
var current_animation := ""
var flipped := false
var frame := 0

static var _warned: Dictionary = {}

var _instance: DofusSpriteInstance
var _time := 0.0
var _tick := 0
var _finished := false
var _suspend := false


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _instance != null:
		_instance.destroy()
		_instance = null


# ── look ───────────────────────────────────────────────────────────────────────

func set_look(new_look: DofusLook) -> void:
	if new_look != null and inject_default_colors:
		new_look = new_look.duplicate_look()
		new_look.inject_default_colors(DofusContent.get_game_data())
	look = new_look
	if look == null:
		if _instance != null:
			_instance.destroy()
			_instance = null
		look_changed.emit()
		return
	if _instance == null or _instance.is_prop != is_prop or _instance.bone_name_override != bone_name:
		if _instance != null:
			_instance.destroy()
		_instance = DofusSpriteInstance.new(look, null, is_prop, bone_name)
		_instance.mask_mode = mask_mode
		RenderingServer.canvas_item_set_parent(_instance.root_item, get_canvas_item())
	else:
		_instance.set_look(look)
	_resolve_and_play()
	look_changed.emit()


func get_look_string() -> String:
	return str(look) if look != null else ""


## Recolour one palette slot (1..15) without rebuilding anything.
func set_color(index: int, color: Color) -> void:
	if look == null:
		return
	look.set_color_from(index, color)
	_instance.set_look(look)
	_render()


# ── animation ──────────────────────────────────────────────────────────────────

## Plays `base` towards `dir` (mirroring the opposite direction when needed).
func play_animation(base: String, dir := -1, loop := true) -> bool:
	looping = loop
	_suspend = true
	if dir >= 0:
		direction = dir
	animation = base
	_suspend = false
	_resolve_and_play()
	return current_animation != ""


## Plays an exact animation name such as "AnimStatique_2". Returns false if unknown.
func play_exact(anim_name: String, flip := false, loop := true) -> bool:
	if _instance == null:
		return false
	looping = loop
	var ok := _instance.play(anim_name)
	if ok:
		_start(anim_name, flip)
	return ok


func _resolve_and_play() -> void:
	if _instance == null:
		return
	var r := DofusAnimNames.resolve(_instance.animations, direction, look.bone, animation)
	if r[0] == "" and animation != "":
		# many monsters lack some animations (run, hit…): fall back to idle, warn once per bone
		var key := "%d/%s" % [look.bone, animation]
		if not _warned.has(key):
			_warned[key] = true
			push_warning("DofusSprite: bone %d has no '%s' animation, using its idle" % [look.bone, animation])
		r = DofusAnimNames.resolve(_instance.animations, direction, look.bone)
	if r[0] != "" and _instance.play(r[0]):
		_start(r[0], r[1])
	else:
		current_animation = ""


func _start(anim_name: String, flip: bool) -> void:
	current_animation = anim_name
	flipped = flip
	_instance.flip = flip
	RenderingServer.canvas_item_set_transform(_instance.root_item,
			Transform2D(Vector2(-1.0 if flip else 1.0, 0.0), Vector2(0.0, -1.0), Vector2.ZERO))
	_instance._refresh_sub_anims()
	_time = 0.0
	_tick = 0
	frame = 0
	_finished = false
	_emit_labels(0)
	_render()


## Every animation of this look: base name -> available directions (mirrors included).
func get_animation_directions() -> Dictionary:
	return DofusAnimNames.directions_by_anim(_instance.animations.keys()) if _instance != null else {}


func get_animation_names() -> PackedStringArray:
	return PackedStringArray(_instance.animations.keys()) if _instance != null else PackedStringArray()


## Decode, in the background, every direction of these animation bases (e.g. the ones
## gameplay will trigger soon) so switching to them never hitches.
func preload_animations(bases: PackedStringArray) -> void:
	if _instance == null:
		return
	var wanted := {}
	for anim_name: String in _instance.animations:
		var base: String = DofusAnimNames.split(anim_name)[0]
		if bases.has(base) or (bases.has("") and base == DofusAnimNames.default_base(look.bone)):
			wanted[anim_name] = _instance.animations[anim_name]
	DofusContent.preload_clips(wanted, is_prop)


func get_frame_count() -> int:
	return _instance.frame_count() if _instance != null else 0


func get_frame_rate() -> float:
	return _instance.frame_rate() if _instance != null else 30.0


func get_labels() -> Dictionary:
	return _instance.baked.clip.labels if _instance != null and _instance.baked != null else {}


func seek(p_frame: int) -> void:
	_tick = maxi(p_frame, 0)
	frame = _frame_of(_tick)
	_render()


## Local bounds of the current frame in node space (y down).
func get_frame_rect() -> Rect2:
	if _instance == null:
		return Rect2()
	var r := _instance.current_bounds()
	var flip_x := -1.0 if flipped else 1.0
	return Transform2D(Vector2(flip_x, 0), Vector2(0, -1), Vector2.ZERO) * r


func _process(delta: float) -> void:
	if not playing or _instance == null or _instance.baked == null or _finished:
		return
	_time += delta * speed_scale * _instance.frame_rate()
	var steps := mini(int(_time), 4) # don't spiral on hitches
	if steps <= 0:
		return
	_time -= int(_time)
	for i in steps:
		_tick += 1
		var f := _frame_of(_tick)
		if not looping and _tick >= get_frame_count() - 1:
			frame = get_frame_count() - 1
			_finished = true
			_render()
			animation_finished.emit(current_animation)
			return
		if f == 0 and looping:
			animation_finished.emit(current_animation)
		frame = f
		_emit_labels(f)
	_render()


func _frame_of(tick: int) -> int:
	var n := get_frame_count()
	if n <= 0:
		return 0
	return posmod(tick, n) if looping else mini(tick, n - 1)


func _emit_labels(f: int) -> void:
	var labels := get_labels()
	if labels.has(f):
		for label: String in labels[f]:
			label_reached.emit(label, current_animation)


func _render() -> void:
	if _instance != null:
		_instance.render(_tick if looping else frame)
