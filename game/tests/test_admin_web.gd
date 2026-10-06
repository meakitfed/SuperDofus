## Admin web (roadmap A1.02a): the dashboard page and the JSON routes of /admin over the real HTTP
## port (127.0.0.1) with two NetBackend players logged in with accounts: 401 without the admin
## token, overview, account search and sheets (the character sheet matches the save), and every
## POST action changes the state and leaves a line in the audit file.
extends TestCase

const Accounts := preload("res://tests/test_accounts.gd")

const LOOK := "{1|120,2195||56}"
const SECRET := "s3cret-admin"
const POTION := 683

var _audit_path := "user://test_admin_web/audit.jsonl"


func _rig() -> Accounts.Rig:
	DirAccess.remove_absolute(_audit_path)
	var rig := Accounts.Rig.new()
	rig.host.ticks = func() -> int: return rig.virtual_ms
	rig.host.set_audit_log(AuditLog.new(_audit_path))
	rig.host.listen_http(0, "127.0.0.1")
	rig.host.admin.token = SECRET
	return rig


func _player(rig: Accounts.Rig, login: String, name: String) -> Accounts.Client:
	rig.host.auth.accounts.register(login, "secret1")
	var c := rig.client()
	rig.ask(c, Protocol.login(login, "secret1"), Protocol.LOGIN_OK)
	c.backend.send(Protocol.hello("tiny", name, LOOK))
	rig.run(5.0, func() -> bool: return c.has(Protocol.WELCOME))
	return c


func _http(rig: Accounts.Rig, path: String, token := SECRET, post := "") -> HttpFetch:
	var f := HttpFetch.new()
	var headers := {}
	if token != "":
		headers["Authorization"] = "Bearer " + token
	if post != "":
		f.start_post("127.0.0.1", rig.host.http_port(), path, post, headers)
	else:
		f.start("127.0.0.1", rig.host.http_port(), path, headers)
	var guard := 0
	while not f.poll() and guard < 3000:
		rig.host.poll(0.005)
		OS.delay_msec(1)
		guard += 1
	return f


func _json(rig: Accounts.Rig, path: String) -> Dictionary:
	var f := _http(rig, path)
	eq(f.status, 200, path)
	var d: Variant = JSON.parse_string(f.body.get_string_from_utf8())
	return d if d is Dictionary else {}


func _act(rig: Accounts.Rig, body: Dictionary) -> Dictionary:
	var f := _http(rig, "/admin/action", SECRET, JSON.stringify(body))
	eq(f.status, 200, "action %s" % body.get("action"))
	var d: Variant = JSON.parse_string(f.body.get_string_from_utf8())
	return d if d is Dictionary else {}


func _audit(rig: Accounts.Rig) -> Array:
	return rig.host.audit.read_all()


func test_page_is_public_and_the_data_needs_the_token() -> void:
	var rig := _rig()
	var page := _http(rig, "/admin", "")
	eq(page.status, 200, "the page asks for the token itself")
	check(str(page.headers.get("content-type", "")).begins_with("text/html"), "html")
	check(page.body.get_string_from_utf8().contains("Authorization"), "the page sends the token as a header")
	eq(_http(rig, "/admin/", "").status, 200, "trailing slash")
	for path in ["/admin/overview", "/admin/accounts", "/admin/account?login=x", "/admin/character?world=tiny&name=x", "/admin/audit"]:
		eq(_http(rig, path, "").status, 401, path + " without token")
		eq(_http(rig, path, "wrong").status, 401, path + " with a wrong token")
	eq(_http(rig, "/admin/action", "", "{}").status, 401, "action without token")
	eq(_http(rig, "/admin/action", SECRET).status, 405, "action is POST only")
	eq(_http(rig, "/admin/action", SECRET, "not json").status, 400, "bad body")
	eq(_http(rig, "/admin/overview", SECRET, "{}").status, 405, "a read route refuses POST")
	eq(_http(rig, "/admin/account?login=nobody").status, 404, "unknown account")
	var big := _http(rig, "/admin/action", SECRET, "x".repeat(HttpServer.MAX_BODY_BYTES + 10))
	eq(big.status, 413, "oversized body " + big.body.get_string_from_utf8() + big.error)
	rig.host.admin.token = ""
	eq(_http(rig, "/admin", "").status, 404, "no admin token configured: no page either")
	rig.host.shutdown()


