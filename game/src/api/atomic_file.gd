## The one durable write of the project (roadmap R.07): the document goes to <path>.tmp, is read
## back and compared, then renamed over <path>. A kill in the middle, a full disk or a refused
## rename leaves the previous file whole and returns false; every failure is counted in
## `failed_writes` (exposed by admin.metrics) and reported with `push_error`.
## Used by FilePersistence, ServerPersistence and WorldCluster (instances.json).
## Not used by sim/, shared/ or client/.
class_name AtomicFile
extends RefCounted

## writes that failed since the process started
static var failed_writes := 0


## JSON (tab-indented) written atomically. False = nothing replaced.
static func write_json(path: String, data: Variant) -> bool:
	return write_text(path, JSON.stringify(data, "\t"))


static func write_text(path: String, text: String) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return _fail(path, "cannot open " + tmp)
	f.store_string(text)
	f.flush()
	f.close()
	if FileAccess.get_file_as_string(tmp) != text: # short write (disk full)
		DirAccess.remove_absolute(tmp)
		return _fail(path, "short write")
	if DirAccess.rename_absolute(tmp, path) != OK:
		DirAccess.remove_absolute(tmp)
		return _fail(path, "rename refused")
	return true


static func _fail(path: String, why: String) -> bool:
	failed_writes += 1
	push_error("atomic write failed (%s): %s" % [why, path])
	return false
