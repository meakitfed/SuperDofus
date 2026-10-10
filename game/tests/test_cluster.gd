## Several worlds on one server (roadmap S.04a), over real WebSockets in this process: two worlds in
## parallel with one player each and no event crossing from one to the other, `server_list`, the
## admin starting / stopping a world while the other keeps running (players saved and told, the
## content list follows), and a stopped world that no hello can reopen by itself.
extends TestCase

const Accounts := preload("res://tests/test_accounts.gd")

const LOOK := "{1|120,2195||56}"
const SECRET := "s3cret-admin"


func _rig() -> Accounts.Rig:
	var rig := Accounts.Rig.new()
	rig.host.ticks = func() -> int: return rig.virtual_ms
	rig.host.server.sources["second"] = WorldSource.from_dicts(
		{"id": "second", "name": "Second", "module": "demo", "start_map": 7, "start_cell": 300},
		[{"id": 7, "coords": [3, 3], "neighbors": {}}])
	rig.host.listen_http(0, "127.0.0.1")
	rig.host.admin.token = SECRET
	return rig


## A published world (C.07): only its pointer, the content list reads nothing else.
func _published(rig: Accounts.Rig, id: String, title: String) -> void:
	var store := ProjectSettings.globalize_path("user://test_cluster/packages")
	DirAccess.make_dir_recursive_absolute(store)
	ContentStore.set_pointer(store, id, {"release": "0123456789abcdef", "name": title, "module": "demo", "size": 0, "files": 0})
	rig.host.content.store = store


func _player(rig: Accounts.Rig, login: String, name: String, world: String) -> Accounts.Client:
	rig.host.auth.accounts.register(login, "secret1")
	var c := rig.client()
	rig.ask(c, Protocol.login(login, "secret1"), Protocol.LOGIN_OK)
	c.backend.send(Protocol.hello(world, name, LOOK))
	rig.run(5.0, func() -> bool: return c.has(Protocol.WELCOME))
	return c


func _http(rig: Accounts.Rig, path: String, token: String, post := "") -> HttpFetch:
	var f := HttpFetch.new()
	var headers := {"Authorization": "Bearer " + token}
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


func _act(rig: Accounts.Rig, body: Dictionary) -> Dictionary:
	var f := _http(rig, "/admin/action", SECRET, JSON.stringify(body))
	var d: Variant = JSON.parse_string(f.body.get_string_from_utf8())
	return d if d is Dictionary else {}


func _admin_worlds(rig: Accounts.Rig) -> Array:
	var d: Variant = JSON.parse_string(_http(rig, "/admin/worlds", SECRET).body.get_string_from_utf8())
	return d["worlds"] if d is Dictionary else []


## the worlds of this test among the ones the project folder holds
func _mine(list: Array) -> Array:
	return list.filter(func(w: Dictionary) -> bool: return w["id"] in ["tiny", "second"])


func _hello_error(rig: Accounts.Rig, c: Accounts.Client, world: String) -> Dictionary:
	c.backend.send(Protocol.hello(world, "", ""))
	rig.run(3.0, func() -> bool: return c.has(Protocol.ERROR))
	var got := c.take(Protocol.ERROR)
	return got[0] if not got.is_empty() else {}


func test_two_worlds_in_parallel_do_not_leak() -> void:
	var rig := _rig()
	var alice := _player(rig, "alice", "Alice", "tiny")
	var bob := _player(rig, "bob", "Bob", "second")
	eq(rig.host.server.worlds.size(), 2, "two WorldSims")
	eq(str(alice.take(Protocol.WELCOME)[0]["world"]["id"]), "tiny")
	eq(str(bob.take(Protocol.WELCOME)[0]["world"]["id"]), "second")
	alice.backend.send(Protocol.move(293))
	bob.backend.send(Protocol.move(310))
	rig.run(3.0)
	for ev in alice.events:
		check(not JSON.stringify(ev).contains("Bob"), "Alice never sees Bob: " + str(ev["t"]))
	for ev in bob.events:
		check(not JSON.stringify(ev).contains("Alice"), "Bob never sees Alice: " + str(ev["t"]))
	var list := rig.ask(alice, ProtocolCluster.server_list(), ProtocolCluster.SERVERS)
	var worlds: Array = list["worlds"]
	eq(worlds.map(func(w: Dictionary) -> String: return w["id"]), ["second", "tiny"], "open worlds")
	for w: Dictionary in worlds:
		eq(int(w["players"]), 1, "one player in " + str(w["id"]))
	eq(str(worlds[0]["name"]), "Second")
	eq(str(worlds[0]["module"]), "demo")
	rig.host.shutdown()


func test_server_list_needs_the_login() -> void:
	var rig := _rig()
	var c := rig.client()
	var err := rig.ask(c, ProtocolCluster.server_list(), Protocol.ERROR)
	eq(str(err.get("code")), Protocol.E_NOT_LOGGED_IN)
	rig.host.shutdown()


