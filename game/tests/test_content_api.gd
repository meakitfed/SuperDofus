## World packages and the content API (roadmap C.02, C.07): the manifest (stable, sensitive to one
## byte), the published release served as static files (token, names checked, Range), the content
## client (plan against the cache, byte ranges, resume from the journal, hash check, stale files). The
## server and the clients run in this process; the server is pumped while a client waits. Fixture game
## folder under user://test_content/.
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
			publish(built)

	## C.07: the build is published into its store, which the content API serves as static files.
	func publish(b: WorldPackage.Built) -> ContentPublisher.Result:
		var r := ContentPublisher.publish_built(b, b.store)
		host.content.store = b.store
		return r

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


# --- HTTP API (static files of the published release) ---------------------------------------------

## The published pieces of the fixture: {release, base (manifest hash), bundle (hash of the first bundle), rel}.
func _published(rig: Rig) -> Dictionary:
	var p := ContentStore.pointer(_store, "fx")
	var rel := ContentStore.read_json(_store.path_join(ContentRelease.release_path("fx", str(p["release"]))))
	var m := ContentRelease.decode_fragment(FileAccess.get_file_as_bytes(_store.path_join(ContentRelease.manifest_path(rel["base"]["manifest"]))),
			rel["base"]["manifest"])
	return {"release": str(p["release"]), "base": str(rel["base"]["manifest"]), "bundle": str(m.manifest["bundles"][0]),
			"rel": rel, "manifest": m.manifest}


func _row(m: Dictionary, path: String) -> Array:
	for row: Array in m["files"]:
		if row[0] == path:
			return row
	return []


func test_api_needs_a_session_token() -> void:
	var rig := Rig.new(_fixture())
	var pub := _published(rig)
	var none := rig.get_path("/worlds", {}, false)
	eq(none.status, 401, "no token")
	var wrong := rig.get_path("/worlds", {"Authorization": "Bearer deadbeef"}, false)
	eq(wrong.status, 401, "unknown token")
	var basic := rig.get_path("/worlds", {"Authorization": "Basic Ym9iOnNlY3JldDE="}, false)
	eq(basic.status, 401, "not a bearer token")
	eq(rig.get_path("/worlds/fx/releases/%s.json" % pub.release, {}, false).status, 401)
	eq(rig.get_path("/" + ContentRelease.manifest_path(pub.base), {}, false).status, 401)
	var no_bundle := rig.get_path("/" + ContentRelease.bundle_path(pub.bundle), {}, false)
	eq(no_bundle.status, 401)
	check(no_bundle.body.get_string_from_utf8().find("fx") == -1, "nothing revealed without a token")
	eq(rig.get_path("/worlds").status, 200)
	rig.host.shutdown()


func test_api_refuses_everything_without_accounts() -> void:
	var rig := Rig.new(_fixture(), false)
	eq(rig.get_path("/worlds", {"Authorization": "Bearer abc"}, false).status, 401, "an open server never serves content")
	rig.host.shutdown()


func test_api_lists_worlds_and_serves_the_release() -> void:
	var b := _fixture()
	var rig := Rig.new(b)
	var pub := _published(rig)
	var list: Variant = JSON.parse_string(rig.get_path("/worlds").body.get_string_from_utf8())
	eq(list.size(), 1)
	eq(list[0]["id"], "fx")
	eq(list[0]["name"], "Fixture")
	eq(list[0]["state"], "ready")
	eq(list[0]["release"], pub.release)
	eq(int(list[0]["files"]), 6)
	eq(int(list[0]["size"]), BIG * 2 + 3 + 7 + 8 + FileAccess.get_file_as_bytes(_root.path_join("worlds/fx/world.json")).size())
	var r := rig.get_path("/worlds/fx/releases/%s.json" % pub.release)
	eq(r.status, 200)
	eq(ContentRelease.release_id(r.body), pub.release, "a release is named by the hash of its bytes")
	eq(ContentRelease.validate_release(JSON.parse_string(r.body.get_string_from_utf8()), "fx"), "")
	var m := rig.get_path("/" + ContentRelease.manifest_path(pub.base))
	eq(m.status, 200)
	var d := ContentRelease.decode_fragment(m.body, pub.base)
	check(d.ok, d.error)
	eq((d.manifest["files"] as Array).size(), 6, "every file of the base, with its place in a bundle")
	eq(d.manifest["files"].map(func(row: Array) -> String: return row[0]), _paths(b.manifest), "sorted like the manifest")
	eq(_row(d.manifest, "content/a/x.bin")[1], _row(d.manifest, "content/a/y.bin")[1], "same content, same hash")
	eq(_row(d.manifest, "content/a/x.bin")[4], _row(d.manifest, "content/a/y.bin")[4], "...and the same bytes in the bundle")
	eq(rig.get_path("/worlds/other/releases/%s.json" % pub.release).status, 404, "unknown world")
	eq(rig.get_path("/worlds/fx/releases/0000000000000000.json").status, 404, "unknown release")
	rig.host.shutdown()


