## Zones of a big world (roadmap C.02c): WorldAssets splits the assets of a fixture world by sub-area
## (base = what every client needs plus the start zone, then one list per zone), WorldPackage builds a
## base manifest and one manifest per zone, the content API serves them (token, whitelist), and a client
## that logs in over a WebSocket on 127.0.0.1 downloads the base, then a zone only when it walks to it
## (ZoneStreamer), reusing the files the zones share. Fixture under user://test_zones/.
extends ZonesRig


func test_assets_split_by_zone() -> void:
	var z := _zoned()
	var base: PackedStringArray = z["base"]
	eq(z["start_zone"], "10", "the zone of start_map")
	for g in [CONTENT + "/Maps/1.json", CONTENT + "/Maps/2.json", CONTENT + "/Maps/Gfx/100.png", CONTENT + "/Maps/Gfx/101.png",
			CONTENT + "/Characters/Bones/666/*", CONTENT + "/Characters/Bones/1/*", CONTENT + "/Fonts/*", CONTENT + "/UI/*"]:
		check(base.has(g), "base: " + g)
	for g in [CONTENT + "/Maps/3.json", CONTENT + "/Maps/Gfx/102.png", CONTENT + "/Characters/Bones/20/*", CONTENT + "/Maps/Gfx/103.png"]:
		check(not base.has(g), "not in the base: " + g)
	eq((z["zones"] as Dictionary).keys().size(), 5, "three zones of maps, the zone of the class and the equipment")
	eq(z["zones"]["20"]["maps"], [3], "the maps of a zone")
	var z20 := _zone_files(z, "20")
	check(z20.has(CONTENT + "/Maps/3.json") and z20.has(CONTENT + "/Maps/Gfx/102.png"), "zone 20: its map and texture")
	check(not z20.has(CONTENT + "/Maps/Gfx/101.png"), "a texture the base holds is not repeated in a zone")
	check((z["zones"]["20"]["dirs"] as Array).has(CONTENT + "/Characters/Bones/20/*"), "zone 20: the monster that lives there")
	check((z["zones"]["20"]["dirs"] as Array).has(CONTENT + "/Characters/Skins/70/*"), "zone 20: the skin of what the monster drops")
	check((z["zones"]["equipment"]["dirs"] as Array).has(CONTENT + "/Characters/Skins/80/*") and not base.has(CONTENT + "/Characters/Skins/80/*"), "the skin of a shop item is in the equipment zone, not in the base")
	check(not (z["zones"]["equipment"]["dirs"] as Array).has(CONTENT + "/Characters/Skins/70/*"), "what a monster drops stays in its zone")
	eq(z["zones"]["equipment"]["skins"], [80], "the equipment zone lists its skins")
	var z30 := _zone_files(z, "30")
	check(z30.has(CONTENT + "/Maps/Gfx/102.png") and z30.has(CONTENT + "/Maps/Gfx/103.png"), "zone 30 lists 102, which zone 20 lists too")
	check((z["zones"]["30"]["dirs"] as Array).has(CONTENT + "/Characters/Bones/40/*"), "zone 30: the NPC standing on its map")
	eq(_zone_files(z, "10"), [], "the start zone adds nothing: it is in the base")
	check(int(z["zones"]["20"]["bytes"]) > 0, "a zone knows its size")
	var plain := WorldAssets.new(_root, "plain")
	check(plain.compute_zoned().is_empty(), "no zone_key: not zoned")


