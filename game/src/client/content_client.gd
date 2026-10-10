## Downloads the content of a world from a content server (roadmap C.02, C.07), the way a game launcher
## patches: a tiny pointer per world (`list_worlds`), a release index, one manifest per fragment (the base,
## each zone), then byte ranges of the bundles (RangeDownloader). No screen: the loading screen (C.03) and
## the zones (C.02c) drive it. Blocking calls that wait by calling `pump` (default: a short sleep), so a
## screen runs them in a thread and the tests pump the server in the same process.
##
##   var cc := ContentClient.new("192.168.1.5", 7778, token)       # token = login_ok.token
##   var worlds := cc.list_worlds()                                 # {ok, worlds: [{id, release, size...}]}
##   var rel := cc.fetch_release("dofus", release)                  # {ok, release}
##   var plan := cc.plan_install("dofus", release, rel.release, [ContentRelease.BASE], cache_dir)
##   var r := cc.install(plan)                                      # {ok, error, bytes, files}
##
## The cache (ContentSource.cache_relative layout) keeps what it installed in `_install/`: `state.json`
## {release, frags: {fragment: manifest hash}} (it marks the cache ready: ContentSource.MANIFEST), the release
## index and the manifests of the installed fragments. Knowing what is installed costs reading that small
## file: never a walk of the cache, never a hash of it (`repair` does that, on demand). A download appends
## each written file to `journal.log`: a cut install resumes without fetching or hashing anything again.
class_name ContentClient
extends RefCounted

const INSTALL_DIR := "_install"
const STATE := "_install/state.json"
const RELEASE := "_install/release.json"
const JOURNAL := "_install/journal.log"
const MANIFESTS := "_install/manifests"

var host := ""
var port := 0
var token := ""
## Callable(), called while waiting for the network
var pump := Callable()
## Callable(done_bytes: int, total_bytes: int, path: String)
var progress := Callable()
## set (from another thread: the loading screen) to stop at the next poll; what was written stays and is
## not fetched again. The error is then "cancelled".
var cancel_requested := false
## slows the download down (screen captures, tests): chunks read per poll and pause per poll
var chunks_per_poll := 64
var poll_delay_ms := 0
## requests in flight (RangeDownloader); tests set 1 to cut a download at a known place
var parallel_downloads := RangeDownloader.PARALLEL
## the largest span one request asks for (tests make it small to cut a download between two files)
var range_max := ContentRelease.RANGE_MAX
## files written by the running install (read with `progress`)
var files_done := 0
var _dl: RangeDownloader
## cache dir -> {path: hash}: what the installed fragments hold (loaded once, kept up to date)
var _have := {}


func _init(p_host := "", p_port := 0, p_token := "") -> void:
	host = p_host
	port = p_port
	token = p_token


## {ok, status, error, worlds}: one small request (the pointers of the worlds the server opens).
func list_worlds() -> Dictionary:
	var r := _http_get("/worlds")
	var data: Variant = JSON.parse_string(r.body.get_string_from_utf8()) if r.ok else null
	if r.ok and not data is Array:
		return {"ok": false, "status": r.status, "error": "bad worlds list", "worlds": []}
	return {"ok": r.ok, "status": r.status, "error": r.error, "worlds": data if r.ok else []}


## {ok, status, error, release}: a release index, checked against its id (the hash of its bytes).
func fetch_release(world: String, release: String) -> Dictionary:
	if not ContentRelease.is_release_id(release):
		return {"ok": false, "status": 0, "error": "bad release id", "release": {}}
	var r := _http_get("/worlds/%s/releases/%s.json" % [world.uri_encode(), release])
	if not r.ok:
		return {"ok": false, "status": r.status, "error": r.error, "release": {}}
	if ContentRelease.release_id(r.body) != release:
		return {"ok": false, "status": r.status, "error": "release damaged (hash mismatch)", "release": {}}
	var data: Variant = JSON.parse_string(r.body.get_string_from_utf8())
	var bad := ContentRelease.validate_release(data, world)
	if bad != "":
		return {"ok": false, "status": r.status, "error": "bad release: " + bad, "release": {}}
	return {"ok": true, "status": r.status, "error": "", "release": data}


