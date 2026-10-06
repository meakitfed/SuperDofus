## The content API (roadmap C.02), served on the HTTP port:
##   GET /worlds                      [{id, name, module, version, files, size}]
##   GET /worlds/<id>/manifest.json   the manifest (ContentManifest)
##   GET /worlds/<id>/files/<hash>    the bytes (Content-Length, ETag, Range for resuming)
##   GET /worlds/<id>/bundle.json     the base bundle index (C.05), 404 when none was built
##   GET /worlds/<id>/bundle/<part>   one zip part of it (Range too); only the names of the index
##   GET /worlds/<id>/zones.json      the zones of a big world (C.02c, ContentZones), 404 when not zoned
##   GET /worlds/<id>/zones/<zone>/manifest.json   the extra files of one zone (their bytes: /files/<hash>)
## Everything else is 404. Every request needs `Authorization: Bearer <session token>` (the token
## of login_ok: AuthService.login_for_token); without a valid token, 401, and no world is
## revealed. A file is served only if its hash is in the manifest of that world: the client never
## supplies a path, the server maps hash -> file from what its own build recorded, and refuses a
## file that changed on disk since the build (409: rebuild the package). Without an
## AuthService (open server, tools) the API refuses everything: content is never public.
## Nothing here knows which game a world runs.
class_name ContentApi
extends RefCounted

## world id -> WorldPackage.Built
var packages := {}
var auth: AuthService
## empty = every package; else only these worlds are listed and served
var allowed_worlds := PackedStringArray()
## set once the cluster pinned the list: an empty `allowed_worlds` then means no world
var pin_allowed := false
## id -> players in that world now (listed with each world), unset = not given
var players_of := Callable()


func set_package(built: WorldPackage.Built) -> void:
	packages[built.world] = built


func handle(req: HttpServer.Request) -> HttpServer.Response:
	var path := req.path.get_slice("?", 0)
	var parts := path.trim_prefix("/").split("/")
	var known := parts[0] == "worlds" and (parts.size() == 1
			or (parts.size() == 3 and (parts[2] == "manifest.json" or parts[2] == "bundle.json" or parts[2] == "zones.json"))
			or (parts.size() == 4 and (parts[2] == "files" or parts[2] == "bundle"))
			or (parts.size() == 5 and parts[2] == "zones" and parts[4] == "manifest.json"))
	if not known:
		return HttpServer.Response.text(404, "not found")
	if not _authorized(req):
		var r := HttpServer.Response.text(401, "authentication required")
		r.headers["WWW-Authenticate"] = "Bearer"
		return r
	if req.method != "GET":
		return HttpServer.Response.text(405, "GET only")
	if parts.size() == 1:
		return _list()
	var built := _package(parts[1])
	if built == null:
		return HttpServer.Response.text(404, "not found")
	if parts.size() == 3 and parts[2] == "manifest.json":
		return _manifest(built)
	if parts.size() == 3 and parts[2] == "bundle.json":
		if built.bundle_index.is_empty():
			return HttpServer.Response.text(404, "not found")
		var r := HttpServer.Response.json(200, built.bundle_index)
		r.headers["ETag"] = '"%s"' % built.manifest["version"]
		return r
	if parts.size() == 3 and parts[2] == "zones.json":
		if built.zone_index.is_empty():
			return HttpServer.Response.text(404, "not found")
		var r := HttpServer.Response.json(200, built.zone_index)
		r.headers["ETag"] = '"%s"' % built.zone_index["version"]
		return r
	if parts.size() == 5:
		var zone: Variant = built.zones.get(parts[3]) # a key of the dictionary, never a path
		if not zone is Dictionary:
			return HttpServer.Response.text(404, "not found")
		var r := HttpServer.Response.json(200, zone)
		r.headers["ETag"] = '"%s"' % zone["version"]
		return r
	if parts.size() == 4 and parts[2] == "files":
		return _file(built, parts[3], req)
	if parts.size() == 4 and parts[2] == "bundle":
		return _part(built, parts[3], req)
	return HttpServer.Response.text(404, "not found")


func _authorized(req: HttpServer.Request) -> bool:
	if auth == null:
		return false
	var h := req.header("authorization")
	if not h.begins_with("Bearer "):
		return false
	var token := h.substr(7).strip_edges()
	return token != "" and auth.login_for_token(token) != ""


func _package(id: String) -> WorldPackage.Built:
	if (pin_allowed or not allowed_worlds.is_empty()) and not allowed_worlds.has(id):
		return null
	return packages.get(id) # an id is a dictionary key, never a path


func _list() -> HttpServer.Response:
	var out: Array = []
	var ids := packages.keys()
	ids.sort()
	for id: String in ids:
		var built := _package(id)
		if built == null:
			continue
		var m := built.manifest
		var total := 0
		for f: Dictionary in m["files"]:
			total += int(f["size"])
		var zones_size := 0
		for z: Dictionary in built.zone_index.get("zones", {}).values():
			zones_size += int(z["size"])
		out.append({"id": id, "name": m["name"], "module": m["module"], "version": m["version"],
				"files": m["files"].size(), "size": total, "zones": built.zones.size(), "zones_size": zones_size,
				"players": int(players_of.call(id)) if players_of.is_valid() else 0})
	return HttpServer.Response.json(200, out)


func _manifest(built: WorldPackage.Built) -> HttpServer.Response:
	var r := HttpServer.Response.json(200, built.manifest)
	r.headers["ETag"] = '"%s"' % built.manifest["version"]
	return r


func _file(built: WorldPackage.Built, hash: String, req: HttpServer.Request) -> HttpServer.Response:
	if not ContentManifest.is_hash(hash):
		return HttpServer.Response.text(404, "not found")
	var blob: Variant = built.blobs.get(hash)
	if not blob is Dictionary:
		return HttpServer.Response.text(404, "not found")
	var size := int(blob["size"])
	var current := FileAccess.open(str(blob["path"]), FileAccess.READ)
	if current == null or current.get_length() != size \
			or FileAccess.get_modified_time(str(blob["path"])) != int(blob["mtime"]):
		return HttpServer.Response.text(409, "file changed since the package was built: rebuild it")
	current = null
	return _stream(str(blob["path"]), size, hash, req)


## A part of the base bundle: the whitelist is the index, the name never reaches the disk as given.
func _part(built: WorldPackage.Built, name: String, req: HttpServer.Request) -> HttpServer.Response:
	var part: Variant = built.bundle_files.get(name) if ContentBundle.is_part_name(name) else null
	if not part is Dictionary:
		return HttpServer.Response.text(404, "not found")
	var path := str(part["path"])
	var current := FileAccess.open(path, FileAccess.READ)
	if current == null or current.get_length() != int(part["size"]) 			or FileAccess.get_modified_time(path) != int(part["mtime"]):
		return HttpServer.Response.text(409, "bundle changed since it was built: rebuild it")
	current = null
	return _stream(path, int(part["size"]), str(part["hash"]), req)


## The bytes of a file on disk (all of it, or the span of a Range request), ETag = `etag`.
func _stream(path: String, size: int, etag: String, req: HttpServer.Request) -> HttpServer.Response:
	var r := HttpServer.Response.new()
	r.headers["Content-Type"] = "application/octet-stream"
	r.headers["ETag"] = '"%s"' % etag
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