func test_package_base_and_zone_manifests() -> void:
	_zoned()
	var b := _build()
	check(b.ok, b.error)
	var base := _paths(b.manifest)
	check(base.has(CONTENT + "/Maps/1.json") and base.has("worlds/zx/world.json") and base.has("data/items.json"), "the base ships")
	check(not base.has(CONTENT + "/Characters/Skins/10/skin.json"), "the skins of a class are not in the base")
	check(not base.has(CONTENT + "/Maps/3.json") and not base.has(CONTENT + "/Maps/Gfx/102.png"), "no zone file in the base")
	check(not base.has("worlds/zx/maps/1.json"), "server_only: the sim maps never reach a client")
	eq(b.zones.keys().size(), 5, "a manifest per zone")
	var m20: Dictionary = b.zones["20"]
	eq(ContentManifest.validate(m20), "", "a zone manifest is an ordinary manifest")
	eq(m20["zone"], "20")
	check(_paths(m20).has(CONTENT + "/Characters/Bones/20/bone.json"), "a folder glob of a zone is walked")
	check(not m20.has("maps"), "the maps are in the index, not in each manifest")
	eq(ContentZones.validate(b.zone_index), "", "the index is valid")
	eq(ContentZones.lookup(b.zone_index)[3], "20", "map -> zone")
	eq(b.zone_index["start_zone"], "10")
	for h: String in ContentManifest.unique_blobs(m20["files"]):
		check(b.blobs.has(h), "the bytes of a zone file are served by hash")
	var again := _build(false)
	eq(again.hashed, 0, "a second build hashes nothing")
	eq(again.zone_index["version"], b.zone_index["version"], "same files, same zones version")
	_write(CONTENT + "/Maps/Gfx/103.png", PackedByteArray([1, 2, 3, 4, 5]))
	var changed := _build(false)
	check(changed.zone_index["zones"]["30"]["version"] != b.zone_index["zones"]["30"]["version"], "one changed file: the zone version changes")
	eq(changed.zone_index["zones"]["20"]["version"], b.zone_index["zones"]["20"]["version"], "the other zones keep theirs")
	eq(changed.manifest["version"], b.manifest["version"], "the base is not concerned")


func test_index_validation() -> void:
	var m := ContentManifest.make("zx", "Z", "", [])
	m["maps"] = [1, 2]
	var idx := ContentZones.make_index("zx", "a", {"a": m})
	eq(ContentZones.validate(idx), "")
	var bad := idx.duplicate(true)
	bad["zones"]["a"]["version"] = "x"
	check(ContentZones.validate(bad) != "", "a version that does not match")
	bad = idx.duplicate(true)
	bad["zones"]["../b"] = bad["zones"]["a"]
	check(ContentZones.validate(bad) != "", "a zone id is never a path")
	var two := {"a": m, "b": m.duplicate(true)}
	check(ContentZones.validate(ContentZones.make_index("zx", "a", two)) != "", "a map in two zones")
	check(ContentZones.validate({"format": 2}) != "", "unknown format")
	check(not ContentZones.is_zone_id("a/b") and not ContentZones.is_zone_id("") and ContentZones.is_zone_id("12-a_B"), "zone ids")


func test_api_routes() -> void:
	_zoned()
	var rig := Rig.new([_build(), WorldPackage.build("plain", _root, _store, true)])
	var token := _login(rig)
	check(token != "", "login_ok gave a token over the WebSocket")
	var cc := rig.client()
	cc.token = token
	var list := cc.list_worlds().worlds as Array
	var zx: Dictionary = list.filter(func(w: Dictionary) -> bool: return w["id"] == "zx")[0]
	eq(int(zx["zones"]), 5, "the world list tells there are zones")
	check(int(zx["zones_size"]) > 0 and int(zx["size"]) > 0, "base size and zones size")
	var rel := cc.fetch_release("zx", str(zx["release"]))
	check(rel.ok, rel.error)
	eq(ContentRelease.zone_lookup(rel.release)[4], "30")
	var dir := ProjectSettings.globalize_path(BASE).path_join("cache/routes")
	var m := cc.fetch_fragment(ContentRelease.fragment_hash(rel.release, "30"), dir)
	check(m.ok, m.error)
	eq(m.manifest["frag"], "30")
	var plain: Dictionary = list.filter(func(w: Dictionary) -> bool: return w["id"] == "plain")[0]
	eq((cc.fetch_release("plain", str(plain["release"])).release["zones"] as Dictionary).size(), 0, "a world that is not zoned has no zone")
	eq(cc.fetch_release("nope", str(zx["release"])).status, 404, "unknown world")
	check(not cc.fetch_release("zx", "../x").ok, "a release id that is a path is refused before any request")
	var anon := ContentClient.new("127.0.0.1", rig.host.http_port(), "")
	anon.pump = rig.pump
	eq(anon.fetch_release("zx", str(zx["release"])).status, 401, "no token, no release")
	eq(anon.fetch_fragment(ContentRelease.fragment_hash(rel.release, "20"), dir.path_join("anon")).status, 401, "no token, no zone manifest")
	_end(rig)


