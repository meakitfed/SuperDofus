## Downloads a world package from a server (roadmap C.02), without any screen: the loading
## screen (C.03) drives it. Blocking calls that wait by calling `pump` (default: a short sleep),
## so a screen runs them in a thread and the tests pump the server in the same process.
##
##   var cc := ContentClient.new("192.168.1.5", 7778, token)   # token = login_ok.token
##   var worlds := cc.list_worlds()                             # {ok, worlds: [{id, name, version...}]}
##   var m := cc.fetch_manifest("dofus")                        # {ok, manifest}
##   var todo := cc.diff(m.manifest, cache_dir)                 # only what the cache lacks
##   var r := cc.download(m.manifest, cache_dir, todo)          # {ok, error, bytes}; or cc.update(...)
##
## Cache layout: ContentSource.cache_relative. Every file is written to `<file>.part` (resumed with
## a Range request after a cut), its SHA-256 checked against the manifest, then renamed: a wrong
## file never lands in the cache. `manifest.json` is written last, it marks the cache ready.
class_name ContentClient
extends RefCounted

const PROGRESS_FILE := "progress.json"
## where the zip parts of the base bundle wait (C.05); deleted once unpacked
const BUNDLE_DIR := "_bundle"
## the bundle is used only when the parts to fetch weigh less than this share of the files they replace
const BUNDLE_GAIN := 0.9
## how many installed files between two saves of the resume state
const PROGRESS_EVERY := 50

var host := ""
var port := 0
var token := ""
## Callable(), called while waiting for the network
var pump := Callable()
## Callable(done_bytes: int, total_bytes: int, path: String)
var progress := Callable()
## set (from another thread: the loading screen) to stop at the next poll; what was downloaded
## stays, the partial file is resumed next time. The error is then "cancelled".
var cancel_requested := false
## slows the download down (screen captures, tests): chunks read per poll and pause per poll
var chunks_per_poll := 64
var poll_delay_ms := 0
## Callable(phase: String, total_bytes: int, total_parts: int), when install_bundle changes phase:
## "archive" (downloading the zip parts) then "extract" (unpacking them, bytes of the files)
var phase_changed := Callable()


func _init(p_host := "", p_port := 0, p_token := "") -> void:
	host = p_host
	port = p_port
	token = p_token


## {ok, status, error, worlds}
func list_worlds() -> Dictionary:
	var r := _get_json("/worlds")
	if r.ok and not r.data is Array:
		return _fail(r.status, "bad worlds list")
	return {"ok": r.ok, "status": r.status, "error": r.error, "worlds": r.data if r.ok else []}


## {ok, status, error, manifest}: the manifest is validated (format, safe paths, version).
func fetch_manifest(world: String) -> Dictionary:
	var r := _get_json("/worlds/%s/manifest.json" % world.uri_encode())
	if not r.ok:
		return {"ok": false, "status": r.status, "error": r.error, "manifest": {}}
	var bad := ContentManifest.validate(r.data)
	if bad != "":
		return {"ok": false, "status": r.status, "error": "bad manifest: " + bad, "manifest": {}}
	if str(r.data["world"]) != world:
		return {"ok": false, "status": r.status, "error": "manifest of another world", "manifest": {}}
	return {"ok": true, "status": r.status, "error": "", "manifest": r.data}


## What the cache of `cache_dir` holds, {path: {hash, size}}: the last complete manifest plus the
## files an interrupted update installed, each kept only if the file is there with its size.
func local_state(cache_dir: String, world: String) -> Dictionary:
	var state := {}
	for name in ["manifest.json", PROGRESS_FILE]:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(cache_dir.path_join(name))) \
				if FileAccess.file_exists(cache_dir.path_join(name)) else null
		if data is Dictionary:
			state.merge(ContentManifest.as_state(data) if name == "manifest.json" else data, true)
	var out := {}
	for path: String in state:
		var rel := ContentSource.cache_relative(path, world)
		var entry: Variant = state[path]
		if rel == "" or not entry is Dictionary:
			continue
		var f := FileAccess.open(cache_dir.path_join(rel), FileAccess.READ)
		if f != null and f.get_length() == int(entry.get("size", -1)):
			out[path] = {"hash": str(entry.get("hash", "")), "size": int(entry["size"])}
	return out


