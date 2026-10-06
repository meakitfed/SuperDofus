## The manifest of a world package (roadmap C.02, docs/PLAN_SERVEUR.md): the list of the files
## a client needs to play a world, each with its SHA-256 and size, and a version.
##
##   {format: 1, world, name, module, version, files: [{path, hash, size}]}
##
## `path` is a logical path (ContentSource: content/..., data/..., worlds/<id>/...).
## `version` = SHA-256 of the sorted "path:hash" lines: same files = same version, one changed
## byte = another version. Pure: no file, no network (the server builds, the client downloads).
## Nothing here knows which game a world runs: `module` is only carried along.
class_name ContentManifest
extends RefCounted

const FORMAT := 1
const HASH_RE := "^[0-9a-f]{64}$"

static var _hash_re := RegEx.create_from_string(HASH_RE)


static func hash_bytes(data: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	if not data.is_empty(): # update() refuses an empty buffer (a zone with no extra file)
		ctx.update(data)
	return ctx.finish().hex_encode()


static func is_hash(text: String) -> bool:
	return _hash_re.search(text) != null


## `files`: Array of {path, hash, size}, any order. The manifest keeps them sorted by path.
static func make(world: String, world_name: String, module: String, files: Array) -> Dictionary:
	var sorted := files.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["path"]) < str(b["path"]))
	var out: Array = []
	for f: Dictionary in sorted:
		out.append({"path": str(f["path"]), "hash": str(f["hash"]), "size": int(f["size"])})
	return {"format": FORMAT, "world": world, "name": world_name, "module": module,
			"version": version_of(out), "files": out}


static func version_of(files: Array) -> String:
	var lines := PackedStringArray()
	for f: Dictionary in files:
		lines.append("%s:%s" % [f["path"], f["hash"]])
	lines.sort()
	return hash_bytes("\n".join(lines).to_utf8_buffer())


## "" when the manifest is well formed (and `version` is the real one), else why not. A manifest
## comes from the network: every path must stay inside the cache (no "..", no absolute path).
static func validate(m: Variant) -> String:
	if not m is Dictionary:
		return "manifest is not an object"
	if int(m.get("format", 0)) != FORMAT:
		return "unsupported manifest format %s" % str(m.get("format", "none"))
	for key in ["world", "module", "version"]:
		if not m.get(key) is String:
			return "missing %s" % key
	if not m.get("files") is Array:
		return "missing files"
	var seen := {}
	for f in m["files"]:
		if not f is Dictionary:
			return "bad file entry"
		var path := str(f.get("path", ""))
		if not safe_path(path):
			return "unsafe path: " + path
		if seen.has(path):
			return "duplicate path: " + path
		seen[path] = true
		if not is_hash(str(f.get("hash", ""))):
			return "bad hash for " + path
		if not (f.get("size") is int or f.get("size") is float) or int(f["size"]) < 0:
			return "bad size for " + path
	if version_of(m["files"]) != str(m["version"]):
		return "version does not match the files"
	return ""


## A relative logical path made of plain segments.
static func safe_path(path: String) -> bool:
	if path == "" or path.begins_with("/") or path.contains("\\") or path.contains(":") or path.contains("//"):
		return false
	for part in path.split("/"):
		if part == "" or part == "." or part == ".." or part.ends_with("."):
			return false
	return true


## The entries a client has to download. `have` = {path: {hash, size}} of what its cache holds
## (verified when it was written); an entry is missing when the path is absent or its hash or
## size differs. Order follows the manifest.
static func diff(manifest: Dictionary, have: Dictionary) -> Array:
	var missing: Array = []
	for f: Dictionary in manifest["files"]:
		var h: Variant = have.get(f["path"])
		if not h is Dictionary or str(h.get("hash", "")) != str(f["hash"]) or int(h.get("size", -1)) != int(f["size"]):
			missing.append(f)
	return missing


## Paths the cache holds that the new manifest no longer lists.
static func stale(manifest: Dictionary, have: Dictionary) -> PackedStringArray:
	var wanted := {}
	for f: Dictionary in manifest["files"]:
		wanted[f["path"]] = true
	var out := PackedStringArray()
	for path: String in have:
		if not wanted.has(path):
			out.append(path)
	return out


## {hash: size} of the distinct contents of a manifest (two paths with one content = one download).
static func unique_blobs(files: Array) -> Dictionary:
	var out := {}
	for f: Dictionary in files:
		out[str(f["hash"])] = int(f["size"])
	return out


## {path: {hash, size}} of a manifest, the shape `diff` expects as `have`.
static func as_state(manifest: Dictionary) -> Dictionary:
	var out := {}
	for f: Dictionary in manifest.get("files", []):
		out[str(f["path"])] = {"hash": str(f["hash"]), "size": int(f["size"])}
	return out


## Glob test for `world.json` `content` entries: "*" and "?" (a "*" crosses "/").
static func glob_matches(pattern: String, path: String) -> bool:
	return path.match(pattern)


## The folder to walk for a glob: the part before the first wildcard, cut at the last "/".
static func glob_base(pattern: String) -> String:
	var cut := pattern.length()
	for ch in ["*", "?", "["]:
		var i := pattern.find(ch)
		if i != -1:
			cut = mini(cut, i)
	var head := pattern.substr(0, cut)
	return head.substr(0, head.rfind("/")) if head.contains("/") else ""