func test_overview_accounts_and_sheets() -> void:
	var rig := _rig()
	var alice := _player(rig, "alice", "Alice")
	_player(rig, "bob", "Bob")
	rig.host.auth.accounts.register("carol", "secret1") # an account with no character
	var o := _json(rig, "/admin/overview")
	eq(int(o["players"]), 2)
	eq((o["player_list"] as Array).size(), 2, "player list")
	eq(str(o["player_list"][0]["name"]), "Alice")
	eq(int(o["accounts"]), 3)
	eq((o["fight_list"] as Array).size(), 0)
	var found := _json(rig, "/admin/accounts?q=ali")
	eq(int(found["total"]), 1, "search by login")
	eq(str(found["accounts"][0]["login"]), "alice")
	eq(bool(found["accounts"][0]["online"]), true)
	eq(int(_json(rig, "/admin/accounts?q=BOB")["total"]), 1, "search by character name, any case")
	eq(int(_json(rig, "/admin/accounts")["total"]), 3, "no query: everyone")
	var sheet := _json(rig, "/admin/account?login=Alice")
	eq(str(sheet["login"]), "alice")
	eq(str(sheet["seen"]["ip"]), "127.0.0.1", "last address")
	check(int(sheet["seen"]["at"]) > 0, "last connection time")
	eq((sheet["characters"] as Array).size(), 1)
	check(not JSON.stringify(sheet).contains("hash") and not JSON.stringify(sheet).contains("salt"), "no credentials in a sheet")
	# the sheet of a connected character is its live document; offline, the save
	var live := _json(rig, "/admin/character?world=tiny&name=Alice")
	eq(bool(live["online"]), true)
	var sim: WorldSim = rig.host.server.worlds["tiny"]
	var p: PlayerActor = sim.chat.find_player("Alice")
	var doc: Dictionary = JSON.parse_string(JSON.stringify(sim.character_write(p)["data"]))
	for k in ["level", "kamas", "map", "cell", "account", "breed", "items"]:
		eq(JSON.stringify(live[k]), JSON.stringify(doc[k]), "live sheet: " + k)
	alice.backend.close()
	rig.run(1.0, func() -> bool: return sim.players.size() == 1)
	var off := _json(rig, "/admin/character?world=tiny&name=Alice")
	eq(bool(off["online"]), false)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(rig.host.server.persistence.load_character("tiny", "Alice")))
	for k in ["level", "kamas", "map", "cell", "account", "items", "stats", "quests"]:
		eq(JSON.stringify(off[k]), JSON.stringify(saved[k]), "saved sheet: " + k)
	eq(bool(_json(rig, "/admin/accounts?q=alice")["accounts"][0]["online"]), false, "offline after leaving")
	eq(_http(rig, "/admin/character?world=tiny&name=Nobody").status, 404)
	rig.host.shutdown()


