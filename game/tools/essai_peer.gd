## One connection of the server trial (tools/essai_serveur.gd): a NetBackend and what it saw
## (events since the last clear(), the whole session for the scenario bot, the map, kamas, bag).
class_name EssaiPeer
extends RefCounted

var name := ""
var backend := NetBackend.new()
var events: Array = [] # every event since the last clear()
var seen: Array = [] # {ev} of the whole session, for the scenario bot
var you := -1
var map_id := 0
var cell := -1
var actors := {} # id -> actor dict (this map)
var kamas := -1
var items := {} # uid -> item dict
var bot: ScenarioBot = null

func _init(p_name: String) -> void:
	name = p_name
	backend.validate_events = true
	backend.event.connect(_on_event)

func _on_event(ev: Dictionary) -> void:
	events.append(ev)
	seen.append({"ev": ev})
	match str(ev["t"]):
		Protocol.WELCOME:
			you = int(ev["you"])
		Protocol.MAP_ENTER:
			map_id = int(ev["map"]["id"])
			actors.clear()
			for a: Dictionary in ev["actors"]:
				actors[int(a["id"])] = a
				if int(a["id"]) == you:
					cell = int(a["cell"])
		Protocol.ACTOR_ADD:
			actors[int(ev["actor"]["id"])] = ev["actor"]
		Protocol.ACTOR_REMOVE:
			actors.erase(int(ev["id"]))
		Protocol.ACTOR_MOVE:
			var path: Array = ev["path"]
			if not path.is_empty() and int(ev["id"]) == you:
				cell = int(path[path.size() - 1])
		Protocol.PLAYER_STATS:
			kamas = int(ev["stats"].get("kamas", kamas))
		Protocol.INVENTORY:
			items.clear()
			for it: Dictionary in ev["items"]:
				items[int(it["uid"])] = it
		Protocol.ITEM_ADDED:
			items[int(ev["item"]["uid"])] = ev["item"]
		Protocol.ITEM_REMOVED:
			items.erase(int(ev["uid"]))

func has(type: String) -> bool:
	return events.any(func(e: Dictionary) -> bool: return e["t"] == type)

func of(type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e["t"] == type)

func last(type: String) -> Dictionary:
	for i in range(events.size() - 1, -1, -1):
		if events[i]["t"] == type:
			return events[i]
	return {}

func errors() -> Array:
	return of(Protocol.ERROR).map(func(e: Dictionary) -> String: return str(e["code"]))

func has_error(code: String) -> bool:
	return errors().has(code)

func clear() -> void:
	events.clear()

func send(cmd: Dictionary) -> void:
	backend.send(cmd)

func actor_named(player_name: String) -> int:
	for id: int in actors:
		if str(actors[id].get("name", "")) == player_name:
			return id
	return -1

func item_of(id: int) -> int:
	for uid: int in items:
		if int(items[uid]["id"]) == id:
			return uid
	return -1


## GET on the content API (game port + 1) with a session token; [status, body] or [-1, ""].
static func http_get(tree: SceneTree, server: String, path: String, token: String) -> Array:
	var host := server.get_slice(":", 0)
	var port := int(server.get_slice(":", 1)) + 1
	var client := HTTPClient.new()
	if client.connect_to_host(host, port) != OK:
		return [-1, ""]
	var deadline := Time.get_ticks_msec() + 8000
	while client.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING] and Time.get_ticks_msec() < deadline:
		client.poll()
		await tree.create_timer(0.02).timeout
	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		return [-1, ""]
	var headers: Array = ["Authorization: Bearer " + token] if token != "" else []
	client.request(HTTPClient.METHOD_GET, path, headers)
	while client.get_status() == HTTPClient.STATUS_REQUESTING and Time.get_ticks_msec() < deadline:
		client.poll()
		await tree.create_timer(0.02).timeout
	if not client.has_response():
		return [-1, ""]
	var body := PackedByteArray()
	while client.get_status() == HTTPClient.STATUS_BODY and Time.get_ticks_msec() < deadline:
		client.poll()
		body.append_array(client.read_response_body_chunk())
		await tree.create_timer(0.005).timeout
	return [client.get_response_code(), body.get_string_from_utf8()]
