## The headless game server (roadmap S.01):
##   godot --headless --path game -s res://src/server/main.gd -- --server --port=7777 \
##         --world=dofus[,incarnam] --save-dir=C:/SuperDofus/saves
## (main.gd adds this node to a SceneTree; an exported server ignores -s and opens
## scenes/server/server.tscn instead, chosen by override.cfg beside the exe: tools/build_release.py)
## Players join with the client ("Serveur" on the launch screen) at <ip>:<port>.
## Options (all after the `--`):
##   --port=7777         WebSocket game API
##   --bind=*            interface to listen on ("*" = all; a Hamachi address limits it to the VPN)
##   --world=a,b         worlds served (default: dofus); a missing world stops the start
##   --save-dir=<dir>    characters (default: user://server_saves)
##   --autosave=<min>    save every connected character this often (default 5, 0 = only on leaving/stop)
##   --backups=<n>       copies kept per saved document in <save-dir>/_backups (default 10, 0 = none)
##   --backup-interval=<min>  minimum time between two copies of one document (default 5)
##   --gm=<login>        accounts with the GM role (default: none; a role can also be set in accounts/<login>.json)
##   --audit-log=<file>  audit trail of the GM commands, one JSON line each (default: <save-dir>/admin_audit.jsonl)
##   --no-register       do not create accounts any more (the accounts that exist can log in)
##   --no-auth           open server, NO login (the account is the address): tools and tests only
##   --seconds=N         stop after N seconds (scripts, tests)
##   --http-in-tick      serve the content API from the game loop (30 FPS) instead of its own thread (tests, comparisons)
##   --http-port=7778    content API (HTTP, session token required); absent = no content API
##   --admin-token=<secret> enables the admin web /admin and its JSON routes (Bearer token; or env SUPERDOFUS_ADMIN_TOKEN); needs --http-port
##   --package-dir=<dir> the PUBLISHED content (C.07, ContentStore: worlds.json, releases, manifests, bundles),
##                       served as static files (default: user://packages). The server never computes it: a world
##                       that was not published is listed "unpublished" until the publication runs
##   --content-root=<d>  folder holding worlds/, data/, content/ (default: the project folder)
##   --build-packages    PUBLISH the content of the served worlds (ContentPublisher: hash, bundles, manifests, release,
##                       pointer last; incremental and resumable), print the result and exit
##   --rebuild           ignore the hash cache when publishing
##   --bundle-mb=N, --keep-versions=N   publication options (docs/EXPORT.md)
##   --check             verify worlds, folders, save dir, packages and free ports, then exit (code 1 on a FAIL)
## An exported server (X.01) has no worlds/data/content in its PCK: they sit beside the
## executable, which is the default --content-root there.
## Clean stop (Ctrl+C / closing the window): characters are saved. They are also
## saved each time a player leaves.
class_name ServerApp
extends Node

const DEFAULT_PORT := 7777
const FPS := 30

var _host: ServerHost
var _stop_at_ms := 0
var _opts := {}


