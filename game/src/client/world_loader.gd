## The model of the loading screen (roadmap C.03), without any Node: which worlds the server
## offers, what each one needs from the local cache (user://worlds/<id>/), the download with its
## progress, and the switch to the downloaded world. The screen (WorldLoadScreen) runs the
## blocking calls in a thread and only reads the fields; the tests call them directly while they
## pump a server in the same process.
##
##   var wl := WorldLoader.new(ContentClient.new(host, http_port, token))
##   wl.refresh()                    # worlds + their status in the cache
##   wl.install("dofus")             # missing files only, then the world is ready
##   wl.launch("dofus")              # ContentSource.use_world: the cache answers from now on
##
## A world's `status`: "current" (cache complete, same version as the server), "new" (nothing
## downloaded), "partial" (an interrupted download: resumed), "update" (the server has another
## version, or a file of the cache is missing or damaged). Nothing here knows which game a world runs.
class_name WorldLoader
extends RefCounted

## a download needs this much more room than its size (partial files, the manifest)
const SPACE_MARGIN := 1.05

var client: ContentClient
## the folder of all the world caches (C.04: ContentSource.cache_base(), chosen by the player)
var cache_base := ContentSource.cache_base()
## Callable(path: String) -> int, the free bytes of the disk of `path` (-1 unknown)
var free_space := DiskSpace.free_bytes

## "idle" | "listing" | "downloading" | "done" | "failed" | "cancelled"
var state := "idle"
## "" or the reason, in plain text (the screen shows it)
var error := ""
## entries: {id, name, version, size, files, status, todo_files, todo_blobs (distinct contents), todo_bytes, manifest, cached_version}
var worlds: Array[Dictionary] = []

# progress of the running install (written by the worker thread, read by the screen)
var world_id := ""
var done_bytes := 0
var total_bytes := 0
var done_files := 0
var total_files := 0
var current_path := ""
var started_ms := 0
## what the running install is doing: "archive" (zip parts of the base bundle, C.05), "extract"
## (unpacking them) or "files" (file by file: the updates, or a server without a bundle)
var phase := "files"
## C.05: a first install goes through the zip base when the server has one (false = file by file)
var use_bundle := true
## the base bundle is not worth it below this many bytes to fetch
var bundle_min_bytes := 4 * 1024 * 1024
## Callable(), called after each progress update of an install (tests)
var on_progress := Callable()


func _init(p_client: ContentClient = null) -> void:
	client = p_client


## "host:port" -> {host, port}; the port defaults to `default_port`.
static func split_address(address: String, default_port: int) -> Dictionary:
	var a := address.strip_edges().trim_prefix("ws://").get_slice("/", 0)
	if a.contains(":"):
		return {"host": a.get_slice(":", 0), "port": int(a.get_slice(":", 1))}
	return {"host": a, "port": default_port}


func cache_dir(id: String) -> String:
	return ContentSource.cache_dir_for(id, cache_base)


## Asks the server for its worlds and compares each manifest with the cache. false = failure
## (`error` says why; the cache is untouched).
func refresh() -> bool:
	state = "listing"
	error = ""
	client.cancel_requested = false
	var r := client.list_worlds()
	if not r.ok:
		return _fail(_network_error(r), "failed")
	var out: Array[Dictionary] = []
	for w: Variant in r.worlds:
		if not w is Dictionary or str(w.get("id", "")) == "":
			continue
		var entry := _inspect(w)
		if entry.is_empty():
			return _fail(error, "failed")
		out.append(entry)
	worlds = out
	state = "idle"
	return true


func entry(id: String) -> Dictionary:
	for w in worlds:
		if w["id"] == id:
			return w
	return {}


## Downloads what the cache of `id` lacks, then it is ready to launch. false = stopped (`error`;
## state "cancelled" when `cancel` was called). What was installed stays: the next call resumes.
func install(id: String) -> bool:
	var e := entry(id)
	if e.is_empty():
		return _fail("monde inconnu : " + id, "failed")
	world_id = id
	error = ""
	client.cancel_requested = false
	done_bytes = 0
	done_files = 0
	current_path = ""
	started_ms = Time.get_ticks_msec()
	total_bytes = int(e["todo_bytes"])
	total_files = int(e["todo_blobs"])
	var m: Dictionary = e["manifest"]
	var dir := cache_dir(id)
	var abs_dir := ProjectSettings.globalize_path(dir)
	if DirAccess.make_dir_recursive_absolute(abs_dir) != OK and not DirAccess.dir_exists_absolute(abs_dir):
		return _fail("Impossible d'écrire dans le dossier des mondes (%s) : disque absent ou accès refusé. Changez de dossier depuis l'écran de lancement." % cache_base, "failed")
	var need := int(total_bytes * SPACE_MARGIN)
	var free: int = int(free_space.call(dir)) if free_space.is_valid() else -1
	if free >= 0 and need > free:
		return _fail("Espace disque insuffisant : %s à télécharger, %s libres sur ce disque (%s). Changez de dossier depuis l'écran de lancement." % [
				format_bytes(need), format_bytes(free), cache_base], "failed")
	state = "downloading"
	var todo := client.diff(m, dir)
	phase = "files"
	if use_bundle and total_bytes >= bundle_min_bytes:
		var b := _install_bundle(m, dir, todo)
		if b != "":
			return _fail(b, "cancelled" if b == "Téléchargement interrompu." else "failed")
		todo = client.diff(m, dir)
		var rest := ContentManifest.unique_blobs(todo)
		var rest_bytes := 0
		for h: String in rest:
			rest_bytes += int(rest[h])
		_begin_phase("files", rest_bytes, rest.size())
	client.progress = func(done: int, _total: int, path: String) -> void:
		done_bytes = done
		if path != current_path: # the previous distinct content is finished
			done_files += 1 if current_path != "" else 0
			current_path = path
		if on_progress.is_valid():
			on_progress.call()
	var r := client.download(m, dir, todo)
	client.progress = Callable()
	if not r.ok:
		var cancelled := str(r["error"]).ends_with("cancelled")
		return _fail("Téléchargement interrompu." if cancelled else _text_error(str(r["error"])),
				"cancelled" if cancelled else "failed")
	done_bytes = total_bytes
	done_files = total_files
	state = "done"
	_inspect_one(id)
	return true