func test_api_serves_bundles_by_range() -> void:
	var b := _fixture()
	var rig := Rig.new(b)
	var pub := _published(rig)
	var row := _row(pub.manifest, "content/a/z.txt")
	var url := "/" + ContentRelease.bundle_path(str(pub.manifest["bundles"][row[3]]))
	var f := rig.get_path(url, {"Range": "bytes=%d-%d" % [row[4], int(row[4]) + 2]})
	eq(f.status, 206)
	eq(f.body.get_string_from_utf8(), "zzz")
	eq(f.headers["content-length"], "3")
	eq(f.headers["accept-ranges"], "bytes")
	check(str(f.headers["cache-control"]).contains("immutable"), "named by its hash: cached forever")
	var big := _row(pub.manifest, "content/a/x.bin")
	var whole := rig.get_path("/" + ContentRelease.bundle_path(str(pub.manifest["bundles"][big[3]])))
	eq(whole.status, 200)
	eq(ContentManifest.hash_bytes(whole.body), str(pub.manifest["bundles"][big[3]]), "a bundle is named by the hash of its bytes")
	eq(whole.body.slice(int(big[4]), int(big[4]) + BIG), _big, "streamed by blocks")
	rig.host.shutdown()


func test_api_only_serves_names_it_checked() -> void:
	var b := _fixture()
	var rig := Rig.new(b)
	var pub := _published(rig)
	eq(rig.get_path("/bundles/00/" + "0".repeat(64) + ".bundle").status, 404, "unknown hash")
	eq(rig.get_path("/bundles/ab/" + pub.bundle + ".bundle").status, 404, "wrong folder")
	eq(rig.get_path("/bundles/" + pub.bundle.substr(0, 2) + "/" + pub.bundle.to_upper() + ".bundle").status, 404, "hash in capitals")
	eq(rig.get_path("/bundles/../worlds.json").status, 404, "path")
	eq(rig.get_path("/bundles/..%2F..%2Fworlds.json").status, 404, "encoded path")
	eq(rig.get_path("/worlds.json").status, 404, "the pointers are listed, not served raw")
	eq(rig.get_path("/bundles.json").status, 404, "the index of the publication is not served")
	eq(rig.get_path("/fx/index.json").status, 404, "nor the hash cache")
	eq(rig.get_path("/worlds/..%2Ffx/releases/" + pub.release + ".json").status, 404, "world id with a path")
	eq(rig.get_path("/worlds/fx/releases/../../worlds.json").status, 404)
	eq(rig.get_path("/").status, 404)
	eq(rig.get_path("/admin").status, 404)
	eq(rig.get_path("/worlds/fx").status, 404)
	rig.host.shutdown()


func test_api_range() -> void:
	var b := _fixture()
	var rig := Rig.new(b)
	var pub := _published(rig)
	var url := "/" + ContentRelease.bundle_path(pub.bundle)
	var size := ContentStore.file_size(_store.path_join(ContentRelease.bundle_path(pub.bundle)))
	var whole := rig.get_path(url).body
	var part := rig.get_path(url, {"Range": "bytes=10-19"})
	eq(part.status, 206)
	eq(part.body, whole.slice(10, 20))
	eq(part.headers["content-range"], "bytes 10-19/%d" % size)
	var tail := rig.get_path(url, {"Range": "bytes=%d-" % (size - 5)})
	eq(tail.body, whole.slice(size - 5))
	eq(rig.get_path(url, {"Range": "bytes=%d-" % size}).status, 416, "past the end")
	eq(rig.get_path(url, {"Range": "bytes=zz"}).status, 416, "garbage")
	rig.host.shutdown()


func test_publication_refuses_a_file_changed_since_its_hash() -> void:
	var b := _fixture()
	_write("content/a/z.txt", "zzX".to_utf8_buffer()) # same size: only the bytes tell
	var r := ContentPublisher.publish_built(b, b.store)
	check(not r.ok and r.error.contains("republier"), "the bundle would not match the manifest: " + r.error)
	eq(ContentStore.pointer(_store, "fx"), {}, "nothing published")


