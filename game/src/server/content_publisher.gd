## The publication of a world's content (roadmap C.07): the build step of a release, run ONCE outside the
## game server (`--build-packages`, tools/publish_content.py, `serveur-lancer.bat publier`), never when it
## starts. It lists and hashes the files (WorldPackage, with its cache), writes the contents no bundle holds
## yet (BundleWriter), one manifest per fragment (the base, each zone), the release index, and moves the
## world's pointer in worlds.json last (ContentStore). Layout: ContentRelease.
##
## Incremental: a content any earlier release of any world wrote is never written again, so republishing
## after a change writes the changed files only, and a client downloads only those bytes.
## Resumable: the hash index and the bundle index are checkpointed; a cut loses the bundle being written.
## Atomic: everything below the pointer is immutable and named by its hash; the pointer moves last.
## Old releases are pruned (`keep` per world) and what no kept release references is removed (`gc`).
class_name ContentPublisher
extends RefCounted

const KEEP_VERSIONS := 3
## contents read at the same time on the worker pool (on Windows an open costs an antivirus scan: in parallel)
const READ_BATCH := 64
const READ_BATCH_BYTES := 64 * 1024 * 1024
## the bundle index is saved at most this often while bundling
const CHECKPOINT_MS := 20000


class Result:
	var ok := false
	var error := ""
	var world := ""
	var release := ""
	## this exact release was already the published one
	var unchanged := false
	var hashed := 0
	var reused := 0
	var zones := 0
	var bundles_written := 0
	var bytes_written := 0
	var seconds := 0.0
	var built: WorldPackage.Built


## `opts`: rebuild (ignore the hash cache), keep, bundle_mb, log (Callable(line)), should_stop (Callable() -> bool),
## abort_after (tests: stop after that many files hashed), checkpoint_ms, read_batch (contents read at once).
static func publish(world: String, root: String, store: String, opts := {}) -> Result:
	var t0 := Time.get_ticks_msec()
	var say := _say(opts)
	say.call("%s: listing and hashing the files (the hash cache makes a second run fast)" % world)
	var built := WorldPackage.build(world, root, store, bool(opts.get("rebuild", false)), {
			"checkpoint_ms": int(opts.get("checkpoint_ms", 5000)), "abort_after": int(opts.get("abort_after", 0)),
			"should_stop": opts.get("should_stop", Callable()),
			"on_progress": func(done: int, reused: int) -> void: say.call("%s: %d files seen (%d from the cache)" % [world, done, reused])})
	if not built.ok:
		var out := Result.new()
		out.world = world
		out.error = built.error
		out.built = built
		return out
	var r := publish_built(built, store, opts)
	r.seconds = (Time.get_ticks_msec() - t0) / 1000.0
	say.call("%s: release %s %s in %.1f s (%d bundles, %.1f MB written)" % [world, r.release,
			"unchanged" if r.unchanged else "published", r.seconds, r.bundles_written, r.bytes_written / 1048576.0])
	return r


