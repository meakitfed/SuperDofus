## Byte ranges of the bundles (roadmap C.07): the plan of the requests (files side by side share one, gaps
## and size limits), the bundle writer (each content once, named by its bytes), and the downloader that cuts
## a stream into files, checks them, and resumes a cut request from its first unfinished file (a real HTTP
## server on 127.0.0.1 serving a published store). Fixture under user://test_ranges/.
extends TestCase

const BASE := "user://test_ranges"


func _e(bundle: String, offset: int, size: int) -> Dictionary:
	return {"bundle": bundle, "offset": offset, "size": size, "hash": "%d" % offset}


func test_plan_groups_neighbours_and_respects_the_limits() -> void:
	var a := "a".repeat(64)
	var b := "b".repeat(64)
	var plan := ContentRelease.plan_ranges([_e(a, 100, 10), _e(a, 0, 50), _e(a, 50, 50), _e(b, 0, 5)], 0, 1000)
	eq(plan.size(), 2, "one request per bundle when the files touch")
	eq([plan[0]["start"], plan[0]["end"]], [0, 110])
	eq(plan[0]["files"].map(func(e: Dictionary) -> int: return e["offset"]), [0, 50, 100], "in the order of the bytes")
	var gap := ContentRelease.plan_ranges([_e(a, 0, 10), _e(a, 30, 10)], 20, 1000)
	eq(gap.size(), 1, "a small gap is read and dropped")
	eq(ContentRelease.ranges_bytes(gap), 40)
	eq(ContentRelease.plan_ranges([_e(a, 0, 10), _e(a, 31, 10)], 20, 1000).size(), 2, "a bigger gap is two requests")
	eq(ContentRelease.plan_ranges([_e(a, 0, 600), _e(a, 600, 600)], 0, 1000).size(), 2, "a request has a size limit")
	eq(ContentRelease.plan_ranges([_e(a, 0, 5000)], 0, 1000).size(), 1, "a bigger file is a request of its own")
	var empty := ContentRelease.plan_ranges([_e(a, 10, 0), _e(a, 0, 10), _e(a, 10, 5)], 0, 1000)
	eq(empty.size(), 1, "an empty file sits between its neighbours")
	eq(empty[0]["files"].map(func(e: Dictionary) -> int: return e["size"]), [10, 0, 5])


func test_the_bundle_writer_writes_each_content_once() -> void:
	var store := ProjectSettings.globalize_path(BASE).path_join("store")
	ContentFolder.remove_dir(ProjectSettings.globalize_path(BASE))
	var w := BundleWriter.new(store, 10)
	var x := "xxxxxx".to_utf8_buffer()
	var y := "yyyyyy".to_utf8_buffer()
	eq(w.add(ContentManifest.hash_bytes(x), x), "")
	eq(w.add(ContentManifest.hash_bytes(x), x), "", "twice the same content")
	eq(w.add(ContentManifest.hash_bytes(y), y), "", "closes the first bundle (past 10 bytes)")
	eq(w.close(), "")
	eq(w.bundles_written, 1, "x and y in one bundle: the limit is checked after a content")
	var at := w.locate(ContentManifest.hash_bytes(y))
	eq(int(at[1]), 6, "y after x, x written once")
	var path := store.path_join(ContentRelease.bundle_path(at[0]))
	eq(ContentManifest.hash_bytes(FileAccess.get_file_as_bytes(path)), at[0], "named by the hash of its bytes")
	check(w.save_index(), "index saved")
	var again := BundleWriter.new(store)
	again.load_index()
	check(again.has(ContentManifest.hash_bytes(x)), "a later publication knows where x is")
	ContentFolder.remove_dir(ProjectSettings.globalize_path(BASE))


