## The base bundle of a world (roadmap C.05): the partition derived from the manifest, the zip
## parts the server builds, their HTTP route (token, whitelist, Range), and the client that
## downloads them (resume after a cut), unpacks them, checks every file against the manifest,
## refuses a damaged zip, then only fetches differences file by file. The server and the clients
## run in this process (the token comes from a WebSocket login on 127.0.0.1, as a real client).
## Fixture under user://test_bundle/.
extends TestCase

const Api := preload("res://tests/test_content_api.gd")
const BASE := "user://test_bundle"
const MAX_SOURCE := 700000

var _root := ""
var _store := ""
var _cache_base := ""


func _text(tag: String, n: int) -> PackedByteArray:
	var s := ""
	while s.length() < n:
		s += "%s line %d of a compressible file\n" % [tag, s.length()]
	return s.substr(0, n).to_utf8_buffer()


func _noise(seed_value: int, n: int) -> PackedByteArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var b := PackedByteArray()
	b.resize(n)
	for i in n:
		b[i] = rng.randi() & 255
	return b


func _write(rel: String, data: PackedByteArray) -> void:
	var path := _root.path_join(rel)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(data)
	f.close()


## The game folder fixture, packaged and bundled (parts of ~0.7 MB): returns the Built.
func _fixture(with_bundle := true) -> WorldPackage.Built:
	var d := ProjectSettings.globalize_path(BASE)
	ContentFolder.remove_dir(d)
	_root = d + "/game"
	_store = d + "/packages"
	_cache_base = d + "/cache"
	_write("worlds/bz/world.json", JSON.stringify({"id": "bz", "name": "Bundle", "module": "demo",
			"content": ["content/*"]}).to_utf8_buffer())
	_write("worlds/bz/maps/1.json", "{\"id\":1}".to_utf8_buffer())
	_write("data/t.json", "[1,2,3]".to_utf8_buffer())
	for i in 4:
		_write("content/t%d.json" % i, _text("t%d" % i, 500000))
	_write("content/dup.json", _text("t0", 500000)) # same content as t0 under another path
	_write("content/p1.webp", _noise(1, 300000))
	_write("content/p2.webp", _noise(2, 300000))
	var built := WorldPackage.build("bz", _root, _store, true)
	check(built.ok, built.error)
	if with_bundle:
		_bundle(built)
	return built


func _bundle(built: WorldPackage.Built) -> WorldBundle.Result:
	var r := WorldBundle.build(built, _store, MAX_SOURCE)
	check(r.ok, r.error)
	built.bundle_index = r.index
	built.bundle_files = r.files
	return r


## A client logged in over WebSocket (127.0.0.1): its token opens the content API.
func _login(rig: Api.Rig) -> NetBackend:
	rig.host.listen(0, "127.0.0.1")
	var backend := NetBackend.new()
	backend.connect_to("127.0.0.1:%d" % rig.host.local_port())
	backend.send(Protocol.register("bundler", "secret3"))
	var waited := 0
	while backend.token == "" and waited < 400:
		rig.pump()
		backend.poll(0.005)
		waited += 1
	check(backend.token != "", "login_ok gave a token")
	return backend


func _client(rig: Api.Rig, backend: NetBackend) -> ContentClient:
	var c := ContentClient.new("127.0.0.1", rig.host.http_port(), backend.token)
	c.pump = rig.pump
	return c


func _cache(id: String) -> String:
	return _cache_base + "/" + id


func _same_as_source(cache: String) -> void:
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(cache.path_join("manifest.json")))
	for f: Dictionary in m["files"]:
		var rel := ContentSource.cache_relative(str(f["path"]), "bz")
		eq(FileHash.sha256(cache.path_join(rel)), str(f["hash"]), str(f["path"]))


# --- the partition (pure) -------------------------------------------------------------

