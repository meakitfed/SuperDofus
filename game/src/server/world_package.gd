## Builds the package of a world (roadmap C.02): lists the files a client needs, hashes them and
## writes `manifest.json`. Server side only (reads the game folder on disk).
##
## What a package holds, as logical paths (ContentSource):
##   worlds/<id>/**     the definition of the world (files starting with "_" are build leftovers)
##   data/**            the light generated tables
##   <world.json "content">   a list of globs ("content/Content/Maps/*.webp"): the assets the world
##                      uses. NOT a copy of the content folder (22 GB): only what the globs select.
## `world.json` also gives `name` and `module` (the game module the world runs, "" if unset), and
## `server_only`: globs of logical paths (`worlds/<id>/maps/*`) the server reads and a client never does,
## kept out of the package.
##
## C.02c, zones: when `_content.json` has `zones` (tools/world_assets.gd), the manifest above is the
## BASE (what every client needs) and each zone gets its own manifest of the extra files its maps need
## (`Built.zones`, `Built.zone_index`, served by ContentApi). Their files are served by hash like the others.
##
## Disk: nothing is copied. The package store (`store_dir`/<id>/) only holds `manifest.json` and
## `index.json` (path -> mtime, size, hash: a file is hashed again only when its date or size
## changed). The bytes are served from where they are, by hash. `store_dir` is configurable
## (`--package-dir`), C: being nearly full. Never touches the client or the sim.
class_name WorldPackage
extends RefCounted

const SKIP_SUFFIXES: PackedStringArray = [".import", ".uid", ".tmp", ".part"]

## what a build returns
class Built:
	var ok := false
	var error := ""
	var world := ""
	var manifest := {}
	## hash -> {path (absolute), size, mtime}: what the content API may serve
	var blobs := {}
	## files hashed by this build (0 = everything came from the cache)
	var hashed := 0
	var reused := 0
	## the manifest on disk was replaced
	var written := false
	## the base bundle (C.05, WorldBundle): its index, and part name -> {path, size, mtime, hash};
	## empty = none built, the world is then installed file by file
	var bundle_index := {}
	var bundle_files := {}
	## C.02c: zone id -> manifest (ContentManifest + `zone`, `maps`), and the index of ContentZones; empty = not zoned
	var zones := {}
	var zone_index := {}
	## C.06: zone id -> {path (absolute), size, mtime, hash}: the zip of a zone (`pack` of its manifest), when published
	var zone_packs := {}
	## the build options (`build` opts) and its counters
	var opts := {}
	var visited := {}
	var _last_checkpoint_ms := 0
	var _last_progress_ms := 0


## Builds (or refreshes) the package of `world_id` from the game folder `root` (absolute path of the
## folder holding worlds/, data/, content/). `force` ignores the hash cache.
## `opts` (C.06, the publication step): `checkpoint_ms` (write the hash index at most this often while
## hashing, so that an interruption keeps the work done; 0 = only at the end), `on_progress`
## Callable(done, reused) called about once a second, `abort_after` (tests: stop with an error after
## that many files were hashed, the index is saved first).
static func build(world_id: String, root: String, store_dir: String, force := false, opts := {}) -> Built:
	var out := Built.new()
	out.world = world_id
	out.opts = opts
	if not is_world_id(world_id):
		out.error = "bad world id"
		return out
	var def_path := root.path_join("worlds").path_join(world_id).path_join("world.json")
	var def: Variant = JSON.parse_string(FileAccess.get_file_as_string(def_path)) if FileAccess.file_exists(def_path) else null
	if not def is Dictionary:
		out.error = "world %s has no world.json under %s" % [world_id, root]
		return out
	var logical := _list(world_id, root, def)
	var pkg_dir := store_dir.path_join(world_id)
	DirAccess.make_dir_recursive_absolute(pkg_dir)
	var index := {} if force else _read_json(pkg_dir.path_join("index.json"))
	var new_index := index.duplicate() # seeded with the cache: a checkpoint never forgets what is not visited yet
	out.opts["_index_path"] = pkg_dir.path_join("index.json")
	var files := _hash_all(logical, root, index, new_index, out)
	if out.error != "":
		return out
	var computed := _read_json(root.path_join("worlds/%s/%s" % [world_id, WorldAssets.FILE]))
	if computed.get("zones") is Dictionary and not (computed["zones"] as Dictionary).is_empty():
		var base_paths := {}
		for f: Dictionary in files:
			base_paths[f["path"]] = true
		_build_zones(out, root, computed, base_paths, index, new_index, def)
		if out.error != "":
			return out
	out.manifest = ContentManifest.make(world_id, str(def.get("name", world_id)), str(def.get("module", "")), files)
	DirAccess.make_dir_recursive_absolute(pkg_dir)
	var manifest_path := pkg_dir.path_join("manifest.json")
	var text := JSON.stringify(out.manifest)
	if FileAccess.get_file_as_string(manifest_path) != text:
		_write_atomic(manifest_path, text)
		out.written = true
	var kept := {}
	for p: String in out.visited:
		kept[p] = new_index[p]
	_write_atomic(pkg_dir.path_join("index.json"), JSON.stringify(kept))
	out.visited = {}
	out.ok = true
	return out


