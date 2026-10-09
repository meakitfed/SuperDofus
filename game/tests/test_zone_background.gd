## Whole world in the background (roadmap C.02f): with the player's option on, ZoneGate installs every zone of
## the index when nothing is asked for, one at a time; a zone the player waits for goes first. Fixture world
## "zx" (ZonesRig) served by a ServerHost on 127.0.0.1.
extends ZonesRig


## A gate on the fixture with the base installed and the index loaded (the zones all missing).
func _ready_gate(rig: Rig, threaded := false) -> ZoneGate:
	var token := _login(rig)
	var dir := ProjectSettings.globalize_path(BASE).path_join("cache/zx")
	var base := rig.client()
	base.token = token
	check(base.update("zx", dir).ok, "base")
	var g: ZoneGate
	if threaded:
		g = ZoneGate.new(ZoneStreamer.new(ContentClient.new("127.0.0.1", rig.host.http_port(), token), "zx", dir))
	else:
		g = _gate(rig, dir, token)
	return g


func test_the_background_is_off_by_default() -> void:
	_zoned()
	var rig := Rig.new([_build()])
	var g := _ready_gate(rig)
	g.start()
	g.run_all()
	check(g.streamer.installed.is_empty(), "nothing is downloaded unless the player asks for it")
	eq(g.background_line(), "")
	_end(rig)


func test_the_background_installs_every_zone() -> void:
	_zoned()
	var rig := Rig.new([_build()])
	var g := _ready_gate(rig)
	g.set_background(true)
	g.start()
	g.run_all()
	var ids: Array = (g.streamer.index["zones"] as Dictionary).keys()
	for z: String in ids:
		check(g.streamer.installed.has(z), "zone %s installed" % z)
	eq(g.bg_done, ids.size(), "the progress line counts them")
	g.run_all()
	eq(g.bg_done, g.bg_total)
	eq(g.background_line(), "", "nothing left: the line disappears")
	check(FileAccess.file_exists(g.streamer.cache_dir.path_join("content/Content/Maps/3.json")), "the files are in the cache")
	_end(rig)


func test_a_zone_asked_for_goes_before_the_background() -> void:
	_zoned()
	var rig := Rig.new([_build()])
	var g := _ready_gate(rig)
	g.start()
	g.run_all() # the index only
	var order: Array = []
	g.streamer.on_zone = func(zone: String, phase: String) -> void:
		if phase == "start":
			order.append(zone)
	g.set_background(true)
	check(not g.admit(_enter(3)), "zone 20 is held")
	g.run_all()
	eq(order[0], "20", "the zone the player waits for comes first (the background would start with 10)")
	check(order.size() > 1, "then the background goes on")
	check(g.streamer.installed.has("30"), "the others follow")
	_end(rig)


func test_the_pause_stops_the_background() -> void:
	_zoned()
	var rig := Rig.new([_build()])
	var g := _ready_gate(rig)
	g.set_background(true)
	g.pause_background(true)
	g.start()
	g.run_all()
	check(g.streamer.installed.is_empty(), "paused: no zone")
	eq(g.background_line(), "")
	g.pause_background(false)
	g.run_all()
	check(not g.streamer.installed.is_empty(), "resumed")
	_end(rig)


func test_the_background_runs_in_the_worker_thread() -> void:
	_zoned()
	var rig := Rig.new([_build()])
	var g := _ready_gate(rig, true)
	g.set_background(true)
	g.start()
	var spins := 0
	while spins < 4000 and not (g.bg_total > 0 and g.bg_done == g.bg_total):
		rig.pump() # the server answers while the worker waits
		g._process(0.0)
		spins += 1
	check(spins < 4000, "every zone arrived through the thread")
	check(not g.waiting(), "the player never waited")
	check(not g.streamer.client.cancel_requested, "nothing left cut")
	g._exit_tree()
	_end(rig)