func test_admin_stops_and_starts_a_world() -> void:
	var rig := _rig()
	DirAccess.remove_absolute("user://test_cluster/audit.jsonl")
	rig.host.set_audit_log(AuditLog.new("user://test_cluster/audit.jsonl"))
	var alice := _player(rig, "alice", "Alice", "tiny")
	var bob := _player(rig, "bob", "Bob", "second")
	_published(rig, "second", "Second")
	eq(_mine(_admin_worlds(rig)).size(), 2)
	eq(str(_act(rig, {"action": "world_stop", "id": "nowhere"})["code"]), Protocol.E_UNKNOWN_WORLD)
	eq(str(_act(rig, {"action": "world_start", "id": "tiny"})["code"]), Protocol.E_BAD_MESSAGE, "already open")
	eq(str(_act(rig, {"action": "world_start", "id": "../x"})["code"]), Protocol.E_BAD_MESSAGE, "never a path")
	var r := _act(rig, {"action": "world_stop", "id": "second"})
	eq(bool(r["ok"]), true, "stop")
	eq(int(r["players"]), 1)
	rig.run(2.0, func() -> bool: return bob.has(Protocol.ERROR))
	eq(str(bob.take(Protocol.ERROR)[0]["code"]), ProtocolCluster.E_WORLD_CLOSED)
	check(not rig.host.server.worlds.has("second"), "the world is gone")
	check(rig.host.server.persistence.list_characters("second").has("Bob"), "Bob is saved")
	eq((rig.host.server.worlds["tiny"] as WorldSim).players.size(), 1, "Alice still plays")
	alice.backend.send(Protocol.move(293))
	rig.run(1.0)
	check(not alice.has(Protocol.ERROR), "Alice has no error")
	eq(str(_hello_error(rig, bob, "second").get("code")), Protocol.E_UNKNOWN_WORLD, "closed for players")
	var open := rig.ask(alice, ProtocolCluster.server_list(), ProtocolCluster.SERVERS)["worlds"] as Array
	eq(open.size(), 1, "only tiny is listed to players")
	check(rig.host.content.release_of("second") != "" and not rig.host.allowed_worlds.has("second"), "published, no longer served")
	eq(_mine(_admin_worlds(rig)).filter(func(w: Dictionary) -> bool: return w["running"]).size(), 1)
	eq(_mine(_admin_worlds(rig)).size(), 2, "the admin still sees the stopped one")
	eq(bool(_act(rig, {"action": "world_start", "id": "second"})["ok"]), true, "start")
	bob.backend.send(Protocol.hello("second", "", ""))
	rig.run(3.0, func() -> bool: return bob.has(Protocol.CHARACTERS))
	var chars: Array = bob.take(Protocol.CHARACTERS)[0]["list"]
	eq(str(chars[0]["name"]), "Bob", "character kept across the restart")
	eq((rig.ask(alice, ProtocolCluster.server_list(), ProtocolCluster.SERVERS)["worlds"] as Array).size(), 2)
	var cmds := rig.host.audit.read_all().map(func(e: Dictionary) -> String: return str(e["cmd"]))
	check(cmds.count("world_stop") == 2 and cmds.count("world_start") == 3, "audited: " + str(cmds))
	rig.host.shutdown()


func test_the_only_world_can_be_stopped() -> void:
	var rig := _rig()
	var alice := _player(rig, "alice", "Alice", "tiny")
	eq(bool(_act(rig, {"action": "world_stop", "id": "second"})["ok"]) if rig.host.server.worlds.has("second") else true, true)
	eq(bool(_act(rig, {"action": "world_stop", "id": "tiny"})["ok"]), true)
	rig.run(1.0)
	eq(str(alice.take(Protocol.ERROR)[0]["code"]), ProtocolCluster.E_WORLD_CLOSED, "told")
	eq(str(_hello_error(rig, alice, "tiny").get("code")), Protocol.E_UNKNOWN_WORLD, "an empty allowed list does not reopen it")
	check(not rig.host.server.worlds.has("tiny"))
	rig.host.shutdown()


func test_the_content_list_carries_the_players() -> void:
	var rig := _rig()
	_player(rig, "alice", "Alice", "tiny")
	_published(rig, "tiny", "Tiny")
	rig.host.auth.accounts.register("carol", "secret1")
	var c := rig.client()
	var ok := rig.ask(c, Protocol.login("carol", "secret1"), Protocol.LOGIN_OK)
	var f := _http(rig, "/worlds", str(ok["token"]))
	eq(f.status, 200)
	var list: Array = JSON.parse_string(f.body.get_string_from_utf8())
	var tiny: Array = list.filter(func(w: Dictionary) -> bool: return w["id"] == "tiny")
	eq(tiny.size(), 1)
	eq(int(tiny[0]["players"]), 1, "players of the world, for the loading screen")
	eq(tiny[0]["state"], "ready", "published")
	rig.host.shutdown()
