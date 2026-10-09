## Interroge /worlds d'un serveur local toutes les 500 ms et affiche l'etat de chaque monde (demarrage instantane) :
##   godot --headless --path game -s res://tools/probe_worlds.gd -- --game-port=7791 --port=7792 --seconds=60
extends SceneTree


func _init() -> void:
	var opts := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() == 2 else "1"
	var net := NetBackend.new()
	net.connect_to("127.0.0.1:%d" % int(opts.get("game-port", 7791)))
	var login := "probe%d" % (Time.get_ticks_msec() % 100000)
	var sent := false
	var t0 := Time.get_ticks_msec()
	for _i in 2000:
		net.poll(0.0)
		if net.state == "open" and not sent:
			sent = true
			net.send(Protocol.register(login, "secret123"))
		if net.token != "":
			break
		OS.delay_msec(10)
	print("PROBE login after %d ms: %s" % [Time.get_ticks_msec() - t0, net.token != ""])
	var cc := ContentClient.new("127.0.0.1", int(opts.get("port", 7792)), net.token)
	var end := Time.get_ticks_msec() + int(float(opts.get("seconds", 60)) * 1000.0)
	var last := ""
	while Time.get_ticks_msec() < end:
		var tl := Time.get_ticks_msec()
		var r := cc.list_worlds()
		var line := ""
		for w: Dictionary in r.worlds:
			line += "%s=%s%s " % [w["id"], w.get("state", "?"), (" (" + str(w.get("note", "")).substr(0, 50) + ")") if str(w.get("note", "")) != "" else ""]
		if line != last:
			print("PROBE +%d ms (list took %d ms): %s" % [Time.get_ticks_msec() - t0, Time.get_ticks_msec() - tl, line])
			last = line
			if not line.contains("preparing") and not line.contains("publishing") and not line.contains("queued") and not line.contains("loading") and line != "":
				break
		OS.delay_msec(500)
	quit(0)
