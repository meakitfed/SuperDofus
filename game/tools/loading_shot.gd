## Capture of the world loading screen (C.03) without a server: the list is filled by hand.
##   godot --path game -s res://tools/loading_shot.gd -- --out=w.png --mode=list|progress|error
## list = worlds offered (one current, one to download, one interrupted); progress = a download under way;
## error = the server does not answer.
extends SceneTree

var _screen: WorldLoadScreen
var _mode := "list"
var _out := "loading.png"
var _t := 0.0
var _done_at := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		if a.begins_with("--mode="):
			_mode = a.substr(7)
	var loader := WorldLoader.new(ContentClient.new("127.0.0.1", 1, ""))
	_screen = WorldLoadScreen.new()
	_screen.setup(loader, "dofus")
	root.add_child(_screen)


func _process(delta: float) -> bool:
	_t += delta
	if _t < 1.5 or _screen._thread != null:
		return false # the first request (dead port) ends: the error is on screen
	if _done_at == 0.0:
		_done_at = _t
	if _mode != "error" and _screen.loader.state == "failed":
		var l := _screen.loader
		l.state = "idle"
		l.error = ""
		l.worlds.assign([
			{"id": "dofus", "name": "Dofus (monde complet)", "size": 4_200_000_000, "files": 18200, "version": "a1b2c3d4e5f6",
					"players": 3, "status": "update", "todo_bytes": 310_000_000, "measured": true},
			{"id": "incarnam", "name": "Incarnam", "size": 52_000_000, "files": 640, "version": "0f9e8d7c6b5a",
					"players": 0, "status": "current", "todo_bytes": 0, "measured": true},
			{"id": "test", "name": "Monde de test", "size": 9_000_000, "files": 80, "version": "11223344aabb",
					"players": 0, "status": "partial", "todo_bytes": 4_000_000, "measured": true},
		])
		_screen._say("")
		_screen._show_worlds()
		_screen._set_buttons(false, false)
		if _mode == "progress":
			l.world_id = "dofus"
			l.total_bytes = 310_000_000
			l.done_bytes = 118_000_000
			l.total_files = 412
			l.done_files = 160
			l.started_ms = Time.get_ticks_msec() - 20000
			l.phase = "files"
			_screen._busy_label = "install"
			_screen._bar.visible = true
			_screen._show_progress()
			_screen._set_buttons(true)
			for row in _screen._rows.get_children():
				row.visible = str(row.get_meta("world", "")) == "dofus"
		return false
	if _t > _done_at + 1.0:
		root.get_texture().get_image().save_png(_out)
		print("saved ", _out)
		return true
	return false
