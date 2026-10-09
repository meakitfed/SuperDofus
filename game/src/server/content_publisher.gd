## The publication step of a world package (roadmap C.06), the "Cytrus" side of the content: it hashes,
## zips and publishes ONCE, outside the game server (`--build-packages`, tools/publish_content.py), and
## the server then only reads what was published (PublishedPackage).
##
## Resumable: the hash index is checkpointed while hashing (WorldPackage), each bundle part and each zone
## pack is recorded in a progress file as soon as it is written. A cut loses at most the current file.
## Atomic: a version is written under versions/<release>/ (a name derived from what it holds, so it is
## never modified once published); `release.json` (the stamp) is written after the artifacts and the
## pointer `current.json` after the stamp. A server (re)starting at any moment sees the previous
## complete version or the new one, never a mix. Older versions are pruned (`keep`, default 3).
##
## Disk: nothing of the 22 GB of content is copied (the bytes stay where they are, `blobs.json` says
## where) unless `copy_files` asks for files/<hash> (a static host, docs/EXPORT.md).
class_name ContentPublisher
extends RefCounted

## contents per zone pack: ZIPReader finds an entry by walking the archive (see ContentBundle.DEFAULT_MAX_ENTRIES)
const PACK_MAX_ENTRIES := 1000
const KEEP_VERSIONS := 3


class Result:
	var ok := false
	var error := ""
	var world := ""
	var version := ""
	var release := ""
	## nothing to do: this exact version was already published (the pointer is fixed if it was not)
	var unchanged := false
	var hashed := 0
	var reused := 0
	var zones := 0
	var zone_packs := 0
	var bundle_parts := 0
	var seconds := 0.0
	var built: WorldPackage.Built


