## Persistence as JSON files (standalone game): <dir>/<collection>/<key>.json,
## each "/" of the key being a sub-folder. A server uses a database instead
## (roadmap S.03); the sim cannot tell the difference.
class_name FilePersistence
extends Persistence

var dir := "user://saves"


func _init(p_dir := "user://saves") -> void:
	dir = p_dir


func _raw_read(collection: String, key: String) -> Dictionary:
	var path := _path(collection, key)
	if not FileAccess.file_exists(path) and collection == CHARACTERS:
		path = dir.path_join(_safe_key(key) + ".json") # saves from before P0.02: <dir>/<world>/<name>.json
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return data if data is Dictionary else {}


func _raw_write(collection: String, key: String, data: Dictionary) -> void:
	var path := _path(collection, key)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp" # write then rename: a crash never leaves half a file
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	DirAccess.rename_absolute(tmp, path)


func _raw_erase(collection: String, key: String) -> void:
	var path := _path(collection, key)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _raw_keys(collection: String) -> PackedStringArray:
	var out := PackedStringArray()
	_walk(dir.path_join(collection), "", out)
	return out


func _walk(path: String, prefix: String, out: PackedStringArray) -> void:
	if not DirAccess.dir_exists_absolute(path): # nothing saved yet: not an error
		return
	for f in DirAccess.get_files_at(path):
		if f.ends_with(".json"):
			out.append(prefix + f.trim_suffix(".json"))
	for d in DirAccess.get_directories_at(path):
		_walk(path.path_join(d), prefix + d + "/", out)


func _path(collection: String, key: String) -> String:
	return dir.path_join(collection.validate_filename()).path_join(_safe_key(key) + ".json")


func _safe_key(key: String) -> String:
	var parts := PackedStringArray()
	for part in key.split("/"):
		parts.append(part.validate_filename())
	return "/".join(parts)