## Full SHA-256 check of what the cache holds for `manifest` (the size-only check of local_state
## trusts the files; this is run after a cut, when a file may have been left damaged): a file whose
## hash differs is deleted so that `diff` asks for it again. Returns the paths it removed.
func verify_cache(manifest: Dictionary, cache_dir: String) -> PackedStringArray:
	var bad := PackedStringArray()
	var world := str(manifest["world"])
	var state := local_state(cache_dir, world)
	var wanted := {}
	for f: Dictionary in manifest["files"]:
		wanted[str(f["path"])] = str(f["hash"])
	for path: String in state:
		if not wanted.has(path) or str(state[path]["hash"]) != wanted[path]:
			continue # not part of this version: diff and the stale cleanup deal with it
		var file := cache_dir.path_join(ContentSource.cache_relative(path, world))
		if FileHash.sha256(file) != wanted[path]:
			DirAccess.remove_absolute(file)
			bad.append(path)
	return bad


## The manifest entries the cache lacks (absent, other hash, other size).
func diff(manifest: Dictionary, cache_dir: String) -> Array:
	return ContentManifest.diff(manifest, local_state(cache_dir, str(manifest["world"])))


## Fetches the manifest, downloads what is missing, removes what the new version dropped, writes
## manifest.json. {ok, error, bytes, files, manifest}
func update(world: String, cache_dir: String) -> Dictionary:
	var m := fetch_manifest(world)
	if not m.ok:
		return {"ok": false, "error": m.error, "bytes": 0, "files": 0, "manifest": {}}
	var r := download(m.manifest, cache_dir, diff(m.manifest, cache_dir))
	r["manifest"] = m.manifest
	return r


## Downloads `missing` (entries of `manifest`) into `cache_dir`, then finishes the update (stale
## files removed, manifest.json written) only when nothing is missing any more. A distinct content
## is fetched once, however many paths use it. Stops at the first error ({ok: false, error}); what
## was installed stays and is not fetched again next time.
## `finish` false (a zone, C.02c): no resume file, no stale cleanup and no manifest.json; the caller
## decides what marks the download complete. A cut leaves a `.part` that the next call resumes.
func download(manifest: Dictionary, cache_dir: String, missing: Array, finish := true) -> Dictionary:
	var world := str(manifest["world"])
	var out := {"ok": false, "error": "", "bytes": 0, "files": 0}
	var by_hash := {} # hash -> [entries]
	for f: Dictionary in missing:
		if not ContentManifest.safe_path(str(f["path"])) or ContentSource.cache_relative(str(f["path"]), world) == "":
			out["error"] = "refused path: " + str(f["path"])
			return out
		by_hash.get_or_add(str(f["hash"]), []).append(f)
	var total := 0
	for h: String in by_hash:
		total += int(by_hash[h][0]["size"])
	var installed := local_state(cache_dir, world) if finish else {}
	var since_save := 0
	var done_bytes := 0
	for h: String in by_hash:
		var entries: Array = by_hash[h]
		var first: Dictionary = entries[0]
		var dest := cache_dir.path_join(ContentSource.cache_relative(str(first["path"]), world))
		var err := _fetch_blob("/worlds/%s/files/%s" % [world, h], h, int(first["size"]), dest, func(n: int) -> void:
			if progress.is_valid():
				progress.call(done_bytes + n, total, str(first["path"])))
		if err != "":
			if finish:
				_save_progress(cache_dir, installed)
			out["error"] = "%s: %s" % [first["path"], err]
			return out
		done_bytes += int(first["size"])
		out["bytes"] = done_bytes
		for i in entries.size():
			var f: Dictionary = entries[i]
			if i > 0: # same content under another path: a local copy, not a download
				var copy := cache_dir.path_join(ContentSource.cache_relative(str(f["path"]), world))
				DirAccess.make_dir_recursive_absolute(copy.get_base_dir())
				DirAccess.copy_absolute(dest, copy)
			installed[f["path"]] = {"hash": f["hash"], "size": f["size"]}
			out["files"] += 1
		since_save += 1
		if finish and since_save >= PROGRESS_EVERY:
			_save_progress(cache_dir, installed)
			since_save = 0
	if not finish:
		out["ok"] = true
		return out
	_save_progress(cache_dir, installed)
	if not diff(manifest, cache_dir).is_empty():
		out["error"] = "some files are still missing"
		return out
	_remove_stale(manifest, cache_dir, world)
	_write_atomic(cache_dir.path_join("manifest.json"), JSON.stringify(manifest))
	DirAccess.remove_absolute(cache_dir.path_join(PROGRESS_FILE))
	out["ok"] = true
	return out