## `opts`: rebuild (ignore the hash cache), no_bundle, bundle_mb, no_zone_packs, copy_files, keep,
## log (Callable(line: String)), abort_after (tests), checkpoint_ms.
static func publish(world: String, root: String, store: String, opts := {}) -> Result:
	var out := Result.new()
	out.world = world
	var t0 := Time.get_ticks_msec()
	var log: Callable = opts.get("log", Callable())
	var say := func(line: String) -> void:
		if log.is_valid():
			log.call(line)
	say.call("%s: listing and hashing the files (the hash cache makes a second run fast)" % world)
	var built := WorldPackage.build(world, root, store, bool(opts.get("rebuild", false)), {
			"checkpoint_ms": int(opts.get("checkpoint_ms", 5000)), "abort_after": int(opts.get("abort_after", 0)),
			"on_progress": func(done: int, reused: int) -> void: say.call("%s: %d files seen (%d from the cache)" % [world, done, reused])})
	out.built = built
	if not built.ok:
		out.error = built.error
		return out
	out.hashed = built.hashed
	out.reused = built.reused
	out.version = str(built.manifest["version"])
	out.zones = built.zones.size()
	var options := {"bundle": not bool(opts.get("no_bundle", false)), "max_source": int(float(opts.get("bundle_mb", 256)) * 1048576.0),
			"zone_packs": not bool(opts.get("no_zone_packs", false)), "copy_files": bool(opts.get("copy_files", false))}
	var zver := str(built.zone_index.get("version", ""))
	out.release = ContentManifest.hash_bytes(("%s|%s|%s" % [out.version, zver, JSON.stringify(options)]).to_utf8_buffer()).substr(0, 16)
	var dir := PublishedPackage.version_dir(store, world, out.release)
	var stamp := PublishedPackage.read_json(dir.path_join(PublishedPackage.RELEASE))
	if str(stamp.get("release", "")) == out.release and _complete(dir, stamp):
		out.unchanged = true
		_point(store, world, out, stamp)
		_prune(store, world, out.release, int(opts.get("keep", KEEP_VERSIONS)))
		out.seconds = (Time.get_ticks_msec() - t0) / 1000.0
		say.call("%s: version %s already published" % [world, out.version.substr(0, 12)])
		return out
	DirAccess.make_dir_recursive_absolute(dir)
	var artifacts := {}
	# 1. the files by hash, when a static host is wanted
	var blobs := {}
	for h: String in built.blobs:
		var b: Dictionary = built.blobs[h]
		blobs[h] = [str(b["path"]).substr(root.length() + 1), int(b["size"]), int(b["mtime"])]
	if bool(options["copy_files"]):
		var err := _copy_files(built, blobs, store, world, say)
		if err != "":
			out.error = err
			return out
	# 2. the zip base
	if bool(options["bundle"]):
		var last := [0]
		var on_part := func(done: int, total: int) -> void:
			if Time.get_ticks_msec() - last[0] >= 1500 or done == total:
				last[0] = Time.get_ticks_msec()
				say.call("%s: bundle part %d/%d" % [world, done, total])
		var bundle := WorldBundle.build(built, store, int(options["max_source"]), on_part,
				ContentBundle.DEFAULT_MAX_ENTRIES, dir.path_join("bundle"))
		if bundle.ok:
			PublishedPackage.write_atomic(dir.path_join("bundle.json"), JSON.stringify(bundle.index))
			artifacts["bundle.json"] = PublishedPackage.file_size(dir.path_join("bundle.json"))
			for name: String in bundle.files:
				artifacts["bundle/" + name] = int(bundle.files[name]["size"])
			out.bundle_parts = bundle.files.size()
			say.call("%s: bundle %d parts, %.0f MB zipped, %s" % [world, out.bundle_parts, bundle.zip_bytes / 1048576.0,
					"built" if bundle.built else "reused"])
		else:
			say.call("WARN %s: bundle: %s (files are served one by one)" % [world, bundle.error])
	# 3. one zip per zone
	if not built.zones.is_empty():
		var err := _pack_zones(built, dir, bool(options["zone_packs"]), say)
		if err != "":
			out.error = err
			return out
		for id: String in built.zones:
			var zdir := dir.path_join("zones").path_join(id)
			PublishedPackage.write_atomic(zdir.path_join("manifest.json"), JSON.stringify(built.zones[id]))
			artifacts["zones/%s/manifest.json" % id] = PublishedPackage.file_size(zdir.path_join("manifest.json"))
			if built.zone_packs.has(id):
				artifacts["zones/%s/pack.zip" % id] = int(built.zone_packs[id]["size"])
		out.zone_packs = built.zone_packs.size()
		PublishedPackage.write_atomic(dir.path_join("zones.json"), JSON.stringify(built.zone_index))
		artifacts["zones.json"] = PublishedPackage.file_size(dir.path_join("zones.json"))
	# 4. manifest, blobs, the stamp, then the pointer
	PublishedPackage.write_atomic(dir.path_join("manifest.json"), JSON.stringify(built.manifest))
	artifacts["manifest.json"] = PublishedPackage.file_size(dir.path_join("manifest.json"))
	PublishedPackage.write_atomic(dir.path_join(PublishedPackage.BLOBS), JSON.stringify(blobs))
	artifacts[PublishedPackage.BLOBS] = PublishedPackage.file_size(dir.path_join(PublishedPackage.BLOBS))
	var stamp_out := {"format": PublishedPackage.FORMAT, "world": world, "release": out.release, "version": out.version,
			"zones_version": zver, "options": options, "files": built.manifest["files"].size(), "zones": out.zones,
			"published_at": int(Time.get_unix_time_from_system()), "artifacts": artifacts}
	if not PublishedPackage.write_atomic(dir.path_join(PublishedPackage.RELEASE), JSON.stringify(stamp_out)):
		out.error = "cannot write the release stamp in " + dir
		return out
	_point(store, world, out, stamp_out)
	if out.error != "":
		return out
	_prune(store, world, out.release, int(opts.get("keep", KEEP_VERSIONS)))
	out.seconds = (Time.get_ticks_msec() - t0) / 1000.0
	say.call("%s: published version %s (release %s) in %.1f s" % [world, out.version.substr(0, 12), out.release, out.seconds])
	return out


static func _complete(dir: String, stamp: Dictionary) -> bool:
	if not stamp.get("artifacts") is Dictionary:
		return false
	for name: String in stamp["artifacts"]:
		if PublishedPackage.file_size(dir.path_join(name)) != int(stamp["artifacts"][name]):
			return false
	return true


static func _point(store: String, world: String, out: Result, stamp: Dictionary) -> void:
	var cur := PublishedPackage.current(store, world)
	if str(cur.get("release", "")) == out.release:
		out.ok = true
		return
	out.ok = PublishedPackage.write_atomic(PublishedPackage.world_dir(store, world).path_join(PublishedPackage.CURRENT),
			JSON.stringify({"format": PublishedPackage.FORMAT, "world": world, "release": out.release, "version": out.version,
			"published_at": int(stamp.get("published_at", 0))}))
	if not out.ok:
		out.error = "cannot write the pointer of " + world


