## The worlds of one server (roadmap S.04): which exist, which are open, and starting / stopping
## them while the server runs (admin). Each open world is its own WorldSim (own events, own
## characters, own map instances) behind the one WebSocket port; the host routes a session to the
## world of its `hello`. The saves are per world (Persistence keys characters by world id), the
## content package per world (C.02). Nothing here knows which game a world runs.
##
## APPROX(S.04a): an instance is a world folder (worlds/<id>) opened once: two instances of the
## same content under two ids ("un monde par groupe d'amis") come with S.04b. Characters do not
## move between worlds (G.01).
## Not used by sim/, shared/ or client/.
class_name WorldCluster
extends RefCounted

var host: ServerHost
## id -> WorldPackage.Built or null: builds the package of a world that opens (set by ServerApp,
## unset in tests = no content API entry)
var package_builder := Callable()


## The open worlds, then (with `all`) the ones that could be started: [{id, name, module, players,
## version, running}] sorted by id.
func list(all := false) -> Array:
	var out: Array = []
	var ids := host.server.worlds.keys()
	if all:
		for id in available():
			if not ids.has(id):
				ids.append(id)
	ids.sort()
	for id: String in ids:
		var sim: WorldSim = host.server.worlds.get(id)
		var info := sim.info if sim != null else _info(id)
		var built: WorldPackage.Built = host.content.packages.get(id) if host.content != null else null
		out.append({"id": id, "name": str(info.get("name", id)), "module": str(info.get("module", "")),
				"players": sim.players.size() if sim != null else 0,
				"version": str(built.manifest["version"]) if built != null else "",
				"running": sim != null})
	return out


## Ids of the worlds that exist (a folder worlds/<id> with a world.json, or a source given to the server).
func available() -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in host.server.sources:
		out.append(id)
	var dir := DirAccess.open(ContentSource.dev_path("worlds"))
	if dir != null:
		for d in dir.get_directories():
			if not out.has(d) and FileAccess.file_exists(ContentSource.dev_path("worlds/%s/world.json" % d)):
				out.append(d)
	return out


## Opens a world: {ok, code, detail}. Its package is built when a builder is set.
func start(id: String) -> Dictionary:
	if not ServerHost.is_world_id(id):
		return _fail(Protocol.E_BAD_MESSAGE, "bad world id")
	if host.server.worlds.has(id):
		return _fail(Protocol.E_BAD_MESSAGE, "already running: " + id)
	if host.server.sources.get(id) == null and not available().has(id):
		return _fail(Protocol.E_UNKNOWN_WORLD, "unknown world: " + id)
	var allowed := host.allowed_worlds
	if host.server.world(id) == null:
		return _fail(Protocol.E_UNKNOWN_WORLD, "unknown world: " + id)
	if host.pin_allowed or not allowed.is_empty():
		allowed.append(id)
		host.allowed_worlds = allowed
	if package_builder.is_valid() and host.content != null:
		var built: WorldPackage.Built = package_builder.call(id)
		if built != null:
			host.content.set_package(built)
	return {"ok": true, "code": "", "detail": ""}


## Closes a world: its players are saved and sent back to the world choice
## (error world_closed), the world leaves the lists and the content API. {ok, code, detail, players}.
func stop(id: String) -> Dictionary:
	var sim: WorldSim = host.server.worlds.get(id)
	if sim == null:
		return _fail(Protocol.E_UNKNOWN_WORLD, "not running: " + id)
	# an open-ended host (no list) would restart the world at the next hello: pin the list first
	var allowed := PackedStringArray()
	if host.allowed_worlds.is_empty():
		for other in host.server.worlds:
			if other != id:
				allowed.append(other)
	else:
		for other in host.allowed_worlds:
			if other != id:
				allowed.append(other)
	var kicked := host.close_world_sessions(sim)
	for pid in sim.players.keys(): # a player nobody holds any more
		sim.disconnect_player(int(pid))
	host.server.worlds.erase(id)
	host.allowed_worlds = allowed
	host.pin_allowed = true
	if host.content != null:
		host.content.packages.erase(id)
	return {"ok": true, "code": "", "detail": "", "players": kicked}


func _info(id: String) -> Dictionary:
	var source: WorldSource = host.server.sources.get(id)
	if source == null:
		source = JsonWorldSource.for_world(id)
	return source.get_info()


static func _fail(code: String, detail: String) -> Dictionary:
	return {"ok": false, "code": code, "detail": detail}
