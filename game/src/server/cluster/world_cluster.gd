## The worlds of one server (roadmap S.04): which exist, which are open, and starting / stopping
## them while the server runs (admin). Each open world is its own WorldSim (own events, own
## characters, own map instances) behind the one WebSocket port; the host routes a session to the
## world of its `hello`. The saves are per world (Persistence keys characters by world id), the
## content package per world (C.02). Nothing here knows which game a world runs.
##
## A world is a folder worlds/<id> opened once, or (S.04b) an INSTANCE: a world id of its own that
## reads the content of another ("amis" over "incarnam": `create`). Saves and lists key on the
## instance id, so two instances never share a character; the content package is the content's.
## Instances live in `instances_path` (instances.json of the save folder), reopened by `restore`.
## APPROX(S.04b): removing an instance keeps its saved characters (a later `create` of the same
## id finds them again). Characters do not move between worlds (G.01).
## Not used by sim/, shared/ or client/.
class_name WorldCluster
extends RefCounted

var host: ServerHost
## where the instances are written ("" = not kept: tests, tools)
var instances_path := ""


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
		out.append({"id": id, "content": str(info.get("content", id)), "name": str(info.get("name", id)),
				"module": str(info.get("module", "")),
				"players": sim.players.size() if sim != null else 0,
				"version": host.content.release_of(id) if host.content != null else "", # C.07: the published release
				"running": sim != null})
	return out


## Ids of the worlds that exist (a folder worlds/<id> with a world.json, or a source given to the server).
func available() -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in host.server.sources:
		out.append(id)
	for id: String in host.server.instances:
		if not out.has(id):
			out.append(id)
	var dir := DirAccess.open(ContentSource.dev_path("worlds"))
	if dir != null:
		for d in dir.get_directories():
			if not out.has(d) and FileAccess.file_exists(ContentSource.dev_path("worlds/%s/world.json" % d)):
				out.append(d)
	return out


## Opens a world: {ok, code, detail}.
func start(id: String) -> Dictionary:
	if not ServerHost.is_world_id(id):
		return _fail(Protocol.E_BAD_MESSAGE, "bad world id")
	if host.server.worlds.has(id):
		return _fail(Protocol.E_BAD_MESSAGE, "already running: " + id)
	if host.server.sources.get(id) == null and not host.server.instances.has(id) and not available().has(id):
		return _fail(Protocol.E_UNKNOWN_WORLD, "unknown world: " + id)
	var allowed := host.allowed_worlds
	if host.server.world(id) == null:
		return _fail(Protocol.E_UNKNOWN_WORLD, "unknown world: " + id)
	if host.pin_allowed or not allowed.is_empty():
		allowed.append(id)
		host.allowed_worlds = allowed
	sync_content() # its content is served as published (C.07): nothing to build
	return {"ok": true, "code": "", "detail": ""}


## Closes a world: its players are saved and sent back to the world choice
## (error world_closed), the world leaves the lists and the content API (no longer allowed). {ok, code, detail, players}.
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
	return {"ok": true, "code": "", "detail": "", "players": kicked}


## The content an id reads: its own for a world, the one it was made from for an instance.
func content_of(id: String) -> String:
	var inst: Variant = host.server.instances.get(id)
	return str(inst["content"]) if inst is Dictionary else id


## Makes an instance `id` of the world `content` and opens it. {ok, code, detail}.
func create(id: String, content: String, p_name := "") -> Dictionary:
	if not ServerHost.is_world_id(id) or not ServerHost.is_world_id(content):
		return _fail(Protocol.E_BAD_MESSAGE, "bad world id")
	if host.server.worlds.has(id) or host.server.instances.has(id) or available().has(id):
		return _fail(Protocol.E_BAD_MESSAGE, "already exists: " + id)
	if host.server.instances.has(content) or not available().has(content):
		return _fail(Protocol.E_UNKNOWN_WORLD, "unknown content: " + content)
	host.server.instances[id] = {"content": content, "name": p_name.strip_edges() if p_name.strip_edges() != "" else id}
	var r := start(id)
	if not r["ok"]:
		host.server.instances.erase(id)
		return r
	_save()
	return r


## Deletes an instance (closes it first). Its saved characters stay on disk (APPROX(S.04b)).
## {ok, code, detail, players}.
func remove(id: String) -> Dictionary:
	if not host.server.instances.has(id):
		return _fail(Protocol.E_UNKNOWN_WORLD, "not an instance: " + id)
	var r := {"ok": true, "code": "", "detail": "", "players": 0}
	if host.server.worlds.has(id):
		r = stop(id)
	host.server.instances.erase(id)
	var allowed := PackedStringArray()
	for other in host.allowed_worlds:
		if other != id:
			allowed.append(other)
	host.allowed_worlds = allowed
	sync_content()
	_save()
	return r


## Tells the content API which ids are instances (after any change).
func sync_content() -> void:
	if host.content == null:
		return
	var map := {}
	var names := {}
	for id: String in host.server.instances:
		map[id] = str(host.server.instances[id]["content"])
		names[id] = str(host.server.instances[id].get("name", id))
	host.content.set_instances(map, names)


## Reads instances.json and opens its instances (server start). Returns how many opened.
func restore() -> int:
	if instances_path == "" or not FileAccess.file_exists(instances_path):
		return 0
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(instances_path))
	var n := 0
	if data is Dictionary:
		var list: Dictionary = data.get("instances", {})
		for id: String in list:
			var inst: Variant = list[id]
			if inst is Dictionary and ServerHost.is_world_id(id) and ServerHost.is_world_id(str(inst.get("content", ""))):
				host.server.instances[id] = {"content": str(inst["content"]), "name": str(inst.get("name", id))}
				if start(id)["ok"]:
					n += 1
				else:
					host.server.instances.erase(id)
	return n


func _save() -> void:
	if instances_path == "":
		return
	var f := FileAccess.open(instances_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"instances": host.server.instances}, "	"))


func _info(id: String) -> Dictionary:
	var source := host.server.source_of(id)
	return source.get_info() if source != null else {}


static func _fail(code: String, detail: String) -> Dictionary:
	return {"ok": false, "code": code, "detail": detail}
