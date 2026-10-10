## The model of the loading screen (roadmap C.03, C.07), without any Node: which worlds the server
## offers, what each one needs from the local cache, the download with its progress, and the switch to the
## downloaded world. The screen (WorldLoadScreen) runs the blocking calls in a thread and only reads the
## fields; the tests call them directly while they pump a server in the same process.
##
##   var wl := WorldLoader.new(ContentClient.new(host, http_port, token))
##   wl.refresh()                    # ONE small request: the worlds and their status against the cache
##   wl.measure()                    # then (in the background) the exact size of each update
##   wl.install("dofus")             # only what the cache lacks, then the world is ready
##   wl.launch("dofus")              # ContentSource.use_world: the cache answers from now on
##
## A world's `status`: "current" (the cache holds the release the server publishes), "new" (nothing
## downloaded), "partial" (an interrupted download: resumed), "update" (the server publishes another
## release), "unavailable" (listed by the server, not published). Listing reads the server's pointers and
## each cache's small state file: no manifest, no walk of the cache, no hash. Nothing here knows which game a world runs.
class_name WorldLoader
extends RefCounted

## a download needs this much more room than its size
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
## entries: {id, content, name, version (the release), size, files, status, note, todo_files, todo_bytes,
## measured (todo_* are exact: the manifests were compared), players}
var worlds: Array[Dictionary] = []

# progress of the running install (written by the worker thread, read by the screen)
var world_id := ""
var done_bytes := 0
var total_bytes := 0
var done_files := 0
var total_files := 0
var started_ms := 0
## "plan" (manifests being compared) then "files" (downloading)
var phase := "files"
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


## Asks the server for its worlds (one small request) and compares each release with the cache. false =
## failure (`error` says why; the cache is untouched).
func refresh() -> bool:
	state = "listing"
	error = ""
	client.cancel_requested = false
	var r := client.list_worlds()
	if not r.ok:
		return _fail(_network_error(r), "failed")
	var out: Array[Dictionary] = []
	for w: Variant in r.worlds:
		if w is Dictionary and str(w.get("id", "")) != "":
			out.append(_inspect(w))
	worlds = out
	state = "idle"
	return true


## The exact size of what each world that is not current needs (its manifests against the cache): run after
## `refresh`, the rows are already shown. A failure leaves the estimate (the size the server announced).
func measure() -> void:
	for i in worlds.size():
		var e := worlds[i]
		if e["status"] in ["current", "unavailable"] or bool(e.get("measured", false)):
			continue
		var p := _plan(e)
		if p.ok:
			e["todo_bytes"] = int(p["bytes"])
			e["todo_files"] = int(p["files"])
			e["measured"] = true


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
	started_ms = Time.get_ticks_msec()
	total_bytes = int(e["todo_bytes"])
	total_files = int(e["todo_files"])
	var dir := cache_dir(str(e["content"])) # an instance (S.04b) shares the cache of its content
	var abs_dir := ProjectSettings.globalize_path(dir)
	if DirAccess.make_dir_recursive_absolute(abs_dir) != OK and not DirAccess.dir_exists_absolute(abs_dir):
		return _fail("Impossible d'écrire dans le dossier des mondes (%s) : disque absent ou accès refusé. Changez de dossier depuis l'écran de lancement." % cache_base, "failed")
	state = "downloading"
	phase = "plan"
	var plan := _plan(e)
	if not plan.ok:
		var cut := str(plan["error"]).ends_with("cancelled")
		return _fail("Téléchargement interrompu." if cut else _network_error(plan), "cancelled" if cut else "failed")
	total_bytes = int(plan["bytes"])
	total_files = int(plan["files"])
	var need := int(total_bytes * SPACE_MARGIN)
	var free: int = int(free_space.call(dir)) if free_space.is_valid() and total_bytes > 0 else -1
	if free >= 0 and need > free:
		return _fail("Espace disque insuffisant : %s à télécharger, %s libres sur ce disque (%s). Changez de dossier depuis l'écran de lancement." % [
				format_bytes(need), format_bytes(free), cache_base], "failed")
	phase = "files"
	started_ms = Time.get_ticks_msec()
	client.progress = func(done: int, _total: int, _path: String) -> void:
		done_bytes = done
		done_files = client.files_done
		if on_progress.is_valid():
			on_progress.call()
	var r := client.install(plan)
	client.progress = Callable()
	if not r.ok:
		var cancelled := str(r["error"]).ends_with("cancelled")
		return _fail("Téléchargement interrompu." if cancelled else _text_error(str(r["error"])),
				"cancelled" if cancelled else "failed")
	done_bytes = total_bytes
	done_files = total_files
	state = "done"
	_inspect_again(id)
	return true