## {ok, error, manifest}: a fragment manifest, from the cache when it was installed, else from the server.
func fetch_fragment(hash: String, cache_dir: String) -> Dictionary:
	var local := cache_dir.path_join(MANIFESTS).path_join(hash + ".json.gz")
	if FileAccess.file_exists(local):
		var m := ContentRelease.decode_fragment(FileAccess.get_file_as_bytes(local), hash)
		if m.ok:
			return m
	var r := _http_get("/" + ContentRelease.manifest_path(hash))
	if not r.ok:
		return {"ok": false, "status": r.status, "error": r.error, "manifest": {}}
	var d := ContentRelease.decode_fragment(r.body, hash)
	if d.ok:
		DirAccess.make_dir_recursive_absolute(local.get_base_dir())
		_write_bytes(local, r.body)
	d["status"] = r.status
	return d


## Brings the cache of `world` to the release the server publishes: the base and the zones it already holds.
## {ok, status, error, bytes, files, release}
func update(world: String, cache_dir: String) -> Dictionary:
	var out := {"ok": false, "status": 0, "error": "", "bytes": 0, "files": 0, "release": ""}
	var listed := list_worlds()
	if not listed.ok:
		out.merge({"status": listed.status, "error": listed.error}, true)
		return out
	for w: Dictionary in listed.worlds:
		if str(w.get("content", w.get("id", ""))) == world and ContentRelease.is_release_id(str(w.get("release", ""))):
			out["release"] = str(w["release"])
	if out["release"] == "":
		out["error"] = "world not published: " + world
		out["status"] = 404
		return out
	var rel := fetch_release(world, out["release"])
	if not rel.ok:
		out.merge({"status": rel.status, "error": rel.error}, true)
		return out
	var frags: Array = [ContentRelease.BASE]
	for frag: String in read_state(cache_dir).get("frags", {}):
		if frag != ContentRelease.BASE and ContentRelease.fragment_hash(rel.release, frag) != "":
			frags.append(frag)
	var plan := plan_install(world, out["release"], rel.release, frags, cache_dir)
	if not plan.ok:
		out.merge({"status": plan.status, "error": plan.error}, true)
		return out
	var r := install(plan)
	out.merge({"ok": r.ok, "error": r.error, "bytes": r.bytes, "files": r.files}, true)
	return out


## Installs one zone of the release installed with the base. {ok, error, bytes, files, already}
func install_zone(world: String, zone: String, cache_dir: String) -> Dictionary:
	var out := {"ok": false, "error": "", "bytes": 0, "files": 0, "already": false}
	var rel := local_release(cache_dir)
	var plan := plan_install(world, installed_release(cache_dir), rel, [zone], cache_dir)
	if not plan.ok:
		out["error"] = plan.error
		return out
	out["already"] = (plan["ranges"] as Array).is_empty() and fragment_installed(cache_dir, rel, zone)
	var r := install(plan)
	out.merge({"ok": r.ok, "error": r.error, "bytes": r.bytes, "files": r.files}, true)
	return out


# --- what the cache holds -------------------------------------------------------------------------

## The install state of a cache: {release, frags: {fragment: manifest hash}} ({} = nothing installed).
static func read_state(cache_dir: String) -> Dictionary:
	var path := cache_dir.path_join(STATE)
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return data if data is Dictionary and data.get("frags") is Dictionary else {}


## The release whose base is installed ("" = none).
static func installed_release(cache_dir: String) -> String:
	return str(read_state(cache_dir).get("release", ""))


## The release index installed with the base ({} = none).
static func local_release(cache_dir: String) -> Dictionary:
	var path := cache_dir.path_join(RELEASE)
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return data if data is Dictionary else {}


## An install was cut: its journal is there.
static func interrupted(cache_dir: String) -> bool:
	return FileAccess.file_exists(cache_dir.path_join(JOURNAL))


## A cache of the downloads before C.07 (manifest.json at its root): adopted by the next install, not downloaded again.
static func legacy(cache_dir: String) -> bool:
	return FileAccess.file_exists(cache_dir.path_join("manifest.json"))


## True when `frag` of `rel` is installed in this exact version.
static func fragment_installed(cache_dir: String, rel: Dictionary, frag: String) -> bool:
	var h := ContentRelease.fragment_hash(rel, frag)
	return h != "" and str(read_state(cache_dir).get("frags", {}).get(frag, "")) == h


# --- install -----------------------------------------------------------------------------------------