## Zone packs: a zip of the distinct contents of each zone, `pack` {size, hash} added to its manifest. The
## progress file lets a cut build keep the packs written (same zone version, same size on disk).
static func _pack_zones(built: WorldPackage.Built, dir: String, with_packs: bool, say: Callable) -> String:
	if not with_packs:
		return ""
	var progress_path := dir.path_join("zones").path_join("progress.json")
	var done := PublishedPackage.read_json(progress_path)
	var ids: Array = built.zones.keys()
	ids.sort()
	var last_save := Time.get_ticks_msec()
	var last_say := last_save
	var n := 0
	for id: String in ids:
		n += 1
		var m: Dictionary = built.zones[id]
		var hashes := ContentManifest.unique_blobs(m["files"]).keys()
		if hashes.is_empty() or hashes.size() > PACK_MAX_ENTRIES:
			continue # nothing to pack, or a zone too fat for one archive: files one by one
		var path := dir.path_join("zones").path_join(id).path_join("pack.zip")
		var kept: Variant = done.get(id)
		if not (kept is Dictionary and str(kept.get("version", "")) == str(m["version"])
				and PublishedPackage.file_size(path) == int(kept.get("size", -1))):
			var err := WorldBundle.pack(built, hashes, path)
			if err != "":
				return "zone %s: %s" % [id, err]
			kept = {"version": str(m["version"]), "size": PublishedPackage.file_size(path), "hash": FileHash.sha256(path)}
			done[id] = kept
		m["pack"] = {"size": int(kept["size"]), "hash": str(kept["hash"])}
		built.zone_packs[id] = {"path": path, "size": int(kept["size"]), "mtime": FileAccess.get_modified_time(path), "hash": str(kept["hash"])}
		var now := Time.get_ticks_msec()
		if now - last_save >= 3000:
			last_save = now
			PublishedPackage.write_atomic(progress_path, JSON.stringify(done))
		if now - last_say >= 1500:
			last_say = now
			say.call("%s: zone packs %d/%d" % [built.world, n, ids.size()])
	PublishedPackage.write_atomic(progress_path, JSON.stringify(done))
	return ""


## files/<hash> beside the versions (shared by all of them): blobs entries become "@files/<hash>". A file
## already there with the right size is kept (a cut copy is resumed), a source changed since the build is refused.
static func _copy_files(built: WorldPackage.Built, blobs: Dictionary, store: String, world: String, say: Callable) -> String:
	var base := PublishedPackage.world_dir(store, world).path_join("files")
	DirAccess.make_dir_recursive_absolute(base)
	var n := 0
	var last_say := Time.get_ticks_msec()
	for h: String in built.blobs:
		var b: Dictionary = built.blobs[h]
		var dest := base.path_join(h)
		if PublishedPackage.file_size(dest) != int(b["size"]):
			if PublishedPackage.file_size(str(b["path"])) != int(b["size"]) or FileAccess.get_modified_time(str(b["path"])) != int(b["mtime"]):
				return "file changed since the package was built: rebuild it (%s)" % str(b["path"])
			var tmp := dest + ".tmp"
			if DirAccess.copy_absolute(str(b["path"]), tmp) != OK or DirAccess.rename_absolute(tmp, dest) != OK:
				return "cannot copy " + str(b["path"])
		blobs[h] = ["@files/" + h, int(b["size"]), FileAccess.get_modified_time(dest)]
		n += 1
		if Time.get_ticks_msec() - last_say >= 1500:
			last_say = Time.get_ticks_msec()
			say.call("%s: files copied %d/%d" % [world, n, built.blobs.size()])
	return ""


## Keeps the `keep` newest complete versions (and the current one), removes the rest and the unfinished
## ones (no stamp). A server started on an older version keeps working until the version it reads is pruned.
static func _prune(store: String, world: String, release: String, keep: int) -> void:
	var base := PublishedPackage.world_dir(store, world).path_join("versions")
	var cur := str(PublishedPackage.current(store, world).get("release", release))
	var dated: Array = []
	for d in DirAccess.get_directories_at(base):
		var st := PublishedPackage.read_json(base.path_join(d).path_join(PublishedPackage.RELEASE))
		if st.is_empty():
			if d != release and d != cur:
				_remove_tree(base.path_join(d))
		else:
			dated.append([int(st.get("published_at", 0)), d])
	dated.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for i in dated.size():
		if i >= maxi(1, keep) and dated[i][1] != release and dated[i][1] != cur:
			_remove_tree(base.path_join(str(dated[i][1])))


static func _remove_tree(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_remove_tree(dir.path_join(d))
	DirAccess.remove_absolute(dir)
