## GET /admin/metrics (roadmap A1.01b): the numbers match what two NetBackend clients do on
## 127.0.0.1 (players, active maps, a running fight), the admin token is required and is not
## a session token, no token configured = no route, the answer is valid JSON.
extends TestCase

const NetTests := preload("res://tests/test_net.gd")
const SECRET := "s3cret-admin"


func _rig() -> NetTests.Rig:
	var rig := NetTests.Rig.new()
	var member := {"look": "{4907|||130}", "name": "Tofu", "level": 3, "hp": 100, "ap": 4, "mp": 3}
	rig.host.server.sources["arena"] = WorldSource.from_dicts(
		{"id": "arena", "name": "Arena", "start_map": 1, "start_cell": 300, "wander_ms": [600000, 600000]},
		[{"id": 1, "coords": [0, 0], "neighbors": {"right": 2}, "groups": [{"name": "Tofus", "members": [member]}]},
		 {"id": 2, "coords": [1, 0], "neighbors": {"left": 1}}])
	return rig


func _fetch(rig: NetTests.Rig, path: String, token: String) -> HttpFetch:
	var f := HttpFetch.new()
	var headers := {}
	if token != "":
		headers["Authorization"] = "Bearer " + token
	f.start("127.0.0.1", rig.host.http_port(), path, headers)
	var guard := 0
	while not f.poll() and guard < 2000:
		rig.host.poll(0.005)
		OS.delay_msec(1)
		guard += 1
	return f


func test_metrics_follow_two_clients_and_a_fight() -> void:
	var rig := _rig()
	rig.host.listen_http(0, "127.0.0.1")
	rig.host.admin.token = SECRET
	var empty: Variant = JSON.parse_string(_fetch(rig, "/admin/metrics", SECRET).body.get_string_from_utf8())
	eq(int(empty["players"]), 0, "nobody yet")
	var a := rig.client("arena", "Alice")
	var b := rig.client("arena", "Bob")
	rig.run(3.0, func() -> bool: return a.has(Protocol.MAP_ENTER) and b.has(Protocol.MAP_ENTER))
	var f := _fetch(rig, "/admin/metrics", SECRET)
	eq(f.status, 200)
	check(str(f.headers.get("Content-Type", f.headers.get("content-type", ""))).begins_with("application/json"), "JSON content type")
	var m: Variant = JSON.parse_string(f.body.get_string_from_utf8())
	check(m is Dictionary, "valid JSON")
	eq(int(m["players"]), 2, "two players")
	eq(int(m["connections"]), 2)
	eq(int(m["maps_active"]), 1, "both on map 1")
	eq(int(m["fights"]), 0)
	eq(int(m["worlds"]["arena"]["players"]), 2)
	check(int(m["uptime_s"]) >= 0 and int(m["memory_bytes"]) > 0, "uptime and memory")
	check(int(m["tick"]["count"]) > 0 and float(m["tick"]["max_ms"]) >= float(m["tick"]["avg_ms"]), "tick duration: %s" % [m["tick"]])
	eq(int(m["protocol"]), Protocol.VERSION)
	# Bob walks to the next map: two active maps; Alice attacks the group: one fight.
	var group := -1
	for ev: Dictionary in a.take(Protocol.MAP_ENTER)[0]["actors"]:
		if ev["kind"] == "monster_group":
			group = int(ev["id"])
	b.backend.send(Protocol.move(20 * 14 + 13))
	rig.run(15.0)
	b.backend.send(Protocol.change_map("right"))
	rig.run(2.0, func() -> bool: return rig.sim_of("arena").players[b.you].map_id == 2)
	a.backend.send(Protocol.fight_attack(group))
	rig.run(3.0, func() -> bool: return a.has(Protocol.FIGHT_START))
	m = JSON.parse_string(_fetch(rig, "/admin/metrics", SECRET).body.get_string_from_utf8())
	eq(int(m["maps_active"]), 2, "one player per map")
	eq(int(m["fights"]), 1, "a fight is running")
	eq(int(m["worlds"]["arena"]["fights"]), 1)
	rig.host.shutdown()


func test_token_is_required_and_distinct_from_sessions() -> void:
	var rig := _rig()
	var store := AccountStore.new(Persistence.new())
	store.iterations = 1000
	rig.host.auth = AuthService.new(store)
	var session: String = rig.host.auth.register("bob", "secret1").token
	rig.host.listen_http(0, "127.0.0.1")
	eq(_fetch(rig, "/admin/metrics", SECRET).status, 404, "no admin token configured: no route")
	rig.host.admin.token = SECRET
	eq(_fetch(rig, "/admin/metrics", "").status, 401, "no token")
	eq(_fetch(rig, "/admin/metrics", "wrong").status, 401, "wrong token")
	eq(_fetch(rig, "/admin/metrics", session).status, 401, "a session token is not an admin token")
	eq(_fetch(rig, "/admin/other", SECRET).status, 404, "unknown admin route")
	eq(_fetch(rig, "/admin/metrics", SECRET).status, 200)
	var content := _fetch(rig, "/worlds", SECRET)
	eq(content.status, 401, "the admin token does not open the content API")
	eq(_fetch(rig, "/worlds", session).status, 200, "content API unchanged")
	check(AdminApi.same("abc", "abc") and not AdminApi.same("abc", "abd") and not AdminApi.same("abc", "ab"), "same()")
	rig.host.shutdown()


func test_tick_window_is_bounded() -> void:
	var m := ServerMetrics.new()
	for i in ServerMetrics.WINDOW + 50:
		m.record_tick(1000 if i != 5 else 9000)
	var s := m.tick_stats()
	eq(int(s["window"]), ServerMetrics.WINDOW)
	eq(int(s["count"]), ServerMetrics.WINDOW + 50)
	near(float(s["max_ms"]), 1.0, 0.0001, "the old spike left the window")
