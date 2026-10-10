## Mesure du telechargement d'un monde depuis un serveur local (C.07) : liste, release, plan, premier octet, fin.
##   godot --headless --path game -s res://tools/bench_download.gd -- --game-port=7791 --port=7792 --world=incarnam [--keep=1] [--zones=N]
## --keep=1 garde le cache (une 2e execution mesure « rien a faire ») ; --zones=N installe ensuite N zones.
extends SceneTree


func _init() -> void:
	var opts := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() == 2 else "1"
	var world := str(opts.get("world", "incarnam"))
	var dir := ProjectSettings.globalize_path("user://bench_" + world)
	if not opts.has("keep"):
		ContentFolder.remove_dir(dir)
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
	var listed := cc.list_worlds()
	var release := ""
	for w: Dictionary in listed.worlds:
		if str(w["id"]) == world:
			release = str(w.get("release", ""))
	print("list: %d ms, release %s, installed %s" % [Time.get_ticks_msec() - t0, release, ContentClient.installed_release(dir)])
	t0 = Time.get_ticks_msec()
	var rel := cc.fetch_release(world, release)
	print("release: ok=%s %d ms, %d zones" % [rel.ok, Time.get_ticks_msec() - t0, rel.release.get("zones", {}).size()])
	if not rel.ok:
		quit(1)
		return
	t0 = Time.get_ticks_msec()
	var plan := cc.plan_install(world, release, rel.release, [ContentRelease.BASE], dir)
	print("plan: ok=%s %d ms, %d files, %.1f MB in %d requests" % [plan.ok, Time.get_ticks_msec() - t0, plan["files"],
			int(plan["bytes"]) / 1048576.0, (plan["ranges"] as Array).size()])
	var first := [-1]
	t0 = Time.get_ticks_msec()
	cc.progress = func(done: int, _total: int, _p: String) -> void:
		if first[0] < 0 and done > 0:
			first[0] = Time.get_ticks_msec() - t0
	var r := cc.install(plan)
	var ms := maxi(1, Time.get_ticks_msec() - t0)
	print("install: ok=%s %s first byte %d ms, %d files %.1f MB in %d ms = %.1f MB/s, %.0f files/s" % [r.ok, r.error, first[0],
			r.files, int(r.bytes) / 1048576.0, ms, int(r.bytes) / 1048576.0 * 1000.0 / ms, int(r.files) * 1000.0 / ms])
	var n := int(opts.get("zones", 0))
	if n > 0:
		var ids: Array = rel.release["zones"].keys()
		ids.sort()
		t0 = Time.get_ticks_msec()
		var bytes := 0
		for z: String in ids.slice(0, n):
			var p := cc.plan_install(world, release, rel.release, [z], dir)
			var zr := cc.install(p)
			bytes += int(zr.bytes)
		print("zones: %d in %d ms, %.1f MB" % [mini(n, ids.size()), Time.get_ticks_msec() - t0, bytes / 1048576.0])
	quit(0)