func test_client_downloads_a_zone_when_it_walks_to_it() -> void:
	_zoned()
	var rig := Rig.new([_build()])
	var cc := rig.client()
	cc.token = _login(rig)
	var cache := ProjectSettings.globalize_path(BASE).path_join("cache")
	var dir := cache.path_join("zx")
	var r := cc.update("zx", dir) # the base: C.03
	check(r.ok, r.error)
	check(FileAccess.file_exists(dir.path_join("content/Content/Maps/1.json")), "the start zone came with the base")
	check(not FileAccess.file_exists(dir.path_join("content/Content/Maps/3.json")), "the other zones did not")
	var zs := ZoneStreamer.new(cc, "zx", dir)
	var events: Array = []
	zs.on_zone = func(zone: String, phase: String) -> void: events.append(zone + ":" + phase)
	var li := zs.load_index()
	check(li.ok and li.zoned, "the world is zoned (from the release kept with the base: no request)")
	eq(zs.zone_of(3), "20")
	check(zs.is_ready(1) == false, "nothing installed yet, even the start zone's turn")
	eq(zs.zones_to_fetch(3, [4, 3, 2]), PackedStringArray(["20", "30", "10"]), "own zone first, then the neighbours, once each")
	check(zs.size_of("20") > 0, "size of a zone")
	var e := zs.ensure(3)
	check(e.ok, e.error)
	check(not e.already and e.files > 0 and e.bytes > 0, "zone 20 downloaded")
	check(FileAccess.file_exists(dir.path_join("content/Content/Maps/3.json")), "its map is in the cache")
	check(FileAccess.file_exists(dir.path_join("content/Content/Maps/Gfx/102.png")), "its texture too")
	check(FileAccess.file_exists(dir.path_join("content/Content/Characters/Bones/20/bone.json")), "and the monster that lives there")
	eq(events, ["20:start", "20:done"])
	check(zs.is_ready(3), "ready now")
	var again := zs.ensure(3)
	check(again.ok and again.already and again.files == 0, "a zone is installed once")
	eq(events.size(), 2, "no request for it")
	check(ContentClient.fragment_installed(dir, zs.index, "20"), "the cache remembers it")
	# the shared texture (102) is not downloaded again for zone 30
	var plan30 := cc.plan_install("zx", zs.release, zs.index, ["30"], dir)
	var planned: Array = []
	for rg: Dictionary in plan30["ranges"]:
		for f: Dictionary in rg["files"]:
			planned.append_array(f["paths"])
	planned.sort()
	eq(planned, [CONTENT + "/Characters/Bones/40/bone.json", CONTENT + "/Characters/Skins/50/skin.json", CONTENT + "/Maps/4.json",
			CONTENT + "/Maps/Gfx/103.png"], "zone 30 asks only for what the cache lacks (102 came with zone 20)")
	var p := zs.prefetch([4])
	check(p.ok, p.error)
	eq(p.zones, ["30"], "the neighbour's zone was prefetched")
	check(FileAccess.file_exists(dir.path_join("content/Content/Maps/Gfx/103.png")), "zone 30 files")
	# a new session: the cache holds the zones, nothing is asked
	var zs2 := ZoneStreamer.new(cc, "zx", dir)
	zs2.load_index()
	var back := zs2.ensure(3)
	check(back.ok and back.already and back.bytes == 0, "a new session finds the zone in the cache")
	# the server publishes a new release (a texture of zone 30 changed): the update fetches that file only
	_end(rig)
	_write(CONTENT + "/Maps/Gfx/103.png", PackedByteArray([9, 9, 9, 9, 9, 9, 9]))
	var rig2 := Rig.new([_build(false)])
	var cc2 := rig2.client()
	cc2.token = _login(rig2)
	var up := cc2.update("zx", dir)
	check(up.ok, up.error)
	eq(int(up.files), 1, "one changed file downloaded, for the base and the installed zones")
	eq(FileAccess.get_file_as_bytes(dir.path_join("content/Content/Maps/Gfx/103.png")).size(), 7, "the new version is in the cache")
	var zs3 := ZoneStreamer.new(cc2, "zx", dir)
	zs3.load_index()
	check(zs3.is_ready(4) and zs3.is_ready(3), "the installed zones followed the release")
	# what the renderer reads comes from the cache
	ContentSource.use_world("zx", cache)
	var provider := ContentSourceProvider.new()
	check(provider.exists("Content/Maps/3.json") and provider.exists("Content/Maps/4.json"), "the zones are readable through the provider")
	ContentSource.use_dev()
	_end(rig2)


