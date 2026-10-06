## Screenshot of the launch screen (windowed, needs a GPU), optionally after typing an
## address and pressing "Rejoindre" (e.g. a dead port: the message is shown).
##   godot --path game -s res://tools/launch_shot.gd -- --out=l.png --seconds=2 [--address=127.0.0.1:1] [--login=jean --password=secret1 [--register=1]] [--pick=<world id>] [--shot1=<s>|<png>] [--slow=1]
## After the login the loading screen (C.03) lists the worlds; --pick clicks one at 1 s after it appeared;
## --slow throttles the download (progress bar visible); --shot1 saves an extra capture at that time.
extends SceneTree

var _launch: LaunchScreen
var _opts := {"out": "launch.png", "seconds": "2", "address": "", "world": "", "login": "", "password": "", "register": "", "pick": "", "shot1": "", "slow": ""}
var _t := 0.0
var _joined := false
var _picked := false
var _pick_at := 0.0
var _shot1_done := false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		if kv.size() == 2:
			_opts[kv[0]] = kv[1]
	UiWindow.reset_layout()
	_launch = (load("res://scenes/client/launch.tscn") as PackedScene).instantiate()
	root.add_child(_launch)


func _process(delta: float) -> bool:
	_t += delta
	if not _joined and _opts["address"] != "" and _t > 0.3:
		_joined = true
		_launch._address.text = _opts["address"]
		if _opts["slow"] != "":
			WorldLoadScreen.throttle_chunks = 1
			WorldLoadScreen.throttle_delay_ms = 60
		_launch._login.text = _opts["login"]
		_launch._password.text = _opts["password"]
		_launch._join_server(_opts["register"] != "")
	var loading: WorldLoadScreen = _launch._loading if is_instance_valid(_launch) else null
	if loading != null and _opts["pick"] != "" and loading.loader.worlds.size() > 0 and not _picked:
		_pick_at = _pick_at if _pick_at > 0.0 else _t + 1.0
		if _t >= _pick_at:
			_picked = true
			loading.pick(_opts["pick"])
	if _opts["shot1"] != "" and not _shot1_done and _t >= float(str(_opts["shot1"]).get_slice("|", 0)):
		_shot1_done = true
		root.get_texture().get_image().save_png(str(_opts["shot1"]).get_slice("|", 1))
	if _t >= float(_opts["seconds"]):
		root.get_texture().get_image().save_png(_opts["out"])
		print("saved ", _opts["out"], " (", _launch._status.text if is_instance_valid(_launch) else "game started", ")")
		return true
	return false