## What installing the fragments `frags` (ContentRelease.BASE and/or zone ids) of `rel` needs: the manifests
## (fetched once, then kept), compared in memory with what the cache holds. {ok, error, status, world, release,
## rel, frags, manifests: {frag: [hash, manifest]}, ranges, bytes (to download), files, dir}
func plan_install(world: String, release: String, rel: Dictionary, frags: Array, cache_dir: String) -> Dictionary:
	var out := {"ok": false, "error": "", "status": 0, "world": world, "release": release, "rel": rel, "frags": frags,
			"manifests": {}, "ranges": [], "bytes": 0, "files": 0, "dir": cache_dir}
	for frag: String in frags:
		var h := ContentRelease.fragment_hash(rel, frag)
		if h == "":
			out["error"] = "unknown fragment " + frag
			return out
		var m := fetch_fragment(h, cache_dir)
		if not m.ok:
			out["error"] = m.error
			out["status"] = int(m.get("status", 0))
			return out
		out["manifests"][frag] = [h, m.manifest]
	var have := _installed(cache_dir, world)
	var wanted := {} # content hash -> entry
	for frag: String in out["manifests"]:
		var m: Dictionary = out["manifests"][frag][1]
		for row: Array in m["files"]:
			var path := str(row[0])
			var rel_path := ContentSource.cache_relative(path, world)
			if rel_path == "":
				out["error"] = "refused path: " + path
				return out
			if str(have.get(path, "")) == str(row[1]):
				continue
			var e: Dictionary = wanted.get(str(row[1]), {})
			if e.is_empty():
				e = {"bundle": str(m["bundles"][int(row[3])]), "offset": int(row[4]), "size": int(row[2]), "hash": str(row[1]),
						"paths": [], "dests": []}
				wanted[str(row[1])] = e
			if not (e["paths"] as Array).has(path):
				(e["paths"] as Array).append(path)
				(e["dests"] as Array).append(cache_dir.path_join(rel_path))
				out["files"] += 1
	out["ranges"] = ContentRelease.plan_ranges(wanted.values(), ContentRelease.RANGE_GAP, range_max)
	out["bytes"] = ContentRelease.ranges_bytes(out["ranges"])
	out["ok"] = true
	return out


## Downloads what `plan` (plan_install) lacks, then records the fragments as installed (state.json), removes
## the files their previous version had and no installed fragment keeps. {ok, error, bytes, files}. Stops at
## the first error or a cancel; what was written stays (journal) and is not fetched again.
func install(plan: Dictionary) -> Dictionary:
	var out := {"ok": false, "error": "", "bytes": 0, "files": 0}
	var dir := str(plan["dir"])
	var world := str(plan["world"])
	var have := _installed(dir, world)
	DirAccess.make_dir_recursive_absolute(dir.path_join(INSTALL_DIR))
	files_done = 0
	if not (plan["ranges"] as Array).is_empty():
		var journal := FileAccess.open(dir.path_join(JOURNAL), FileAccess.READ_WRITE if interrupted(dir) else FileAccess.WRITE)
		if journal == null:
			out["error"] = "cannot write in " + dir
			return out
		journal.seek_end()
		var total := int(plan["bytes"])
		var received := [0]
		var last_flush := [Time.get_ticks_msec()]
		var err := _downloader().fetch_all(plan["ranges"], func(bundle: String) -> String: return "/" + ContentRelease.bundle_path(bundle),
				func(n: int) -> void:
					received[0] = clampi(received[0] + n, 0, total)
					out["bytes"] = received[0]
					if progress.is_valid():
						progress.call(received[0], total, ""),
				func(e: Dictionary) -> void:
					for p: String in e["paths"]:
						journal.store_line("%s\t%s" % [p, e["hash"]])
						have[p] = str(e["hash"])
						out["files"] += 1
					files_done = int(out["files"])
					if progress.is_valid():
						progress.call(int(out["bytes"]), int(plan["bytes"]), str(e["paths"][0]))
					if Time.get_ticks_msec() - int(last_flush[0]) >= 1000:
						last_flush[0] = Time.get_ticks_msec()
						journal.flush())
		journal.close()
		if err != "":
			out["error"] = err
			return out
	_finish(plan, have)
	out["ok"] = true
	return out


