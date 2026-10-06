## Builds the base bundle of a world package (roadmap C.05): zip parts (ContentBundle) holding
## every distinct content of the manifest, compressed (already compressed images are stored).
## Server side only. Stored in `<store>/<id>/bundle/<version>/` (`index.json` + `part-NNN.zip`);
## rebuilt only when the manifest version changed, older versions are deleted. Reads the bytes
## from where the package says they are (`Built.blobs`) and refuses a file changed since the
## build (rebuild the package). The disk check is the caller's (`--package-dir`).
class_name WorldBundle
extends RefCounted

## a build's result
class Result:
	var ok := false
	var error := ""
	var index := {}
	## part name -> {path (absolute), size, mtime, hash}: what the content API may serve
	var files := {}
	## false = the bundle of this version was already on disk
	var built := false
	var source_bytes := 0
	var zip_bytes := 0
	var seconds := 0.0


## `on_part` (optional): Callable(done_parts, total_parts), called after each part is written.
static func build(pkg: WorldPackage.Built, store_dir: String, max_source := ContentBundle.DEFAULT_MAX_SOURCE,
		on_part := Callable(), max_entries := ContentBundle.DEFAULT_MAX_ENTRIES) -> Result:
	var out := Result.new()
	var t0 := Time.get_ticks_msec()
	var manifest := pkg.manifest
	var version := str(manifest["version"])
	var base := store_dir.path_join(pkg.world).path_join("bundle")
	var dir := base.path_join(version.substr(0, 16))
	var planned := ContentBundle.plan(manifest, max_source, max_entries)
	for p: Dictionary in planned:
		out.source_bytes += int(p["source"])
	var existing: Variant = _read_json(dir.path_join("index.json"))
	if ContentBundle.validate(existing, manifest) == "" and int(existing["max_source"]) == max_source and int(existing["max_entries"]) == max_entries \
			and _register(out, existing, dir):
		out.index = existing
		out.ok = true
		out.seconds = (Time.get_ticks_msec() - t0) / 1000.0
		return out
	out.files.clear()
	DirAccess.make_dir_recursive_absolute(dir)
	var parts: Array = []
	for i in planned.size():
		var name := ContentBundle.part_name(i)
		var path := dir.path_join(name)
		var err := _write_part(pkg, planned[i], path)
		if err != "":
			out.error = "%s: %s" % [name, err]
			return out
		parts.append({"name": name, "size": _size(path), "hash": FileHash.sha256(path)})
		if on_part.is_valid():
			on_part.call(i + 1, planned.size())
	var index := ContentBundle.make_index(manifest, max_source, parts, max_entries)
	_write_atomic(dir.path_join("index.json"), JSON.stringify(index))
	_register(out, index, dir)
	out.index = index
	out.built = true
	out.ok = true
	for d in DirAccess.get_directories_at(base): # the bundles of older versions
		if d != version.substr(0, 16):
			_remove_tree(base.path_join(d))
	out.seconds = (Time.get_ticks_msec() - t0) / 1000.0
	return out


## Fills `out.files` from an index and the parts on disk; false when a part is missing or has
## another size (the bundle is then rebuilt).
static func _register(out: Result, index: Dictionary, dir: String) -> bool:
	out.zip_bytes = 0
	for p: Dictionary in index["parts"]:
		var path := dir.path_join(str(p["name"]))
		if _size(path) != int(p["size"]):
			out.files.clear()
			return false
		out.files[str(p["name"])] = {"path": path, "size": int(p["size"]),
				"mtime": FileAccess.get_modified_time(path), "hash": str(p["hash"])}
		out.zip_bytes += int(p["size"])
	return true


static func _write_part(pkg: WorldPackage.Built, part: Dictionary, path: String) -> String:
	var tmp := path + ".tmp"
	var zip := ZIPPacker.new()
	if zip.open(tmp) != OK:
		return "cannot write " + tmp
	for h: String in part["hashes"]:
		var blob: Variant = pkg.blobs.get(h)
		if not blob is Dictionary:
			zip.close()
			return "content %s is not in the package" % h
		var src := str(blob["path"])
		if _size(src) != int(blob["size"]) or FileAccess.get_modified_time(src) != int(blob["mtime"]):
			zip.close()
			return "file changed since the package was built: rebuild it (%s)" % src
		var data := FileAccess.get_file_as_bytes(src)
		if data.size() != int(blob["size"]):
			zip.close()
			return "cannot read " + src
		zip.compression_level = 0 if ContentBundle.stored(src) else 6
		if zip.start_file(h) != OK or zip.write_file(data) != OK or zip.close_file() != OK:
			zip.close()
			return "cannot pack " + src
	zip.close()
	DirAccess.remove_absolute(path)
	if DirAccess.rename_absolute(tmp, path) != OK:
		return "cannot write " + path
	return ""


static func _size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_length() if f != null else -1


static func _read_json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null


static func _write_atomic(path: String, text: String) -> void:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(text)
	f.close()
	DirAccess.rename_absolute(tmp, path)


static func _remove_tree(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_remove_tree(dir.path_join(d))
	DirAccess.remove_absolute(dir)
