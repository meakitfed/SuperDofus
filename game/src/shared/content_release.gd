## The published form of a world's content (roadmap C.07), the way game launchers ship content (Riot's
## RMAN, Ankama's Cytrus, Steam depots): content-addressed BUNDLES (immutable files of concatenated
## contents), MANIFESTS that say where each file lives in them, and a tiny POINTER per world. A client
## fetches the pointer, compares it with what it installed, and downloads byte ranges of the bundles.
##
##   worlds.json                        {format, worlds: {id: {release, name, module, size, files, zones, zones_size}}}
##   <world>/releases/<release>.json    the release index (below); <release> = 16 hex of the SHA-256 of its bytes
##   manifests/<hh>/<hash>.json.gz      a fragment manifest, named by the SHA-256 of its (gzip) bytes
##   bundles/<hh>/<hash>.bundle         raw contents one after the other, named by the SHA-256 of its bytes
##
## Release index: {format, world, name, module, start_zone,
##                 base: {manifest, files, size}, zones: {id: {manifest, files, size, maps, requires?, skins?}}}
## The base is what every client needs, each zone what its maps add (C.02c); a world that is not zoned has
## no zones. Fragment manifest: {format, world, frag, bundles: [hash], files: [[path, hash, size, bundle, offset]]}
## (`bundle` = index in `bundles`). Everything below the pointer is immutable: a name is the hash of the bytes,
## so a client checks what it got against the name it asked for, and anything may be cached forever.
## Pure: no file, no network. Nothing here knows which game a world runs.
class_name ContentRelease
extends RefCounted

const FORMAT := 2
## the fragment id of the base in a client's install state ("" is not a zone id)
const BASE := "@base"
## a request asks for at most this many bytes of a bundle (spread over the connections)
const RANGE_MAX := 8 * 1024 * 1024
## two files of a bundle this close are fetched in one request (the bytes between them are read and dropped)
const RANGE_GAP := 256 * 1024
## FileAccess.COMPRESSION_GZIP (the value: shared/ never names FileAccess, tests/test_architecture.gd)
const GZIP := 3

static var _hex16 := RegEx.create_from_string("^[0-9a-f]{16}$")


static func is_release_id(text: String) -> bool:
	return _hex16.search(text) != null


static func release_id(bytes: PackedByteArray) -> String:
	return ContentManifest.hash_bytes(bytes).substr(0, 16)


static func bundle_path(hash: String) -> String:
	return "bundles/%s/%s.bundle" % [hash.substr(0, 2), hash]


static func manifest_path(hash: String) -> String:
	return "manifests/%s/%s.json.gz" % [hash.substr(0, 2), hash]


static func release_path(world: String, release: String) -> String:
	return "%s/releases/%s.json" % [world, release]


## The bytes of a fragment manifest: `files` [{path, hash, size}] (sorted by path here), `locate(hash)` -> [bundle hash, offset].
static func encode_fragment(world: String, frag: String, files: Array, locate: Callable) -> PackedByteArray:
	var sorted := files.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["path"]) < str(b["path"]))
	var bundles: Array = []
	var bundle_index := {}
	var rows: Array = []
	for f: Dictionary in sorted:
		var at: Array = locate.call(str(f["hash"]))
		var b := str(at[0])
		if not bundle_index.has(b):
			bundle_index[b] = bundles.size()
			bundles.append(b)
		rows.append([str(f["path"]), str(f["hash"]), int(f["size"]), int(bundle_index[b]), int(at[1])])
	var doc := {"format": FORMAT, "world": world, "frag": frag, "bundles": bundles, "files": rows}
	return JSON.stringify(doc).to_utf8_buffer().compress(GZIP)


## {ok, error, manifest}: the gzip bytes of a fragment manifest, checked against the name it was asked by.
static func decode_fragment(gz: PackedByteArray, expected_hash: String) -> Dictionary:
	if ContentManifest.hash_bytes(gz) != expected_hash:
		return {"ok": false, "error": "manifest damaged (hash mismatch)", "manifest": {}}
	var raw := gz.decompress_dynamic(-1, GZIP)
	var data: Variant = JSON.parse_string(raw.get_string_from_utf8())
	var bad := validate_fragment(data)
	if bad != "":
		return {"ok": false, "error": "bad manifest: " + bad, "manifest": {}}
	return {"ok": true, "error": "", "manifest": data}