## Hashes every installed file of `id` (on the player's demand: "Vérifier"); a damaged one is fetched again
## by the next install. {ok, checked, bad}
func repair(id: String) -> Dictionary:
	var e := entry(id)
	if e.is_empty():
		return {"ok": false, "checked": 0, "bad": 0}
	var r := client.repair(cache_dir(str(e["content"])), str(e["content"]))
	_inspect_again(id)
	return r


## What installing `e` needs: the base, plus the zones the cache already holds (updated with it).
func _plan(e: Dictionary) -> Dictionary:
	var content := str(e["content"])
	var rel := client.fetch_release(content, str(e["version"]))
	if not rel.ok:
		return {"ok": false, "error": rel.error, "status": rel.status}
	var dir := cache_dir(content)
	var frags: Array = [ContentRelease.BASE]
	for frag: String in ContentClient.read_state(dir).get("frags", {}):
		if frag != ContentRelease.BASE and ContentRelease.fragment_hash(rel.release, frag) != "":
			frags.append(frag)
	return client.plan_install(content, str(e["version"]), rel.release, frags, dir)


## Stops a running install at the next network poll (callable from the screen's thread).
func cancel() -> void:
	client.cancel_requested = true


## Makes the cache of `id` the active content (ContentSource); false while it is not complete.
func launch(id: String) -> bool:
	var e := entry(id)
	if e.is_empty() or e["status"] != "current":
		return false
	var content := content_of(id)
	ContentSource.use_world(content, cache_base)
	return ContentSource.using_cache() and ContentSource.world() == content


## The content a world id reads (S.04b: an instance of another world's content), the id itself otherwise.
func content_of(id: String) -> String:
	return str(entry(id).get("content", id))


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


## The entries of `id` and of every world reading the same content, against the cache again.
func _inspect_again(id: String) -> void:
	var content := content_of(id)
	for i in worlds.size():
		if worlds[i]["id"] == id or worlds[i]["content"] == content: # same cache
			worlds[i] = _inspect(worlds[i]["listed"])


## One world of the list: the release the server publishes against the state of the cache (a small file).
func _inspect(w: Dictionary) -> Dictionary:
	var id := str(w["id"])
	var content := str(w.get("content", id)) # S.04b: an instance reads (and caches) the content of another world
	var release := str(w.get("release", ""))
	var e := {"id": id, "content": content, "name": str(w.get("name", id)), "version": release,
			"size": int(w.get("size", 0)), "files": int(w.get("files", 0)), "players": int(w.get("players", 0)),
			"note": str(w.get("note", "")), "todo_files": 0, "todo_bytes": 0, "measured": false, "listed": w}
	var dir := cache_dir(content)
	var installed := ContentClient.installed_release(dir)
	if str(w.get("state", "ready")) != "ready" or not ContentRelease.is_release_id(release):
		e["status"] = "unavailable"
	elif ContentClient.interrupted(dir):
		e["status"] = "partial"
	elif installed == release:
		e["status"] = "current"
		e["measured"] = true
	elif installed == "" and not ContentClient.legacy(dir):
		e["status"] = "new"
		e["todo_bytes"] = e["size"] # the whole base: exact, nothing to compare
		e["todo_files"] = e["files"]
		e["measured"] = true
	else:
		e["status"] = "update"
	if not e["measured"] and e["status"] != "current" and e["status"] != "unavailable":
		e["todo_bytes"] = e["size"] # at most: `measure` says exactly
		e["todo_files"] = e["files"]
	return e


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
			or e.contains("network error") or e.contains("connection closed") or e.contains("body cut") \
			or e.contains("short answer"):
		return "Connexion perdue avec le serveur. Le téléchargement reprendra où il s'est arrêté."
	return e