func test_a_world_without_zones_streams_nothing() -> void:
	_zoned()
	var rig := Rig.new([WorldPackage.build("plain", _root, _store, true)])
	var cc := rig.client()
	cc.token = _login(rig)
	var dir := ProjectSettings.globalize_path(BASE).path_join("cache/plain")
	check(cc.update("plain", dir).ok, "base")
	var zs := ZoneStreamer.new(cc, "plain", dir)
	var li := zs.load_index()
	check(li.ok and not li.zoned, "not zoned is not an error")
	check(zs.is_ready(1) and zs.ensure(1).ok, "everything is in the base")
	eq(zs.zones_to_fetch(1, [2]).size(), 0)
	_end(rig)


func test_a_cut_in_a_zone_keeps_the_cache_clean_and_resumes() -> void:
	_zoned()
	var rig := Rig.new([_build()])
	var cc := rig.client()
	cc.token = _login(rig)
	var dir := ProjectSettings.globalize_path(BASE).path_join("cache/zx")
	check(cc.update("zx", dir).ok, "base")
	var zs := ZoneStreamer.new(cc, "zx", dir)
	zs.load_index()
	# the server stops answering: the zone fails, nothing is marked installed
	var dead := ContentClient.new("127.0.0.1", 1, cc.token)
	var zdead := ZoneStreamer.new(dead, "zx", dir)
	zdead.load_index() # local: the release kept with the base
	var fail := zdead.ensure(3)
	check(not fail.ok and fail.error != "", "an unreachable server is an error, not a hang")
	check(not zdead.is_ready(3), "not marked installed")
	check(not ContentClient.fragment_installed(dir, zs.index, "20"), "the cache does not remember it")
	var ok := zs.ensure(3)
	check(ok.ok, ok.error)
	check(zs.is_ready(3), "retry works")
	_end(rig)


# ── C.02d: the zones wired to map_enter (ZoneGate, ZoneIndicator, SessionLink) ──

func test_the_gate_holds_a_map_until_its_zone_is_installed() -> void:
	_zoned()
	var rig := Rig.new([_build()])
	var token := _login(rig)
	var dir := ProjectSettings.globalize_path(BASE).path_join("cache/zx")
	var base := rig.client()
	base.token = token
	check(base.update("zx", dir).ok, "base")
	var g := _gate(rig, dir, token)
	var fired := [0]
	g.zone_ready.connect(func() -> void: fired[0] += 1)
	g.start()
	check(not g.admit(_enter(3)), "before the index is known, the map waits")
	eq(g.state, "indexing")
	check(g.waiting(), "indicator on")
	g.run_all()
	eq(fired[0], 1, "the index arrived: the held event is asked again")
	check(not g.admit(_enter(3, {"right": 4})), "zone 20 is not in the cache: held")
	eq(g.state, "loading")
	eq(g.zone, "20")
	check(g.waiting(), "blocking indicator")
	var t := ZoneIndicator.text_for(g.state, g.error, 50, 200)
	eq(t["title"], "Chargement de la zone…")
	eq(t["value"], 0.25, "the bar follows the bytes")
	g.run_all()
	eq(fired[0], 2, "the zone is there: ready fires")
	check(not g.waiting(), "indicator off")
	check(FileAccess.file_exists(dir.path_join("content/Content/Maps/3.json")), "the map's file is in the cache")
	check(g.admit(_enter(3, {"right": 4})), "now the map opens")
	g.run_all() # the background prefetch of the neighbour's zone
	check(FileAccess.file_exists(dir.path_join("content/Content/Maps/4.json")), "the neighbour's zone came behind")
	check(g.admit(_enter(4)), "so walking there needs no wait")
	check(g.admit({"t": Protocol.ACTOR_ADD}), "only map_enter is held")
	_end(rig)


