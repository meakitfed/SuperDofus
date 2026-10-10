## The publication of the content (roadmap C.07): ContentPublisher writes content-addressed bundles, one
## manifest per fragment (the base, each zone), a release index and the world's pointer last; a second
## publication writes nothing, a change writes only the changed contents, a cut publication publishes
## nothing and resumes, old releases are pruned with what only they used. A client installs a zone in a
## request or two from a real HTTP server on 127.0.0.1. Fixture: user://test_zones/.
extends ZonesRig


func _publish(opts := {}) -> ContentPublisher.Result:
	return ContentPublisher.publish("zx", _root, _store, opts)


func _release(id: String) -> Dictionary:
	return ContentStore.read_json(_store.path_join(ContentRelease.release_path("zx", id)))


func _files_under(dir: String) -> int:
	var n := 0
	for sub in DirAccess.get_directories_at(dir):
		n += DirAccess.get_files_at(dir.path_join(sub)).size()
	return n


func test_publish_writes_bundles_manifests_a_release_and_the_pointer() -> void:
	_zoned()
	var r := _publish()
	check(r.ok, r.error)
	check(not r.unchanged and r.hashed > 0 and r.bundles_written >= 1, "first publication hashes and bundles")
	var p := ContentStore.pointer(_store, "zx")
	eq(p["release"], r.release, "the pointer names the release")
	eq(ContentStore.check(_store, "zx"), "", "published")
	var text := FileAccess.get_file_as_bytes(_store.path_join(ContentRelease.release_path("zx", r.release)))
	eq(ContentRelease.release_id(text), r.release, "a release is named by the hash of its bytes")
	var rel := _release(r.release)
	eq(ContentRelease.validate_release(rel, "zx"), "")
	eq((rel["zones"] as Dictionary).keys().size(), r.built.zones.size(), "every zone is a fragment")
	eq(rel["zones"]["20"]["maps"].map(func(m: Variant) -> int: return int(m)), [3], "the maps of a zone")
	eq(int(p["zones"]), r.built.zones.size())
	# every file of every fragment is in a bundle, at its offset
	for frag: String in [ContentRelease.BASE] + (rel["zones"] as Dictionary).keys():
		var h := ContentRelease.fragment_hash(rel, frag)
		var d := ContentRelease.decode_fragment(FileAccess.get_file_as_bytes(_store.path_join(ContentRelease.manifest_path(h))), h)
		check(d.ok, d.error)
		for row: Array in d.manifest["files"]:
			var bundle := FileAccess.open(_store.path_join(ContentRelease.bundle_path(d.manifest["bundles"][row[3]])), FileAccess.READ)
			bundle.seek(int(row[4]))
			eq(ContentManifest.hash_bytes(bundle.get_buffer(int(row[2]))), row[1], "%s is in its bundle" % row[0])
	# each content once in the whole store
	var index: Dictionary = ContentStore.read_json(_store.path_join(ContentStore.BUNDLE_INDEX))["contents"]
	eq(index.size(), r.built.blobs.size(), "one place per distinct content")
	# a second run: nothing hashed, nothing written, same release
	var again := _publish()
	check(again.ok and again.unchanged and again.hashed == 0 and again.bundles_written == 0, "republishing the same files does nothing")
	eq(again.release, r.release)


func test_a_change_writes_only_the_changed_content() -> void:
	_zoned()
	var first := _publish()
	var bundles := _files_under(_store.path_join("bundles"))
	_write(CONTENT + "/Maps/Gfx/103.png", PackedByteArray([7, 7, 7, 7, 7, 7]))
	var second := _publish()
	check(second.ok and second.release != first.release, "another release")
	eq(second.bundles_written, 1, "one small bundle for the one changed file")
	eq(second.bytes_written, 6)
	eq(_files_under(_store.path_join("bundles")), bundles + 1, "the earlier bundles are reused as they are")
	var a := _release(first.release)
	var b := _release(second.release)
	eq(a["base"]["manifest"], b["base"]["manifest"], "an unchanged fragment keeps its manifest (same hash)")
	check(a["zones"]["30"]["manifest"] != b["zones"]["30"]["manifest"], "the zone of the changed texture has a new one")


