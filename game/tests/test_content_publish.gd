## The publication step of the content (roadmap C.06): ContentPublisher writes a versioned, immutable
## package (checkpointed hash index, bundle parts, one zip per zone, stamp, pointer), PublishedPackage
## reads it back without hashing anything, and a client downloads a zone in ONE request from a real
## HTTP server on 127.0.0.1 (file by file when the zip is absent or damaged). Fixture: user://test_zones/.
extends ZonesRig


func _publish(opts := {}) -> ContentPublisher.Result:
	return ContentPublisher.publish("zx", _root, _store, opts)


func _read(path: String) -> Dictionary:
	return PublishedPackage.read_json(path)


func test_publish_writes_an_immutable_version_and_a_pointer() -> void:
	_zoned()
	var r := _publish()
	check(r.ok, r.error)
	check(not r.unchanged and r.hashed > 0, "first publication hashes")
	var cur := PublishedPackage.current(_store, "zx")
	eq(cur["release"], r.release, "the pointer names the release")
	eq(cur["version"], r.version)
	var dir := PublishedPackage.version_dir(_store, "zx", r.release)
	for name in ["manifest.json", "blobs.json", "release.json", "zones.json", "bundle.json"]:
		check(FileAccess.file_exists(dir.path_join(name)), name + " is published")
	check(FileAccess.file_exists(dir.path_join("zones/20/manifest.json")) and FileAccess.file_exists(dir.path_join("zones/20/pack.zip")),
			"a manifest and a zip per zone")
	var stamp := _read(dir.path_join("release.json"))
	check((stamp["artifacts"] as Dictionary).has("zones/20/pack.zip") and (stamp["artifacts"] as Dictionary).has("bundle/part-000.zip"),
			"the stamp lists every artifact with its size")
	eq(PublishedPackage.verify(_store, "zx"), "", "complete")
	var zm := _read(dir.path_join("zones/20/manifest.json"))
	check(ContentManifest.validate(zm) == "" and zm.get("pack") is Dictionary, "the zone manifest stays valid and carries its pack")
	eq(int(zm["pack"]["size"]), FileAccess.open(dir.path_join("zones/20/pack.zip"), FileAccess.READ).get_length())
	eq(FileHash.sha256(dir.path_join("zones/20/pack.zip")), zm["pack"]["hash"], "the hash of the zip")
	# the zip holds each distinct content of the zone, named by hash
	var zip := ZIPReader.new()
	eq(zip.open(dir.path_join("zones/20/pack.zip")), OK)
	var names := zip.get_files()
	eq(names.size(), ContentManifest.unique_blobs(zm["files"]).size(), "one entry per distinct content")
	for h: String in ContentManifest.unique_blobs(zm["files"]):
		eq(ContentManifest.hash_bytes(zip.read_file(h)), h, "entry " + h.substr(0, 8))
	zip.close()
	# a second run: nothing hashed, nothing rebuilt, same release
	var again := _publish()
	check(again.ok and again.unchanged and again.hashed == 0, "republishing the same files does nothing")
	eq(again.release, r.release)


func test_the_server_reads_what_was_published_without_hashing() -> void:
	_zoned()
	var r := _publish()
	check(r.ok, r.error)
	var built := PublishedPackage.load_package(_store, "zx", _root)
	check(built.ok, built.error)
	eq(built.manifest["version"], r.built.manifest["version"], "same manifest")
	eq(built.zone_index["version"], r.built.zone_index["version"], "same zones")
	eq(built.zones.size(), r.built.zones.size())
	var with_files := built.zones.values().filter(func(z: Dictionary) -> bool: return not (z["files"] as Array).is_empty())
	eq(built.zone_packs.size(), with_files.size(), "every zone that has files has a zip")
	eq(built.bundle_index["version"], built.manifest["version"], "the bundle index is the one of the version")
	eq(built.bundle_files.size(), (built.bundle_index["parts"] as Array).size())
	eq(built.hashed, 0, "reading hashes nothing")
	for h: String in r.built.blobs:
		check(built.blobs.has(h) and FileAccess.file_exists(str(built.blobs[h]["path"])), "a blob resolves to a file " + h.substr(0, 8))
		eq(built.blobs[h]["path"], r.built.blobs[h]["path"], "same place on disk")
	# not published, cut, damaged: a clear message that names the build step
	var other := PublishedPackage.load_package(_store, "plain", _root)
	check(not other.ok and other.error.contains("--build-packages"), "a world never published: " + other.error)
	var dir := PublishedPackage.version_dir(_store, "zx", r.release)
	var pack_path := dir.path_join("zones/20/pack.zip")
	var f := FileAccess.open(pack_path, FileAccess.READ_WRITE)
	f.seek_end()
	f.store_8(0)
	f.close()
	var bad := PublishedPackage.load_package(_store, "zx", _root)
	check(not bad.ok and bad.error.contains("zones/20/pack.zip"), "a zip of another size is refused: " + bad.error)
	var fixed := _publish()
	check(fixed.ok and not fixed.unchanged, "republishing repairs it")
	check(PublishedPackage.load_package(_store, "zx", _root).ok, "readable again")