## The install is complete: stale files removed, state written, journal and old markers dropped.
func _finish(plan: Dictionary, have: Dictionary) -> void:
	var dir := str(plan["dir"])
	var world := str(plan["world"])
	var state := read_state(dir)
	if state.is_empty():
		state = {"format": ContentRelease.FORMAT, "world": world, "release": "", "frags": {}}
	var rel: Dictionary = plan["rel"]
	var frags: Dictionary = state["frags"]
	var replaced := {} # frag -> old manifest hash
	for frag: String in plan["manifests"]:
		var old := str(frags.get(frag, ""))
		var h: String = plan["manifests"][frag][0]
		if old != "" and old != h:
			replaced[frag] = old
		frags[frag] = h
	if (plan["frags"] as Array).has(ContentRelease.BASE): # a new release: the fragments it no longer has go
		for frag: String in frags.keys():
			if frag != ContentRelease.BASE and ContentRelease.fragment_hash(rel, frag) == "":
				replaced[frag] = frags[frag]
				frags.erase(frag)
		state["release"] = str(plan["release"])
		_write_text(dir.path_join(RELEASE), JSON.stringify(rel))
	# the files a replaced version listed and no installed fragment keeps
	if not replaced.is_empty():
		var keep := {}
		for frag: String in frags:
			var m := fetch_fragment(str(frags[frag]), dir)
			for row: Array in m["manifest"].get("files", []):
				keep[str(row[0])] = true
		for frag: String in replaced:
			var m := fetch_fragment(str(replaced[frag]), dir)
			for row: Array in m["manifest"].get("files", []):
				var path := str(row[0])
				if not keep.has(path):
					have.erase(path)
					var rel_path := ContentSource.cache_relative(path, world)
					if rel_path != "":
						DirAccess.remove_absolute(dir.path_join(rel_path))
	_write_text(dir.path_join(STATE), JSON.stringify(state))
	DirAccess.remove_absolute(dir.path_join(JOURNAL))
	var used := {}
	for frag: String in frags:
		used[str(frags[frag]) + ".json.gz"] = true
	for f in (DirAccess.get_files_at(dir.path_join(MANIFESTS)) if DirAccess.dir_exists_absolute(dir.path_join(MANIFESTS)) else PackedStringArray()):
		if not used.has(f):
			DirAccess.remove_absolute(dir.path_join(MANIFESTS).path_join(f))
	_drop_legacy(dir)


## {path: hash} of what the cache holds: the installed fragments' manifests, the journal of a cut install and
## (once) a cache of the downloads before C.07. Loaded once per cache, then kept up to date.
func _installed(dir: String, world: String) -> Dictionary:
	if _have.has(dir):
		return _have[dir]
	var have := {}
	var state := read_state(dir)
	for frag: String in state.get("frags", {}):
		var m := fetch_fragment(str(state["frags"][frag]), dir)
		for row: Array in m["manifest"].get("files", []):
			have[str(row[0])] = str(row[1])
	if legacy(dir): # trusted when the file is there with its size: they were checked when written
		var docs: Array = [dir.path_join("manifest.json")]
		for f in (DirAccess.get_files_at(dir.path_join("_zones")) if DirAccess.dir_exists_absolute(dir.path_join("_zones")) else PackedStringArray()):
			if f.ends_with(".json"):
				docs.append(dir.path_join("_zones").path_join(f))
		for doc: String in docs:
			var m: Variant = JSON.parse_string(FileAccess.get_file_as_string(doc))
			for f: Variant in (m.get("files", []) if m is Dictionary else []):
				var rel_path := ContentSource.cache_relative(str(f["path"]), world)
				if rel_path != "" and FileHash.size_of(dir.path_join(rel_path)) == int(f["size"]):
					have[str(f["path"])] = str(f["hash"])
	if interrupted(dir):
		for line in FileAccess.get_file_as_string(dir.path_join(JOURNAL)).split("\n", false):
			var cut := line.split("\t")
			if cut.size() == 2:
				have[cut[0]] = cut[1]
	_have[dir] = have
	return have


func _drop_legacy(dir: String) -> void:
	for f in ["manifest.json", "version.txt", "progress.json"]:
		DirAccess.remove_absolute(dir.path_join(f))
	for sub in ["_zones", "_bundle"]:
		if DirAccess.dir_exists_absolute(dir.path_join(sub)):
			for f in DirAccess.get_files_at(dir.path_join(sub)):
				DirAccess.remove_absolute(dir.path_join(sub).path_join(f))
			DirAccess.remove_absolute(dir.path_join(sub))


