## The content API (roadmap C.02, C.07), served on the HTTP port: the published content folder
## (ContentStore, `--package-dir`) as static files, the way a CDN serves a launcher.
##   GET /worlds                                   [{id, content, name, module, release, state, size, files, zones, zones_size, players}]
##   GET /worlds/<id>/releases/<release>.json      a release index (ContentRelease)
##   GET /manifests/<hh>/<hash>.json.gz            a fragment manifest
##   GET /bundles/<hh>/<hash>.bundle               a bundle (Range: one byte span per request)
## Nothing is computed per request: a file is streamed from where the publication wrote it, and `/worlds` is
## worlds.json filtered by the worlds this server opens. An open world
## that was never published is listed with state "unpublished". Everything runs on the HTTP thread.
## Every request needs `Authorization: Bearer <session token>` (AuthService.login_for_token); without a valid
## token, 401, and no world is revealed. Without an AuthService (open server, tools) the API refuses
## everything: content is never public. Names are checked (hex hashes, ids), never used as given paths.
## Nothing here knows which game a world runs.
class_name ContentApi
extends RefCounted

## the published content folder (absolute), "" = nothing published
var store := ""
var auth: AuthService
## empty = every published world; else only these worlds are listed and served
var allowed_worlds := PackedStringArray()
## set once the cluster pinned the list: an empty `allowed_worlds` then means no world
var pin_allowed := false
## instance id -> content id (S.04b): an instance is listed under its own id and served from the
## release of its content (the client caches by content, `content` of each entry)
var instances := {}
var instances_names := {} # instance id -> display name
## world id -> players in that world now (given by the game thread: `sync_state`)
var players := {}
## `handle` runs on the I/O thread of HttpServer while the game thread changes the state above: every
## change goes through the methods that take this lock
var _lock := Mutex.new()


func set_instances(map: Dictionary, names: Dictionary) -> void:
	_lock.lock()
	instances = map
	instances_names = names
	_lock.unlock()


## The host's view (accounts, worlds served, players), given each frame: only a change takes the lock.
func sync_state(p_auth: AuthService, p_allowed: PackedStringArray, p_pin: bool, p_players := {}) -> void:
	if auth == p_auth and pin_allowed == p_pin and allowed_worlds == p_allowed and players == p_players:
		return
	_lock.lock()
	auth = p_auth
	allowed_worlds = p_allowed
	pin_allowed = p_pin
	players = p_players.duplicate()
	_lock.unlock()


## The published release of a world ("" = not published).
func release_of(id: String) -> String:
	_lock.lock()
	var p: Variant = _read_pointers().get(str(instances.get(id, id)))
	_lock.unlock()
	return str(p.get("release", "")) if p is Dictionary else ""


func handle(req: HttpServer.Request) -> HttpServer.Response:
	var path := req.path.get_slice("?", 0)
	var parts := path.trim_prefix("/").split("/")
	var kind := ""
	if parts.size() == 1 and parts[0] == "worlds":
		kind = "list"
	elif parts.size() == 4 and parts[0] == "worlds" and parts[2] == "releases" and parts[3].ends_with(".json"):
		kind = "release"
	elif parts.size() == 3 and parts[0] == "manifests" and parts[2].ends_with(".json.gz"):
		kind = "manifest"
	elif parts.size() == 3 and parts[0] == "bundles" and parts[2].ends_with(".bundle"):
		kind = "bundle"
	if kind == "":
		return HttpServer.Response.text(404, "not found")
	_lock.lock()
	var r := _handle(kind, parts, req)
	_lock.unlock()
	return r


func _handle(kind: String, parts: PackedStringArray, req: HttpServer.Request) -> HttpServer.Response:
	if not _authorized(req):
		var r := HttpServer.Response.text(401, "authentication required")
		r.headers["WWW-Authenticate"] = "Bearer"
		return r
	if req.method != "GET":
		return HttpServer.Response.text(405, "GET only")
	if kind == "list":
		return _list()
	if store == "":
		return HttpServer.Response.text(404, "not found")
	match kind:
		"release":
			var id := parts[1]
			var release := parts[3].trim_suffix(".json")
			if not _open(id) or not ContentRelease.is_release_id(release) or not ServerHost.is_world_id(id):
				return HttpServer.Response.text(404, "not found")
			return _static(ContentRelease.release_path(str(instances.get(id, id)), release), "application/json", req)
		"manifest":
			var h := parts[2].trim_suffix(".json.gz")
			if not ContentManifest.is_hash(h) or parts[1] != h.substr(0, 2):
				return HttpServer.Response.text(404, "not found")
			return _static(ContentRelease.manifest_path(h), "application/gzip", req)
		"bundle":
			var h := parts[2].trim_suffix(".bundle")
			if not ContentManifest.is_hash(h) or parts[1] != h.substr(0, 2):
				return HttpServer.Response.text(404, "not found")
			return _static(ContentRelease.bundle_path(h), "application/octet-stream", req)
	return HttpServer.Response.text(404, "not found")


