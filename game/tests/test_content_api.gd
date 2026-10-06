## World packages and the content API (roadmap C.02): the manifest (stable, sensitive to one
## byte), the HTTP API (token, whitelist, Range), the content client (diff, resume, hash check,
## atomic install). The server and the clients run in this process; the server is pumped while
## a client waits. Fixture game folder under user://test_content/.
extends TestCase

const BASE := "user://test_content"
const BIG := 2500000 # more than two 1 MB blocks

var _root := ""
var _store := ""
var _big := PackedByteArray()


class Rig:
	var host := ServerHost.new()
	var token := ""
	var auth: AuthService

	func _init(built: WorldPackage.Built, with_auth := true) -> void:
		if with_auth:
			var store := AccountStore.new(Persistence.new())
			store.iterations = 1000
			auth = AuthService.new(store)
			host.auth = auth
			token = auth.register("bob", "secret1").token
		host.listen_http(0, "127.0.0.1")
		if built != null:
			host.content.set_package(built)

	func pump() -> void:
		host.poll(0.005)
		OS.delay_msec(1)

	## One GET; headers are added to the token's.
	func get_path(path: String, extra := {}, with_token := true) -> HttpFetch:
		var f := fetch(path, extra, with_token)
		while not f.poll():
			pump()
		return f

	func fetch(path: String, extra := {}, with_token := true) -> HttpFetch:
		var headers := extra.duplicate()
		if with_token:
			headers["Authorization"] = "Bearer " + token
		var f := HttpFetch.new()
		f.start("127.0.0.1", host.http_port(), path, headers)
		return f

	func client() -> ContentClient:
		var c := ContentClient.new("127.0.0.1", host.http_port(), token)
		c.pump = pump
		return c


## Writes the fixture folder and returns the package built from it.
func _fixture(force := true) -> WorldPackage.Built:
	_root = ProjectSettings.globalize_path(BASE + "/game")
	_store = ProjectSettings.globalize_path(BASE + "/packages")
	_rm(ProjectSettings.globalize_path(BASE))
	if _big.is_empty():
		_big.resize(BIG)
		for i in BIG:
			_big[i] = (i * 31 + (i >> 8)) & 255
	_write("worlds/fx/world.json", JSON.stringify({"id": "fx", "name": "Fixture", "module": "demo",
			"content": ["content/a/*", "../outside/*", "*"]}).to_utf8_buffer())
	_write("worlds/fx/_leftover.json", "{}".to_utf8_buffer())
	_write("worlds/fx/maps/1.json", "{\"id\":1}".to_utf8_buffer())
	_write("data/t.json", "[1,2,3]".to_utf8_buffer())
	_write("content/a/x.bin", _big)
	_write("content/a/y.bin", _big) # same content under another path
	_write("content/a/z.txt", "zzz".to_utf8_buffer())
	_write("content/secret.txt", "not for you".to_utf8_buffer())
	return WorldPackage.build("fx", _root, _store, force)


func _write(rel: String, data: PackedByteArray) -> void:
	var path := _root.path_join(rel)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(data)
	f.close()