func test_every_action_changes_the_state_and_is_audited() -> void:
	var rig := _rig()
	var alice := _player(rig, "alice", "Alice")
	var bob := _player(rig, "bob", "Bob")
	var sim: WorldSim = rig.host.server.worlds["tiny"]
	var p: PlayerActor = sim.chat.find_player("Alice")
	var n := _audit(rig).size()
	var r := _act(rig, {"action": "kamas", "world": "tiny", "player": "Alice", "amount": 500})
	eq(bool(r["ok"]), true, "kamas")
	eq(p.character.kamas, 500)
	r = _act(rig, {"action": "give", "world": "tiny", "player": "alice", "item": POTION, "qty": 3})
	eq(bool(r["ok"]), true, "give: %s" % [r])
	eq(p.character.inventory.count(POTION), 3)
	r = _act(rig, {"action": "level", "world": "tiny", "player": "Alice", "level": 20})
	eq(p.character.level, 20, "level")
	p.character.set_hp(1, sim.now)
	r = _act(rig, {"action": "heal", "world": "tiny", "player": "Alice"})
	eq(p.character.hp_at(sim.now), p.character.max_hp(), "heal")
	alice.events.clear()
	r = _act(rig, {"action": "say", "world": "tiny", "text": "serveur dans 5 minutes"})
	rig.run(1.0, func() -> bool: return alice.has(ProtocolAdmin.ANNOUNCE) and bob.has(ProtocolAdmin.ANNOUNCE))
	check(alice.has(ProtocolAdmin.ANNOUNCE) and bob.has(ProtocolAdmin.ANNOUNCE), "say reaches every player")
	r = _act(rig, {"action": "mute", "world": "tiny", "player": "Bob", "minutes": 5})
	eq(bool(r["ok"]), true, "mute")
	check(Sanctions.mute_left_ms(rig.host.server.persistence, "bob", sim.clock.now_unix_ms()) > 0, "bob is muted")
	eq(int(_json(rig, "/admin/account?login=bob")["mute_left_s"]) > 0, true, "the sheet shows it")
	_act(rig, {"action": "unmute", "world": "tiny", "player": "Bob"})
	eq(Sanctions.mute_left_ms(rig.host.server.persistence, "bob", sim.clock.now_unix_ms()), 0, "unmute")
	p.cell = 250
	r = _act(rig, {"action": "tp", "world": "tiny", "player": "Alice", "x": 0, "y": 0})
	eq(bool(r["ok"]), true, "tp: %s" % [r])
	eq(p.map_id, 1)
	check(p.cell != 250, "tp moved Alice (cell %d)" % p.cell)
	eq(str(_act(rig, {"action": "tp", "world": "tiny", "player": "Alice", "x": 99, "y": 99})["code"]), Protocol.E_UNKNOWN_MAP, "no such map")
	r = _act(rig, {"action": "password", "login": "bob", "password": "newsecret"})
	eq(bool(r["ok"]), true, "password")
	eq(rig.host.auth.accounts.check("bob", "newsecret"), "", "the new password works")
	eq(rig.host.auth.accounts.check("bob", "secret1"), Protocol.E_BAD_CREDENTIALS, "the old one does not")
	eq(str(_act(rig, {"action": "password", "login": "bob", "password": "x"})["code"]), Protocol.E_BAD_LOGIN, "too short")
	r = _act(rig, {"action": "save"})
	eq(int(r["saved"]), 2, "manual save")
	eq(rig.host.server.persistence.load_character("tiny", "Alice")["kamas"], 500, "the save holds the kamas")
	check(bool(_act(rig, {"action": "reload"})["ok"]), "reload")
	# refusals
	eq(str(_act(rig, {"action": "kamas", "world": "tiny", "player": "Nobody", "amount": 5})["code"]), Protocol.E_PLAYER_OFFLINE)
	eq(str(_act(rig, {"action": "kamas", "world": "tiny", "amount": 5})["code"]), Protocol.E_BAD_MESSAGE, "player missing")
	eq(str(_act(rig, {"action": "give", "world": "tiny", "player": "Alice", "item": 999999999})["code"]), Protocol.E_UNKNOWN_ITEM)
	eq(str(_act(rig, {"action": "kamas", "world": "nowhere", "player": "Alice", "amount": 5})["code"]), Protocol.E_BAD_MESSAGE, "unknown world")
	eq(str(_act(rig, {"action": "explode"})["code"]), Protocol.E_UNKNOWN_COMMAND)
	# ban: Bob is thrown out, refused at login, then unbanned
	r = _act(rig, {"action": "ban", "world": "tiny", "player": "Bob", "reason": "test"})
	eq(bool(r["ok"]), true, "ban")
	rig.run(2.0, func() -> bool: return sim.players.size() == 1)
	eq(sim.players.size(), 1, "Bob left the world")
	var again := rig.client()
	eq(str(rig.ask(again, Protocol.login("bob", "newsecret"), Protocol.LOGIN_ERROR).get("code")), ProtocolAdmin.E_BANNED, "refused at login")
	var sheet := _json(rig, "/admin/account?login=bob")
	eq(bool(sheet["banned"]), true)
	eq(str(sheet["sanction"]["ban"]["reason"]), "test")
	_act(rig, {"action": "unban", "world": "tiny", "name": "Bob"})
	eq(bool(_json(rig, "/admin/account?login=bob")["banned"]), false, "unban")
	var bob2 := rig.client()
	check(not rig.ask(bob2, Protocol.login("bob", "newsecret"), Protocol.LOGIN_OK).is_empty(), "Bob can log in again")
	bob2.backend.send(Protocol.hello("tiny", "Bob", LOOK))
	rig.run(5.0, func() -> bool: return bob2.has(Protocol.WELCOME))
	_act(rig, {"action": "kick", "world": "tiny", "player": "Bob"})
	rig.run(2.0, func() -> bool: return sim.players.size() == 1)
	eq(sim.players.size(), 1, "kick")
	# every call above left one line in the audit file, in order, without a password
	var lines := _audit(rig).slice(n)
	var cmds := lines.map(func(e: Dictionary) -> String: return str(e["cmd"]))
	eq(cmds.slice(0, 5), ["kamas", "give", "level", "heal", "say"], "audit order")
	for e: Dictionary in lines:
		eq(str(e["account"]), "web-admin", "audited as the web admin")
	check(not FileAccess.get_file_as_string(_audit_path).contains("newsecret"), "no password in the audit")
	var by_cmd := {}
	for e: Dictionary in lines:
		by_cmd[str(e["cmd"])] = e
	for c in ["mute", "unmute", "tp", "password", "save", "reload", "ban", "unban", "kick"]:
		check(by_cmd.has(c), "audit has " + c)
	eq(bool(by_cmd["kamas"]["ok"]), false, "the last (refused) kamas is the one kept in the map")
	var shown := _json(rig, "/admin/audit?limit=5")
	eq((shown["entries"] as Array).size(), 5, "limit")
	eq(str(shown["entries"][0]["cmd"]), "kick", "newest first")
	rig.host.shutdown()