func test_an_interrupted_build_resumes_and_publishes_nothing() -> void:
	_zoned()
	var total := _publish().hashed
	check(total > 6, "fixture has files to hash")
	ContentFolder.remove_dir(_store)
	var cut := _publish({"abort_after": 4})
	check(not cut.ok and cut.error.contains("interrupted"), "the build stopped: " + cut.error)
	eq(PublishedPackage.current(_store, "zx"), {}, "no pointer: nothing was published")
	check(PublishedPackage.verify(_store, "zx").contains("non publie"), "the server would refuse to start, and say why")
	var index := _read(_store.path_join("zx/index.json"))
	check(index.size() >= 4, "the hash index was checkpointed (%d entries)" % index.size())
	var resumed := _publish()
	check(resumed.ok, resumed.error)
	check(resumed.hashed <= total - 4, "the second run reuses what was hashed (%d of %d)" % [resumed.hashed, total])
	eq(PublishedPackage.verify(_store, "zx"), "")


func test_a_new_version_does_not_touch_the_previous_one_and_old_ones_are_pruned() -> void:
	_zoned()
	var first := _publish({"keep": 2})
	_write(CONTENT + "/Maps/Gfx/103.png", PackedByteArray([7, 7, 7, 7]))
	OS.delay_msec(1100) # published_at is in seconds
	var second := _publish({"keep": 2})
	check(second.ok and second.release != first.release, "another release")
	eq(PublishedPackage.current(_store, "zx")["release"], second.release, "the pointer moved last")
	check(PublishedPackage.verify(_store, "zx") == "" and FileAccess.file_exists(PublishedPackage.version_dir(_store, "zx", first.release).path_join("release.json")),
			"the previous version is still there, complete")
	_write(CONTENT + "/Maps/Gfx/103.png", PackedByteArray([8, 8, 8, 8, 8]))
	OS.delay_msec(1100)
	var third := _publish({"keep": 2})
	check(third.ok, third.error)
	check(not DirAccess.dir_exists_absolute(PublishedPackage.version_dir(_store, "zx", first.release)), "the oldest one was pruned")
	check(DirAccess.dir_exists_absolute(PublishedPackage.version_dir(_store, "zx", second.release)), "the two newest are kept")


func test_a_client_installs_a_zone_with_one_request() -> void:
	_zoned()
	check(_publish().ok, "published")
	var built := PublishedPackage.load_package(_store, "zx", _root)
	var rig := Rig.new([built])
	var cc := rig.client()
	cc.token = _login(rig)
	var dir := ProjectSettings.globalize_path(BASE).path_join("cache/zx")
	check(cc.update("zx", dir).ok, "base")
	var m := cc.fetch_zone("zx", "20")
	check(m.ok and m.manifest.get("pack") is Dictionary, "the zone manifest announces its zip")
	var r := cc.install_zone("zx", "20", dir)
	check(r.ok, r.error)
	check(r.pack and r.files > 0, "the zone came from its zip")
	for f: Dictionary in m.manifest["files"]:
		check(FileHash.sha256(dir.path_join(ContentSource.cache_relative(f["path"], "zx"))) == f["hash"], "installed " + f["path"])
	check(not FileAccess.file_exists(dir.path_join("_zones/20.zip")), "the zip does not stay in the cache")
	eq(ContentClient.zone_version(dir, "20"), m.manifest["version"])
	# the route: whitelist and token
	var f := HttpFetch.new()
	f.start("127.0.0.1", rig.host.http_port(), "/worlds/zx/zones/20/pack.zip", {})
	while not f.poll():
		rig.pump()
	eq(f.status, 401, "no token, no zip")
	f = HttpFetch.new()
	f.start("127.0.0.1", rig.host.http_port(), "/worlds/zx/zones/99/pack.zip", {"Authorization": "Bearer " + cc.token})
	while not f.poll():
		rig.pump()
	eq(f.status, 404, "unknown zone")
	f = HttpFetch.new()
	f.start("127.0.0.1", rig.host.http_port(), "/worlds/zx/zones/20/pack.zip", {"Authorization": "Bearer " + cc.token, "Range": "bytes=0-9"})
	while not f.poll():
		rig.pump()
	eq(f.status, 206, "the zip can be resumed")
	_end(rig)