func test_an_interrupted_publication_resumes_and_publishes_nothing() -> void:
	_zoned()
	var total := _publish().hashed
	check(total > 6, "fixture has files to hash")
	ContentFolder.remove_dir(_store)
	var cut := _publish({"abort_after": 4})
	check(not cut.ok and cut.error.contains("interrupted"), "the build stopped: " + cut.error)
	eq(ContentStore.pointer(_store, "zx"), {}, "no pointer: nothing was published")
	check(ContentStore.check(_store, "zx").contains("non publie"), "the server says why it cannot serve it")
	var index := ContentStore.read_json(_store.path_join("zx/index.json"))
	check(index.size() >= 4, "the hash index was checkpointed (%d entries)" % index.size())
	# a stop while bundling: one content per bundle, the index saved after each read, stop once one bundle is indexed
	var index_path := _store.path_join(ContentStore.BUNDLE_INDEX)
	var stopped := _publish({"bundle_mb": 0.000001, "read_batch": 2, "checkpoint_ms": 1,
			"should_stop": func() -> bool: return FileAccess.file_exists(index_path)})
	check(not stopped.ok, "stopped while bundling: " + stopped.error)
	eq(ContentStore.pointer(_store, "zx"), {}, "still nothing published")
	var resumed := _publish()
	check(resumed.ok, resumed.error)
	check(resumed.hashed <= total - 4, "the second run reuses what was hashed (%d of %d)" % [resumed.hashed, total])
	eq(ContentStore.check(_store, "zx"), "")
	for f in DirAccess.get_files_at(_store.path_join("bundles")):
		check(not f.ends_with(".tmp"), "no bundle left half written: " + f)


func test_old_releases_are_pruned_with_what_only_they_used() -> void:
	_zoned()
	var first := _publish({"keep": 2})
	_write(CONTENT + "/Maps/Gfx/103.png", PackedByteArray([7, 7, 7, 7]))
	var second := _publish({"keep": 2})
	check(second.ok and second.release != first.release)
	check(FileAccess.file_exists(_store.path_join(ContentRelease.release_path("zx", first.release))), "the previous release is kept")
	var first_zone: String = _release(first.release)["zones"]["30"]["manifest"]
	_write(CONTENT + "/Maps/Gfx/103.png", PackedByteArray([8, 8, 8, 8, 8]))
	var third := _publish({"keep": 2})
	check(third.ok, third.error)
	check(not FileAccess.file_exists(_store.path_join(ContentRelease.release_path("zx", first.release))), "the oldest one was pruned")
	check(FileAccess.file_exists(_store.path_join(ContentRelease.release_path("zx", second.release))), "the two newest are kept")
	check(not FileAccess.file_exists(_store.path_join(ContentRelease.manifest_path(first_zone))), "a manifest only it used is gone")
	var index: Dictionary = ContentStore.read_json(_store.path_join(ContentStore.BUNDLE_INDEX))["contents"]
	check(not index.has(ContentManifest.hash_bytes(PackedByteArray([7, 7, 7, 7]))) or FileAccess.file_exists(
			_store.path_join(ContentRelease.bundle_path(str(index[ContentManifest.hash_bytes(PackedByteArray([7, 7, 7, 7]))][0])))),
			"the index never points to a removed bundle")
	check(index.has(ContentManifest.hash_bytes(PackedByteArray([8, 8, 8, 8, 8]))), "the newest content is indexed")


func test_a_client_installs_a_zone_in_a_few_requests() -> void:
	_zoned()
	check(_publish().ok, "published")
	var rig := Rig.new([])
	rig.host.content.store = _store
	var cc := rig.client()
	cc.token = _login(rig)
	var dir := ProjectSettings.globalize_path(BASE).path_join("cache/zx")
	var base := cc.update("zx", dir)
	check(base.ok, base.error)
	var rel := ContentClient.local_release(dir)
	eq(ContentRelease.validate_release(rel, "zx"), "", "the release is kept with the base")
	var plan := cc.plan_install("zx", ContentClient.installed_release(dir), rel, ["30"], dir)
	check(plan.ok, plan.error)
	check((plan["ranges"] as Array).size() <= 2, "a zone's contents are side by side: %d request(s)" % (plan["ranges"] as Array).size())
	var r := cc.install(plan)
	check(r.ok, r.error)
	check(ContentClient.fragment_installed(dir, rel, "30"), "remembered as installed")
	check(FileAccess.file_exists(dir.path_join(CONTENT + "/Maps/4.json")), "its files are there")
	var again := cc.plan_install("zx", ContentClient.installed_release(dir), rel, ["30"], dir)
	check((again["ranges"] as Array).is_empty(), "nothing left to fetch")
	_end(rig)


func test_the_server_starts_without_reading_the_content() -> void:
	_zoned()
	check(_publish().ok)
	# what a starting server does with the store: one small file (the pointers), nothing hashed, nothing walked
	var t0 := Time.get_ticks_usec()
	eq(ContentStore.check(_store, "zx"), "")
	check(Time.get_ticks_usec() - t0 < 200000, "instant")
	var rig := Rig.new([])
	rig.host.content.store = _store
	var token := _login(rig)
	var f := HttpFetch.new()
	f.start("127.0.0.1", rig.host.http_port(), "/worlds", {"Authorization": "Bearer " + token})
	while not f.poll():
		rig.pump()
	var list: Array = JSON.parse_string(f.body.get_string_from_utf8())
	eq(list[0]["release"], ContentStore.pointer(_store, "zx")["release"], "listed from the pointer")
	_end(rig)