## Downloads one content into `dest`, resuming `dest.part`; "" when installed, else the error.
func _fetch_blob(url: String, hash: String, size: int, dest: String, on_bytes: Callable) -> String:
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	var part := dest + ".part"
	for attempt in 2:
		var have := _file_size(part)
		if have > size:
			DirAccess.remove_absolute(part)
			have = 0
		if have < size:
			var err := _get_range(url, part, have, on_bytes)
			if err == "restart": # the server refused the range: start from zero
				DirAccess.remove_absolute(part)
				continue
			if err != "":
				return err
		if FileHash.sha256(part) != hash:
			DirAccess.remove_absolute(part) # never keep a bad file, and never resume from it
			return "hash mismatch"
		if DirAccess.rename_absolute(part, dest) != OK:
			return "cannot write " + dest
		return ""
	return "download failed"


## Appends the bytes of `hash` from offset `have` to `part`.
func _get_range(url: String, part: String, have: int, on_bytes: Callable) -> String:
	var file := FileAccess.open(part, FileAccess.READ_WRITE if have > 0 else FileAccess.WRITE)
	if file == null:
		return "cannot write " + part
	if have > 0:
		file.seek_end()
	var written := [have]
	var sink := func(chunk: PackedByteArray) -> void:
		file.store_buffer(chunk)
		written[0] += chunk.size()
		on_bytes.call(written[0])
	var headers := _auth()
	if have > 0:
		headers["Range"] = "bytes=%d-" % have
	var f := HttpFetch.new()
	f.max_chunks = chunks_per_poll
	f.start(host, port, url, headers, sink)
	_wait(f)
	file.close()
	if f.error != "":
		return f.error
	if have > 0 and f.status == 200: # whole file sent: the range was ignored
		return "restart"
	if f.status == 416:
		return "restart"
	if f.status != 200 and f.status != 206:
		return "http %d %s" % [f.status, f.body.get_string_from_utf8()]
	return ""


func _get_json(path: String) -> Dictionary:
	var f := HttpFetch.new()
	f.start(host, port, path, _auth())
	_wait(f)
	if f.error != "":
		return {"ok": false, "status": f.status, "error": f.error, "data": null}
	if f.status != 200:
		return {"ok": false, "status": f.status, "error": "http %d %s" % [f.status, f.body.get_string_from_utf8()], "data": null}
	var data: Variant = JSON.parse_string(f.body.get_string_from_utf8())
	if data == null:
		return {"ok": false, "status": f.status, "error": "bad JSON", "data": null}
	return {"ok": true, "status": f.status, "error": "", "data": data}


static func _fail(status: int, message: String) -> Dictionary:
	return {"ok": false, "status": status, "error": message, "worlds": []}


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


static func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_length() if f != null else 0