func test_a_failed_download_keeps_the_gate_and_the_installed_maps_playable() -> void:
	_zoned()
	var rig := Rig.new([_build()])
	var token := _login(rig)
	var dir := ProjectSettings.globalize_path(BASE).path_join("cache/zx")
	var base := rig.client()
	base.token = token
	check(base.update("zx", dir).ok, "base")
	var g := _gate(rig, dir, token)
	g.retry_s = 0.0
	g.start()
	g.run_all()
	check(g.admit(_enter(3)) == false, "held")
	g.run_all()
	check(g.admit(_enter(3)), "zone 20 installed")
	# the server goes away: the next zone fails, the installed one stays playable
	g.streamer.client.port = 1
	check(not g.admit(_enter(4)), "zone 30 is missing: held")
	g.run_all()
	eq(g.state, "failed")
	check(g.error != "" and g.waiting(), "the error is shown and the player still waits")
	var t := ZoneIndicator.text_for(g.state, g.error, 0, 0)
	eq(t["title"], "Zone indisponible")
	check(g.admit(_enter(3)), "a map of an installed zone opens anyway")
	# the server is back: the next ask succeeds
	g.streamer.client.port = rig.host.http_port()
	check(not g.admit(_enter(4)), "asked again")
	g.run_all()
	check(g.admit(_enter(4)), "installed after the retry")
	_end(rig)


func test_without_an_index_the_map_is_shown_as_is() -> void:
	_zoned()
	var rig := Rig.new([_build()])
	var token := _login(rig)
	var g := _gate(rig, ProjectSettings.globalize_path(BASE).path_join("cache/zx"), token)
	g.streamer.client.port = 1 # no content API
	g.start()
	check(not g.admit(_enter(3)), "waits for the index first")
	g.run_all()
	check(g.admit(_enter(3)), "the index failed: the map is shown (small worlds, tests), the index is tried again later")
	check(not g.waiting())
	_end(rig)


func test_session_link_holds_map_enter_and_replays_it() -> void:
	_zoned()
	var rig := Rig.new([_build()])
	var token := _login(rig)
	var dir := ProjectSettings.globalize_path(BASE).path_join("cache/zx")
	var base := rig.client()
	base.token = token
	check(base.update("zx", dir).ok, "base")
	var g := _gate(rig, dir, token)
	g.start()
	g.run_all()
	var s := ClientSession.new()
	s._hud_layer = CanvasLayer.new()
	s.zone_gate = g
	var link := SessionLink.new(s)
	s._link = link
	g.zone_ready.disconnect(s._on_sequence_done) # the real replay shows the map: out of scope for this test
	var ev := _enter(3)
	check(link.handle(Protocol.MAP_ENTER, ev), "held by the link")
	check(s._blocked and s._queue.size() == 1, "the event waits at the head of the queue, the queue is blocked")
	g.run_all()
	check(not link.handle(Protocol.MAP_ENTER, s._queue[0]), "installed: the map is let through")
	check(not link.handle(Protocol.ACTOR_ADD, {"t": Protocol.ACTOR_ADD}), "other events untouched")
	s._hud_layer.free()
	s.free()
	_end(rig)


func test_the_gate_downloads_in_a_worker_thread() -> void:
	_zoned()
	var rig := Rig.new([_build()])
	var token := _login(rig)
	var dir := ProjectSettings.globalize_path(BASE).path_join("cache/zx")
	var base := rig.client()
	base.token = token
	check(base.update("zx", dir).ok, "base")
	var cc := ContentClient.new("127.0.0.1", rig.host.http_port(), token) # no pump: the worker polls its own sockets
	var g := ZoneGate.new(ZoneStreamer.new(cc, "zx", dir))
	var fired := [0]
	g.zone_ready.connect(func() -> void: fired[0] += 1)
	g.start()
	var ev := _enter(3)
	var spins := 0
	while spins < 2000 and not g.admit(ev):
		rig.pump() # the server answers while the worker waits
		g._process(0.0)
		spins += 1
	check(spins < 2000, "the zone arrived through the thread")
	check(fired[0] >= 1, "zone_ready fired")
	check(FileAccess.file_exists(dir.path_join("content/Content/Maps/3.json")), "its files are in the cache")
	g._exit_tree()
	_end(rig)


# ── C.02e: class zones and blocks of a big zone ──

