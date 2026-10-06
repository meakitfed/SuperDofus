## Parity standalone / server (roadmap S.07): every reference scenario (tests/scenarios/*.jsonl)
## replays through a real ServerHost on 127.0.0.1 and a NetBackend (WebSocket, JSON) and must give
## the expected events, in order, exactly as LocalBackend does in test_scenarios.gd. Only the clock
## differs (the network backend follows the server's clock estimated by ping): times are not compared.
extends TestCase

const DIR := "res://tests/scenarios"
const STEP := 0.05


## A server and one NetBackend pumped together on a virtual clock, behind the GameBackend API
## (so Scenario.run drives it like any backend).
class NetRig extends GameBackend:
	var host := ServerHost.new()
	var net := NetBackend.new()
	var virtual_ms := 0

	func _init() -> void:
		host.gm_accounts = PackedStringArray(["ip-127.0.0.1"]) # the local player is a GM in standalone
		host.listen(0, "127.0.0.1")
		net.validate_events = true
		net.ticks = func() -> int: return virtual_ms
		net.event.connect(func(ev: Dictionary) -> void: event.emit(ev))
		net.connect_to("127.0.0.1:%d" % host.local_port())

	## Called by Scenario.run: same seed, same saved character as the LocalBackend run.
	func prepare_scenario(header: Dictionary) -> void:
		host.server.seed = int(header.get("seed", 1))
		if header.has("character") and str(header.get("player", "Tester")) != "":
			var ch: Dictionary = (header["character"] as Dictionary).duplicate(true)
			ch["name"] = str(header.get("player", "Tester"))
			host.server.persistence.save_character(str(header["world"]), ch["name"], ch)

	func send(cmd: Dictionary) -> void:
		net.send(cmd)

	func poll(delta: float) -> void:
		virtual_ms += int(delta * 1000.0)
		host.poll(delta)
		net.poll(delta)

	func time_ms() -> int:
		return virtual_ms

	func close() -> void:
		net.close()
		for i in 4:
			host.poll(STEP)
		host.shutdown()


func _init() -> void:
	SpellBook.use_file("")
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()


func _scenario_files() -> Array:
	return Array(DirAccess.get_files_at(DIR)).filter(func(f: String) -> bool: return f.ends_with(".jsonl"))


func test_every_scenario_passes_through_the_network() -> void:
	var files := _scenario_files()
	check(files.size() >= 3, "the scenarios exist")
	for f: String in files:
		var s := Scenario.load_file(DIR.path_join(f))
		var rig := NetRig.new()
		var events := s.run(rig)
		check(not rig.net.has_method("x") and rig.net.schema_errors.is_empty(), "%s: events follow the schema (%s)" % [f, rig.net.schema_errors])
		for failure in s.check(events, true):
			check(false, "%s (network): %s" % [f, failure])


func test_the_replay_is_not_vacuous() -> void:
	var s := Scenario.load_file(DIR.path_join("fight_won.jsonl"))
	var rig := NetRig.new()
	var events := s.run(rig)
	check(events.size() > 20 and s.expects.size() > 20, "the fight really went through the socket")
	var wrong := Scenario.load_file(DIR.path_join("explore.jsonl"))
	var rig2 := NetRig.new()
	var ev2 := wrong.run(rig2)
	eq(wrong.check(ev2, true), PackedStringArray(), "explore passes")
	(wrong.expects[3]["expect"] as Dictionary)["t"] = "nonexistent"
	eq(wrong.check(ev2, true).size(), 1, "a wrong expectation is caught on the network replay too")


# --- two players: the same script on a shared LocalServer and on a ServerHost ---

const LOOK := "{1|120,2195||56}"
const EDGE := 20 * 14 + 13


