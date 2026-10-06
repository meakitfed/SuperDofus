## Scripted start of the client (roadmap X.01), for the exported executable which cannot run
## tools/launch_shot.gd: connects, logs in, picks a world, saves a capture and quits.
##   SuperDofus.exe -- --auto-connect=127.0.0.1:7777 --login=ami --password=secret1 --register=1 \
##       --pick=test --character=Eli --auto-shot=out.png --auto-seconds=15
## --character creates (if needed) and plays that character once the selection screen shows.
## Only started by LaunchScreen when --auto-connect is on the command line; nothing here
## knows the game.
class_name AutoRun
extends Node

var launch: LaunchScreen
var opts := {}
var _t := 0.0
var _joined := false
var _picked := false
var _pick_at := 0.0
var _done := false
var _char_step := 0
var _char_at := 0.0


static func options() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() == 2 else "1"
	return out


func _process(delta: float) -> void:
	_t += delta
	if _done:
		return
	if not _joined and _t > 0.3 and is_instance_valid(launch):
		_joined = true
		launch.drive_connect(str(opts["auto-connect"]), str(opts.get("login", "")),
				str(opts.get("password", "")), opts.has("register"))
	var loading: WorldLoadScreen = launch._loading if is_instance_valid(launch) else null
	if loading != null and opts.has("pick") and not _picked and loading.loader.worlds.size() > 0:
		_pick_at = _pick_at if _pick_at > 0.0 else _t + 1.0
		if _t >= _pick_at:
			_picked = true
			loading.pick(str(opts["pick"]))
	_drive_character()
	if _t >= float(opts.get("auto-seconds", "15")):
		_done = true
		if opts.has("auto-shot"):
			var path := str(opts["auto-shot"])
			get_viewport().get_texture().get_image().save_png(path)
			print("auto: saved ", path)
		get_tree().quit()


## create_character, then select_character 1.5 s later, on the ClientSession the game started.
func _drive_character() -> void:
	if not opts.has("character") or _char_step >= 2:
		return
	var client: ClientSession = null
	for child in get_tree().root.get_children():
		if child is ClientSession:
			client = child
	if client == null or client.character_select == null or client.backend == null:
		return
	if _char_step == 0:
		client.backend.send(Protocol.create_character(str(opts["character"])))
		_char_at = _t + 1.5
		_char_step = 1
	elif _t >= _char_at:
		client.backend.send(Protocol.select_character(str(opts["character"])))
		_char_step = 2
