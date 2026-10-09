## Mesure du telechargement d'un monde depuis un serveur local (--no-auth) :
##   godot --headless --path game -s res://tools/bench_download.gd -- --port=7792 --world=incarnam --mode=files|bundle [--limit=500]
extends SceneTree


func _init() -> void:
	var opts := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() == 2 else "1"
	var world := str(opts.get("world", "incarnam"))
	var dir := ProjectSettings.globalize_path("user://bench_" + world)
	var net := NetBackend.new()
	net.connect_to("127.0.0.1:%d" % int(opts.get("game-port", 7791)))
	var login := "bench%d" % (Time.get_ticks_msec() % 100000)
	var sent := false
	for _i in 600:
		net.poll(0.0)
		if net.state == "open" and not sent:
			sent = true
			net.send(Protocol.register(login, "secret123"))
		if net.token != "":
			break
		OS.delay_msec(10)
	print("token: ", net.token != "")
	var cc := ContentClient.new("127.0.0.1", int(opts.get("port", 7792)), net.token)
	var t0 := Time.get_ticks_msec()
	var m := cc.fetch_manifest(world)
	print("manifest: ok=%s %d ms, %d files" % [m.ok, Time.get_ticks_msec() - t0, m.manifest.get("files", []).size()])
	if not m.ok:
		quit(1)
		return
	var missing := cc.diff(m.manifest, dir)
	if str(opts.get("mode", "files")) == "bundle":
		t0 = Time.get_ticks_msec()
		cc.phase_changed = func(phase: String, bytes: int, parts: int) -> void:
			print("  phase %s at %d ms (%d MB, %d parts)" % [phase, Time.get_ticks_msec() - t0, bytes / 1048576, parts])
		var r := cc.install_bundle(m.manifest, dir, missing)
		print("bundle: %s used=%s %d MB zip, %d files, %d ms" % [r.ok, r.used, r.bytes / 1048576, r.files, Time.get_ticks_msec() - t0])
	else:
		var limit := int(opts.get("limit", 500))
		var part := missing.slice(0, limit)
		var bytes := 0
		for f: Dictionary in part:
			bytes += int(f["size"])
		t0 = Time.get_ticks_msec()
		var r := cc.download(m.manifest, dir, part, false)
		var ms := maxi(1, Time.get_ticks_msec() - t0)
		print("error: ", r.get("error"))
		print("files: %s %d files %.1f MB in %d ms = %.1f files/s, %.1f MB/s" % [r.ok, part.size(), bytes / 1048576.0, ms,
				part.size() * 1000.0 / ms, bytes / 1048576.0 * 1000.0 / ms])
	quit(0)
