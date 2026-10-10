## Writes the bundles of a content store (roadmap C.07): each content (by hash) is written ONCE in the whole
## store, appended to the open bundle; a bundle is closed past `max_bytes` and renamed by the SHA-256 of its
## bytes (ContentRelease.bundle_path). `index` (bundles.json) says where every content lives: a content an
## earlier publication (of any world) already wrote is never written again, so a new release only adds the
## files that changed. Publication side only.
##
## Resumable: the index is saved when asked (`save`); a cut loses the bundle being written and the bundles
## closed since the last save (they are no longer referenced: ContentPublisher.gc removes them).
class_name BundleWriter
extends RefCounted

const MAX_BYTES := 32 * 1024 * 1024

var store := ""
var max_bytes := MAX_BYTES
## hash -> [bundle hash, offset, size]
var index := {}
## bundles closed by this writer, bytes written
var bundles_written := 0
var bytes_written := 0

var _file: FileAccess
var _tmp := ""
var _ctx: HashingContext
var _pos := 0
var _open: Array = [] # [hash, offset, size] of the bundle being written
var _in_open := {} # hash -> true, the contents of the bundle being written


func _init(p_store: String, p_max := MAX_BYTES) -> void:
	store = p_store
	max_bytes = p_max


func load_index() -> void:
	var doc := ContentStore.read_json(store.path_join(ContentStore.BUNDLE_INDEX))
	index = doc.get("contents", {}) if doc.get("contents") is Dictionary else {}


func save_index() -> bool:
	return ContentStore.write_atomic(store.path_join(ContentStore.BUNDLE_INDEX), JSON.stringify({"contents": index}))


func has(hash: String) -> bool:
	return index.has(hash) or _in_open.has(hash)


## [bundle hash, offset] of a content written (by this writer once closed, or earlier).
func locate(hash: String) -> Array:
	var at: Array = index[hash]
	return [str(at[0]), int(at[1])]


## Appends the bytes of one content (already checked against `hash`). "" or the error.
func add(hash: String, bytes: PackedByteArray) -> String:
	if has(hash):
		return ""
	if _file == null:
		var err := _start()
		if err != "":
			return err
	_file.store_buffer(bytes)
	if not bytes.is_empty():
		_ctx.update(bytes)
	_open.append([hash, _pos, bytes.size()])
	_in_open[hash] = true
	_pos += bytes.size()
	if _pos >= max_bytes:
		return close()
	return ""


## Ends the bundle being written: renamed by its hash, its contents enter the index. "" or the error.
func close() -> String:
	if _file == null:
		return ""
	_file.close()
	_file = null
	if _open.is_empty():
		DirAccess.remove_absolute(_tmp)
		return ""
	var hash := _ctx.finish().hex_encode()
	var dest := store.path_join(ContentRelease.bundle_path(hash))
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	if FileAccess.file_exists(dest): # the same bytes were bundled before (a cut publication): keep that one
		DirAccess.remove_absolute(_tmp)
	elif DirAccess.rename_absolute(_tmp, dest) != OK:
		return "cannot write " + dest
	for e: Array in _open:
		index[e[0]] = [hash, e[1], e[2]]
	bundles_written += 1
	bytes_written += _pos
	_open = []
	_in_open = {}
	return ""


## Abandons the bundle being written (an error or a stop).
func discard() -> void:
	if _file != null:
		_file.close()
		_file = null
		DirAccess.remove_absolute(_tmp)
	_open = []
	_in_open = {}


func _start() -> String:
	var dir := store.path_join("bundles")
	DirAccess.make_dir_recursive_absolute(dir)
	_tmp = dir.path_join("writing-%d.tmp" % Time.get_ticks_usec())
	_file = FileAccess.open(_tmp, FileAccess.WRITE)
	if _file == null:
		return "cannot write in " + dir
	_ctx = HashingContext.new()
	_ctx.start(HashingContext.HASH_SHA256)
	_pos = 0
	_open = []
	_in_open = {}
	return ""