func test_plan_is_derived_from_the_manifest() -> void:
	var files: Array = []
	for i in 6:
		files.append({"path": "content/f%d" % i, "hash": ContentManifest.hash_bytes(str(i % 5).to_utf8_buffer()), "size": 400})
	var m := ContentManifest.make("w", "W", "", files)
	var plan := ContentBundle.plan(m, 1000)
	var seen := {}
	for p: Dictionary in plan:
		check(int(p["source"]) <= 1000 or p["hashes"].size() == 1, "a part holds at most max_source")
		for h: String in p["hashes"]:
			check(not seen.has(h), "each content is in one part only")
			seen[h] = true
	eq(seen.size(), 5, "5 distinct contents for 6 paths")
	eq(plan.size(), 3, "400 + 400, 400 + 400, 400")
	eq(ContentBundle.plan(m, 1000), plan, "same manifest, same plan")
	eq(ContentBundle.plan(m, 400).size(), 5, "a part may hold one content only")
	eq(ContentBundle.plan(m, 1000000, 2).size(), 3, "a part holds at most max_entries contents (tiny files)")
	eq(ContentBundle.parts_needed(plan, {plan[1]["hashes"][0]: true}), [1] as Array[int])
	check(ContentBundle.is_part_name("part-012.zip"))
	check(not ContentBundle.is_part_name("../part-0.zip") and not ContentBundle.is_part_name("part-abc.zip"))
	var parts: Array = plan.map(func(p: Dictionary) -> Dictionary:
			return {"name": p["name"], "size": 10, "hash": ContentManifest.hash_bytes("x".to_utf8_buffer())})
	var index := ContentBundle.make_index(m, 1000, parts)
	eq(ContentBundle.validate(index, m), "")
	var wrong := index.duplicate(true)
	wrong["version"] = "x"
	check(ContentBundle.validate(wrong, m) != "", "another version is refused")
	wrong = index.duplicate(true)
	wrong["parts"].pop_back()
	check(ContentBundle.validate(wrong, m) != "", "a missing part is refused")
	wrong = index.duplicate(true)
	wrong["parts"][0]["hash"] = "nothash"
	check(ContentBundle.validate(wrong, m) != "", "a bad hash is refused")
	check(ContentBundle.validate("text", m) != "")


# --- the server builds the zip ----------------------------------------------------------

func test_the_server_packs_every_content_once_and_reuses_the_build() -> void:
	var built := _fixture(false)
	var r := WorldBundle.build(built, _store, MAX_SOURCE)
	check(r.ok, r.error)
	check(r.built, "first build")
	check(r.index["parts"].size() >= 3, "several parts (%d)" % r.index["parts"].size())
	var wanted := ContentManifest.unique_blobs(built.manifest["files"])
	var found := {}
	for name: String in r.files:
		var zip := ZIPReader.new()
		eq(zip.open(r.files[name]["path"]), OK)
		for entry in zip.get_files():
			check(wanted.has(entry), "an entry is named by the hash of a manifest content")
			found[entry] = ContentManifest.hash_bytes(zip.read_file(entry)) == entry
		zip.close()
		eq(FileHash.sha256(r.files[name]["path"]), r.files[name]["hash"], "the index hash is the file's")
	eq(found.size(), wanted.size(), "every distinct content, once")
	check(not found.values().has(false), "the entries are the contents")
	check(r.zip_bytes < r.source_bytes * 0.7, "compressed: %d of %d" % [r.zip_bytes, r.source_bytes])
	var again := WorldBundle.build(built, _store, MAX_SOURCE)
	check(again.ok and not again.built, "same version: the zip is reused")
	eq(again.index["version"], r.index["version"])
	eq(again.index["parts"].size(), r.index["parts"].size())
	# a changed file: new version, the old version's zips are removed
	_write("content/t1.json", _text("changed", 500000))
	var built2 := WorldPackage.build("bz", _root, _store, true)
	var third := WorldBundle.build(built2, _store, MAX_SOURCE)
	check(third.ok and third.built, "new version: rebuilt")
	eq(DirAccess.get_directories_at(_store + "/bz/bundle").size(), 1, "older bundle deleted")
	ContentFolder.remove_dir(ProjectSettings.globalize_path(BASE))


# --- the HTTP route ---------------------------------------------------------------------

func test_the_route_needs_a_token_serves_only_the_index_and_resumes() -> void:
	var built := _fixture()
	var rig := Api.Rig.new(built)
	var f := rig.get_path("/worlds/bz/bundle.json", {}, false)
	eq(f.status, 401)
	f = rig.get_path("/worlds/bz/bundle.json")
	eq(f.status, 200)
	var index: Variant = JSON.parse_string(f.body.get_string_from_utf8())
	eq(ContentBundle.validate(index, built.manifest), "", "the client can check it against the manifest")
	var part: Dictionary = index["parts"][0]
	f = rig.get_path("/worlds/bz/bundle/" + part["name"], {}, false)
	eq(f.status, 401)
	f = rig.get_path("/worlds/bz/bundle/" + part["name"])
	eq(f.status, 200)
	eq(f.body.size(), int(part["size"]))
	eq(ContentManifest.hash_bytes(f.body), part["hash"])
	f = rig.get_path("/worlds/bz/bundle/" + part["name"], {"Range": "bytes=100-199"})
	eq(f.status, 206)
	eq(f.body.size(), 100, "Range: a resumed download")
	eq(rig.get_path("/worlds/bz/bundle/part-099.zip").status, 404, "a name outside the index")
	eq(rig.get_path("/worlds/bz/bundle/..%2Fmanifest.json").status, 404)
	eq(rig.get_path("/worlds/bz/bundle/../../x").status, 404)
	eq(rig.get_path("/worlds/bz/bundle/part-000.zip/extra").status, 404)
	# a world with no bundle: 404, the clients go file by file
	var plain := _fixture(false)
	var rig2 := Api.Rig.new(plain)
	eq(rig2.get_path("/worlds/bz/bundle.json").status, 404)
	rig2.host.shutdown()
	rig.host.shutdown()
	ContentFolder.remove_dir(ProjectSettings.globalize_path(BASE))


