## Instances of one content (roadmap S.04b), over real WebSockets in this process: an instance "amis"
## of the world "second" has its own characters and its own players (a name taken in one is free in
## the other), `servers` and `welcome` carry `content`, the content API lists it under its own id
## and serves the package of its content, and instances.json brings it back after a restart.
extends TestCase

const Accounts := preload("res://tests/test_accounts.gd")

const LOOK := "{1|120,2195||56}"
const SECRET := "s3cret-admin"
const PATH := "user://test_instances.json"


func _rig(persistence := Persistence.new()) -> Accounts.Rig:
	var rig := Accounts.Rig.new(persistence)
	rig.host.ticks = func() -> int: return rig.virtual_ms
	rig.host.server.sources["second"] = WorldSource.from_dicts(
		{"id": "second", "name": "Second", "module": "demo", "start_map": 7, "start_cell": 300},
		[{"id": 7, "coords": [3, 3], "neighbors": {}}])
	rig.host.listen_http(0, "127.0.0.1")
	rig.host.admin.token = SECRET
	rig.host.cluster.instances_path = PATH
	var built := WorldPackage.Built.new()
	built.ok = true
	built.world = "second"
	built.manifest = ContentManifest.make("second", "Second", "demo", [])
	rig.host.content.set_package(built)
	return rig


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


func _clean() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_two_instances_keep_their_own_characters() -> void:
	_clean()
	var rig := _rig()
	var r := _act(rig, {"action": "world_create", "id": "amis", "content": "second", "name": "Les amis"})
	eq(bool(r.get("ok", false)), true, "created: " + str(r))
	var alice := _player(rig, "alice", "Alice", "second")
	var bob := _player(rig, "bob", "Berthe", "amis")
	var w1: Dictionary = alice.take(Protocol.WELCOME)[0]["world"]
	var w2: Dictionary = bob.take(Protocol.WELCOME)[0]["world"]
	eq([str(w1["id"]), str(w1["content"])], ["second", "second"], "ordinary world")
	eq([str(w2["id"]), str(w2["content"]), str(w2["name"])], ["amis", "second", "Les amis"], "instance")
	# the same character name is free in the other world: the saves key on the world id
	var carol := _player(rig, "carol", "Alice", "amis")
	check(carol.has(Protocol.WELCOME), "Alice exists in amis and in second")
	eq(rig.host.server.persistence.list_characters("amis").size(), 2)
	eq(rig.host.server.persistence.list_characters("second").size(), 1)
	var list := rig.ask(alice, ProtocolCluster.server_list(), ProtocolCluster.SERVERS)
	var by_id := {}
	for w: Dictionary in list["worlds"]:
		by_id[str(w["id"])] = w
	eq(str(by_id["amis"]["content"]), "second")
	eq(str(by_id["second"]["content"]), "second")
	eq(int(by_id["amis"]["players"]), 2)
	eq(int(by_id["second"]["players"]), 1)
	rig.host.shutdown()
	_clean()


func test_content_api_lists_the_instance_with_its_content() -> void:
	_clean()
	var rig := _rig()
	rig.host.auth.accounts.register("alice", "secret1")
	var c := rig.client()
	var ok := rig.ask(c, Protocol.login("alice", "secret1"), Protocol.LOGIN_OK)
	var token := str(ok.get("token", ""))
	_act(rig, {"action": "world_create", "id": "amis", "content": "second"})
	var listing: Variant = JSON.parse_string(_http(rig, "/worlds", token).body.get_string_from_utf8())
	var ids := []
	for w: Dictionary in listing:
		ids.append(str(w["id"]))
		if w["id"] == "amis":
			eq(str(w["content"]), "second")
	check(ids.has("amis") and ids.has("second"), "listed: " + str(ids))
	eq(_http(rig, "/worlds/amis/manifest.json", token).status, 200, "the instance serves its content's manifest")
	var m: Variant = JSON.parse_string(_http(rig, "/worlds/amis/manifest.json", token).body.get_string_from_utf8())
	eq(str(m["world"]), "second")
	eq(_http(rig, "/worlds/nowhere/manifest.json", token).status, 404)
	rig.host.shutdown()
	_clean()


func test_create_rules_and_remove() -> void:
	_clean()
	var rig := _rig()
	eq(str(_act(rig, {"action": "world_create", "id": "second", "content": "tiny"})["code"]), Protocol.E_BAD_MESSAGE, "id taken")
	eq(str(_act(rig, {"action": "world_create", "id": "x1", "content": "nowhere"})["code"]), Protocol.E_UNKNOWN_WORLD)
	eq(str(_act(rig, {"action": "world_create", "id": "../x", "content": "second"})["code"]), Protocol.E_BAD_MESSAGE, "never a path")
	check(bool(_act(rig, {"action": "world_create", "id": "amis", "content": "second"})["ok"]))
	eq(str(_act(rig, {"action": "world_create", "id": "deux", "content": "amis"})["code"]), Protocol.E_UNKNOWN_WORLD, "no instance of an instance")
	eq(str(_act(rig, {"action": "world_create", "id": "amis", "content": "second"})["code"]), Protocol.E_BAD_MESSAGE, "twice")
	var alice := _player(rig, "alice", "Alice", "amis")
	var gone := _act(rig, {"action": "world_remove", "id": "amis"})
	check(bool(gone["ok"]), str(gone))
	eq(int(gone["players"]), 1, "the player was told")
	check(not rig.host.server.worlds.has("amis") and not rig.host.server.instances.has("amis"), "removed")
	rig.run(1.0, func() -> bool: return alice.has(Protocol.ERROR))
	check(alice.has(Protocol.ERROR), "world_closed sent")
	eq(str(_act(rig, {"action": "world_remove", "id": "second"})["code"]), Protocol.E_UNKNOWN_WORLD, "only an instance")
	check(FileAccess.get_file_as_string(PATH).contains("instances"), "file written")
	rig.host.shutdown()
	_clean()


func test_instances_come_back_after_a_restart() -> void:
	_clean()
	var persistence := Persistence.new()
	var rig := _rig(persistence)
	check(bool(_act(rig, {"action": "world_create", "id": "amis", "content": "second", "name": "Les amis"})["ok"]))
	_player(rig, "alice", "Alice", "amis")
	rig.host.server.save_all()
	rig.host.shutdown()
	var again := _rig(persistence)
	eq(again.host.cluster.restore(), 1, "one instance reopened")
	check(again.host.server.worlds.has("amis"), "running")
	eq(str(again.host.server.worlds["amis"].info["content"]), "second")
	eq(str(again.host.server.worlds["amis"].info["name"]), "Les amis")
	# its character survived: the roster of the instance lists it
	eq(persistence.list_characters("amis").size(), 1)
	again.host.auth.accounts.register("alice", "secret1")
	var c := again.client()
	again.ask(c, Protocol.login("alice", "secret1"), Protocol.LOGIN_OK)
	c.backend.send(Protocol.hello("amis", "", ""))
	again.run(5.0, func() -> bool: return c.has(Protocol.CHARACTERS))
	var chars: Dictionary = c.take(Protocol.CHARACTERS)[0]
	eq(str(chars["world"]["content"]), "second")
	again.host.shutdown()
	_clean()