## Publishes what WorldPackage.build listed and hashed (the tests build once and publish).
static func publish_built(built: WorldPackage.Built, store: String, opts := {}) -> Result:
	var out := Result.new()
	out.world = built.world
	out.built = built
	out.hashed = built.hashed
	out.reused = built.reused
	out.zones = built.zones.size()
	var say := _say(opts)
	_cleanup_legacy(store, built.world)
	# 1. the fragments: the base, then the zones in the order of their ids
	var frags: Array = [[ContentRelease.BASE, built.manifest["files"]]]
	var ids: Array = built.zones.keys()
	ids.sort()
	for id: String in ids:
		frags.append([id, built.zones[id]["files"]])
	# 2. the contents no bundle holds yet, in the order of the fragments (a zone's files end up side by side)
	var writer := BundleWriter.new(store, int(float(opts.get("bundle_mb", 32)) * 1048576.0))
	writer.load_index()
	var todo: Array = []
	var queued := {}
	var todo_bytes := 0
	for fr: Array in frags:
		for f: Dictionary in fr[1]:
			var h := str(f["hash"])
			if writer.has(h) or queued.has(h):
				continue
			queued[h] = true
			todo.append(h)
			todo_bytes += int(f["size"])
	var free := DiskSpace.free_bytes(store)
	if free >= 0 and todo_bytes > free:
		out.error = "espace disque insuffisant dans %s : %.1f Go a ecrire, %.1f Go libres" % [store, todo_bytes / 1073741824.0, free / 1073741824.0]
		return out
	if not todo.is_empty():
		say.call("%s: %d contents to bundle (%.1f MB)" % [built.world, todo.size(), todo_bytes / 1048576.0])
		var err := _bundle(built, writer, todo, opts, say)
		if err != "":
			writer.discard()
			writer.save_index()
			out.error = err
			return out
	writer.save_index()
	out.bundles_written = writer.bundles_written
	out.bytes_written = writer.bytes_written
	# 3. one manifest per fragment, named by its hash
	var rel := {"format": ContentRelease.FORMAT, "world": built.world, "name": str(built.manifest["name"]),
			"module": str(built.manifest["module"]), "start_zone": str(built.zone_index.get("start_zone", "")), "zones": {}}
	var zones_size := 0
	for fr: Array in frags:
		var files: Array = fr[1]
		var bytes := ContentRelease.encode_fragment(built.world, str(fr[0]), files, writer.locate)
		var h := ContentManifest.hash_bytes(bytes)
		var path := store.path_join(ContentRelease.manifest_path(h))
		if ContentStore.file_size(path) != bytes.size() and not ContentStore.write_bytes_atomic(path, bytes):
			out.error = "cannot write " + path
			return out
		var size := 0
		for f: Dictionary in files:
			size += int(f["size"])
		var entry := {"manifest": h, "files": files.size(), "size": size}
		if fr[0] == ContentRelease.BASE:
			rel["base"] = entry
			continue
		var z: Dictionary = built.zone_index["zones"][fr[0]]
		entry["maps"] = z.get("maps", [])
		for key in ["requires", "skins"]:
			if (z.get(key, []) as Array).size() > 0:
				entry[key] = z[key]
		rel["zones"][fr[0]] = entry
		zones_size += size
	# 4. the release index, then the pointer (last)
	var text := JSON.stringify(rel, "", true)
	out.release = ContentRelease.release_id(text.to_utf8_buffer())
	var rel_path := store.path_join(ContentRelease.release_path(built.world, out.release))
	if ContentStore.file_size(rel_path) != text.to_utf8_buffer().size() and not ContentStore.write_atomic(rel_path, text):
		out.error = "cannot write " + rel_path
		return out
	out.unchanged = str(ContentStore.pointer(store, built.world).get("release", "")) == out.release
	_remember(store, built.world, out.release)
	if not out.unchanged and not ContentStore.set_pointer(store, built.world, {"release": out.release, "name": rel["name"],
			"module": rel["module"], "size": int(rel["base"]["size"]), "files": int(rel["base"]["files"]),
			"zones": (rel["zones"] as Dictionary).size(), "zones_size": zones_size}):
		out.error = "cannot write the pointer of " + built.world
		return out
	gc(store, int(opts.get("keep", KEEP_VERSIONS)), say)
	out.ok = true
	return out


## Reads the contents of `todo` (hashes) BATCH at a time on the worker pool, checks each against its hash and
## appends it to the bundles. "" or the error.
static func _bundle(built: WorldPackage.Built, writer: BundleWriter, todo: Array, opts: Dictionary, say: Callable) -> String:
	var stop: Variant = opts.get("should_stop")
	var every := int(opts.get("checkpoint_ms", CHECKPOINT_MS))
	var last_save := Time.get_ticks_msec()
	var last_say := last_save
	var pos := 0
	while pos < todo.size():
		if stop is Callable and (stop as Callable).is_valid() and bool((stop as Callable).call()):
			return "interrupted"
		var batch: Array = []
		var bytes := 0
		while pos < todo.size() and batch.size() < int(opts.get("read_batch", READ_BATCH)) and (batch.is_empty() or bytes < READ_BATCH_BYTES):
			var h: String = todo[pos]
			batch.append(h)
			bytes += int(built.blobs[h]["size"])
			pos += 1
		var read: Array = []
		read.resize(batch.size())
		var group := WorkerThreadPool.add_group_task(func(k: int) -> void:
			var b: Dictionary = built.blobs[batch[k]]
			var data := FileAccess.get_file_as_bytes(str(b["path"]))
			read[k] = data if data.size() == int(b["size"]) and ContentManifest.hash_bytes(data) == batch[k] else null,
			batch.size(), -1, true, "read the contents to bundle")
		WorkerThreadPool.wait_for_group_task_completion(group)
		for k in batch.size():
			if read[k] == null:
				return "%s a change depuis son hachage : republier" % built.blobs[batch[k]]["path"]
			var err := writer.add(batch[k], read[k])
			if err != "":
				return err
		var now := Time.get_ticks_msec()
		if every > 0 and now - last_save >= every:
			last_save = now
			writer.save_index() # the closed bundles survive a cut
		if now - last_say >= 1500:
			last_say = now
			say.call("%s: bundling %d/%d contents, %.0f MB written" % [built.world, pos, todo.size(), writer.bytes_written / 1048576.0])
	return writer.close()


