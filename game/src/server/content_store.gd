## The folder of the published content (roadmap C.07, `--package-dir`): the static tree a content server
## (the game server's HTTP port, or any static host / CDN) serves as is. Layout: ContentRelease; besides it,
## files that are never served:
##   bundles.json            content hash -> [bundle, offset, size]: where the publication put each content
##   <world>/index.json      the hash cache of the publication (path -> mtime, size, hash)
##   <world>/history.json    the releases published for the world, newest last (pruning)
## `worlds.json` is written LAST by a publication: a server or a client sees the previous complete release
## or the new one, never a mix. Reading it is the only thing a game server does with this folder.
class_name ContentStore
extends RefCounted

const WORLDS := "worlds.json"
const BUNDLE_INDEX := "bundles.json"
const HISTORY := "history.json"


## id -> pointer {release, name, module, size, files, zones, zones_size} of every published world.
static func pointers(store: String) -> Dictionary:
	var doc := read_json(store.path_join(WORLDS))
	if int(doc.get("format", 0)) != ContentRelease.FORMAT or not doc.get("worlds") is Dictionary:
		return {}
	return doc["worlds"]


## The pointer of a world ({} = never published).
static func pointer(store: String, world: String) -> Dictionary:
	var p: Variant = pointers(store).get(world)
	return p if p is Dictionary and ContentRelease.is_release_id(str(p.get("release", ""))) else {}


## Sets the pointer of `world` (the other worlds are kept), atomically.
static func set_pointer(store: String, world: String, entry: Dictionary) -> bool:
	var all := pointers(store)
	all[world] = entry
	return write_atomic(store.path_join(WORLDS), JSON.stringify({"format": ContentRelease.FORMAT, "worlds": all}, "\t"))


## "" when `world` is published and its release index is on disk, else what to do.
static func check(store: String, world: String) -> String:
	var p := pointer(store, world)
	if p.is_empty():
		return "monde %s non publie : lancer la publication (--build-packages, ou tools/publish_content.py)" % world
	if file_size(store.path_join(ContentRelease.release_path(world, str(p["release"])))) <= 0:
		return "monde %s : release %s introuvable dans %s : republier" % [world, p["release"], store]
	return ""


static func read_json(path: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return data if data is Dictionary else {}


## Writes `text` through a temporary file (the old file stays whole until the new one is).
static func write_atomic(path: String, text: String) -> bool:
	return write_bytes_atomic(path, text.to_utf8_buffer())


static func write_bytes_atomic(path: String, bytes: PackedByteArray) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(bytes)
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path) == OK


## -1 when absent (a stat, never an open).
static func file_size(path: String) -> int:
	return FileHash.size_of(path)


static func remove_tree(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		remove_tree(dir.path_join(d))
	DirAccess.remove_absolute(dir)