func test_a_class_leaves_the_base_for_its_own_zone() -> void:
	var z := _class_zoned()
	var base: PackedStringArray = z["base"]
	check(base.has(CONTENT + "/Characters/Bones/1-combat/*") and base.has(CONTENT + "/Characters/Bones/1-static/*"), "the generic bundles stay in the base")
	check(base.has(CONTENT + "/Characters/Bones/666/*"), "and the fallback bone")
	for g in ["1-1-combat", "1-1-static", "1-2-combat"]:
		check(not base.has(CONTENT + "/Characters/Bones/%s/*" % g), "not in the base: " + g)
	check(not base.has(CONTENT + "/Characters/Skins/2012/*") and not base.has(CONTENT + "/Characters/Skins/10/*"), "nor the skins of a class")
	var c1: Dictionary = z["zones"]["class_1"]
	eq(c1["maps"], [], "a class zone has no map")
	for g in ["1-1-combat", "1-1-static"]:
		check((c1["dirs"] as Array).has(CONTENT + "/Characters/Bones/%s/*" % g), "class 1: " + g)
	check(not (c1["dirs"] as Array).has(CONTENT + "/Characters/Bones/1-2-combat/*"), "class 1 has no bundle of class 2")
	check((c1["dirs"] as Array).has(CONTENT + "/Characters/Skins/2012/*") and (c1["dirs"] as Array).has(CONTENT + "/Characters/Skins/10/*"), "its creation face and its look")
	var c2: Dictionary = z["zones"]["class_2"]
	check((c2["dirs"] as Array).has(CONTENT + "/Characters/Bones/1-2-combat/*") and (c2["dirs"] as Array).has(CONTENT + "/Characters/Skins/2022/*"), "class 2")
	check(not (c2["dirs"] as Array).has(CONTENT + "/Characters/Skins/2012/*"), "the face of class 1 is not in class 2")
	var b := _build()
	check(b.ok, b.error)
	eq(ContentZones.validate(b.zone_index), "", "the index with class zones is valid")
	check(b.zone_index["zones"].has("class_1") and not ContentZones.lookup(b.zone_index).values().has("class_1"), "no map leads to a class zone")
	check(_paths(b.zones["class_2"]).has(CONTENT + "/Characters/Bones/1-2-combat/bone.json"), "the class manifest holds the bundle")
	var plain := WorldAssets.new(_root, "zx").compute()
	check(plain.has(CONTENT + "/Characters/Bones/1-2-combat/*"), "without zones nothing leaves: the complete list keeps every class")


func test_a_big_zone_is_cut_in_blocks_of_neighbouring_maps() -> void:
	var z := _class_zoned()
	var zones: Dictionary = z["zones"]
	check(not zones.has("40"), "zone 40 weighs more than the limit: cut")
	eq(zones["40-1"]["maps"], [8, 7], "the first block: the maps at the west (smallest x)")
	eq(zones["40-2"]["maps"], [6, 5], "the second: the east")
	for id in ["40-1", "40-2"]:
		check(int(zones[id]["bytes"]) <= 2500 and int(zones[id]["bytes"]) > 0, "%s fits the limit (%d)" % [id, int(zones[id]["bytes"])])
	check(zones.has("20") and zones.has("30"), "the small zones keep their id")
	var b := _build()
	check(b.ok, b.error)
	eq(ContentZones.validate(b.zone_index), "", "each map in one block")
	var lookup := ContentZones.lookup(b.zone_index)
	eq([lookup[5], lookup[6], lookup[7], lookup[8]], ["40-2", "40-2", "40-1", "40-1"])


func test_the_block_of_the_start_map_is_in_the_base() -> void:
	var z := _class_zoned(2500, 6)
	eq(z["start_zone"], "40-2", "the start zone is the block holding start_map")
	var base: PackedStringArray = z["base"]
	check(base.has(CONTENT + "/Maps/6.json") and base.has(CONTENT + "/Maps/5.json") and base.has(CONTENT + "/Maps/Gfx/201.png"), "its maps come with the base")
	check(not base.has(CONTENT + "/Maps/7.json"), "the other block does not")
	eq(z["zones"]["40-2"]["files"], {}, "the start block adds nothing")
	check(int(z["zones"]["40-1"]["bytes"]) > 0, "the other block is a zone")