## "" when a fragment manifest is well formed (it comes from the network: every path stays inside the cache).
static func validate_fragment(m: Variant) -> String:
	if not m is Dictionary or int(m.get("format", 0)) != FORMAT:
		return "unsupported manifest"
	if not m.get("world") is String or not m.get("bundles") is Array or not m.get("files") is Array:
		return "missing fields"
	for b: Variant in m["bundles"]:
		if not b is String or not ContentManifest.is_hash(b):
			return "bad bundle"
	var nb: int = (m["bundles"] as Array).size()
	for row: Variant in m["files"]:
		if not row is Array or (row as Array).size() != 5:
			return "bad file entry"
		var path := str(row[0])
		if not ContentManifest.safe_path(path):
			return "unsafe path: " + path
		if not ContentManifest.is_hash(str(row[1])):
			return "bad hash for " + path
		if int(row[2]) < 0 or int(row[3]) < 0 or int(row[3]) >= nb or int(row[4]) < 0:
			return "bad location for " + path
	return ""


## "" when a release index is well formed and belongs to `world`.
static func validate_release(r: Variant, world: String) -> String:
	if not r is Dictionary or int(r.get("format", 0)) != FORMAT:
		return "unsupported release"
	if str(r.get("world", "")) != world:
		return "release of another world"
	if not r.get("base") is Dictionary or not ContentManifest.is_hash(str(r["base"].get("manifest", ""))):
		return "missing base"
	if not r.get("zones") is Dictionary:
		return "missing zones"
	var seen := {}
	for id: Variant in r["zones"]:
		if not id is String or not ContentZones.is_zone_id(id):
			return "bad zone id"
		var z: Variant = r["zones"][id]
		if not z is Dictionary or not ContentManifest.is_hash(str(z.get("manifest", ""))) or not z.get("maps") is Array:
			return "bad zone " + id
		for m: Variant in z["maps"]:
			if not (m is int or m is float):
				return "bad map in zone " + id
			if seen.has(int(m)):
				return "map %d in two zones" % int(m)
			seen[int(m)] = true
		for q: Variant in z.get("requires", []):
			if not q is String or not r["zones"].has(q):
				return "bad requirement in zone " + id
	return ""


## {map id: zone id} of a release index.
static func zone_lookup(r: Dictionary) -> Dictionary:
	var out := {}
	for id: String in r.get("zones", {}):
		for m: Variant in r["zones"][id]["maps"]:
			out[int(m)] = id
	return out


## The manifest hash of a fragment of a release (BASE or a zone id), "" when the release has no such fragment.
static func fragment_hash(r: Dictionary, frag: String) -> String:
	if frag == BASE:
		return str(r.get("base", {}).get("manifest", ""))
	return str(r.get("zones", {}).get(frag, {}).get("manifest", ""))


## The requests that fetch `wanted`: [{bundle, offset, size, hash, paths}] (one per distinct content). Each
## request is {bundle, start, end (exclusive), files: [entries sorted by offset]}: files of one bundle close
## to each other share a request, at most `max_bytes` long (a bigger file is a request of its own).
static func plan_ranges(wanted: Array, gap := RANGE_GAP, max_bytes := RANGE_MAX) -> Array:
	var by_bundle := {}
	for e: Dictionary in wanted:
		by_bundle.get_or_add(str(e["bundle"]), []).append(e)
	var names := by_bundle.keys()
	names.sort()
	var out: Array = []
	for b: String in names:
		var list: Array = by_bundle[b]
		list.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
			return int(x["offset"]) < int(y["offset"]) or (int(x["offset"]) == int(y["offset"]) and int(x["size"]) < int(y["size"])))
		var cur := {}
		for e: Dictionary in list:
			var start := int(e["offset"])
			var end := start + int(e["size"])
			# contents never overlap in a bundle (an empty one sits where the next starts: sorted before it)
			if not cur.is_empty() and start >= int(cur["end"]) and start - int(cur["end"]) <= gap and end - int(cur["start"]) <= max_bytes:
				cur["end"] = end
				(cur["files"] as Array).append(e)
				continue
			if not cur.is_empty():
				out.append(cur)
			cur = {"bundle": b, "start": start, "end": end, "files": [e]}
		if not cur.is_empty():
			out.append(cur)
	return out


## Bytes the requests of `ranges` read (the gaps included).
static func ranges_bytes(ranges: Array) -> int:
	var n := 0
	for r: Dictionary in ranges:
		n += int(r["end"]) - int(r["start"])
	return n