func _authorized(req: HttpServer.Request) -> bool:
	if auth == null:
		return false
	var h := req.header("authorization")
	if not h.begins_with("Bearer "):
		return false
	var token := h.substr(7).strip_edges()
	return token != "" and auth.login_for_token(token) != ""


## Served: the world is open, or it is the content of an open instance.
func _open(id: String) -> bool:
	if not (pin_allowed or not allowed_worlds.is_empty()) or allowed_worlds.has(id):
		return true
	for inst: String in instances:
		if instances[inst] == id and allowed_worlds.has(inst):
			return true
	return false


func _listed(id: String) -> bool:
	return (not pin_allowed and allowed_worlds.is_empty()) or allowed_worlds.has(id)


## worlds.json, read at each call: a few hundred bytes per world, asked once per login (a date has the
## second for unit: a publication within the same second would go unseen by a cache keyed on it).
func _read_pointers() -> Dictionary:
	return ContentStore.pointers(store) if store != "" else {}


func _list() -> HttpServer.Response:
	var pointers := _read_pointers()
	var ids: Array = []
	for id: String in pointers:
		if _listed(id):
			ids.append(id)
	for inst: String in instances: # an open instance is a world of its own in the list
		if _listed(inst) and not ids.has(inst):
			ids.append(inst)
	for id in allowed_worlds: # open but never published: listed, not downloadable
		if not ids.has(id):
			ids.append(id)
	ids.sort()
	var out: Array = []
	for id: String in ids:
		var content := str(instances.get(id, id))
		var p: Variant = pointers.get(content)
		var e := {"id": id, "content": content, "players": int(players.get(id, 0))}
		if p is Dictionary:
			e.merge({"name": str(instances_names.get(id, p.get("name", id))), "module": str(p.get("module", "")),
					"release": str(p.get("release", "")), "state": "ready", "size": int(p.get("size", 0)),
					"files": int(p.get("files", 0)), "zones": int(p.get("zones", 0)), "zones_size": int(p.get("zones_size", 0))})
		else:
			e.merge({"name": str(instances_names.get(id, id)), "module": "", "release": "", "state": "unpublished",
					"note": "contenu non publie sur le serveur", "size": 0, "files": 0, "zones": 0, "zones_size": 0})
		out.append(e)
	return HttpServer.Response.json(200, out)


## A file of the store (all of it, or the span of a Range request). Immutable: cached forever.
func _static(rel: String, mime: String, req: HttpServer.Request) -> HttpServer.Response:
	var path := store.path_join(rel)
	var size := ContentStore.file_size(path)
	if size < 0:
		return HttpServer.Response.text(404, "not found")
	var r := HttpServer.Response.new()
	r.headers["Content-Type"] = mime
	r.headers["Cache-Control"] = "private, max-age=31536000, immutable"
	r.headers["Accept-Ranges"] = "bytes"
	r.file_path = path
	var range_header := req.header("range")
	if range_header == "":
		r.file_length = size
		return r
	var span := parse_range(range_header, size)
	if span.is_empty():
		var bad := HttpServer.Response.text(416, "bad range")
		bad.headers["Content-Range"] = "bytes */%d" % size
		return bad
	r.status = 206
	r.file_offset = span[0]
	r.file_length = span[1] - span[0] + 1
	r.headers["Content-Range"] = "bytes %d-%d/%d" % [span[0], span[1], size]
	return r


## "bytes=a-", "bytes=a-b", "bytes=-n" (one range) -> [first, last] inclusive, [] if unsatisfiable.
static func parse_range(header: String, size: int) -> Array:
	if not header.begins_with("bytes=") or header.contains(","):
		return []
	var spec := header.substr(6).split("-")
	if spec.size() != 2:
		return []
	var first: int
	var last: int
	if spec[0] == "":
		if not spec[1].is_valid_int() or int(spec[1]) <= 0:
			return []
		first = maxi(0, size - int(spec[1]))
		last = size - 1
	else:
		if not spec[0].is_valid_int():
			return []
		first = int(spec[0])
		last = size - 1 if spec[1] == "" else (int(spec[1]) if spec[1].is_valid_int() else -1)
	last = mini(last, size - 1)
	if first < 0 or last < first or first >= size:
		return []
	return [first, last]