## The zip base (C.05) then the rest file by file. "" = go on (done, unusable or not worth it),
## else the reason to stop (network error, cancelled).
func _install_bundle(m: Dictionary, dir: String, todo: Array) -> String:
	client.phase_changed = func(p: String, total: int, parts: int) -> void:
		_begin_phase(p, total, parts)
	client.progress = func(done: int, _total: int, path: String) -> void:
		done_bytes = done
		if path != current_path:
			done_files += 1 if current_path != "" else 0
			current_path = path
		if on_progress.is_valid():
			on_progress.call()
	var r := client.install_bundle(m, dir, todo)
	client.progress = Callable()
	client.phase_changed = Callable()
	if r.ok or r.fallback:
		return ""
	if str(r["error"]).ends_with("cancelled"):
		return "Téléchargement interrompu."
	return _text_error(str(r["error"]))


func _begin_phase(p: String, total: int, parts: int) -> void:
	phase = p
	total_bytes = total
	total_files = parts
	done_bytes = 0
	done_files = 0
	current_path = ""
	started_ms = Time.get_ticks_msec()


## Stops a running install at the next network poll (callable from the screen's thread).
func cancel() -> void:
	client.cancel_requested = true


## Makes the cache of `id` the active content (ContentSource); false while it is not complete.
func launch(id: String) -> bool:
	var e := entry(id)
	if e.is_empty() or e["status"] != "current":
		return false
	ContentSource.use_world(id, cache_base)
	return ContentSource.using_cache() and ContentSource.world() == id


## bytes per second since the install began (0 before the first bytes)
func speed() -> float:
	var ms := Time.get_ticks_msec() - started_ms
	return float(done_bytes) * 1000.0 / ms if ms > 200 and done_bytes > 0 else 0.0


## seconds left at the current speed (-1 unknown)
func eta() -> int:
	var s := speed()
	return int((total_bytes - done_bytes) / s) if s > 0.0 else -1


## "12,4 Mo", "830 Ko"
static func format_bytes(n: int) -> String:
	if n >= 1 << 30:
		return ("%.1f Go" % (n / float(1 << 30))).replace(".", ",")
	if n >= 1 << 20:
		return ("%.1f Mo" % (n / float(1 << 20))).replace(".", ",")
	if n >= 1 << 10:
		return "%d Ko" % int(round(n / 1024.0))
	return "%d o" % n


func _inspect_one(id: String) -> void:
	for i in worlds.size():
		if worlds[i]["id"] == id:
			var fresh := _inspect({"id": id, "name": worlds[i]["name"], "version": worlds[i]["version"],
					"size": worlds[i]["size"], "files": worlds[i]["files"], "players": worlds[i].get("players", 0)}, false)
			if not fresh.is_empty():
				worlds[i] = fresh


## One world of the list: its manifest against the cache. {} = failure (`error`).
func _inspect(w: Dictionary, verify := true) -> Dictionary:
	var id := str(w["id"])
	var m := client.fetch_manifest(id)
	if not m.ok:
		error = _network_error(m)
		return {}
	var manifest: Dictionary = m.manifest
	var dir := cache_dir(id)
	var interrupted := FileAccess.file_exists(dir.path_join(ContentClient.PROGRESS_FILE))
	if verify and interrupted:
		client.verify_cache(manifest, dir) # after a cut a file may be damaged: full hash check
	var todo := client.diff(manifest, dir)
	var blobs := ContentManifest.unique_blobs(todo)
	var todo_bytes := 0
	for h: String in blobs:
		todo_bytes += int(blobs[h])
	var cached_version := _cached_version(dir)
	var status := "current"
	if not todo.is_empty() or cached_version != str(manifest["version"]):
		if interrupted:
			status = "partial"
		elif cached_version == "":
			status = "new"
		else:
			status = "update"
	return {"id": id, "name": str(w.get("name", id)), "version": str(manifest["version"]),
			"size": int(w.get("size", 0)), "files": int(w.get("files", 0)), "status": status,
			"todo_files": todo.size(), "todo_blobs": blobs.size(), "todo_bytes": todo_bytes, "manifest": manifest,
			"cached_version": cached_version, "players": int(w.get("players", 0))}


func _cached_version(dir: String) -> String:
	var path := dir.path_join("manifest.json")
	if not FileAccess.file_exists(path):
		return ""
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return str(data.get("version", "")) if data is Dictionary else ""


func _fail(message: String, new_state: String) -> bool:
	error = message
	state = new_state
	return false


## A failed ContentClient result in plain words.
static func _network_error(r: Dictionary) -> String:
	var status := int(r.get("status", 0))
	if status == 401:
		return "Session refusée par le serveur : reconnectez-vous."
	if status == 404:
		return "Ce serveur ne propose pas ce contenu."
	return _text_error(str(r.get("error", "")))


static func _text_error(e: String) -> String:
	if e.contains("hash mismatch"):
		return "Fichier reçu corrompu, réessayez : " + e
	if e.contains("cannot connect") or e.contains("cannot reach") or e.contains("timeout") \
			or e.contains("network error") or e.contains("connection closed") or e.contains("body cut"):
		return "Connexion perdue avec le serveur. Le téléchargement reprendra où il s'est arrêté."
	return e