func test_two_clients_download_at_the_same_time() -> void:
	var b := _fixture()
	var rig := Rig.new(b)
	var pub := _published(rig)
	var url := "/" + ContentRelease.bundle_path(pub.bundle)
	var whole := rig.get_path(url).body
	var a := rig.fetch(url)
	var c := rig.fetch(url, {"Range": "bytes=1000-"})
	var d := rig.fetch("/worlds")
	while not (a.done and c.done and d.done):
		a.poll()
		c.poll()
		d.poll()
		rig.pump()
	eq(a.error, "")
	eq(a.body, whole)
	eq(c.body, whole.slice(1000))
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


func test_an_open_world_never_published_is_listed_not_downloadable() -> void:
	var b := _fixture()
	var rig := Rig.new(b)
	rig.host.allowed_worlds = PackedStringArray(["fx", "later"])
	rig.pump()
	var list: Array = JSON.parse_string(rig.get_path("/worlds").body.get_string_from_utf8())
	eq(list.map(func(w: Dictionary) -> String: return w["id"]), ["fx", "later"])
	eq(list[1]["state"], "unpublished")
	eq(list[1]["release"], "")
	rig.host.allowed_worlds = PackedStringArray(["later"])
	rig.pump()
	eq(rig.get_path("/worlds/fx/releases/%s.json" % _published(rig).release).status, 404, "a world the server does not open is not served")
	rig.host.shutdown()


# --- content client ---------------------------------------------------------------------------------

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
	check(int(r.bytes) < BIG * 2, "x and y are one content: fetched once (%d bytes)" % r.bytes)
	eq(FileAccess.get_file_as_bytes(cache.path_join("content/a/x.bin")), _big)
	eq(FileAccess.get_file_as_bytes(cache.path_join("content/a/y.bin")), _big, "written under both paths")
	eq(FileAccess.get_file_as_string(cache.path_join("world/world.json")).contains("Fixture"), true, "worlds/<id>/x lands in world/x")
	eq(FileAccess.get_file_as_string(cache.path_join("data/t.json")), "[1,2,3]")
	eq(ContentClient.installed_release(cache), r.release, "the state marks the cache ready")
	check(not ContentClient.interrupted(cache), "no journal left")
	# the cache is then readable through ContentSource
	ContentSource.use_world("fx", ProjectSettings.globalize_path(BASE))
	eq(ContentSource.read_text("data/t.json"), "[1,2,3]")
	eq(ContentSource.read_json("worlds/fx/maps/1.json")["id"], 1)
	ContentSource.use_dev()
	# an up-to-date cache downloads nothing, and a new client knows it from the small state file
	var again := rig.client().update("fx", cache)
	check(again.ok, again.error)
	eq(int(again.files), 0, "nothing missing")
	eq(int(again.bytes), 0)
	rig.host.shutdown()


func test_client_resumes_a_cut_download_from_its_journal() -> void:
	var b := _fixture()
	var rig := Rig.new(b)
	var cc := rig.client()
	cc.parallel_downloads = 1
	cc.chunks_per_poll = 1
	cc.range_max = 1 # one file per request: the cut falls between two files
	var cache := _cache("resume")
	cc.progress = func(_done: int, _total: int, path: String) -> void:
		if path != "":
			cc.cancel_requested = true # stop after the first file written
	var cut := cc.update("fx", cache)
	check(not cut.ok and str(cut.error).contains("cancelled"), "cut: " + str(cut.error))
	check(ContentClient.interrupted(cache), "the journal says what was written")
	eq(ContentClient.installed_release(cache), "", "not ready")
	var written := int(cut.files)
	check(written >= 1 and written < 6, "some files arrived (%d)" % written)
	var next := rig.client()
	var r := next.update("fx", cache)
	check(r.ok, r.error)
	eq(int(r.files), 6 - written, "only what the journal does not hold")
	eq(FileAccess.get_file_as_bytes(cache.path_join("content/a/x.bin")), _big, "complete and identical")
	check(not ContentClient.interrupted(cache))
	rig.host.shutdown()


func test_client_rejects_bytes_with_the_wrong_hash() -> void:
	var b := _fixture()
	var rig := Rig.new(b)
	var pub := _published(rig)
	var row := _row(pub.manifest, "content/a/z.txt")
	var path := _store.path_join(ContentRelease.bundle_path(str(pub.manifest["bundles"][row[3]])))
	var good := FileAccess.get_file_as_bytes(path)
	var bad := good.duplicate()
	bad[int(row[4])] ^= 255 # the store was damaged on the server
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bad)
	f.close()
	var cache := _cache("bad")
	var r := rig.client().update("fx", cache)
	check(not r.ok, "download refused")
	check(str(r.error).contains("hash mismatch"), str(r.error))
	check(not FileAccess.file_exists(cache.path_join("content/a/z.txt")), "the bad file is not installed")
	eq(ContentClient.installed_release(cache), "", "the cache is not marked ready")
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(good)
	f.close()
	var again := rig.client().update("fx", cache)
	check(again.ok, again.error)
	eq(FileAccess.get_file_as_string(cache.path_join("content/a/z.txt")), "zzz")
	rig.host.shutdown()


