## The durable store of the server (roadmap S.03): FilePersistence made reliable.
##   - atomic write: the document goes to <file>.tmp, is read back and checked, then
##     renamed over the real file: a kill in the middle leaves the previous file whole
##     (a stale .tmp is ignored by reads and swept by `sweep_tmp`);
##   - rotating copies: before a document is replaced, the old one is copied to
##     <dir>/_backups/<collection>/<key>/<stamp>.json, at most once per `backup_interval_ms`
##     (a deletion always keeps a copy), and only the newest `keep` copies survive;
##   - recovery: a document that does not parse (disk full, bad edit) is rebuilt from
##     its newest valid copy, and the fact is recorded in `recovered`;
##   - `restore` puts a chosen copy back by hand.
## The `Persistence` interface does not change: the sim cannot tell (SQLite later, S.03 notes).
## Nothing here knows which game a world runs.
class_name ServerPersistence
extends FilePersistence

const BACKUPS := "_backups"

## copies kept per document. APPROX(S.03): 10, as the roadmap says
var keep := 10
## minimum time between two copies of one document. APPROX(S.03): 5 min, so that a character
## saved at every map change does not push the useful old copies out in a minute
var backup_interval_ms := 300000
## wall clock in ms (replaceable in tests)
var now_ms := Callable(ServerPersistence, "_system_ms")
## [{collection, key, from}] documents rebuilt from a copy since this object exists
var recovered: Array[Dictionary] = []
## writes that failed (disk full, no right): [{collection, key}]
var failed_writes: Array[Dictionary] = []


func _init(p_dir := "user://server_saves") -> void:
	super(p_dir)


static func _system_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


# --- reads -----------------------------------------------------------------

func _raw_read(collection: String, key: String) -> Dictionary:
	var path := _path(collection, key)
	if FileAccess.file_exists(path):
		var data := _parse(path)
		if not data.is_empty() or _is_empty_object(path):
			return data
		return _recover(collection, key)
	return super(collection, key) # legacy layout (before P0.02) or nothing


func _recover(collection: String, key: String) -> Dictionary:
	for stamp in backups(collection, key): # newest first
		var data := _parse(_backup_path(collection, key, stamp))
		if not data.is_empty():
			recovered.append({"collection": collection, "key": key, "from": stamp})
			push_warning("persistence: %s/%s unreadable, restored from copy %d" % [collection, key, stamp])
			_write_atomic(_path(collection, key), data) # heal the main file
			return data
	push_error("persistence: %s/%s unreadable and no valid copy" % [collection, key])
	return {}


func _parse(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _is_empty_object(path: String) -> bool:
	return FileAccess.get_file_as_string(path).strip_edges() == "{}"


# --- writes ----------------------------------------------------------------

func _raw_write(collection: String, key: String, data: Dictionary) -> void:
	var path := _path(collection, key)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if FileAccess.file_exists(path):
		_backup(collection, key, false)
	if not _write_atomic(path, data):
		failed_writes.append({"collection": collection, "key": key})
		push_error("persistence: cannot write %s/%s" % [collection, key])


func _raw_erase(collection: String, key: String) -> void:
	if FileAccess.file_exists(_path(collection, key)):
		_backup(collection, key, true)
	super(collection, key)


## tmp file, read back and checked, then renamed over `path`. False = nothing replaced.
func _write_atomic(path: String, data: Dictionary) -> bool:
	var tmp := path + ".tmp"
	var text := JSON.stringify(data, "\t")
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.flush()
	f.close()
	if FileAccess.get_file_as_string(tmp) != text: # short write (disk full)
		DirAccess.remove_absolute(tmp)
		return false
	if DirAccess.rename_absolute(tmp, path) != OK:
		DirAccess.remove_absolute(tmp)
		return false
	return true


# --- copies ----------------------------------------------------------------

## Copy of the current file of a document; `force` ignores the interval.
func _backup(collection: String, key: String, force: bool) -> void:
	if keep <= 0:
		return
	var path := _path(collection, key)
	if _parse(path).is_empty() and not _is_empty_object(path):
		return # never rotate a damaged file over the good copies
	var stamps := backups(collection, key)
	var now := int(now_ms.call())
	if not force and not stamps.is_empty() and now - stamps[0] < backup_interval_ms:
		return
	var stamp := now
	if not stamps.is_empty() and stamp <= stamps[0]:
		stamp = stamps[0] + 1 # strictly increasing, even with a frozen or stepped-back clock
	var dest := _backup_path(collection, key, stamp)
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	DirAccess.copy_absolute(path, dest)
	stamps = backups(collection, key)
	for i in range(keep, stamps.size()):
		DirAccess.remove_absolute(_backup_path(collection, key, stamps[i]))


## Stamps (ms) of the copies of a document, newest first.
func backups(collection: String, key: String) -> Array[int]:
	var out: Array[int] = []
	var folder := _backup_dir(collection, key)
	if DirAccess.dir_exists_absolute(folder):
		for f in DirAccess.get_files_at(folder):
			if f.ends_with(".json") and f.trim_suffix(".json").is_valid_int():
				out.append(int(f.trim_suffix(".json")))
	out.sort()
	out.reverse()
	return out


## Puts the copy `stamp` back as the document (the current file is itself kept as a copy first).
## stamp 0 = the newest valid copy. False if there is none.
func restore(collection: String, key: String, stamp := 0) -> bool:
	var stamps := backups(collection, key)
	if stamp == 0:
		for s in stamps:
			if not _parse(_backup_path(collection, key, s)).is_empty():
				stamp = s
				break
	if stamp == 0 or not stamps.has(stamp):
		return false
	var data := _parse(_backup_path(collection, key, stamp))
	if data.is_empty():
		return false
	var path := _path(collection, key)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if FileAccess.file_exists(path):
		_backup(collection, key, true)
	return _write_atomic(path, data)


## Removes the .tmp files a crash left behind; returns how many.
func sweep_tmp() -> int:
	return _sweep(dir)


func _sweep(path: String) -> int:
	var n := 0
	if not DirAccess.dir_exists_absolute(path):
		return 0
	for f in DirAccess.get_files_at(path):
		if f.ends_with(".json.tmp"):
			DirAccess.remove_absolute(path.path_join(f))
			n += 1
	for d in DirAccess.get_directories_at(path):
		n += _sweep(path.path_join(d))
	return n


func _backup_dir(collection: String, key: String) -> String:
	return dir.path_join(BACKUPS).path_join(collection.validate_filename()).path_join(_safe_key(key))


func _backup_path(collection: String, key: String, stamp: int) -> String:
	return _backup_dir(collection, key).path_join("%d.json" % stamp)
