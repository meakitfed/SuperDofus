## What the admin web does (roadmap A1.02): POST /admin/action {action, ...}. Game commands go
## through the sim's WorldAdmin (the same rules and the same audit as the GM console, run as the
## transient GM "web-admin"); server actions (password reset, manual save, data reload) are
## audited here with the same entry shape. Every action, accepted or refused, leaves one audit
## line. Returns {ok, code, detail, result}. Nothing here knows which game a world runs.
## Not used by sim/, shared/ or client/.
##
## Actions (JSON fields): tp{world, player, map, cell?} or tp{world, player, x, y}  give{world, player, item, qty?}
## kamas{world, player, amount}  level{world, player, level}  heal{world, player}
## kick{world, player}  ban{world, player, reason?}  unban{world, name}  mute{world, player,
## minutes?}  unmute{world, player}  say{world, text}  password{login, password}
## save{}  reload{}  world_start{id}  world_stop{id}  (S.04: open / close a world while the server runs)
## world_create{id, content, name?}  world_remove{id}  (S.04b: an instance of a content, kept in instances.json)
## APPROX(A1.02a): give / kamas / level / heal / tp / kick need the player connected and out of a
## fight (as the console); ban / mute / unban also work on a saved character.
class_name AdminActions
extends RefCounted

const WEB := "web-admin"

var host: ServerHost


func run(req: Dictionary) -> Dictionary:
	var action := str(req.get("action", ""))
	match action:
		"password":
			return _password(str(req.get("login", "")), str(req.get("password", "")))
		"world_start":
			var r := host.cluster.start(str(req.get("id", "")))
			return _server_done(action, [str(req.get("id", ""))], {"detail": r.detail}, r.code if not r.ok else "")
		"world_create": # S.04b: an instance `id` of the content `content`
			var r := host.cluster.create(str(req.get("id", "")), str(req.get("content", "")), str(req.get("name", "")))
			return _server_done(action, [str(req.get("id", "")), str(req.get("content", ""))], {"detail": r.detail}, r.code if not r.ok else "")
		"world_remove":
			var r := host.cluster.remove(str(req.get("id", "")))
			var extra := {"detail": r.detail}
			if r.ok:
				extra["players"] = r.players
			return _server_done(action, [str(req.get("id", ""))], extra, r.code if not r.ok else "")
		"world_stop":
			var r := host.cluster.stop(str(req.get("id", "")))
			var extra := {"detail": r.detail}
			if r.ok:
				extra["players"] = r.players
			return _server_done(action, [str(req.get("id", ""))], extra, r.code if not r.ok else "")
		"save":
			return _server_done(action, [], {"saved": host.server.save_all()})
		"reload":
			GameData.clear_cache() # same effect as the console's reload (APPROX(A1.01): tables only)
			return _server_done(action, [])
		"say", "tp", "give", "kamas", "level", "heal", "kick", "ban", "unban", "mute", "unmute":
			pass
		_:
			return _fail(Protocol.E_UNKNOWN_COMMAND, action)
	var args: Variant = _args(action, req)
	if args == null:
		return _fail(Protocol.E_BAD_MESSAGE, "missing field for " + action)
	return _in_world(str(req.get("world", "")), action, args as Array)


## The command arguments from the request fields, null when a required field is missing.
func _args(action: String, req: Dictionary) -> Variant:
	var who := str(req.get("player", req.get("name", ""))).strip_edges()
	match action:
		"say":
			return [str(req.get("text", ""))] if str(req.get("text", "")).strip_edges() != "" else null
		"tp":
			if who != "" and req.has("x") and req.has("y"): # coordinates, as `/tp x y` of the console
				return [who, int(req["x"]), int(req["y"])]
			if who == "" or not req.has("map"):
				return null
			var a := [who, int(req["map"])]
			if req.has("cell"):
				a.append(int(req["cell"]))
			return a
		"give":
			return null if who == "" or not req.has("item") else [int(req["item"]), int(req.get("qty", 1)), who]
		"kamas":
			return null if who == "" or not req.has("amount") else [int(req["amount"]), who]
		"level":
			return null if who == "" or not req.has("level") else [int(req["level"]), who]
		"heal", "kick", "unmute", "unban":
			return null if who == "" else [who]
		"ban":
			return null if who == "" else [who, str(req.get("reason", ""))]
		"mute":
			return null if who == "" else ([who, int(req["minutes"])] if req.has("minutes") else [who])
	return null


func _in_world(world: String, action: String, args: Array) -> Dictionary:
	var sim: WorldSim = host.server.worlds.get(world)
	if sim == null:
		return _fail(Protocol.E_BAD_MESSAGE, "unknown world: " + world)
	return sim.admin.run_web(WEB, action, args)


func _password(login: String, password: String) -> Dictionary:
	if host.auth == null:
		return _fail(Protocol.E_BAD_MESSAGE, "this server has no accounts")
	var code := host.auth.accounts.set_password(login, password)
	# the audit line never carries the password
	return _server_done("password", [AccountStore.normalize(login)], {}, code)


func _server_done(action: String, args: Array, extra := {}, code := "") -> Dictionary:
	var entry := {"at": host.server.clock.now_unix_ms(), "world": "", "account": WEB, "name": WEB,
			"cmd": action, "args": args, "ok": code == "", "code": code}
	if host.server.audit_sink.is_valid():
		host.server.audit_sink.call(entry)
	var out := {"ok": code == "", "code": code, "detail": "", "result": args}
	out.merge(extra)
	return out


func _fail(code: String, detail: String) -> Dictionary:
	return {"ok": false, "code": code, "detail": detail, "result": []}
