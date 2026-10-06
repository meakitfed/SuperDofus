## Downloads the zones of a big world when the player walks near them (roadmap C.02c), without any
## screen: a window (C.02d) shows `progress` and asks `ensure` / `prefetch` on each map change.
##
##   var zs := ZoneStreamer.new(content_client, "dofus", cache_dir)
##   zs.load_index()                      # {ok, zoned}: one request, the map -> zone table
##   zs.ensure(map_id)                    # the zone of the map being entered (blocking: loading indicator)
##   zs.prefetch(neighbor_map_ids)        # the zones of the maps one step away, before the player gets there
##
## The base package (WorldLoader) is complete before any of this; a zone only adds the files its maps
## need. Every zone is installed once per session (a changed version is fetched again at the next
## session: `ensure` asks the server for the zone manifest only the first time).
## Nothing here knows what a zone is made of.
class_name ZoneStreamer
extends RefCounted

## C.02g: the zone holding the skins of the items
const EQUIPMENT := "equipment"

var client: ContentClient
var world := ""
var cache_dir := ""
## the zones index of the server (ContentZones), {} until load_index
var index := {}
## zone -> bytes downloaded this session (an installed zone is not asked again)
var installed := {}
## Callable(zone: String, phase: String), phase "start" / "done" / "error": drives the loading indicator
var on_zone := Callable()
var _zone_of := {}
var _worn := {} # C.02g: skin id -> true, the skins of the equipment zone


func _init(p_client: ContentClient, p_world: String, p_cache_dir: String) -> void:
	client = p_client
	world = p_world
	cache_dir = p_cache_dir


## {ok, zoned, error}: `zoned` false for a world the server did not split (everything is in the base).
func load_index() -> Dictionary:
	var r := client.fetch_zones(world)
	if r.ok:
		index = r.index
		_zone_of = ContentZones.lookup(index)
		_worn.clear()
		for k: Variant in (index.get("zones", {}) as Dictionary).get(EQUIPMENT, {}).get("skins", []):
			_worn[int(k)] = true
		return {"ok": true, "zoned": true, "error": ""}
	if int(r.status) == 404:
		index = {}
		_zone_of = {}
		_worn.clear()
		return {"ok": true, "zoned": false, "error": ""}
	return {"ok": false, "zoned": false, "error": r.error}


func zoned() -> bool:
	return not index.is_empty()


## The zone holding a map ("" = not zoned, or a map the world does not know).
func zone_of(map_id: int) -> String:
	return str(_zone_of.get(map_id, ""))


## C.02e: the zone holding the skeletons and creation skins of a playable class ("" = in the base: the
## world is not zoned, or has no such zone).
func class_zone(breed: int) -> String:
	var id := "class_%d" % breed
	return id if (index.get("zones", {}) as Dictionary).has(id) else ""


func class_ready(breed: int) -> bool:
	var z := class_zone(breed)
	return z == "" or installed.has(z)


## C.02g: the equipment zone ("" = the world has none: the skins are in the base).
func equipment_zone() -> String:
	return EQUIPMENT if (index.get("zones", {}) as Dictionary).has(EQUIPMENT) else ""


func equipment_ready() -> bool:
	var z := equipment_zone()
	return z == "" or installed.has(z)


## True when one of the `looks` (Dofus look strings) wears a skin of the equipment zone that is not installed.
func needs_equipment(looks: Array) -> bool:
	if equipment_ready():
		return false
	for l: Variant in looks:
		if _look_wears(DofusLook.parse(str(l))):
			return true
	return false


func _look_wears(l: DofusLook) -> bool:
	for s: Variant in l.skins:
		if _worn.has(int(s)):
			return true
	for category: Variant in l.sub_entities:
		for sub: Variant in (l.sub_entities[category] as Dictionary).values():
			if _look_wears(sub):
				return true
	return false


## C.02g: the zones a zone needs besides itself (the monsters of its sub-area), not yet installed.
func requires_of(zone: String) -> PackedStringArray:
	var out := PackedStringArray()
	for r: Variant in (index.get("zones", {}) as Dictionary).get(zone, {}).get("requires", []):
		if not installed.has(str(r)):
			out.append(str(r))
	return out


## The zones still to install before a map (-1 = none) and the classes `breeds` can be shown: the zone of
## the map first, then the class zones, without duplicates.
func missing_zones(map_id: int, breeds: Array = []) -> PackedStringArray:
	var out := PackedStringArray()
	var z := zone_of(map_id)
	if z != "":
		for r in requires_of(z): # C.02g: its monsters first
			out.append(r)
		if not installed.has(z):
			out.append(z)
	for b: Variant in breeds:
		var c := class_zone(int(b))
		if c != "" and not installed.has(c) and not out.has(c):
			out.append(c)
	return out


## Download size of a zone in bytes (an upper bound: files already in the cache are not downloaded again).
func size_of(zone: String) -> int:
	return int(index.get("zones", {}).get(zone, {}).get("size", 0))


## True when the zone of `map_id` is installed (or when nothing is zoned).
func is_ready(map_id: int) -> bool:
	var z := zone_of(map_id)
	return z == "" or (installed.has(z) and requires_of(z).is_empty())


## The zones to fetch, in order: the one of `map_id` first, then those of `near` (the maps one exit
## away), without duplicates and without what is already installed.
func zones_to_fetch(map_id: int, near: Array = []) -> PackedStringArray:
	var out := PackedStringArray()
	for m: Variant in [map_id] + near:
		var z := zone_of(int(m))
		if z == "":
			continue
		for r in requires_of(z):
			if not out.has(r):
				out.append(r)
		if not installed.has(z) and not out.has(z):
			out.append(z)
	return out


## Installs the zone of `map_id` now. {ok, zone, bytes, files, already, error}
func ensure(map_id: int) -> Dictionary:
	var z := zone_of(map_id)
	if z == "":
		return {"ok": true, "zone": z, "bytes": 0, "files": 0, "already": true, "error": ""}
	for r in requires_of(z): # C.02g: the monsters of the sub-area first
		var rr := _install(r)
		if not rr.ok:
			return rr
	if installed.has(z):
		return {"ok": true, "zone": z, "bytes": 0, "files": 0, "already": true, "error": ""}
	return _install(z)


## Installs one zone by its id (a worker thread of ZoneGate takes them one by one, C.02d).
func ensure_zone(zone: String) -> Dictionary:
	if zone == "" or installed.has(zone):
		return {"ok": true, "zone": zone, "bytes": 0, "files": 0, "already": true, "error": ""}
	return _install(zone)


## Installs the zones of the neighbouring maps, one by one, and stops at the first error or when the
## client is cancelled. {ok, zones: [installed now], error}
func prefetch(near: Array) -> Dictionary:
	var out := {"ok": true, "zones": [], "error": ""}
	for z in zones_to_fetch(-1, near):
		if client.cancel_requested:
			break
		var r := _install(z)
		if not r.ok:
			out["ok"] = false
			out["error"] = r.error
			break
		out["zones"].append(z)
	return out


func _install(zone: String) -> Dictionary:
	if on_zone.is_valid():
		on_zone.call(zone, "start")
	var r := client.install_zone(world, zone, cache_dir)
	r["zone"] = zone
	if r.ok:
		installed[zone] = int(r["bytes"])
	if on_zone.is_valid():
		on_zone.call(zone, "done" if r.ok else "error")
	return r
