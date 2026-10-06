## The zones of a world package (roadmap C.02c): a big world is not downloaded whole. The base
## manifest (ContentManifest) holds what every client needs; each zone is a group of maps with the
## extra files they need, fetched when the player walks near it.
##
##   zones.json   {format: 1, world, version, start_zone, zones: {id: {version, files, size, maps: [ids]}}}
##   zone manifest  an ordinary manifest (ContentManifest) of the files the zone needs that the base does not
##                  hold, plus `zone: id`. Two zones may list the same file: the client downloads it once.
##
## `version` of the index = SHA-256 of the sorted "id:zone version" lines, so a client sees that one
## zone changed without reading them all. Pure: no file, no network. Nothing here knows what a map
## or a zone is made of: ids are plain strings, maps plain integers.
class_name ContentZones
extends RefCounted

const FORMAT := 1
const ID_RE := "^[A-Za-z0-9_-]{1,64}$"

static var _id_re := RegEx.create_from_string(ID_RE)


static func is_zone_id(id: String) -> bool:
	return _id_re.search(id) != null


## `zones`: {id: manifest (ContentManifest) + "maps": [ids]}. The index only keeps what a client needs
## to choose a zone (version, size, maps), never the file lists.
static func make_index(world: String, start_zone: String, zones: Dictionary) -> Dictionary:
	var out := {}
	for id: String in zones:
		var m: Dictionary = zones[id]
		var size := 0
		for f: Dictionary in m["files"]:
			size += int(f["size"])
		var maps: Array = []
		for x: Variant in m.get("maps", []):
			maps.append(int(x))
		var e := {"version": str(m["version"]), "files": (m["files"] as Array).size(), "size": size, "maps": maps}
		# C.02g: `requires` = zones a block needs besides itself (the monsters of its sub-area),
		# `skins` = the skin ids of an equipment zone (the client asks for it when it sees one)
		if (m.get("requires", []) as Array).size() > 0:
			e["requires"] = (m["requires"] as Array).duplicate()
		if (m.get("skins", []) as Array).size() > 0:
			e["skins"] = (m["skins"] as Array).duplicate()
		out[id] = e
	return {"format": FORMAT, "world": world, "version": version_of(out), "start_zone": start_zone, "zones": out}


static func version_of(zones: Dictionary) -> String:
	var lines := PackedStringArray()
	for id: String in zones:
		lines.append("%s:%s" % [id, zones[id]["version"]])
	lines.sort()
	return ContentManifest.hash_bytes("\n".join(lines).to_utf8_buffer())


## "" when the index is well formed, else why not (it comes from the network).
static func validate(idx: Variant) -> String:
	if not idx is Dictionary:
		return "zones index is not an object"
	if int(idx.get("format", 0)) != FORMAT:
		return "unsupported zones format %s" % str(idx.get("format", "none"))
	for key in ["world", "version", "start_zone"]:
		if not idx.get(key) is String:
			return "missing %s" % key
	if not idx.get("zones") is Dictionary:
		return "missing zones"
	var seen := {}
	for id: Variant in idx["zones"]:
		if not id is String or not is_zone_id(id):
			return "bad zone id"
		var z: Variant = idx["zones"][id]
		if not z is Dictionary or not z.get("version") is String or not z.get("maps") is Array:
			return "bad zone " + id
		for m: Variant in z["maps"]:
			if not (m is int or m is float):
				return "bad map in zone " + id
			if seen.has(int(m)):
				return "map %d in two zones" % int(m)
			seen[int(m)] = true
		for r: Variant in z.get("requires", []):
			if not r is String or not is_zone_id(r) or not idx["zones"].has(r):
				return "bad requirement in zone " + id
		for k: Variant in z.get("skins", []):
			if not (k is int or k is float):
				return "bad skin in zone " + id
	if version_of(idx["zones"]) != str(idx["version"]):
		return "version does not match the zones"
	return ""


## {map id: zone id} of an index.
static func lookup(idx: Dictionary) -> Dictionary:
	var out := {}
	for id: String in idx.get("zones", {}):
		for m: Variant in idx["zones"][id]["maps"]:
			out[int(m)] = id
	return out


## "" when the manifest is the one of `zone`.
static func check_zone_manifest(m: Dictionary, world: String, zone: String) -> String:
	var bad := ContentManifest.validate(m)
	if bad != "":
		return bad
	if str(m["world"]) != world or str(m.get("zone", "")) != zone:
		return "manifest of another zone"
	return ""