func test_client_refuses_an_unsafe_manifest_and_unauthorised_access() -> void:
	var evil := {"format": ContentRelease.FORMAT, "world": "fx", "frag": "", "bundles": ["a".repeat(64)],
			"files": [["content/../../outside.txt", "b".repeat(64), 1, 0, 0]]}
	var gz := JSON.stringify(evil).to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)
	var d := ContentRelease.decode_fragment(gz, ContentManifest.hash_bytes(gz))
	check(not d.ok and str(d.error).contains("unsafe"), "unsafe path refused before any request: " + str(d.error))
	check(not ContentRelease.decode_fragment(gz, "c".repeat(64)).ok, "bytes that are not the name asked for are refused")
	var b := _fixture()
	var rig := Rig.new(b)
	var stranger := ContentClient.new("127.0.0.1", rig.host.http_port(), "nope")
	stranger.pump = rig.pump
	var denied := stranger.list_worlds()
	check(not denied.ok)
	eq(int(denied.status), 401)
	check(not stranger.fetch_release("fx", _published(rig).release).ok)
	rig.host.shutdown()


func test_client_update_removes_what_the_new_release_dropped() -> void:
	var b := _fixture()
	var rig := Rig.new(b)
	var cache := _cache("upd")
	check(rig.client().update("fx", cache).ok)
	var first := ContentClient.installed_release(cache)
	DirAccess.remove_absolute(_root.path_join("content/a/z.txt"))
	_write("content/a/w.txt", "new file".to_utf8_buffer())
	var pub := rig.publish(WorldPackage.build("fx", _root, _store, true))
	check(pub.ok and pub.bundles_written == 1, "a new release writes only the new content (%d bundle)" % pub.bundles_written)
	var r := rig.client().update("fx", cache)
	check(r.ok, r.error)
	eq(int(r.files), 1, "only the new file")
	eq(int(r.bytes), "new file".length(), "only its bytes")
	check(not FileAccess.file_exists(cache.path_join("content/a/z.txt")), "stale file removed")
	eq(FileAccess.get_file_as_string(cache.path_join("content/a/w.txt")), "new file")
	check(ContentClient.installed_release(cache) != first and ContentClient.installed_release(cache) == pub.release, "the new release")
	rig.host.shutdown()


func test_repair_finds_a_damaged_file_and_the_next_update_fetches_it_alone() -> void:
	var b := _fixture()
	var rig := Rig.new(b)
	var cache := _cache("rep")
	var cc := rig.client()
	check(cc.update("fx", cache).ok)
	var f := FileAccess.open(cache.path_join("content/a/x.bin"), FileAccess.READ_WRITE)
	f.seek(1000)
	f.store_8(f.get_8() ^ 0xFF) # a bad sector: same size, other bytes
	f.close()
	check(cc.update("fx", cache).files == 0, "an update trusts what it wrote: no file is read")
	var r := cc.repair(cache, "fx")
	eq(int(r.bad), 1, "the full check finds it")
	check(ContentClient.interrupted(cache), "the good files are the journal of an install to finish")
	var u := rig.client().update("fx", cache)
	check(u.ok, u.error)
	eq(int(u.files), 1, "only the damaged file")
	eq(FileAccess.get_file_as_bytes(cache.path_join("content/a/x.bin")), _big)
	rig.host.shutdown()


func test_a_cache_of_the_previous_format_is_adopted_without_downloading() -> void:
	var b := _fixture()
	var rig := Rig.new(b)
	var cache := _cache("legacy")
	check(rig.client().update("fx", cache).ok)
	# make it look like a C.06 cache: manifest.json at its root, no install state
	DirAccess.remove_absolute(cache.path_join(ContentClient.STATE))
	var f := FileAccess.open(cache.path_join("manifest.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(b.manifest))
	f.close()
	var r := rig.client().update("fx", cache)
	check(r.ok, r.error)
	eq(int(r.files), 0, "every file was already there")
	check(not FileAccess.file_exists(cache.path_join("manifest.json")), "the old marker is gone")
	check(ContentClient.installed_release(cache) != "")
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