func test_the_gate_holds_the_characters_until_their_class_is_installed() -> void:
	_class_zoned()
	var rig := Rig.new([_build()])
	var token := _login(rig)
	var dir := ProjectSettings.globalize_path(BASE).path_join("cache/zx")
	var base := rig.client()
	base.token = token
	check(base.update("zx", dir).ok, "base")
	var g := _gate(rig, dir, token)
	var got: Array = []
	g.class_installed.connect(func(breed: int) -> void: got.append(breed))
	g.start()
	g.run_all()
	var chars := {"t": Protocol.CHARACTERS, "list": [{"name": "A", "breed": 2, "level": 1}], "max": 5, "world": {}, "breeds": [1, 2]}
	check(not g.admit(chars), "the class zone is not in the cache: the selection waits")
	eq(g.zone, "class_2")
	g.run_all()
	eq(got, [2], "class_installed")
	check(FileAccess.file_exists(dir.path_join("content/Content/Characters/Bones/1-2-combat/bone.json")), "its skeleton is in the cache")
	check(not FileAccess.file_exists(dir.path_join("content/Content/Characters/Bones/1-1-combat/bone.json")), "the other class was not downloaded")
	check(g.admit(chars), "the selection shows")
	# a map_enter shows its players too: a player of class 1 is on the map
	var enter := {"t": Protocol.MAP_ENTER, "map": {"id": 1, "neighbors": {}}, "actors": [{"kind": "player", "breed": 1, "id": 3}]}
	check(not g.admit(enter), "zone 10 and class 1 are missing")
	g.run_all()
	check(g.admit(enter), "both installed")
	eq(got, [2, 1])
	_end(rig)


func test_a_player_of_another_class_is_fetched_behind() -> void:
	_class_zoned()
	var rig := Rig.new([_build()])
	var token := _login(rig)
	var dir := ProjectSettings.globalize_path(BASE).path_join("cache/zx")
	var base := rig.client()
	base.token = token
	check(base.update("zx", dir).ok, "base")
	var g := _gate(rig, dir, token)
	g.start()
	g.run_all()
	check(not g.want_class(1), "class 1 is not installed: queued in front")
	eq(g.streamer.class_zone(1), "class_1")
	check(not g.streamer.class_ready(1))
	g.run_all()
	check(g.streamer.class_ready(1) and g.want_class(1), "ready after the download")
	g.observe({"t": Protocol.ACTOR_ADD, "actor": {"kind": "player", "breed": 2, "id": 9}})
	g.run_all()
	check(g.streamer.class_ready(2), "a player of class 2 came into view: its zone was fetched without holding anything")
	check(not g.waiting(), "no blocking indicator")
	eq(g.streamer.missing_zones(8, [1, 2]), PackedStringArray(["40-1"]), "only the zone of the map is left")
	_end(rig)


# -- C.02g: equipment zone and monster zones --

func test_the_monsters_of_a_heavy_sub_area_have_their_own_zone() -> void:
	var z := _monster_zoned()
	var zones: Dictionary = z["zones"]
	check(zones.has("50-m") and zones["50-m"]["maps"] == [], "zone 50-m: the monsters, no map")
	check((zones["50-m"]["dirs"] as Array).has(CONTENT + "/Characters/Bones/60/*"), "it holds the monster's skeleton")
	check(zones.has("50") and not (zones["50"]["dirs"] as Array).has(CONTENT + "/Characters/Bones/60/*"), "the block does not repeat it")
	eq(zones["50"]["requires"], ["50-m"], "the block requires the monsters")
	check(not zones["20"].has("requires") and not zones.has("20-m"), "a light zone keeps its monsters")
	var b := _build()
	check(b.ok, b.error)
	eq(ContentZones.validate(b.zone_index), "", "the index with requirements is valid")
	eq(b.zone_index["zones"]["50"]["requires"], ["50-m"])
	check(not (b.zones["50"] as Dictionary).has("requires"), "the manifest does not repeat what the index says")
	var bad: Dictionary = b.zone_index.duplicate(true)
	bad["zones"]["50"]["requires"] = ["nope"]
	bad["version"] = ContentZones.version_of(bad["zones"])
	check(ContentZones.validate(bad) != "", "a requirement that is not a zone is refused")