## Full check of what the cache holds (the only place the files are hashed, on the player's demand): the
## installed fragments and the files a cut install wrote (its journal). A fragment with a missing or damaged
## file is no longer installed (its bad files are deleted): a zone is fetched again when needed, the base by
## the next install, which skips the good files (they become the journal of an install to finish).
## {ok, checked, bad}
func repair(cache_dir: String, world: String) -> Dictionary:
	const JOURNALED := "@journal"
	var state := read_state(cache_dir)
	var owners := {} # path -> [hash, [fragments]]
	for frag: String in state.get("frags", {}):
		var m := fetch_fragment(str(state["frags"][frag]), cache_dir)
		for row: Array in m["manifest"].get("files", []):
			owners.get_or_add(str(row[0]), [str(row[1]), []])[1].append(frag)
	if interrupted(cache_dir):
		for line in FileAccess.get_file_as_string(cache_dir.path_join(JOURNAL)).split("\n", false):
			var cut := line.split("\t")
			if cut.size() == 2:
				var o: Array = owners.get_or_add(cut[0], [cut[1], []])
				o[0] = cut[1] # the journal is newer than an installed fragment
				o[1].append(JOURNALED)
	var paths := owners.keys()
	var good: Array = []
	good.resize(paths.size())
	var group := WorkerThreadPool.add_group_task(func(k: int) -> void:
		var rel_path := ContentSource.cache_relative(str(paths[k]), world)
		good[k] = rel_path != "" and FileHash.sha256(cache_dir.path_join(rel_path)) == str(owners[paths[k]][0]),
		paths.size(), -1, true, "check the content cache")
	WorkerThreadPool.wait_for_group_task_completion(group)
	var dropped := {}
	var bad := 0
	for k in paths.size():
		if not good[k]:
			bad += 1
			DirAccess.remove_absolute(cache_dir.path_join(ContentSource.cache_relative(str(paths[k]), world)))
			for frag: String in owners[paths[k]][1]:
				dropped[frag] = true
	if bad > 0:
		if dropped.has(ContentRelease.BASE) or dropped.has(JOURNALED):
			var lines := PackedStringArray()
			for k in paths.size():
				var by: Array = owners[paths[k]][1]
				if good[k] and (by.has(JOURNALED) or (dropped.has(ContentRelease.BASE) and by.has(ContentRelease.BASE))):
					lines.append("%s\t%s" % [paths[k], owners[paths[k]][0]])
			DirAccess.make_dir_recursive_absolute(cache_dir.path_join(INSTALL_DIR))
			_write_text(cache_dir.path_join(JOURNAL), "\n".join(lines) + "\n")
		if not state.is_empty():
			if dropped.has(ContentRelease.BASE):
				state["release"] = ""
			for frag: String in dropped:
				(state["frags"] as Dictionary).erase(frag)
			_write_text(cache_dir.path_join(STATE), JSON.stringify(state))
		_have.erase(cache_dir)
	return {"ok": true, "checked": paths.size(), "bad": bad}


# --- network ----------------------------------------------------------------------------------------

## The parallel downloader of this client (its connections stay open between calls).
func _downloader() -> RangeDownloader:
	if _dl == null or _dl.host != host or _dl.port != port:
		_dl = RangeDownloader.new(host, port, _auth())
	_dl.headers = _auth()
	_dl.parallel = parallel_downloads
	_dl.max_chunks = chunks_per_poll
	_dl.loop_delay_ms = poll_delay_ms
	_dl.pump = pump
	_dl.cancelled = func() -> bool: return cancel_requested
	return _dl


## {ok, status, error, body}
func _http_get(path: String) -> Dictionary:
	var f := HttpFetch.new()
	f.start(host, port, path, _auth())
	_wait(f)
	if f.error != "":
		return {"ok": false, "status": f.status, "error": f.error, "body": PackedByteArray()}
	if f.status != 200:
		return {"ok": false, "status": f.status, "error": "http %d %s" % [f.status, f.body.get_string_from_utf8()], "body": f.body}
	return {"ok": true, "status": f.status, "error": "", "body": f.body}


func _auth() -> Dictionary:
	return {"Authorization": "Bearer " + token}


func _wait(f: HttpFetch) -> void:
	while not f.poll():
		if cancel_requested:
			f.abort()
			break
		if pump.is_valid():
			pump.call()
		else:
			OS.delay_msec(maxi(2, poll_delay_ms))


static func _write_text(path: String, text: String) -> void:
	_write_bytes(path, text.to_utf8_buffer())


static func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(bytes)
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(tmp, path)
