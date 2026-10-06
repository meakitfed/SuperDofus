## Spawns N wandering monsters in the iso demo and measures frame times:
##   godot --path . -s res://tools/benchmark.gd -- [count=100] [shot.png] [warmup_frames=600]
## (the warm-up lets every entity bake the first loop of its animations)
extends SceneTree

var _demo: Node
var _frame := 0
var _times: PackedFloat64Array = []
var _proc: PackedFloat64Array = []
var _last := 0
var _count := 100
var _shot := ""
var _warmup := 600


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_count = int(args[0])
	if args.size() > 1:
		_shot = args[1]
	if args.size() > 2:
		_warmup = int(args[2])
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.size = Vector2i(1280, 800)
	_demo = load("res://scenes/demo/iso_demo.tscn").instantiate()
	root.add_child(_demo)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		var t0 := Time.get_ticks_msec()
		while _demo.entities.size() < _count:
			_demo._spawn_monster()
		print("spawned %d entities in %d ms" % [_demo.entities.size(), Time.get_ticks_msec() - t0])
		for e in _demo.entities:
			if e != _demo.player:
				e.follow_path(_demo.grid.find_path(e.cell, Vector2i(randi() % 16, randi() % 16)))
	elif _frame % 30 == 0:
		print("frame %d process %.1f ms  physics %.1f  objects %d  nodes %d  draw calls %d" % [_frame,
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	if _frame > _warmup:
		var now := Time.get_ticks_usec()
		if _last > 0:
			_times.append((now - _last) / 1000.0)
			_proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		_last = now
	if _frame == _warmup + 300:
		var sorted := _times.duplicate()
		sorted.sort()
		var total := 0.0
		for t in _times:
			total += t
		print("frames %d  avg %.2f ms (%.0f fps)  p50 %.2f  p95 %.2f  p99 %.2f ms" % [_times.size(), total / _times.size(),
				1000.0 / (total / _times.size()), sorted[sorted.size() / 2], sorted[int(sorted.size() * 0.95)], sorted[int(sorted.size() * 0.99)]])
		print("content ", DofusContent.stats())
		var spikes := 0
		var spike_proc := 0.0
		for i in _times.size():
			if _times[i] > 20.0:
				spikes += 1
				spike_proc += _proc[i]
		if spikes > 0:
			print("%d frames > 20 ms, their avg process time %.1f ms" % [spikes, spike_proc / spikes])
		if _shot != "":
			root.get_texture().get_image().save_png(_shot)
		DofusContent.clear_caches()
		quit()
	return false