func _save_progress(cache_dir: String, installed: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(cache_dir)
	_write_atomic(cache_dir.path_join(PROGRESS_FILE), JSON.stringify(installed))


## Deletes the files the previous complete manifest listed and the new one dropped.
func _remove_stale(manifest: Dictionary, cache_dir: String, world: String) -> void:
	var old_path := cache_dir.path_join("manifest.json")
	var old: Variant = JSON.parse_string(FileAccess.get_file_as_string(old_path)) if FileAccess.file_exists(old_path) else null
	if not old is Dictionary:
		return
	for path in ContentManifest.stale(manifest, ContentManifest.as_state(old)):
		var rel := ContentSource.cache_relative(path, world)
		if rel != "":
			DirAccess.remove_absolute(cache_dir.path_join(rel))


static func _write_atomic(path: String, text: String) -> void:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(text)
	f.close()
	DirAccess.rename_absolute(tmp, path)


## {ok, status, error, index}: the base bundle index of a world (C.05), checked against `manifest`.
func fetch_bundle(manifest: Dictionary) -> Dictionary:
	var r := _get_json("/worlds/%s/bundle.json" % str(manifest["world"]).uri_encode())
	if not r.ok:
		return {"ok": false, "status": r.status, "error": r.error, "index": {}}
	var bad := ContentBundle.validate(r.data, manifest)
	if bad != "":
		return {"ok": false, "status": r.status, "error": "bad bundle: " + bad, "index": {}}
	return {"ok": true, "status": r.status, "error": "", "index": r.data}


## Installs what `missing` lacks from the world's zip base (C.05): downloads the parts that hold
## it (resumed after a cut, each checked against the hash of the index and refused if damaged),
## unpacks them into the cache, checking every file against the manifest, deletes the zips. It does
## NOT finish the update: call `download(manifest, cache_dir, diff(...))` afterwards (it fetches what
## is still missing, removes the stale files, writes manifest.json).
## {ok, used, fallback, error, bytes (zip), files}: `used` false = nothing done on purpose (no
## bundle, or not worth it for such a small update); `ok` false with `fallback` true = the bundle is
## unusable (damaged, other version), download file by file; `fallback` false = network error or
## cancelled: stop (what is done stays, the next call resumes).
func install_bundle(manifest: Dictionary, cache_dir: String, missing: Array) -> Dictionary:
	var out := {"ok": false, "used": false, "fallback": false, "error": "", "bytes": 0, "files": 0}
	var world := str(manifest["world"])
	var b := fetch_bundle(manifest)
	if not b.ok:
		if int(b.status) == 404 or str(b.error).begins_with("bad bundle"):
			out["ok"] = true # no bundle, or one of another version: file by file, always possible
		else:
			out["error"] = b.error # no answer, refused: a real network error
		return out
	var index: Dictionary = b.index
	var planned := ContentBundle.plan(manifest, int(index["max_source"]), int(index["max_entries"]))
	var by_hash := {} # hash -> [entries]
	var missing_bytes := 0
	for f: Dictionary in missing:
		if not ContentManifest.safe_path(str(f["path"])) or ContentSource.cache_relative(str(f["path"]), world) == "":
			out["error"] = "refused path: " + str(f["path"])
			return out
		if not by_hash.has(str(f["hash"])):
			missing_bytes += int(f["size"])
		by_hash.get_or_add(str(f["hash"]), []).append(f)
	var needed := ContentBundle.parts_needed(planned, by_hash)
	var zip_bytes := 0
	for i in needed:
		zip_bytes += int(index["parts"][i]["size"])
	if needed.is_empty() or zip_bytes >= missing_bytes * BUNDLE_GAIN:
		out["ok"] = true
		return out
	out["used"] = true
	var dir := cache_dir.path_join(BUNDLE_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	# 1. the zip parts
	if phase_changed.is_valid():
		phase_changed.call("archive", zip_bytes, needed.size())
	var done := 0
	for i in needed:
		var p: Dictionary = index["parts"][i]
		var dest := dir.path_join(str(p["name"]))
		if not (_file_size(dest) == int(p["size"]) and FileHash.sha256(dest) == str(p["hash"])):
			var base := done
			var err := _fetch_blob("/worlds/%s/bundle/%s" % [world, p["name"]], str(p["hash"]), int(p["size"]), dest,
					func(n: int) -> void:
						if progress.is_valid():
							progress.call(base + n, zip_bytes, str(p["name"])))
			if err != "":
				DirAccess.remove_absolute(dest)
				out["error"] = "%s: %s" % [p["name"], err]
				out["fallback"] = err == "hash mismatch" or err.begins_with("http 4") or err.begins_with("http 5")
				return out
		done += int(p["size"])
		out["bytes"] = done
	# 2. unpack, part by part
	if phase_changed.is_valid():
		phase_changed.call("extract", missing_bytes, needed.size())
	var installed := local_state(cache_dir, world)
	var got := 0
	var since_save := 0
	var made_dirs := {}
	for i in needed:
		var name := str(index["parts"][i]["name"])
		var zip := ZIPReader.new()
		if zip.open(dir.path_join(name)) != OK:
			DirAccess.remove_absolute(dir.path_join(name))
			out["error"] = name + ": cannot open the archive"
			out["fallback"] = true
			return out
		for h: String in planned[i]["hashes"]:
			if not by_hash.has(h):
				continue
			if cancel_requested:
				zip.close()
				_save_progress(cache_dir, installed)
				out["error"] = "cancelled"
				return out
			var entries: Array = by_hash[h]
			var bytes := zip.read_file(h, false)
			if bytes.size() != int(entries[0]["size"]) or ContentManifest.hash_bytes(bytes) != h:
				zip.close()
				_save_progress(cache_dir, installed)
				DirAccess.remove_absolute(dir.path_join(name))
				out["error"] = "%s: damaged content %s" % [name, h.substr(0, 12)]
				out["fallback"] = true
				return out
			for e: Dictionary in entries:
				var dest := cache_dir.path_join(ContentSource.cache_relative(str(e["path"]), world))
				if _install_bytes(dest, bytes, made_dirs) != OK:
					zip.close()
					_save_progress(cache_dir, installed)
					out["error"] = "cannot write " + dest
					return out
				installed[e["path"]] = {"hash": e["hash"], "size": e["size"]}
				out["files"] += 1
			got += bytes.size()
			if progress.is_valid():
				progress.call(got, missing_bytes, name)
			since_save += 1
			if since_save >= PROGRESS_EVERY:
				_save_progress(cache_dir, installed)
				since_save = 0
		zip.close()
		DirAccess.remove_absolute(dir.path_join(name))
		_save_progress(cache_dir, installed)
	DirAccess.remove_absolute(dir)
	out["ok"] = true
	return out


## Writes `bytes` (already checked against their hash) straight to `dest`: no `.part` and rename,
## which cost as much as the write on Windows (thousands of small files). A cut leaves a short
## file, which `local_state` refuses by size and `verify_cache` by hash, so it is fetched again.
static func _install_bytes(dest: String, bytes: PackedByteArray, made: Dictionary) -> int:
	var dir := dest.get_base_dir()
	if not made.has(dir):
		DirAccess.make_dir_recursive_absolute(dir)
		made[dir] = true
	var f := FileAccess.open(dest, FileAccess.WRITE)
	if f == null:
		return ERR_CANT_CREATE
	f.store_buffer(bytes)
	f.close()
	return OK


# --- zones (C.02c) ------------------------------------------------------------------------------

## Where the manifest of an installed zone is remembered (not a world path: ContentSource never reads it).
const ZONES_DIR := "_zones"


## {ok, status, error, index}: the zones of a world (ContentZones), validated. A world that is not
## zoned answers 404: `ok` false, `status` 404.
func fetch_zones(world: String) -> Dictionary:
	var r := _get_json("/worlds/%s/zones.json" % world.uri_encode())
	if not r.ok:
		return {"ok": false, "status": r.status, "error": r.error, "index": {}}
	var bad := ContentZones.validate(r.data)
	if bad == "" and str(r.data["world"]) != world:
		bad = "zones of another world"
	if bad != "":
		return {"ok": false, "status": r.status, "error": "bad zones: " + bad, "index": {}}
	return {"ok": true, "status": r.status, "error": "", "index": r.data}


## {ok, status, error, manifest}: the manifest of one zone, validated.
func fetch_zone(world: String, zone: String) -> Dictionary:
	if not ContentZones.is_zone_id(zone):
		return {"ok": false, "status": 0, "error": "bad zone id", "manifest": {}}
	var r := _get_json("/worlds/%s/zones/%s/manifest.json" % [world.uri_encode(), zone])
	if not r.ok:
		return {"ok": false, "status": r.status, "error": r.error, "manifest": {}}
	var bad := ContentZones.check_zone_manifest(r.data, world, zone)
	if bad != "":
		return {"ok": false, "status": r.status, "error": "bad zone manifest: " + bad, "manifest": {}}
	return {"ok": true, "status": r.status, "error": "", "manifest": r.data}


## The version of the zone installed in `cache_dir` ("" = none, or a download that did not finish).
static func zone_version(cache_dir: String, zone: String) -> String:
	var path := cache_dir.path_join(ZONES_DIR).path_join(zone + ".json")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return str(data.get("version", "")) if data is Dictionary else ""


## What `manifest` (a zone) still needs in `cache_dir`: the entries whose file is absent or of another
## size, or that the base cache or the previous version of the zone knew under another hash.
## APPROX(C.02c): a file shared with another zone is trusted by its size alone (a shared file that
## changed without changing size would not be refreshed until the zone that owns it is reinstalled).
func zone_missing(manifest: Dictionary, cache_dir: String) -> Array:
	var world := str(manifest["world"])
	var known := local_state(cache_dir, world) # the base manifest (and an interrupted update)
	var path := cache_dir.path_join(ZONES_DIR).path_join(str(manifest["zone"]) + ".json")
	var own: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if own is Dictionary:
		known.merge(ContentManifest.as_state(own), true)
	var have := {}
	for f: Dictionary in manifest["files"]:
		var rel := ContentSource.cache_relative(str(f["path"]), world)
		if rel == "":
			continue
		var fa := FileAccess.open(cache_dir.path_join(rel), FileAccess.READ)
		if fa == null or fa.get_length() != int(f["size"]):
			continue
		var k: Variant = known.get(f["path"])
		if k is Dictionary and str(k.get("hash", "")) != str(f["hash"]):
			continue # the version of the file changed: fetch it again
		have[f["path"]] = {"hash": f["hash"], "size": f["size"]}
	return ContentManifest.diff(manifest, have)


## Installs one zone: fetches its manifest, downloads the files the cache lacks (resumed after a cut,
## each checked against its hash) and remembers the manifest. {ok, error, bytes, files, version,
## already}: `already` = the cache held this version, nothing was asked of the server but the manifest.
func install_zone(world: String, zone: String, cache_dir: String) -> Dictionary:
	var out := {"ok": false, "error": "", "bytes": 0, "files": 0, "version": "", "already": false}
	var m := fetch_zone(world, zone)
	if not m.ok:
		out["error"] = m.error
		return out
	var manifest: Dictionary = m.manifest
	out["version"] = str(manifest["version"])
	var missing := zone_missing(manifest, cache_dir)
	out["already"] = missing.is_empty() and zone_version(cache_dir, zone) == str(manifest["version"])
	if not missing.is_empty():
		var r := download(manifest, cache_dir, missing, false)
		out["bytes"] = r["bytes"]
		out["files"] = r["files"]
		if not r.ok:
			out["error"] = r["error"]
			return out
	if not out["already"]:
		DirAccess.make_dir_recursive_absolute(cache_dir.path_join(ZONES_DIR))
		_write_atomic(cache_dir.path_join(ZONES_DIR).path_join(zone + ".json"), JSON.stringify(manifest))
	out["ok"] = true
	return out