# --- the client ---------------------------------------------------------------------------

func test_a_client_installs_from_the_zip_then_updates_file_by_file() -> void:
	var built := _fixture()
	var rig := Api.Rig.new(built)
	var backend := _login(rig)
	var cc := _client(rig, backend)
	var cache := _cache("bz")
	var m: Dictionary = cc.fetch_manifest("bz").manifest
	var phases: Array = []
	cc.phase_changed = func(p: String, _t: int, _n: int) -> void: phases.append(p)
	var todo := cc.diff(m, cache)
	var b := cc.install_bundle(m, cache, todo)
	check(b.ok and b.used, str(b))
	eq(phases, ["archive", "extract"])
	check(int(b.bytes) < 2600000, "fewer bytes on the wire than the files: %d" % int(b.bytes))
	check(not DirAccess.dir_exists_absolute(cache.path_join(ContentClient.BUNDLE_DIR)), "the zips are deleted once unpacked")
	eq(cc.diff(m, cache).size(), 0, "everything installed")
	var r := cc.download(m, cache, cc.diff(m, cache)) # finishes: manifest.json
	check(r.ok, r.error)
	_same_as_source(cache)
	eq(FileAccess.get_file_as_bytes(cache.path_join("content/dup.json")), FileAccess.get_file_as_bytes(cache.path_join("content/t0.json")))
	# one file changes on the server: an update fetches that file only, the bundle is not used
	_write("content/p1.webp", _noise(9, 300000))
	var built2 := WorldPackage.build("bz", _root, _store, true)
	_bundle(built2)
	rig.host.content.set_package(built2)
	var m2: Dictionary = cc.fetch_manifest("bz").manifest
	var todo2 := cc.diff(m2, cache)
	eq(todo2.size(), 1)
	var b2 := cc.install_bundle(m2, cache, todo2)
	check(b2.ok and not b2.used, "not worth a zip part for one file")
	var r2 := cc.download(m2, cache, todo2)
	check(r2.ok, r2.error)
	eq(int(r2.files), 1)
	_same_as_source(cache)
	backend.close()
	rig.host.shutdown()
	ContentFolder.remove_dir(ProjectSettings.globalize_path(BASE))


func test_a_cut_download_resumes_in_the_archive_and_in_the_unpacking() -> void:
	var built := _fixture()
	var rig := Api.Rig.new(built)
	var backend := _login(rig)
	var cc := _client(rig, backend)
	var cache := _cache("cut")
	var m: Dictionary = cc.fetch_manifest("bz").manifest
	var parts: Array = built.bundle_index["parts"]
	var cut_at := int(parts[0]["size"]) + int(int(parts[1]["size"]) / 2) # in the middle of the second zip
	cc.chunks_per_poll = 1
	# cut in the middle of the first zip
	cc.progress = func(done: int, _total: int, _p: String) -> void:
		if done >= cut_at:
			cc.cancel_requested = true
	var b := cc.install_bundle(m, cache, cc.diff(m, cache))
	check(not b.ok and not b.fallback, "a cut is a stop, not a reason to leave the zip")
	var part_file := cache.path_join("_bundle/part-001.zip.part")
	check(FileAccess.file_exists(part_file), "the partial zip stays")
	var kept := FileAccess.open(part_file, FileAccess.READ).get_length()
	check(kept > 0 and kept < int(parts[1]["size"]), "kept %d" % kept)
	# second run resumes (Range): the first progress is past what was kept
	cc.cancel_requested = false
	var first := [-1]
	var seen_extract := [false]
	cc.phase_changed = func(p: String, _t: int, _n: int) -> void:
		if p == "extract": # cut again, as the unpacking starts (it runs on several threads: the cut is not between two files)
			seen_extract[0] = true
			cc.cancel_requested = true
	cc.progress = func(done: int, _total: int, _p: String) -> void:
		if first[0] < 0:
			first[0] = done
	b = cc.install_bundle(m, cache, cc.diff(m, cache))
	check(first[0] >= kept, "the download resumed at %d, not at 0 (first progress %d)" % [kept, first[0]])
	check(seen_extract[0], "the unpacking was reached")
	check(not b.ok and str(b.error).ends_with("cancelled"), str(b))
	check(FileAccess.file_exists(cache.path_join("_bundle/part-001.zip")), "the downloaded zips stay for the next run")
	# third run: finishes, what is installed is not unpacked again
	cc.cancel_requested = false
	cc.progress = Callable()
	cc.phase_changed = Callable()
	b = cc.install_bundle(m, cache, cc.diff(m, cache))
	check(b.ok, str(b))
	eq(cc.diff(m, cache).size(), 0)
	check(cc.download(m, cache, []).ok)
	_same_as_source(cache)
	backend.close()
	rig.host.shutdown()
	ContentFolder.remove_dir(ProjectSettings.globalize_path(BASE))


