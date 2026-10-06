## The base bundle of a world package (roadmap C.05): the same contents as the manifest, packed
## in a few zip parts so that a first install is a handful of big downloads (and compressed)
## instead of 20 000 requests. Pure: no file, no network.
##
##   index (GET /worlds/<id>/bundle.json): {format: 1, world, version, max_source, max_entries, parts: [{name, size, hash}]}
##
## The partition is DERIVED from the manifest (`plan`): both sides compute the same parts, so the
## index only carries the zip sizes and hashes, and a client knows which part holds which content
## without a list of hashes. A zip entry is named by the SHA-256 of its content (one entry per
## distinct content, however many paths use it): no path in the archive, nothing to escape from.
## Every part has its own hash (a damaged part is refused before it is opened) and every entry is
## checked again against the manifest when it is installed.
## Nothing here knows which game a world runs.
class_name ContentBundle
extends RefCounted

const FORMAT := 1
## source bytes per part (about this much before compression)
const DEFAULT_MAX_SOURCE := 256 * 1024 * 1024
## contents per part: ZIPReader finds an entry by walking the archive, so a part of thousands of
## tiny files would unpack in quadratic time (measured on Incarnam: minutes for 10 000 tiny files)
const DEFAULT_MAX_ENTRIES := 400
## extensions already compressed: stored as they are (the deflate would only cost time)
const STORED_EXTENSIONS: PackedStringArray = ["webp", "png", "jpg", "jpeg", "ogg", "mp3", "zip", "dds"]


static func part_name(i: int) -> String:
	return "part-%03d.zip" % i


static func is_part_name(name: String) -> bool:
	return name.length() == 12 and name.begins_with("part-") and name.ends_with(".zip") \
			and name.substr(5, 3).is_valid_int()


## [{name, hashes: [hash...], source: bytes}]: the distinct contents of `manifest` in manifest
## order (sorted by path: neighbours share a folder, so a small update touches few parts), filled
## greedily up to `max_source` bytes and `max_entries` contents (a content larger than that gets a part of its own).
static func plan(manifest: Dictionary, max_source := DEFAULT_MAX_SOURCE, max_entries := DEFAULT_MAX_ENTRIES) -> Array:
	var parts: Array = []
	var seen := {}
	var cur := {"name": part_name(0), "hashes": [], "source": 0}
	for f: Dictionary in manifest["files"]:
		var h := str(f["hash"])
		if seen.has(h):
			continue
		seen[h] = true
		var size := int(f["size"])
		if cur["source"] > 0 and (int(cur["source"]) + size > max_source or cur["hashes"].size() >= max_entries):
			parts.append(cur)
			cur = {"name": part_name(parts.size()), "hashes": [], "source": 0}
		cur["hashes"].append(h)
		cur["source"] += size
	if not cur["hashes"].is_empty():
		parts.append(cur)
	return parts


static func make_index(manifest: Dictionary, max_source: int, parts: Array, max_entries := DEFAULT_MAX_ENTRIES) -> Dictionary:
	return {"format": FORMAT, "world": str(manifest["world"]), "version": str(manifest["version"]),
			"max_source": max_source, "max_entries": max_entries, "parts": parts}


## "" when `index` is well formed and describes `manifest` exactly (same version, same number of
## parts as the plan, names, sizes and hashes), else why not. It comes from the network.
static func validate(index: Variant, manifest: Dictionary) -> String:
	if not index is Dictionary:
		return "bundle index is not an object"
	if int(index.get("format", 0)) != FORMAT:
		return "unsupported bundle format"
	if str(index.get("version", "")) != str(manifest["version"]) or str(index.get("world", "")) != str(manifest["world"]):
		return "bundle of another version"
	var max_source := int(index.get("max_source", 0))
	var max_entries := int(index.get("max_entries", 0))
	if max_source < 1 or max_entries < 1 or not index.get("parts") is Array:
		return "bad bundle index"
	var planned := plan(manifest, max_source, max_entries)
	var parts: Array = index["parts"]
	if parts.size() != planned.size():
		return "bundle does not match the manifest"
	for i in parts.size():
		var p: Variant = parts[i]
		if not p is Dictionary or str(p.get("name", "")) != planned[i]["name"] \
				or int(p.get("size", -1)) < 0 or not ContentManifest.is_hash(str(p.get("hash", ""))):
			return "bad bundle part %d" % i
	return ""


## The parts holding at least one of the contents in `wanted` ({hash: true}): indices into `plan`.
static func parts_needed(planned: Array, wanted: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for i in planned.size():
		for h: String in planned[i]["hashes"]:
			if wanted.has(h):
				out.append(i)
				break
	return out


static func stored(path: String) -> bool:
	return STORED_EXTENSIONS.has(path.get_extension().to_lower())
