## Gameplay-side entity. Pure logic: cells, facing, state machine, movement timing.
## It knows NOTHING about rendering (no nodes, no animation names); the presentation
## layer observes its signals. The look is plain appearance data (a string).
class_name GameEntity
extends RefCounted

enum State { IDLE, MOVE, RUN, ATTACK, HIT, DIE }
## 8 facings, numbered clockwise from screen-east (same convention as the client data).
enum Facing { EAST, SOUTH_EAST, SOUTH, SOUTH_WEST, WEST, NORTH_WEST, NORTH, NORTH_EAST }

signal state_changed(state: State, facing: Facing)
signal cell_changed(cell: Vector2i)
signal died

var id: int
var look: String
var cell := Vector2i.ZERO
## continuous position in cell space while walking (for smooth display)
var position := Vector2.ZERO
var facing: Facing = Facing.SOUTH_EAST
var state: State = State.IDLE
var hp := 100
var walk_speed := 2.6 # cells / s
var run_speed := 5.0

var _path: Array[Vector2i] = []
var _segment_t := 0.0
var _running := false


func _init(p_id: int, p_look: String, p_cell: Vector2i) -> void:
	id = p_id
	look = p_look
	cell = p_cell
	position = Vector2(p_cell)


func is_alive() -> bool:
	return state != State.DIE


func follow_path(path: Array[Vector2i], run := false) -> void:
	if not is_alive() or path.is_empty():
		return
	if path[0] == cell:
		path = path.slice(1)
	if path.is_empty():
		return
	_path = path
	_running = run
	_segment_t = 0.0
	_face_towards(_path[0])
	_set_state(State.RUN if run else State.MOVE)


func attack(target_cell: Vector2i) -> void:
	if not is_alive():
		return
	_path.clear()
	_face_towards(target_cell)
	_set_state(State.ATTACK)


func take_hit(damage: int) -> void:
	if not is_alive():
		return
	hp -= damage
	if hp <= 0:
		_set_state(State.DIE)
		died.emit()
	else:
		_set_state(State.HIT)


## Called by the presentation when a one-shot action has finished playing, or by an AI/timer.
func action_done() -> void:
	if state in [State.ATTACK, State.HIT]:
		_set_state(State.IDLE)


func tick(delta: float) -> void:
	if _path.is_empty():
		return
	var speed := run_speed if _running else walk_speed
	var next := _path[0]
	var seg_len := Vector2(next - cell).length()
	_segment_t += delta * speed / maxf(seg_len, 0.001)
	if _segment_t >= 1.0:
		cell = next
		position = Vector2(cell)
		_path.pop_front()
		_segment_t = 0.0
		cell_changed.emit(cell)
		if _path.is_empty():
			_set_state(State.IDLE)
			return
		var old := facing
		_face_towards(_path[0])
		if old != facing:
			state_changed.emit(state, facing)
	else:
		position = Vector2(cell).lerp(Vector2(next), _segment_t)


func _face_towards(target: Vector2i) -> void:
	var d := target - cell
	if d != Vector2i.ZERO:
		facing = IsoGrid.facing_for_cell_delta(d)


func _set_state(s: State) -> void:
	state = s
	state_changed.emit(state, facing)
