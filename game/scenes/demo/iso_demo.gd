## Gameplay/visual separation demo on an isometric grid.
##   left click: walk (shift: run) · right click: attack towards the cell
##   B: spawn 25 wandering monsters (benchmark) · C: clear them
## Gameplay (GameEntity, IsoGrid) never touches rendering; EntityView does.
extends Node2D

const GRID_SIZE := Vector2i(16, 16)
const PLAYER_LOOK := "{1|120,2195,4072,4941,3963,5716|1=13418918,2=4077879,3=16022817,4=14386944,5=4275500,6=9904435|56|1@0={1420|||90}}"
const FALLBACK_MONSTER_LOOKS := ["{4907|||130}", "{2069|||100}", "{1420|||90}"]

var grid := IsoGrid.new(GRID_SIZE)
var entities: Array[GameEntity] = []
var player: GameEntity

var _world: Node2D
var _camera: Camera2D
var _hud: Label
var _monster_looks: Array = []
var _next_id := 1
var _rng := RandomNumberGenerator.new()
var _events: PackedStringArray = []


func _ready() -> void:
	_rng.seed = 42
	_world = Node2D.new()
	_world.y_sort_enabled = true
	add_child(_world)
	_camera = Camera2D.new()
	_camera.position = IsoGrid.cell_to_world(Vector2(GRID_SIZE) * 0.5)
	add_child(_camera)
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(12, 8)
	layer.add_child(_hud)
	for c in [Vector2i(5, 9), Vector2i(6, 9), Vector2i(10, 4)]:
		grid.set_blocked(c, true)
	_monster_looks = _load_monster_looks()
	player = _spawn(PLAYER_LOOK, Vector2i(8, 8))
	for i in 4:
		_spawn_monster()


func _process(delta: float) -> void:
	for e in entities:
		e.tick(delta)
	_wander(delta)
	_hud.text = "%d fps · %d entities · %s\nleft click walk (shift run) · right click attack · B +25 monsters · C clear" % [
		Engine.get_frames_per_second(), entities.size(), DofusContent.stats()]
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		var target := IsoGrid.world_to_cell(get_global_mouse_position())
		if mb.button_index == MOUSE_BUTTON_LEFT:
			player.follow_path(grid.find_path(player.cell, target), mb.shift_pressed)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			player.attack(target)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera.zoom *= 1.1
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera.zoom /= 1.1
	elif event is InputEventKey and event.pressed:
		match (event as InputEventKey).keycode:
			KEY_B:
				for i in 25:
					_spawn_monster()
			KEY_C:
				for e in entities.duplicate():
					if e != player:
						_despawn(e)


func _draw() -> void:
	for x in GRID_SIZE.x:
		for y in GRID_SIZE.y:
			var c := IsoGrid.cell_to_world(Vector2(x, y))
			var pts := PackedVector2Array([c + Vector2(0, -IsoGrid.CELL_H / 2), c + Vector2(IsoGrid.CELL_W / 2, 0),
					c + Vector2(0, IsoGrid.CELL_H / 2), c + Vector2(-IsoGrid.CELL_W / 2, 0)])
			var fill := Color(0.35, 0.45, 0.3) if (x + y) % 2 == 0 else Color(0.32, 0.42, 0.28)
			if grid.is_blocked(Vector2i(x, y)):
				fill = Color(0.25, 0.25, 0.28)
			draw_colored_polygon(pts, fill)
	var hover := IsoGrid.world_to_cell(get_global_mouse_position())
	if grid.in_bounds(hover):
		var c := IsoGrid.cell_to_world(Vector2(hover))
		draw_polyline(PackedVector2Array([c + Vector2(0, -IsoGrid.CELL_H / 2), c + Vector2(IsoGrid.CELL_W / 2, 0),
				c + Vector2(0, IsoGrid.CELL_H / 2), c + Vector2(-IsoGrid.CELL_W / 2, 0), c + Vector2(0, -IsoGrid.CELL_H / 2)]),
				Color(1, 1, 1, 0.6), 2.0)


# ── spawning (the only place that wires gameplay to presentation) ──────────────

func _spawn(look: String, cell: Vector2i) -> GameEntity:
	var e := GameEntity.new(_next_id, look, cell)
	_next_id += 1
	entities.append(e)
	var view := EntityView.new()
	view.name = "Entity%d" % e.id
	_world.add_child(view)
	view.bind(e)
	view.visual_event.connect(_on_visual_event)
	e.set_meta("view", view)
	return e


func _despawn(e: GameEntity) -> void:
	entities.erase(e)
	(e.get_meta("view") as Node).queue_free()


func _spawn_monster() -> void:
	for attempt in 20:
		var c := Vector2i(_rng.randi_range(0, GRID_SIZE.x - 1), _rng.randi_range(0, GRID_SIZE.y - 1))
		if not grid.is_blocked(c):
			var look: String = _monster_looks[_rng.randi() % _monster_looks.size()]
			_spawn(look, c)
			return


func _wander(_delta: float) -> void:
	for e in entities:
		if e != player and e.state == GameEntity.State.IDLE and _rng.randf() < 0.004:
			var target := e.cell + Vector2i(_rng.randi_range(-3, 3), _rng.randi_range(-3, 3))
			e.follow_path(grid.find_path(e.cell, target))


func _on_visual_event(source: GameEntity, label: String) -> void:
	# gameplay reacts to the animation's own markers: SHOT = impact frame, Sound(...) = sfx cue
	if label == "SHOT":
		_events.insert(0, "entity %d: impact frame" % source.id)
	elif source == player:
		_events.insert(0, "player: %s" % label.left(48))
	else:
		return
	if _events.size() > 6:
		_events.resize(6)


## Monster looks whose bone has been extracted.
func _load_monster_looks() -> Array:
	var out: Array = []
	var data: Variant = DofusContent.get_provider().read_json("Content/Data/monstersdataroot.json")
	if data is Dictionary:
		for m: Dictionary in (data["objectsById"] as Dictionary).values():
			var look := DofusLook.parse(str(m.get("look", "")))
			if look.bone > 1 and DofusContent.get_provider().exists("Content/Characters/Bones/%d/bone.json" % look.bone):
				out.append(str(m["look"]))
			if out.size() >= 60:
				break
	return out if not out.is_empty() else FALLBACK_MONSTER_LOOKS