func _rm(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_rm(dir.path_join(d))
	DirAccess.remove_absolute(dir)


func _paths(m: Dictionary) -> Array:
	return m["files"].map(func(f: Dictionary) -> String: return f["path"])


func _hash_of(m: Dictionary, path: String) -> String:
	for f: Dictionary in m["files"]:
		if f["path"] == path:
			return f["hash"]
	return ""


# --- manifest -------------------------------------------------------------------------

func test_manifest_lists_the_package_and_nothing_else() -> void:
	var b := _fixture()
	check(b.ok, b.error)
	var m := b.manifest
	eq(ContentManifest.validate(m), "", "valid manifest")
	eq(m["format"], 1)
	eq(m["world"], "fx")
	eq(m["module"], "demo")
	eq(m["name"], "Fixture")
	eq(_paths(m), ["content/a/x.bin", "content/a/y.bin", "content/a/z.txt", "data/t.json",
			"worlds/fx/maps/1.json", "worlds/fx/world.json"], "world, data and the selected content only")
	eq(_hash_of(m, "content/a/x.bin"), ContentManifest.hash_bytes(_big), "SHA-256 of the content")
	eq(_hash_of(m, "content/a/x.bin"), _hash_of(m, "content/a/y.bin"), "same content, same hash")
	eq(b.blobs.size(), 5, "one blob per distinct content")


func test_manifest_is_stable_and_sensitive_to_one_byte() -> void:
	var a := _fixture()
	var again := WorldPackage.build("fx", _root, _store)
	eq(again.manifest["version"], a.manifest["version"], "same content, same version")
	eq(again.hashed, 0, "nothing hashed again: the cache knows every file")
	eq(again.reused, 6)
	check(not again.written, "manifest.json untouched")
	# one byte changed, same size and (maybe) same second: a forced build sees it
	var flipped := _big.duplicate()
	flipped[1234] ^= 1
	_write("content/a/x.bin", flipped)
	var forced := WorldPackage.build("fx", _root, _store, true)
	check(forced.manifest["version"] != a.manifest["version"], "one byte changes the version")
	eq(forced.hashed, 6)
	# a changed size is seen without force
	_write("content/a/z.txt", "zzzz".to_utf8_buffer())
	var sized := WorldPackage.build("fx", _root, _store)
	check(sized.manifest["version"] != forced.manifest["version"], "size change seen by the cache")
	eq(sized.hashed, 1, "only the changed file is hashed")
	check(sized.written, "manifest.json rewritten")


func test_a_package_cannot_escape_the_game_folder() -> void:
	var b := _fixture()
	for p in _paths(b.manifest):
		check(ContentManifest.safe_path(p), p)
		check(not p.contains("secret") and not p.contains("outside") and not p.contains("_leftover"), p)
	check(not WorldPackage.build("../fx", _root, _store).ok, "an id is never a path")
	check(not WorldPackage.build("nope", _root, _store).ok, "unknown world")


func test_validate_rejects_a_bad_manifest() -> void:
	var good := _fixture().manifest
	check(ContentManifest.validate(good) == "")
	var bad_path := good.duplicate(true)
	bad_path["files"][0]["path"] = "../x"
	check(ContentManifest.validate(bad_path) != "", "path with ..")
	var absolute := good.duplicate(true)
	absolute["files"][0]["path"] = "/etc/passwd"
	check(ContentManifest.validate(absolute) != "", "absolute path")
	var bad_hash := good.duplicate(true)
	bad_hash["files"][0]["hash"] = "xyz"
	check(ContentManifest.validate(bad_hash) != "", "bad hash")
	var wrong_version := good.duplicate(true)
	wrong_version["files"][0]["hash"] = "0".repeat(64)
	check(ContentManifest.validate(wrong_version) != "", "version does not match the files")
	check(ContentManifest.validate({"format": 2}) != "", "unknown format")
	check(ContentManifest.validate("x") != "", "not an object")


func test_diff_only_asks_for_what_is_missing() -> void:
	var m := _fixture().manifest
	var have := ContentManifest.as_state(m)
	eq(ContentManifest.diff(m, have).size(), 0, "complete cache: nothing to fetch")
	have.erase("data/t.json")
	have["content/a/z.txt"]["hash"] = "0".repeat(64)
	have["worlds/fx/world.json"]["size"] = 1
	var todo := ContentManifest.diff(m, have).map(func(f: Dictionary) -> String: return f["path"])
	eq(todo, ["content/a/z.txt", "data/t.json", "worlds/fx/world.json"], "absent, other hash, other size")
	have["old/file"] = {"hash": "a".repeat(64), "size": 1}
	eq(ContentManifest.stale(m, have), PackedStringArray(["old/file"]))
	eq(ContentManifest.unique_blobs(m["files"]).size(), 5, "x and y are one download")
	eq(ContentManifest.glob_base("content/Content/Maps/*.webp"), "content/Content/Maps")
	eq(ContentManifest.glob_base("*"), "")


func test_range_parsing() -> void:
	eq(ContentApi.parse_range("bytes=10-19", 100), [10, 19])
	eq(ContentApi.parse_range("bytes=90-", 100), [90, 99])
	eq(ContentApi.parse_range("bytes=-5", 100), [95, 99])
	eq(ContentApi.parse_range("bytes=50-500", 100), [50, 99], "end clamped")
	eq(ContentApi.parse_range("bytes=100-", 100), [], "past the end")
	eq(ContentApi.parse_range("bytes=9-3", 100), [])
	eq(ContentApi.parse_range("bytes=0-1,5-6", 100), [], "one range only")
	eq(ContentApi.parse_range("lines=0-1", 100), [])
	eq(ContentApi.parse_range("bytes=a-b", 100), [])


# --- HTTP API -------------------------------------------------------------------------

func test_api_needs_a_session_token() -> void:
	var rig := Rig.new(_fixture())
	var none := rig.get_path("/worlds", {}, false)
	eq(none.status, 401, "no token")
	var wrong := rig.get_path("/worlds", {"Authorization": "Bearer deadbeef"}, false)
	eq(wrong.status, 401, "unknown token")
	var basic := rig.get_path("/worlds", {"Authorization": "Basic Ym9iOnNlY3JldDE="}, false)
	eq(basic.status, 401, "not a bearer token")
	var no_manifest := rig.get_path("/worlds/fx/manifest.json", {}, false)
	eq(no_manifest.status, 401)
	var no_file := rig.get_path("/worlds/fx/files/" + "0".repeat(64), {}, false)
	eq(no_file.status, 401)
	check(no_file.body.get_string_from_utf8().find("fx") == -1, "nothing revealed without a token")
	var ok := rig.get_path("/worlds")
	eq(ok.status, 200)
	rig.host.shutdown()


func test_api_refuses_everything_without_accounts() -> void:
	var rig := Rig.new(_fixture(), false)
	eq(rig.get_path("/worlds", {"Authorization": "Bearer abc"}, false).status, 401, "an open server never serves content")
	rig.host.shutdown()


func test_api_lists_worlds_and_serves_the_manifest() -> void:
	var b := _fixture()
	var rig := Rig.new(b)
	var list: Variant = JSON.parse_string(rig.get_path("/worlds").body.get_string_from_utf8())
	eq(list.size(), 1)
	eq(list[0]["id"], "fx")
	eq(list[0]["name"], "Fixture")
	eq(list[0]["version"], b.manifest["version"])
	eq(int(list[0]["files"]), 6)
	var m := rig.get_path("/worlds/fx/manifest.json")
	eq(m.status, 200)
	var parsed: Variant = JSON.parse_string(m.body.get_string_from_utf8())
	eq(ContentManifest.validate(parsed), "", "the client can validate what it got")
	eq(parsed["version"], b.manifest["version"])
	eq(rig.get_path("/worlds/other/manifest.json").status, 404, "unknown world")
	rig.host.shutdown()


func test_api_serves_files_by_hash() -> void:
	var b := _fixture()
	var rig := Rig.new(b)
	var h := _hash_of(b.manifest, "content/a/z.txt")
	var f := rig.get_path("/worlds/fx/files/" + h)
	eq(f.status, 200)
	eq(f.body.get_string_from_utf8(), "zzz")
	eq(f.headers["content-length"], "3")
	eq(f.headers["etag"], '"%s"' % h)
	eq(f.headers["accept-ranges"], "bytes")
	var big := rig.get_path("/worlds/fx/files/" + _hash_of(b.manifest, "content/a/x.bin"))
	eq(big.body.size(), BIG, "streamed by blocks")
	eq(ContentManifest.hash_bytes(big.body), _hash_of(b.manifest, "content/a/x.bin"))
	rig.host.shutdown()


func test_api_only_serves_what_the_manifest_lists() -> void:
	var b := _fixture()
	var rig := Rig.new(b)
	var secret := ContentManifest.hash_bytes("not for you".to_utf8_buffer()) # on disk, not in the manifest
	eq(rig.get_path("/worlds/fx/files/" + secret).status, 404, "file outside the manifest")
	eq(rig.get_path("/worlds/fx/files/" + "0".repeat(64)).status, 404, "unknown hash")
	eq(rig.get_path("/worlds/fx/files/../../data/t.json").status, 404, "path")
	eq(rig.get_path("/worlds/fx/files/..%2F..%2Fdata%2Ft.json").status, 404, "encoded path")
	eq(rig.get_path("/worlds/fx/files/content/a/z.txt").status, 404, "a path is not a hash")
	eq(rig.get_path("/worlds/fx/files/" + _hash_of(b.manifest, "data/t.json").to_upper()).status, 404, "hash in capitals")
	eq(rig.get_path("/worlds/..%2Ffx/manifest.json").status, 404, "world id with a path")
	eq(rig.get_path("/worlds/../manifest.json").status, 404)
	eq(rig.get_path("/").status, 404)
	eq(rig.get_path("/admin").status, 404)
	eq(rig.get_path("/worlds/fx").status, 404)
	rig.host.shutdown()


func test_api_range() -> void:
	var b := _fixture()
	var rig := Rig.new(b)
	var url := "/worlds/fx/files/" + _hash_of(b.manifest, "content/a/x.bin")
	var part := rig.get_path(url, {"Range": "bytes=10-19"})
	eq(part.status, 206)
	eq(part.body, _big.slice(10, 20))
	eq(part.headers["content-range"], "bytes 10-19/%d" % BIG)
	var tail := rig.get_path(url, {"Range": "bytes=%d-" % (BIG - 5)})
	eq(tail.body, _big.slice(BIG - 5))
	eq(rig.get_path(url, {"Range": "bytes=%d-" % BIG}).status, 416, "past the end")
	eq(rig.get_path(url, {"Range": "bytes=zz"}).status, 416, "garbage")
	rig.host.shutdown()


func test_api_refuses_a_file_changed_since_the_build() -> void:
	var b := _fixture()
	var rig := Rig.new(b)
	var h := _hash_of(b.manifest, "content/a/z.txt")
	_write("content/a/z.txt", "something else".to_utf8_buffer())
	eq(rig.get_path("/worlds/fx/files/" + h).status, 409, "the package must be rebuilt")
	rig.host.shutdown()


func test_two_clients_download_at_the_same_time() -> void:
	var b := _fixture()
	var rig := Rig.new(b)
	var url := "/worlds/fx/files/" + _hash_of(b.manifest, "content/a/x.bin")
	var a := rig.fetch(url)
	var c := rig.fetch(url, {"Range": "bytes=1000-"})
	var d := rig.fetch("/worlds/fx/manifest.json")
	while not (a.done and c.done and d.done):
		a.poll()
		c.poll()
		d.poll()
		rig.pump()
	eq(a.error, "")
	eq(a.body, _big)
	eq(c.body, _big.slice(1000))
	eq(d.status, 200)
	rig.host.shutdown()


func test_token_of_a_websocket_login_opens_the_content_api() -> void:
	var b := _fixture()
	var rig := Rig.new(b)
	rig.host.listen(0, "127.0.0.1")
	var backend := NetBackend.new()
	backend.connect_to("127.0.0.1:%d" % rig.host.local_port())
	backend.send(Protocol.register("amy", "secret2"))
	var waited := 0
	while backend.token == "" and waited < 400:
		rig.pump()
		backend.poll(0.005)
		waited += 1
	check(backend.token != "", "login_ok gave a token")
	var f := rig.get_path("/worlds", {"Authorization": "Bearer " + backend.token}, false)
	eq(f.status, 200, "the session token is the content token")
	backend.close()
	waited = 0
	while rig.auth.login_for_token(backend.token) != "" and waited < 400:
		rig.pump()
		backend.poll(0.005)
		waited += 1
	eq(rig.get_path("/worlds", {"Authorization": "Bearer " + backend.token}, false).status, 401, "the token dies with the connection")
	rig.host.shutdown()


# --- content client -------------------------------------------------------------------

func _cache(name: String) -> String:
	return ProjectSettings.globalize_path(BASE + "/" + name)


func test_client_downloads_a_world_into_its_cache() -> void:
	var b := _fixture()
	var rig := Rig.new(b)
	var cc := rig.client()
	var worlds := cc.list_worlds()
	check(worlds.ok, worlds.error)
	eq(worlds.worlds[0]["id"], "fx")
	var cache := _cache("fx")
	var r := cc.update("fx", cache)
	check(r.ok, r.error)
	eq(int(r.files), 6)
	eq(FileAccess.get_file_as_bytes(cache.path_join("content/a/x.bin")), _big)
	eq(FileAccess.get_file_as_bytes(cache.path_join("content/a/y.bin")), _big, "copied, not fetched twice")
	eq(FileAccess.get_file_as_string(cache.path_join("world/world.json")).contains("Fixture"), true, "worlds/<id>/x lands in world/x")
	eq(FileAccess.get_file_as_string(cache.path_join("data/t.json")), "[1,2,3]")
	check(FileAccess.file_exists(cache.path_join("manifest.json")), "manifest.json marks the cache ready")
	check(not FileAccess.file_exists(cache.path_join("progress.json")), "no resume state left")
	check(not FileAccess.file_exists(cache.path_join("content/a/x.bin.part")), "no .part left")
	# the cache is then readable through ContentSource
	ContentSource.use_world("fx", ProjectSettings.globalize_path(BASE))
	eq(ContentSource.read_text("data/t.json"), "[1,2,3]")
	eq(ContentSource.read_json("worlds/fx/maps/1.json")["id"], 1)
	ContentSource.use_dev()
	# an up-to-date cache downloads nothing
	var again := cc.update("fx", cache)
	check(again.ok, again.error)
	eq(int(again.files), 0, "nothing missing")
	eq(int(again.bytes), 0)
	rig.host.shutdown()


func test_client_resumes_a_cut_download() -> void:
	var b := _fixture()
	var rig := Rig.new(b)
	var cc := rig.client()
	var cache := _cache("resume")
	var m: Dictionary = cc.fetch_manifest("fx").manifest
	var dest := cache.path_join("content/a/x.bin")
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	var part := FileAccess.open(dest + ".part", FileAccess.WRITE)
	part.store_buffer(_big.slice(0, 1200000)) # the connection was cut here
	part.close()
	var first := [-1]
	cc.progress = func(done: int, _total: int, path: String) -> void:
		if first[0] < 0 and path == "content/a/x.bin":
			first[0] = done
	var r := cc.download(m, cache, cc.diff(m, cache))
	check(r.ok, r.error)
	check(first[0] > 1200000, "the first progress is past the resume point (%d)" % first[0])
	eq(FileAccess.get_file_as_bytes(dest), _big, "complete and identical")
	rig.host.shutdown()


func test_client_rejects_a_file_with_the_wrong_hash() -> void:
	var b := _fixture()
	var rig := Rig.new(b)
	var cc := rig.client()
	var cache := _cache("bad")
	var m: Dictionary = cc.fetch_manifest("fx").manifest
	var dest := cache.path_join("content/a/x.bin")
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	var corrupt := _big.slice(0, 1200000)
	corrupt[500] ^= 255 # a resumed part that was damaged
	var part := FileAccess.open(dest + ".part", FileAccess.WRITE)
	part.store_buffer(corrupt)
	part.close()
	var r := cc.download(m, cache, cc.diff(m, cache))
	check(not r.ok, "download refused")
	check(str(r.error).contains("hash mismatch"), str(r.error))
	check(not FileAccess.file_exists(dest), "the bad file is not installed")
	check(not FileAccess.file_exists(dest + ".part"), "and not kept for a resume")
	check(not FileAccess.file_exists(cache.path_join("manifest.json")), "the cache is not marked ready")
	# the next attempt starts again and succeeds
	var again := cc.download(m, cache, cc.diff(m, cache))
	check(again.ok, again.error)
	rig.host.shutdown()


func test_client_refuses_an_unsafe_manifest_and_unauthorised_access() -> void:
	var b := _fixture()
	var rig := Rig.new(b)
	var cc := rig.client()
	var evil := b.manifest.duplicate(true)
	evil["files"][0]["path"] = "content/../../outside.txt"
	evil["version"] = ContentManifest.version_of(evil["files"])
	var r := cc.download(evil, _cache("evil"), evil["files"])
	check(not r.ok, "unsafe path refused before any request")
	check(not FileAccess.file_exists(_cache("evil").get_base_dir().path_join("outside.txt")))
	var stranger := ContentClient.new("127.0.0.1", rig.host.http_port(), "nope")
	stranger.pump = rig.pump
	var denied := stranger.list_worlds()
	check(not denied.ok)
	eq(int(denied.status), 401)
	check(not stranger.fetch_manifest("fx").ok)
	rig.host.shutdown()


func test_client_update_removes_what_the_new_version_dropped() -> void:
	var b := _fixture()
	var rig := Rig.new(b)
	var cc := rig.client()
	var cache := _cache("upd")
	check(cc.update("fx", cache).ok)
	DirAccess.remove_absolute(_root.path_join("content/a/z.txt"))
	_write("content/a/w.txt", "new file".to_utf8_buffer())
	var b2 := WorldPackage.build("fx", _root, _store, true)
	rig.host.content.set_package(b2)
	var r := cc.update("fx", cache)
	check(r.ok, r.error)
	eq(int(r.files), 1, "only the new file")
	check(not FileAccess.file_exists(cache.path_join("content/a/z.txt")), "stale file removed")
	eq(FileAccess.get_file_as_string(cache.path_join("content/a/w.txt")), "new file")
	var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(cache.path_join("manifest.json")))
	eq(m["version"], b2.manifest["version"], "manifest.json is the new version")
	rig.host.shutdown()


func test_the_real_incarnam_world_packages() -> void:
	# C.02b: the real world's package holds the data and the assets its _content.json selects (hashing
	# 20 000 files is for the server: here only the selection is checked, not built)
	var root := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var wa := WorldAssets.new(root, "incarnam")
	var globs := wa.compute()
	if globs.is_empty():
		return # no extracted content on this machine
	check(globs.has("content/Content/Maps/154010373.json"), "the start map")
	check(globs.size() < 20000, "a selection, not the content folder")
	check(wa.size_of(globs) < 4000000000, "Incarnam is far below the 22 GB of content/")
	check(not Array(globs).any(func(g: Variant) -> bool: return str(g).begins_with("content/Content/Maps/Gfx/*")), "no whole-folder glob on the textures")
	var written: Variant = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("worlds/incarnam/" + WorldAssets.FILE)))
	check(written is Dictionary and (written as Dictionary).get("globs", []).size() == globs.size(),
			"worlds/incarnam/_content.json is up to date: rerun tools/world_assets.gd --world=incarnam")