static func _duo_world() -> WorldSource:
	return WorldSource.from_dicts(
		{"id": "duo", "name": "Duo", "start_map": 1, "start_cell": 300, "wander_ms": [600000, 600000]},
		[{"id": 1, "coords": [0, 0], "neighbors": {"right": 2}},
		 {"id": 2, "coords": [1, 0], "neighbors": {"left": 1}}])


## What each client saw, reduced to what the rules decide (type + a few fields), pongs and clock left out.
static func _digest(events: Array) -> Array:
	var out := []
	for e: Dictionary in events:
		var t := str(e["t"])
		match t:
			Protocol.PONG:
				pass
			Protocol.ACTOR_ADD:
				out.append([t, str((e["actor"] as Dictionary).get("name", ""))])
			Protocol.ACTOR_MOVE:
				out.append([t, int(e["id"]), (e["path"] as Array).size()])
			Protocol.ACTOR_REMOVE:
				out.append([t, int(e["id"])])
			Protocol.MAP_ENTER:
				out.append([t, int((e["map"] as Dictionary)["id"]), ((e["actors"] as Array).map(func(a: Dictionary) -> String: return str(a["name"])))])
			Protocol.CHAT_MSG:
				out.append([t, str(e.get("from", "")), str(e.get("text", ""))])
			_:
				out.append([t])
	return out


## The script, driven by `pump.call(seconds)`; `a` and `b` are the two backends.
static func _duo_script(a: GameBackend, b: GameBackend, pump: Callable) -> void:
	a.send(Protocol.hello("duo", "Alice", LOOK))
	pump.call(1.0)
	b.send(Protocol.hello("duo", "Bob", LOOK))
	pump.call(1.0)
	b.send(Protocol.move(EDGE))
	pump.call(15.0)
	a.send(Protocol.chat_send("general", "salut"))
	pump.call(1.0)
	b.send(Protocol.change_map("right"))
	pump.call(1.0)
	b.close()
	pump.call(1.0)


func test_two_players_see_the_same_on_both_backends() -> void:
	# standalone side: two LocalBackends on one LocalServer
	var server := LocalServer.new()
	server.sources["duo"] = _duo_world()
	var la := LocalBackend.new()
	var lb := LocalBackend.new()
	la.server = server
	lb.server = server
	la.account = "alice"
	lb.account = "bob"
	var lev := [[], []]
	la.event.connect(func(ev: Dictionary) -> void: lev[0].append(ev))
	lb.event.connect(func(ev: Dictionary) -> void: lev[1].append(ev))
	_duo_script(la, lb, func(sec: float) -> void:
		for i in int(sec / STEP):
			server.tick(int(STEP * 1000.0))
			la.poll(STEP)
			lb.poll(STEP))
	# server side: two NetBackends on one ServerHost
	var host := ServerHost.new()
	host.server.sources["duo"] = _duo_world()
	host.listen(0, "127.0.0.1")
	var ms := [0]
	var na := NetBackend.new()
	var nb := NetBackend.new()
	var nev := [[], []]
	for i in 2:
		var n: NetBackend = [na, nb][i]
		n.validate_events = true
		n.ticks = func() -> int: return ms[0]
		var idx := i
		n.event.connect(func(ev: Dictionary) -> void: nev[idx].append(ev))
		n.connect_to("127.0.0.1:%d" % host.local_port())
	_duo_script(na, nb, func(sec: float) -> void:
		for i in int(sec / STEP):
			ms[0] += int(STEP * 1000.0)
			host.poll(STEP)
			na.poll(STEP)
			nb.poll(STEP))
	host.shutdown()
	eq(na.schema_errors.size() + nb.schema_errors.size(), 0, "network events match the schema")
	var da := _digest(lev[0])
	var net_a := _digest(nev[0])
	check(da.size() > 5, "Alice saw something")
	eq(JSON.stringify(net_a), JSON.stringify(da), "Alice: same events on both backends")
	eq(JSON.stringify(_digest(nev[1])), JSON.stringify(_digest(lev[1])), "Bob: same events on both backends")