func test_a_damaged_zip_is_refused_and_the_loader_falls_back_to_files() -> void:
	var built := _fixture()
	# the stored zip is damaged without the server noticing (same size, dates re-recorded)
	var victim: Dictionary = built.bundle_files["part-001.zip"]
	var f := FileAccess.open(victim["path"], FileAccess.READ_WRITE)
	f.seek(100)
	var byte := f.get_8()
	f.seek(100)
	f.store_8(byte ^ 0xff)
	f.close()
	victim["mtime"] = FileAccess.get_modified_time(victim["path"])
	var rig := Api.Rig.new(built)
	var backend := _login(rig)
	var cc := _client(rig, backend)
	var cache := _cache("bad")
	var m: Dictionary = cc.fetch_manifest("bz").manifest
	var b := cc.install_bundle(m, cache, cc.diff(m, cache))
	check(not b.ok and b.fallback, "refused: %s" % str(b))
	check(str(b.error).contains("hash mismatch"), str(b.error))
	check(not FileAccess.file_exists(cache.path_join("_bundle/part-001.zip")), "the bad zip is not kept")
	# the loader goes on file by file and the world ends complete and identical
	var wl := WorldLoader.new(_client(rig, backend))
	wl.cache_base = _cache_base
	wl.free_space = func(_p: String) -> int: return -1
	wl.bundle_min_bytes = 1
	check(wl.refresh(), wl.error)
	var phases: Array = []
	wl.on_progress = func() -> void:
		if phases.is_empty() or phases[-1] != wl.phase:
			phases.append(wl.phase)
	check(wl.install("bz"), wl.error)
	eq(wl.entry("bz")["status"], "current")
	eq(phases.back(), "files", "the damaged part was replaced by plain downloads")
	_same_as_source(_cache("bz"))
	backend.close()
	rig.host.shutdown()
	ContentFolder.remove_dir(ProjectSettings.globalize_path(BASE))


func test_the_loader_reports_the_archive_then_the_unpacking() -> void:
	var built := _fixture()
	var rig := Api.Rig.new(built)
	var backend := _login(rig)
	var wl := WorldLoader.new(_client(rig, backend))
	wl.cache_base = _cache_base
	wl.free_space = func(_p: String) -> int: return -1
	wl.bundle_min_bytes = 1
	check(wl.refresh(), wl.error)
	var phases: Array = []
	var etas: Array = []
	wl.on_progress = func() -> void:
		if phases.is_empty() or phases[-1] != wl.phase:
			phases.append(wl.phase)
		etas.append(wl.eta())
	check(wl.install("bz"), wl.error)
	eq(phases, ["archive", "extract"], "nothing left to fetch file by file")
	eq(wl.entry("bz")["status"], "current")
	check(wl.launch("bz"))
	check(ContentSource.exists("content/p1.webp"))
	ContentSource.use_dev()
	ContentSource.set_cache_base("")
	check(WorldLoadScreen.format_duration(200) == "3 min 20 s" and WorldLoadScreen.format_duration(45) == "45 s"
			and WorldLoadScreen.format_duration(3900) == "1 h 05 min")
	# a second client with the same cache downloads nothing
	var again := WorldLoader.new(_client(rig, backend))
	again.cache_base = _cache_base
	check(again.refresh(), again.error)
	eq(again.entry("bz")["status"], "current")
	eq(int(again.entry("bz")["todo_bytes"]), 0)
	backend.close()
	rig.host.shutdown()
	ContentFolder.remove_dir(ProjectSettings.globalize_path(BASE))
