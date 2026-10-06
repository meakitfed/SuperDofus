## One animated sprite on the map. Holds a movement (path, t0, run) received
## from the game and draws it at the game time given to update(), using the
## same shared/Movement code the sim uses to decide arrival. Can also play
## one-shot actions (spell, hit, death) and report their animation labels.
class_name ActorView
extends Node2D

signal label_reached(label: String)
signal action_finished

var sprite: DofusSprite
var anim_map: AnimMap
var cell := 0
var dir := 1
var path: Array = []
var t0 := 0
var run := false
## idle animation candidates, first available wins ("" = the bone's default idle)
var idle_candidates: Array = [""]
var dead := false
## animation suffix while carrying someone (P1.12: "Carrying", the Pandawa's
## AnimStatiqueCarrying / AnimMarcheCarrying...), "" otherwise
var carrying := ""

var _state := ""
var _anim_dir := -1
var _acting := false


func setup(look: String, p_cell: int, p_dir: int) -> void:
	anim_map = load("res://src/presentation/default_anim_map.tres")
	sprite = DofusSprite.new()
	add_child(sprite)
	sprite.look_string = look
	sprite.preload_animations(PackedStringArray(["AnimMarche", "AnimCourse"]))
	sprite.label_reached.connect(func(label: String, _anim: String) -> void: label_reached.emit(label))
	sprite.animation_finished.connect(_on_animation_finished)
	cell = p_cell
	dir = p_dir
	position = MapGeometry.to_screen(cell)
	_play("IDLE", dir)


## actor_look: the new look (worn items, a carried fighter), same place and animation state.
func set_look(look: String, p_carrying := carrying) -> void:
	carrying = p_carrying
	sprite.look_string = look
	if dead: # stays on its last death frame
		if sprite.play_animation("AnimMort", dir, false):
			sprite.seek(sprite.get_frame_count() - 1)
		return
	var s := _state
	_state = ""
	_play(s if s != "" and s != "ACTION" else "IDLE", dir)


func set_move(p_path: Array, p_t0: int, p_run: bool) -> void:
	path = p_path
	t0 = p_t0
	run = p_run
	_acting = false


## Puts the actor on `p_cell` at once (placement, teleport).
func place(p_cell: int) -> void:
	cell = p_cell
	path = []
	position = MapGeometry.to_screen(cell)


## Cell the actor is heading to (or standing on).
func dest_cell() -> int:
	return path[-1] if path.size() >= 2 else cell


func is_moving(now: int) -> bool:
	return path.size() >= 2 and now < t0 + Movement.duration_ms(path, run)


func is_acting() -> bool:
	return _acting


## Walk to `target` continuing the current step smoothly (client-side planning,
## used for purely visual actors such as group followers).
func walk_to(target: int, now: int, finder: MapPathfinder, delay_ms := 0) -> void:
	var r := Movement.replan(path, t0, run, cell, now, target, finder, delay_ms)
	if not r["path"].is_empty():
		set_move(r["path"], r["t0"], false)


func update(now: int) -> void:
	if path.size() < 2:
		return
	var s := Movement.sample(path, t0, run, now)
	position = IsoGrid.cell_to_world(s["pos"])
	if s["moving"]:
		_play("RUN" if run else "MOVE", s["dir"])
	elif now > t0:
		cell = path[-1]
		dir = s["dir"]
		path = []
		_play("IDLE", dir)


func face(d: int) -> void:
	if d >= 0 and d != dir:
		dir = d
		if not _acting:
			_play("IDLE", dir)


## First animation base of `candidates` this look actually has ("" if none).
func first_available(candidates: Array) -> String:
	var have := sprite.get_animation_directions()
	for c: String in candidates:
		if c == "" or have.has(c):
			return c
	return ""


## Plays a one-shot animation (first available candidate); false if none exists.
func play_action(candidates: Array, d := -1) -> bool:
	var base := first_available(candidates)
	if base == "":
		return false
	if d >= 0:
		dir = d
	_acting = true
	_state = "ACTION"
	sprite.play_animation(base, dir, false)
	return true


func _on_animation_finished(_anim: String) -> void:
	if not _acting or sprite.looping:
		return
	_acting = false
	action_finished.emit()
	if not dead:
		_play("IDLE", dir)


func _play(state: String, d: int) -> void:
	if state == _state and d == _anim_dir:
		return
	_state = state
	_anim_dir = d
	var base := first_available(idle_candidates) if state == "IDLE" else anim_map.base_for_name(state)
	if carrying != "":
		var alt := first_available([("AnimStatique" if state == "IDLE" else base) + carrying])
		if alt != "":
			base = alt
	sprite.play_animation(base, d, true)