## Hashes `logical` paths (a file whose date and size match the cache `index` is not read again),
## fills `new_index` and `out.blobs`; returns the manifest entries. `out.error` is set when a file is unreadable.
static func _hash_all(logical: PackedStringArray, root: String, index: Dictionary, new_index: Dictionary, out: Built) -> Array:
	var files: Array = []
	for path in logical:
		var abs_path := root.path_join(path)
		var size := _size(abs_path)
		var mtime := FileAccess.get_modified_time(abs_path)
		var cached: Variant = new_index.get(path) # the cache, or what this very build already hashed (a file shared by two zones)
		var digest := ""
		if cached is Array and cached.size() == 3 and int(cached[0]) == mtime and int(cached[1]) == size:
			digest = str(cached[2])
			out.reused += 1
		else:
			digest = hash_file(abs_path)
			out.hashed += 1
		if digest == "":
			out.error = "cannot read " + path
			return files
		new_index[path] = [mtime, size, digest]
		out.visited[path] = true
		_tick(out, new_index)
		if out.error != "":
			return files
		files.append({"path": path, "hash": digest, "size": size})
		out.blobs[digest] = {"path": abs_path, "size": size, "mtime": mtime}
	return files


## C.06: progress report and checkpoint of the hash index (atomic: a cut keeps the last complete one).
static func _tick(out: Built, new_index: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	var every := int(out.opts.get("checkpoint_ms", 0))
	var abort_after := int(out.opts.get("abort_after", 0))
	var aborting := abort_after > 0 and out.hashed >= abort_after
	if (every > 0 and now - out._last_checkpoint_ms >= every) or aborting:
		out._last_checkpoint_ms = now
		_write_atomic(str(out.opts["_index_path"]), JSON.stringify(new_index))
	var cb: Variant = out.opts.get("on_progress")
	if cb is Callable and (cb as Callable).is_valid() and now - out._last_progress_ms >= 1000:
		out._last_progress_ms = now
		(cb as Callable).call(out.hashed + out.reused, out.reused)
	if aborting:
		out.error = "interrupted (abort_after)"


## C.02c: one manifest per zone of `computed` (the content of _content.json): literal files by
## folder (`files`) and folder globs (`dirs`), minus what the base holds.
static func _build_zones(out: Built, root: String, computed: Dictionary, base_paths: Dictionary, index: Dictionary,
		new_index: Dictionary, def: Dictionary) -> void:
	var walked := {} # glob -> PackedStringArray: zones share their folders
	var ids: Array = (computed["zones"] as Dictionary).keys()
	ids.sort()
	for id: String in ids:
		if not ContentZones.is_zone_id(id):
			continue
		var z: Dictionary = computed["zones"][id]
		var set := {}
		var dirs: Dictionary = z.get("files", {})
		for dir: String in dirs:
			for name: Variant in dirs[dir]:
				var path := dir + "/" + str(name)
				if ContentManifest.safe_path(path) and FileAccess.file_exists(root.path_join(path)):
					set[path] = true
		for g: Variant in z.get("dirs", []):
			var pattern := str(g)
			if not ContentManifest.safe_path(pattern.replace("*", "x").replace("?", "x")) or ContentManifest.glob_base(pattern) == "":
				continue
			if not walked.has(pattern):
				var found := {}
				_walk(root, ContentManifest.glob_base(pattern),
						func(p: String) -> bool: return ContentManifest.glob_matches(pattern, p), found)
				walked[pattern] = found.keys()
			for p: String in walked[pattern]:
				set[p] = true
		var logical := PackedStringArray()
		for p: String in set:
			if not base_paths.has(p):
				logical.append(p)
		logical.sort()
		var files := _hash_all(logical, root, index, new_index, out)
		if out.error != "":
			return
		var m := ContentManifest.make(out.world, str(def.get("name", out.world)), str(def.get("module", "")), files)
		m["zone"] = id
		m["maps"] = z.get("maps", [])
		m["requires"] = z.get("requires", []) # C.02g
		m["skins"] = z.get("skins", [])
		out.zones[id] = m
	out.zone_index = ContentZones.make_index(out.world, str(computed.get("start_zone", "")), out.zones)
	for id: String in out.zones: # the maps are in the index, not repeated in each manifest
		(out.zones[id] as Dictionary).erase("maps")
		(out.zones[id] as Dictionary).erase("requires")
		(out.zones[id] as Dictionary).erase("skins")


static func is_world_id(id: String) -> bool:
	var re := RegEx.create_from_string("^[A-Za-z0-9_-]{1,64}$")
	return re.search(id) != null


static func hash_file(abs_path: String) -> String:
	return FileHash.sha256(abs_path)


## Sorted logical paths of the package.
static func _list(world_id: String, root: String, def: Dictionary) -> PackedStringArray:
	var set := {}
	var server_only: Array = def.get("server_only", []) if def.get("server_only") is Array else []
	_walk(root, "worlds/" + world_id, func(p: String) -> bool:
		if p.get_file().begins_with("_"):
			return false
		for g: Variant in server_only:
			if ContentManifest.glob_matches(str(g), p):
				return false
		return true, set)
	_walk(root, "data", func(_p: String) -> bool: return true, set)
	var globs: Array = []
	if def.get("content") is Array:
		globs.append_array(def["content"])
	var computed := _read_json(root.path_join("worlds/%s/%s" % [world_id, WorldAssets.FILE]))
	if computed.get("globs") is Array: # C.02b: what tools/world_assets.gd selected
		globs.append_array(computed["globs"])
	for g in globs:
		var pattern := str(g)
		if not ContentManifest.safe_path(pattern.replace("*", "x").replace("?", "x")):
			continue # a glob is a relative logical path, never an escape
		if not (pattern.contains("*") or pattern.contains("?") or pattern.contains("[")):
			if FileAccess.file_exists(root.path_join(pattern)): # a literal file: no walk
				set[pattern] = true
			continue
		if ContentManifest.glob_base(pattern) == "":
			continue # a glob must name a folder: never walk the whole game
		_walk(root, ContentManifest.glob_base(pattern),
				func(p: String) -> bool: return ContentManifest.glob_matches(pattern, p), set)
	var out := PackedStringArray(set.keys())
	out.sort()
	return out


static func _walk(root: String, rel_dir: String, keep: Callable, set: Dictionary) -> void:
	var dir := root.path_join(rel_dir) if rel_dir != "" else root
	for f in DirAccess.get_files_at(dir):
		var skip := false
		for suffix in SKIP_SUFFIXES:
			if f.ends_with(suffix):
				skip = true
		var rel := (rel_dir + "/" + f) if rel_dir != "" else f
		if not skip and not f.begins_with(".") and keep.call(rel):
			set[rel] = true
	for d in DirAccess.get_directories_at(dir):
		if not d.begins_with("."):
			_walk(root, (rel_dir + "/" + d) if rel_dir != "" else d, keep, set)


static func _size(abs_path: String) -> int:
	var f := FileAccess.open(abs_path, FileAccess.READ)
	return f.get_length() if f != null else -1


static func _read_json(path: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return data if data is Dictionary else {}


static func _write_atomic(path: String, text: String) -> void:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(text)
	f.close()
	DirAccess.rename_absolute(tmp, path)