## Keeps the `keep` newest releases of every world (and its current one), removes the others, then every
## manifest and bundle no kept release references, and the bundle index entries of the removed bundles.
static func gc(store: String, keep := KEEP_VERSIONS, say := Callable()) -> void:
	var manifests := {}
	var pointers := ContentStore.pointers(store)
	for world: String in DirAccess.get_directories_at(store):
		var dir := store.path_join(world).path_join("releases")
		if not DirAccess.dir_exists_absolute(dir):
			continue
		var history: Array = ContentStore.read_json(store.path_join(world).path_join(ContentStore.HISTORY)).get("releases", [])
		var kept := {}
		for i in range(history.size() - 1, maxi(-1, history.size() - 1 - maxi(1, keep)), -1):
			kept[str(history[i])] = true
		kept[str(pointers.get(world, {}).get("release", ""))] = true
		for f in DirAccess.get_files_at(dir):
			var id := f.get_basename()
			if not kept.has(id):
				DirAccess.remove_absolute(dir.path_join(f))
				continue
			var rel := ContentStore.read_json(dir.path_join(f))
			manifests[str(rel.get("base", {}).get("manifest", ""))] = true
			for z: Dictionary in rel.get("zones", {}).values():
				manifests[str(z.get("manifest", ""))] = true
		ContentStore.write_atomic(store.path_join(world).path_join(ContentStore.HISTORY),
				JSON.stringify({"releases": history.filter(func(r: Variant) -> bool: return kept.has(str(r)))}))
	var bundles := {}
	for h: String in manifests:
		var path := store.path_join(ContentRelease.manifest_path(h))
		var m := ContentRelease.decode_fragment(FileAccess.get_file_as_bytes(path), h)
		for b: Variant in m["manifest"].get("bundles", []):
			bundles[str(b)] = true
	_sweep(store.path_join("manifests"), manifests, ".json.gz")
	var gone := _sweep(store.path_join("bundles"), bundles, ".bundle")
	if not gone.is_empty():
		var writer := BundleWriter.new(store)
		writer.load_index()
		for h: String in writer.index.keys():
			if gone.has(str(writer.index[h][0])):
				writer.index.erase(h)
		writer.save_index()
		if say.is_valid():
			say.call("gc: %d bundle(s) no release uses any more removed" % gone.size())


## Removes the files of `dir/<hh>/` whose name (minus `suffix`) is not in `keep`, and the leftovers of a cut
## publication; returns {name: true} of what it removed.
static func _sweep(dir: String, keep: Dictionary, suffix: String) -> Dictionary:
	var out := {}
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".tmp"):
			DirAccess.remove_absolute(dir.path_join(f))
	for sub in DirAccess.get_directories_at(dir):
		for f in DirAccess.get_files_at(dir.path_join(sub)):
			var name := f.trim_suffix(suffix)
			if f.ends_with(".tmp") or not keep.has(name):
				DirAccess.remove_absolute(dir.path_join(sub).path_join(f))
				out[name] = true
	return out


static func _remember(store: String, world: String, release: String) -> void:
	var path := store.path_join(world).path_join(ContentStore.HISTORY)
	var history: Array = ContentStore.read_json(path).get("releases", [])
	if history.is_empty() or str(history[history.size() - 1]) != release:
		history.erase(release)
		history.append(release)
		ContentStore.write_atomic(path, JSON.stringify({"releases": history}))


## What the publications before C.07 left (versions, zips, copies of the files): gigabytes nothing reads any more.
static func _cleanup_legacy(store: String, world: String) -> void:
	var dir := store.path_join(world)
	for sub in ["versions", "bundle", "files"]:
		if DirAccess.dir_exists_absolute(dir.path_join(sub)):
			ContentStore.remove_tree(dir.path_join(sub))
	for f in ["current.json", "manifest.json"]:
		DirAccess.remove_absolute(dir.path_join(f))


static func _say(opts: Dictionary) -> Callable:
	var log: Callable = opts.get("log", Callable())
	return func(line: String) -> void:
		if log.is_valid():
			log.call(line)