func test_a_block_downloads_its_monsters_first() -> void:
	_monster_zoned()
	var rig := Rig.new([_build()])
	var token := _login(rig)
	var dir := ProjectSettings.globalize_path(BASE).path_join("cache/zx")
	var base := rig.client()
	base.token = token
	check(base.update("zx", dir).ok, "base")
	var g := _gate(rig, dir, token)
	g.start()
	g.run_all()
	eq(g.streamer.missing_zones(9), PackedStringArray(["50-m", "50"]), "the monsters, then the block")
	var enter := _enter(9)
	check(not g.admit(enter), "the zone of map 9 is missing")
	g.run_all()
	check(g.admit(enter), "both installed")
	check(FileAccess.file_exists(dir.path_join("content/Content/Characters/Bones/60/bone.json")), "the monster is in the cache")
	check(g.streamer.is_ready(9), "ready")
	_end(rig)


func test_equipment_skins_are_fetched_when_worn() -> void:
	_class_zoned()
	var rig := Rig.new([_build()])
	var token := _login(rig)
	var dir := ProjectSettings.globalize_path(BASE).path_join("cache/zx")
	var base := rig.client()
	base.token = token
	check(base.update("zx", dir).ok, "base")
	check(not FileAccess.file_exists(dir.path_join("content/Content/Characters/Skins/80/skin.json")), "the base does not hold the skin of an item")
	var g := _gate(rig, dir, token)
	var got: Array = []
	g.equipment_installed.connect(func() -> void: got.append(1))
	g.start()
	g.run_all()
	eq(g.streamer.equipment_zone(), "equipment")
	check(not g.streamer.equipment_ready())
	check(not g.streamer.needs_equipment(["{1|10||53}"]), "a bare look wears nothing of the zone")
	check(g.streamer.needs_equipment(["{1|10||53}", "{1|10,80||53}"]), "one skin of an item")
	g.observe({"t": Protocol.ACTOR_ADD, "actor": {"kind": "player", "breed": 1, "id": 4, "looks": ["{1|10||53}"]}})
	g.run_all()
	check(not g.streamer.equipment_ready() and got.is_empty(), "nothing worn: nothing fetched")
	g.observe({"t": Protocol.ACTOR_LOOK, "id": 4, "looks": ["{1|10,80||53}"]})
	check(not g.waiting(), "fetched behind, nothing is held")
	g.run_all()
	check(g.streamer.equipment_ready(), "the equipment zone is installed")
	eq(got, [1], "equipment_installed")
	check(FileAccess.file_exists(dir.path_join("content/Content/Characters/Skins/80/skin.json")), "the skin is in the cache")
	check(g.want_equipment(), "already there")
	_end(rig)


func test_the_inventory_asks_for_the_equipment_zone() -> void:
	_class_zoned()
	var rig := Rig.new([_build()])
	var token := _login(rig)
	var dir := ProjectSettings.globalize_path(BASE).path_join("cache/zx")
	var base := rig.client()
	base.token = token
	check(base.update("zx", dir).ok, "base")
	var g := _gate(rig, dir, token)
	g.start()
	g.run_all()
	check(not g.want_equipment(), "queued in front")
	g.run_all()
	check(g.want_equipment() and g.streamer.equipment_ready(), "installed")
	_end(rig)


func test_what_every_block_repeats_goes_to_a_common_zone() -> void:
	var z := _common_zoned()
	var zones: Dictionary = z["zones"]
	check(zones.has("60-c1") and zones["60-c1"]["maps"] == [], "zone 60-c1: no map")
	check((zones["60-c1"]["dirs"] as Array).has(CONTENT + "/Characters/Bones/61/*"), "it holds the NPC the four maps share")
	check(zones.has("60") and not (zones["60"]["dirs"] as Array).has(CONTENT + "/Characters/Bones/61/*"), "the block does not repeat it")
	eq(zones["60"]["requires"], ["60-c1"])
	var b := _build()
	check(b.ok, b.error)
	eq(ContentZones.validate(b.zone_index), "")
	var rig := Rig.new([b])
	var token := _login(rig)
	var dir := ProjectSettings.globalize_path(BASE).path_join("cache/zx")
	var base := rig.client()
	base.token = token
	check(base.update("zx", dir).ok, "base")
	var g := _gate(rig, dir, token)
	g.start()
	g.run_all()
	check(not g.admit(_enter(13)), "the common zone and the block are missing")
	g.run_all()
	check(g.admit(_enter(13)), "both installed")
	check(FileAccess.file_exists(dir.path_join("content/Content/Characters/Bones/61/bone.json")), "the shared NPC is in the cache")
	_end(rig)