func test_without_a_zip_or_with_a_damaged_one_the_files_come_one_by_one() -> void:
	_zoned()
	check(_publish({"no_zone_packs": true}).ok, "published without zone zips")
	var built := PublishedPackage.load_package(_store, "zx", _root)
	check(built.zone_packs.is_empty() and not (built.zones["20"] as Dictionary).has("pack"), "no zip announced")
	var rig := Rig.new([built])
	var cc := rig.client()
	cc.token = _login(rig)
	var dir := ProjectSettings.globalize_path(BASE).path_join("cache/zx")
	check(cc.update("zx", dir).ok, "base")
	var r := cc.install_zone("zx", "20", dir)
	check(r.ok and not r.pack and r.files > 0, "file by file still works")
	_end(rig)
	# damaged: same size, other bytes -> the hash of the manifest refuses it, the files are fetched one by one
	_zoned()
	var pub := _publish()
	check(pub.ok, pub.error)
	var pack_path := PublishedPackage.version_dir(_store, "zx", pub.release).path_join("zones/30/pack.zip")
	var bytes := FileAccess.get_file_as_bytes(pack_path)
	bytes[bytes.size() / 2] = (bytes[bytes.size() / 2] + 1) & 255
	var w := FileAccess.open(pack_path, FileAccess.WRITE)
	w.store_buffer(bytes)
	w.close()
	var rig2 := Rig.new([PublishedPackage.load_package(_store, "zx", _root)])
	var cc2 := rig2.client()
	cc2.token = _login(rig2)
	var dir2 := ProjectSettings.globalize_path(BASE).path_join("cache/zx2")
	check(cc2.update("zx", dir2).ok, "base")
	var d := cc2.install_zone("zx", "30", dir2)
	check(d.ok and not d.pack and d.files > 0, "a damaged zip is ignored: " + d.error)
	check(FileAccess.file_exists(dir2.path_join("content/Content/Maps/4.json")), "the zone is installed anyway")
	_end(rig2)


func test_files_by_hash_for_a_static_host() -> void:
	_zoned()
	var pub := _publish({"copy_files": true})
	check(pub.ok, pub.error)
	var built := PublishedPackage.load_package(_store, "zx", _root)
	check(built.ok, built.error)
	for h: String in built.blobs:
		check(str(built.blobs[h]["path"]).begins_with(_store), "a blob is read from the published files/")
		check(FileAccess.file_exists(_store.path_join("zx/files").path_join(h)), "files/<hash> exists " + h.substr(0, 8))
		eq(FileHash.sha256(_store.path_join("zx/files").path_join(h)), h, "named by its hash")
		break
	var rig := Rig.new([built])
	var cc := rig.client()
	cc.token = _login(rig)
	var dir := ProjectSettings.globalize_path(BASE).path_join("cache/zx3")
	check(cc.update("zx", dir).ok, "the server serves the published copies")
	_end(rig)


func test_the_published_layout_is_the_api_layout() -> void:
	_zoned()
	var pub := _publish()
	var dir := PublishedPackage.version_dir(_store, "zx", pub.release)
	var rig := Rig.new([PublishedPackage.load_package(_store, "zx", _root)])
	var cc := rig.client()
	cc.token = _login(rig)
	for pair in [["manifest.json", "/worlds/zx/manifest.json"], ["zones.json", "/worlds/zx/zones.json"],
			["zones/20/manifest.json", "/worlds/zx/zones/20/manifest.json"], ["bundle.json", "/worlds/zx/bundle.json"]]:
		var served := cc._get_json(pair[1])
		check(served.ok, pair[1])
		eq(served.data, _read(dir.path_join(pair[0])), "%s on disk is what the API serves" % pair[0])
	_end(rig)
