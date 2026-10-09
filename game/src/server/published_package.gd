## A published world package (roadmap C.06): what the publication step (ContentPublisher) leaves on disk
## and what the server reads at start, WITHOUT hashing or walking anything.
##
##   <store>/<world>/current.json            pointer {format, world, release, version, published_at}, written LAST
##   <store>/<world>/index.json              hash cache of the build (path -> mtime, size, hash), not published
##   <store>/<world>/files/<hash>            optional (--copy-files): the bytes by hash, for a static host
##   <store>/<world>/versions/<release>/     one IMMUTABLE version, laid out like the content API (docs/EXPORT.md):
##       manifest.json  bundle.json  bundle/part-NNN.zip  zones.json  zones/<zone>/manifest.json  zones/<zone>/pack.zip
##       blobs.json     hash -> [path, size, mtime]: where the server reads a file by hash (not published)
##       release.json   the stamp: version, options and the size of every artifact (checked at start)
##
## `load` only reads the small JSON files and checks that each artifact exists with its recorded size
## (a stat, no hashing): a package cut in the middle of a publication has no release.json / no pointer
## and is refused with a message that names the build step. Nothing here knows which game a world runs.
class_name PublishedPackage
extends RefCounted

const FORMAT := 1
const CURRENT := "current.json"
const RELEASE := "release.json"
const BLOBS := "blobs.json"


static func world_dir(store: String, world: String) -> String:
	return store.path_join(world)


static func version_dir(store: String, world: String, release: String) -> String:
	return world_dir(store, world).path_join("versions").path_join(release)


## The pointer of a world ({} = nothing published).
static func current(store: String, world: String) -> Dictionary:
	var c := read_json(world_dir(store, world).path_join(CURRENT))
	return c if int(c.get("format", 0)) == FORMAT and str(c.get("release", "")) != "" else {}


## "" when the package is published and complete (existence and size of every artifact), else why not.
static func verify(store: String, world: String) -> String:
	var r := _stamp(store, world)
	return str(r["error"])


static func _stamp(store: String, world: String) -> Dictionary:
	var cur := current(store, world)
	if cur.is_empty():
		return {"error": "paquet %s non publie : lancer l'etape de build (--build-packages, ou tools/publish_content.py)" % world}
	var dir := version_dir(store, world, str(cur["release"]))
	var rel := read_json(dir.path_join(RELEASE))
	if int(rel.get("format", 0)) != FORMAT or str(rel.get("release", "")) != str(cur["release"]) \
			or str(rel.get("version", "")) != str(cur.get("version", "")) or not rel.get("artifacts") is Dictionary:
		return {"error": "paquet %s : publication incomplete ou illisible (%s) : relancer --build-packages" % [world, dir]}
	for name: String in rel["artifacts"]:
		var size := file_size(dir.path_join(name))
		if size != int(rel["artifacts"][name]):
			return {"error": "paquet %s : %s manquant ou de taille differente : relancer --build-packages" % [world, name]}
	return {"error": "", "dir": dir, "release": rel, "current": cur}


## The package `world` as ServerApp / ContentApi use it. `root` = the folder holding worlds/, data/, content/
## (blobs.json paths are relative to it). `error` says what to do when not `ok`.
static func load_package(store: String, world: String, root: String) -> WorldPackage.Built:
	var out := WorldPackage.Built.new()
	out.world = world
	var st := _stamp(store, world)
	if str(st["error"]) != "":
		out.error = str(st["error"])
		return out
	var dir: String = st["dir"]
	var rel: Dictionary = st["release"]
	out.manifest = read_json(dir.path_join("manifest.json"))
	if str(out.manifest.get("version", "")) != str(rel["version"]):
		out.error = "paquet %s : manifest d'une autre version : relancer --build-packages" % world
		return out
	var blobs := read_json(dir.path_join(BLOBS))
	for h: String in blobs:
		var e: Array = blobs[h]
		var path := str(e[0])
		out.blobs[h] = {"path": world_dir(store, world).path_join(path.substr(1)) if path.begins_with("@") else root.path_join(path),
				"size": int(e[1]), "mtime": int(e[2])}
	var artifacts: Dictionary = rel["artifacts"]
	if artifacts.has("bundle.json"):
		out.bundle_index = read_json(dir.path_join("bundle.json"))
		for p: Dictionary in out.bundle_index.get("parts", []):
			var path := dir.path_join("bundle").path_join(str(p["name"]))
			out.bundle_files[str(p["name"])] = {"path": path, "size": int(p["size"]),
					"mtime": FileAccess.get_modified_time(path), "hash": str(p["hash"])}
	if artifacts.has("zones.json"):
		out.zone_index = read_json(dir.path_join("zones.json"))
		for id: String in out.zone_index.get("zones", {}):
			var m := read_json(dir.path_join("zones").path_join(id).path_join("manifest.json"))
			out.zones[id] = m
			if m.get("pack") is Dictionary:
				var path := dir.path_join("zones").path_join(id).path_join("pack.zip")
				out.zone_packs[id] = {"path": path, "size": int(m["pack"]["size"]), "mtime": FileAccess.get_modified_time(path),
						"hash": str(m["pack"]["hash"])}
	out.ok = true
	return out


static func file_size(path: String) -> int:
	return FileHash.size_of(path)


static func read_json(path: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return data if data is Dictionary else {}


## Writes `text` to `path` through a temporary file (the old file stays until the new one is complete).
static func write_atomic(path: String, text: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path) == OK
