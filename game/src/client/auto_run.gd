## Scripted start of the client (roadmap X.01), for the exported executable which cannot run
## tools/launch_shot.gd: connects, logs in, picks a world, saves a capture and quits.
##   SuperDofus.exe -- --auto-connect=127.0.0.1:7777 --login=ami --password=secret1 --register=1 \
##       --pick=test --character=Eli --auto-shot=out.png --auto-seconds=15
## --character creates (if needed) and plays that character once the selection screen shows.
## --attack-at=<s> (seconds after the start) attacks the nearest monster group, --ready-at=<s> is ready in the placement:
## a real fight through the whole launch path (loading screen, zone gate, cache content).
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
var _attacked := false
var _readied := false


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
	_drive_fight()
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


func _session() -> ClientSession:
	for child in get_tree().root.get_children():
		if child is ClientSession:
			return child
	return null


func _drive_fight() -> void:
	var client := _session()
	if client == null or client.backend == null:
		return
	if opts.has("attack-at") and not _attacked and _t >= float(opts["attack-at"]):
		var me: Vector2 = client.views[client.you].position if client.views.has(client.you) else Vector2.ZERO
		var best := -1
		for id: int in client.views:
			if client.views[id] is GroupView and (best < 0 or me.distance_to(client.views[id].position) < me.distance_to(client.views[best].position)):
				best = id
		if best >= 0:
			_attacked = true
			client.backend.send(Protocol.fight_attack(best))
	if opts.has("ready-at") and not _readied and client.fight != null and _t >= float(opts["ready-at"]):
		_readied = true
		client.backend.send(Protocol.fight_ready())