## A store with one bundle of `files` (name -> bytes), served on 127.0.0.1.
class Rig:
	var host := ServerHost.new()
	var token := ""
	var store := ""
	var locs := {} # name -> [bundle, offset, size, hash]

	func _init(p_store: String, files: Dictionary) -> void:
		store = p_store
		var auth := AuthService.new(AccountStore.new(Persistence.new()))
		auth.accounts.iterations = 1000
		host.auth = auth
		token = auth.register("bob", "secret1").token
		var w := BundleWriter.new(store)
		for name: String in files:
			w.add(ContentManifest.hash_bytes(files[name]), files[name])
		w.close()
		for name: String in files:
			var h := ContentManifest.hash_bytes(files[name])
			var at := w.locate(h)
			locs[name] = [at[0], at[1], (files[name] as PackedByteArray).size(), h]
		host.package_dir = store
		host.listen_http(0, "127.0.0.1")

	func pump() -> void:
		host.poll(0.005)
		OS.delay_msec(1)

	func entries(dir: String) -> Array:
		var out: Array = []
		for name: String in locs:
			var l: Array = locs[name]
			out.append({"bundle": l[0], "offset": l[1], "size": l[2], "hash": l[3], "paths": [name], "dests": [dir.path_join(name)]})
		return out


func _blob(n: int, seed_value: int) -> PackedByteArray:
	var block := PackedByteArray()
	block.resize(65521) # a prime: the pattern never lines up with a block of the server
	for i in block.size():
		block[i] = (i * (7 + seed_value) + (i >> 9)) & 255
	var b := PackedByteArray()
	while b.size() < n:
		b.append_array(block)
	return b.slice(0, n)


func test_the_downloader_cuts_the_stream_into_checked_files() -> void:
	var base := ProjectSettings.globalize_path(BASE)
	ContentFolder.remove_dir(base)
	var files := {"a.bin": _blob(300000, 1), "empty.txt": PackedByteArray(), "b.bin": _blob(700000, 2), "c.txt": "ccc".to_utf8_buffer()}
	var rig := Rig.new(base.path_join("store"), files)
	var dir := base.path_join("out")
	var dl := RangeDownloader.new("127.0.0.1", rig.host.http_port(), {"Authorization": "Bearer " + rig.token})
	dl.pump = rig.pump
	var ranges := ContentRelease.plan_ranges(rig.entries(dir))
	eq(ranges.size(), 1, "all side by side: one request")
	var done: Array = []
	var got := [0]
	var err := dl.fetch_all(ranges, func(b: String) -> String: return "/" + ContentRelease.bundle_path(b),
			func(n: int) -> void: got[0] += n, func(e: Dictionary) -> void: done.append(e["paths"][0]))
	eq(err, "")
	done.sort()
	eq(done, ["a.bin", "b.bin", "c.txt", "empty.txt"], "every file reported once written")
	eq(got[0], ContentRelease.ranges_bytes(ranges), "the bytes received")
	for name: String in files:
		eq(FileAccess.get_file_as_bytes(dir.path_join(name)), files[name], name)
	rig.host.shutdown()
	ContentFolder.remove_dir(base)


func test_a_cut_request_resumes_from_its_first_unfinished_file() -> void:
	var base := ProjectSettings.globalize_path(BASE)
	ContentFolder.remove_dir(base)
	var files := {"a.bin": _blob(200000, 3), "b.bin": _blob(6000000, 4), "c.bin": _blob(200000, 5)}
	var rig := Rig.new(base.path_join("store"), files)
	var dir := base.path_join("out")
	var dl := RangeDownloader.new("127.0.0.1", rig.host.http_port(), {"Authorization": "Bearer " + rig.token})
	dl.max_chunks = 1
	var cut := [false]
	var asked: Array = []
	dl.pump = func() -> void:
		rig.pump()
		# the server drops the connection once, in the middle of b.bin
		for c in rig.host.http._conns:
			if not cut[0] and c.response != null and c.remaining > 400000 and c.remaining < 4000000:
				cut[0] = true
				c.stream.disconnect_from_host()
	var done: Array = []
	var err := dl.fetch_all(ContentRelease.plan_ranges(rig.entries(dir)), func(b: String) -> String:
			asked.append(b)
			return "/" + ContentRelease.bundle_path(b),
			func(_n: int) -> void: pass, func(e: Dictionary) -> void: done.append(e["paths"][0]))
	eq(err, "")
	check(cut[0], "the connection was cut")
	eq(asked.size(), 2, "asked again once")
	done.sort()
	eq(done, ["a.bin", "b.bin", "c.bin"], "each file reported once")
	for name: String in files:
		eq(FileAccess.get_file_as_bytes(dir.path_join(name)), files[name], name)
	rig.host.shutdown()
	ContentFolder.remove_dir(base)