func _ready() -> void:
	_opts = _parse(OS.get_cmdline_user_args())
	ContentSource.set_dev_root(_content_root())
	Engine.max_fps = FPS # a headless loop would otherwise spin one core at 100 %
	get_tree().auto_accept_quit = false # a close request saves the characters first (_notification)
	_host = ServerHost.new()
	var save_dir := str(_opts.get("save-dir", "user://server_saves"))
	var store_p := ServerPersistence.new(save_dir)
	store_p.keep = int(_opts.get("backups", store_p.keep))
	store_p.backup_interval_ms = int(float(_opts.get("backup-interval", 5)) * 60000.0)
	var swept := store_p.sweep_tmp()
	if swept > 0:
		print("server: %d unfinished write(s) from a previous crash discarded" % swept)
	_host.server.persistence = store_p
	_host.autosave_ms = int(float(_opts.get("autosave", 5)) * 60000.0)
	_host.server.clock = SystemClock.new()
	if not _opts.has("no-auth"):
		var store := AccountStore.new(_host.server.persistence)
		store.registration_open = not _opts.has("no-register")
		_host.auth = AuthService.new(store)
	_host.set_audit_log(AuditLog.new(str(_opts.get("audit-log", save_dir.path_join("admin_audit.jsonl")))))
	_host.gm_accounts = PackedStringArray(str(_opts.get("gm", "")).split(",", false))
	var worlds := PackedStringArray(str(_opts.get("world", "dofus")).split(",", false))
	if _opts.has("check"):
		var http_p := int(_opts.get("http-port", 0))
		var report := ServerCheck.run(worlds, _content_root(), _package_dir(), _save_dir(),
				int(_opts.get("port", DEFAULT_PORT)), http_p)
		for line in report["lines"]:
			print("check: " + line)
		print("check: " + ("tout est pret" if report["ok"] else "des problemes bloquent le demarrage"))
		get_tree().quit(0 if report["ok"] else 1)
		return
	if _opts.has("build-packages"): # the build step: no world is opened
		var published := _publish(worlds)
		get_tree().quit(0 if published else 1)
		return
	var t0 := Time.get_ticks_msec()
	var missing := _host.preload_worlds(worlds)
	if not missing.is_empty():
		push_error("server: unknown world(s): " + ", ".join(missing))
		get_tree().quit(1)
		return
	print("server: worlds opened in %d ms" % (Time.get_ticks_msec() - t0))
	if _opts.has("http-port"):
		var http_port := int(_opts["http-port"])
		_host.package_dir = _package_dir()
		if _host.listen_http(http_port, str(_opts.get("bind", "*")), not _opts.has("http-in-tick")) != OK:
			push_error("server: cannot listen on HTTP port %d" % http_port)
			get_tree().quit(1)
			return
		_host.admin.token = str(_opts.get("admin-token", OS.get_environment("SUPERDOFUS_ADMIN_TOKEN")))
		print("server: content API on port %d, published content in %s" % [_host.http_port(), _package_dir()])
		for id in worlds:
			var why := ContentStore.check(_package_dir(), id) # one stat: the server reads nothing else of the content
			print("server: " + (why if why != "" else "monde %s publie (release %s)" % [id, ContentStore.pointer(_package_dir(), id)["release"]]))
	_host.cluster.instances_path = save_dir.path_join("instances.json") # S.04b: reopen the instances
	var reopened := _host.cluster.restore()
	if reopened > 0:
		print("server: %d instance(s) reopened" % reopened)
	var port := int(_opts.get("port", DEFAULT_PORT))
	var err := _host.listen(port, str(_opts.get("bind", "*")))
	if err != OK:
		push_error("server: cannot listen on port %d (%s)" % [port, error_string(err)])
		get_tree().quit(1)
		return
	if _opts.has("seconds"):
		_stop_at_ms = Time.get_ticks_msec() + int(float(_opts["seconds"]) * 1000.0)
	print("server: worlds %s on port %d, saves in %s" % [", ".join(worlds), _host.local_port(), save_dir])


## Publishes the content of every served world (the explicit build step); false on the first failure.
func _publish(worlds: PackedStringArray) -> bool:
	var log := func(line: String) -> void:
		print("publish: " + line)
	for id in worlds:
		var r := ContentPublisher.publish(id, _content_root(), _package_dir(), {"rebuild": _opts.has("rebuild"),
				"bundle_mb": float(_opts.get("bundle-mb", 32)),
				"keep": int(_opts.get("keep-versions", ContentPublisher.KEEP_VERSIONS)), "log": log})
		if not r.ok:
			push_error("server: publication %s: %s" % [id, r.error])
			return false
		print("publish: %s release %s: %d files (%d hashed, %d from the cache), %d zones, %d bundles written (%.1f MB), %s, %.1f s" % [id,
				r.release, r.built.manifest["files"].size(), r.hashed, r.reused, r.zones, r.bundles_written,
				r.bytes_written / 1048576.0, "unchanged" if r.unchanged else "new", r.seconds])
	return true


## Folder holding worlds/, data/, content/: --content-root, else beside the executable of an
## exported server, else the project folder.
func _content_root() -> String:
	if _opts.has("content-root"):
		return str(_opts["content-root"]).replace("\\", "/").trim_suffix("/")
	if OS.has_feature("template"):
		return OS.get_executable_path().get_base_dir().replace("\\", "/")
	return ProjectSettings.globalize_path("res://").trim_suffix("/")


func _package_dir() -> String:
	return ProjectSettings.globalize_path(str(_opts.get("package-dir", "user://packages")))


func _save_dir() -> String:
	return str(_opts.get("save-dir", "user://server_saves"))


func _process(delta: float) -> void:
	if _host == null:
		return
	_host.poll(delta)
	if _stop_at_ms > 0 and Time.get_ticks_msec() >= _stop_at_ms:
		_stop()
		get_tree().quit()


func _notification(what: int) -> void:
	if what == Node.NOTIFICATION_WM_CLOSE_REQUEST:
		_stop()
		get_tree().quit()


func _stop() -> void:
	if _host != null:
		_host.shutdown()
		_host = null
		print("server: stopped, characters saved")


static func _parse(args: PackedStringArray) -> Dictionary:
	var out := {}
	for arg in args:
		if not arg.begins_with("--"):
			continue
		var kv := arg.trim_prefix("--").split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() == 2 else "1"
	return out
