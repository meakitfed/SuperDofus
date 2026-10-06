## Security (roadmap S.05a): rate limit per connection (error then cut), frame size, connections
## per address, login attempts per address, content API paths, and a fuzz of the commands (the
## sim never crashes whatever the client sends). Real WebSockets on 127.0.0.1 in this process.
extends TestCase

const LOOK := "{1|120,2195||56}"
const STEP := 0.05
const Players := preload("res://tests/test_players.gd")


func _init() -> void:
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()
	SpellBook.use_file("res://tests/fixtures/spells.json")


class Rig:
	var host := ServerHost.new()
	var virtual_ms := 0
	var raws: Array[WebSocketPeer] = []

	func _init(with_auth := true) -> void:
		var persistence := Persistence.new()
		host.server.persistence = persistence
		host.server.sources["duo"] = Players._server().sources["duo"]
		if with_auth:
			var store := AccountStore.new(persistence)
			store.iterations = 1000
			host.auth = AuthService.new(store)
		host.ticks = func() -> int: return virtual_ms
		host.listen(0, "127.0.0.1")

	## A bare WebSocket client (no NetBackend: it sends what it likes).
	func raw() -> WebSocketPeer:
		var p := WebSocketPeer.new()
		p.outbound_buffer_size = 4 * 1024 * 1024
		p.connect_to_url("ws://127.0.0.1:%d" % host.local_port())
		raws.append(p)
		return p

	func run(seconds: float, advance := true) -> void:
		for i in int(seconds / STEP):
			if advance:
				virtual_ms += int(STEP * 1000.0)
			host.poll(STEP)
			for p in raws:
				p.poll()

	func open(p: WebSocketPeer) -> bool:
		for i in 200:
			run(STEP)
			if p.get_ready_state() == WebSocketPeer.STATE_OPEN:
				return true
		return false

	## Everything the peer received so far, as dictionaries.
	func received(p: WebSocketPeer) -> Array:
		var out := []
		while p.get_available_packet_count() > 0:
			var parsed: Variant = JSON.parse_string(p.get_packet().get_string_from_utf8())
			if parsed is Dictionary:
				out.append(parsed)
		return out

	func closed(p: WebSocketPeer) -> bool:
		return p.get_ready_state() == WebSocketPeer.STATE_CLOSED

	func shutdown() -> void:
		host.shutdown()


static func _codes(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.ERROR).map(func(e: Dictionary) -> String: return str(e["code"]))


# -- the bucket ----------------------------------------------------------------------------

func test_a_bucket_allows_a_burst_then_the_rate() -> void:
	var b := RateLimiter.new(5.0, 2.0)
	var ok := 0
	for i in 10:
		if b.take(1000):
			ok += 1
	eq(ok, 5, "the burst")
	check(not b.take(1100), "0.2 s = 0.4 token: not yet")
	check(b.take(1600), "0.5 s more: one token")
	check(not b.take(1600))
	for i in 5:
		b.take(10000000) # a long silence refills up to the capacity only
	eq(b.tokens() < 1.0, true)
	check(RateLimiter.new(5.0, 2.0).take(0, 5.0), "a cost can take the whole bucket")


# -- the host --------------------------------------------------------------------------------

func test_a_flood_gets_an_error_then_the_cut() -> void:
	var rig := Rig.new(false)
	var p := rig.raw()
	check(rig.open(p))
	for i in 200:
		p.send_text(JSON.stringify(Protocol.list_characters()))
	rig.run(0.5, false) # the clock does not move: no refill
	# the error of the first refused message is read in test_a_short_burst_recovers
	check(rig.closed(p), "and cut")
	check(rig.host.refused_rate > 0)
	rig.shutdown()


func test_a_normal_client_is_never_limited() -> void:
	var rig := Rig.new(false)
	var p := rig.raw()
	check(rig.open(p))
	for second in 20: # 10 messages per second for 20 s, above any real client
		for i in 10:
			p.send_text(JSON.stringify(Protocol.list_characters()))
		rig.run(1.0)
	var codes := _codes(rig.received(p))
	check(not codes.has(ProtocolSecurity.E_RATE_LIMITED), "no limit")
	eq(p.get_ready_state(), WebSocketPeer.STATE_OPEN)
	rig.shutdown()


func test_a_short_burst_recovers() -> void:
	var rig := Rig.new(false)
	var p := rig.raw()
	check(rig.open(p))
	for i in 70: # a few too many: refused, but fewer than the strikes that cut
		p.send_text(JSON.stringify(Protocol.list_characters()))
	rig.run(0.2, false)
	check(_codes(rig.received(p)).has(ProtocolSecurity.E_RATE_LIMITED))
	eq(p.get_ready_state(), WebSocketPeer.STATE_OPEN, "still connected")
	rig.run(3.0) # the bucket refills
	p.send_text(JSON.stringify(Protocol.list_characters()))
	rig.run(0.3)
	check(not _codes(rig.received(p)).has(ProtocolSecurity.E_RATE_LIMITED), "served again")
	rig.shutdown()


func test_a_frame_too_big_is_refused() -> void:
	var rig := Rig.new(false)
	var p := rig.raw()
	check(rig.open(p))
	p.send_text(JSON.stringify({"t": "chat_send", "text": "x".repeat(ServerHost.MAX_FRAME_BYTES + 10)}))
	rig.run(1.0)
	check(rig.closed(p), "the connection is closed")
	eq(rig.host.connections, 0)
	rig.shutdown()


func test_connections_per_address_are_capped() -> void:
	var rig := Rig.new(false)
	rig.host.max_per_address = 3
	var peers: Array[WebSocketPeer] = []
	for i in 5:
		peers.append(rig.raw())
		rig.run(0.3)
	rig.run(1.0)
	var open := peers.filter(func(p: WebSocketPeer) -> bool: return p.get_ready_state() == WebSocketPeer.STATE_OPEN).size()
	eq(open, 3, "three stay")
	eq(rig.host.connections, 3)
	check(rig.host.refused_connections >= 2)
	peers[0].close(1000)
	rig.run(1.0)
	var again := rig.raw()
	check(rig.open(again), "a freed slot is usable")
	rig.shutdown()


func test_login_attempts_are_limited_per_address() -> void:
	var rig := Rig.new()
	rig.host.auth_burst = 6.0
	rig.host.auth_per_sec = 0.01
	var answers := []
	for i in 3: # three connections, three tries each: below the cut of 5 bad passwords per connection
		var p := rig.raw()
		check(rig.open(p))
		for j in 3:
			p.send_text(JSON.stringify(Protocol.login("nobody%d" % i, "wrongpass")))
		var mine := []
		for k in 200: # the hashing runs in a thread (S.05c): poll until the three answers came
			rig.run(0.05, false)
			mine.append_array(rig.received(p))
			if mine.size() >= 3:
				break
			OS.delay_msec(5)
		answers.append_array(mine)
	var codes := answers.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.LOGIN_ERROR).map(func(e: Dictionary) -> String: return str(e["code"]))
	eq(codes.size(), 9)
	eq(codes.count(Protocol.E_TOO_MANY_ATTEMPTS), 3, "the last three are refused without hashing: %s" % [codes])
	rig.shutdown()


func test_a_real_client_plays_through_the_limits() -> void:
	var rig := Rig.new()
	var backend := NetBackend.new()
	var events: Array = []
	backend.validate_events = true
	backend.ticks = func() -> int: return rig.virtual_ms
	backend.event.connect(func(ev: Dictionary) -> void: events.append(ev))
	backend.connect_to("127.0.0.1:%d" % rig.host.local_port())
	backend.send(Protocol.register("secure", "secret1"))
	for i in 200:
		rig.virtual_ms += 50
		rig.host.poll(STEP)
		backend.poll(STEP)
		if events.any(func(e: Dictionary) -> bool: return e["t"] == Protocol.LOGIN_OK):
			break
	backend.send(Protocol.hello("duo", "Hero", LOOK))
	for i in 100:
		rig.virtual_ms += 50
		rig.host.poll(STEP)
		backend.poll(STEP)
		if events.any(func(e: Dictionary) -> bool: return e["t"] == Protocol.MAP_ENTER):
			break
	check(events.any(func(e: Dictionary) -> bool: return e["t"] == Protocol.MAP_ENTER), "in the game")
	check(not _codes(events).has(ProtocolSecurity.E_RATE_LIMITED))
	check(ErrorTexts.TEXTS.has(ProtocolSecurity.E_RATE_LIMITED), "the client has a text for it")
	backend.close()
	rig.shutdown()


# -- the content API ---------------------------------------------------------------------------

func test_content_paths_never_reach_the_disk() -> void:
	var rig := Rig.new()
	var api := ContentApi.new()
	api.auth = rig.host.auth
	var token := rig.host.auth.register("bob", "secret1").token
	for path in ["/worlds/duo/files/../../project.godot", "/worlds/../files/x", "/worlds/duo/files/%2e%2e%2f%2e%2e%2fproject.godot",
			"/worlds/duo/files/C:/Windows/win.ini", "/worlds/duo/files/", "/worlds//files/x", "/files/x", "/../project.godot", "/worlds/duo/manifest.json/../x"]:
		var req := HttpServer.Request.new()
		req.method = "GET"
		req.path = path
		req.headers["authorization"] = "Bearer " + token
		var r := api.handle(req)
		check(r.status == 404 or r.status == 400, "%s -> %d" % [path, r.status])
		check(r.file_path == "", "no file for " + path)
	rig.shutdown()


# -- fuzz ----------------------------------------------------------------------------------------

## Every client -> game message type of the protocol, with its fields.
static func _client_messages() -> Dictionary:
	var out := {}
	for table: Dictionary in [Protocol.SCHEMA, ProtocolParty.SCHEMA, ProtocolWatch.SCHEMA, ProtocolResume.SCHEMA, ProtocolAdmin.SCHEMA, ProtocolCluster.SCHEMA, ProtocolTrade.SCHEMA]:
		for type: String in table:
			if str(table[type][0]) == Protocol.C2S:
				out[type] = table[type][2]
	return out


static func _junk(rng: RandomNumberGenerator, depth := 0) -> Variant:
	match rng.randi() % 14:
		0: return null
		1: return rng.randi_range(-3, 3)
		2: return rng.randi()
		3: return -rng.randi()
		4: return rng.randf_range(-1e9, 1e9)
		5: return 1e300
		6: return ""
		7: return "x".repeat(rng.randi_range(1, 2000))
		8: return ["../../etc", "%s%d", "{}", "\u0000", "é€𝄞", "res://project.godot", "/tp 1 1"].pick_random()
		9: return rng.randi() % 2 == 0
		10: return [] if depth > 2 else [_junk(rng, depth + 1), _junk(rng, depth + 1)]
		11: return {} if depth > 2 else {"a": _junk(rng, depth + 1), "t": _junk(rng, depth + 1)}
		12: return 9223372036854775807
		_: return rng.randi_range(0, 600)


static func _fuzz_message(rng: RandomNumberGenerator, types: Dictionary) -> Dictionary:
	var names := types.keys()
	var type: String = names[rng.randi() % names.size()]
	var msg := {"t": type}
	for field: String in types[type]:
		if rng.randi() % 8 != 0: # sometimes a missing field
			msg[field] = _junk(rng) if rng.randi() % 3 == 0 else _plausible(rng, str(types[type][field]))
	if rng.randi() % 10 == 0:
		msg[["x", "t0", "id", "cell"].pick_random()] = _junk(rng)
	if rng.randi() % 25 == 0:
		msg["t"] = _junk(rng)
	return msg


## A value of the declared type that is often accepted by the schema (so that the rules run).
static func _plausible(rng: RandomNumberGenerator, kind: String) -> Variant:
	match kind:
		"int": return [0, 1, -1, 14, 293, 300, 559, 683, 1000, 154010371, 1040662, 2147483647, rng.randi_range(0, 600)].pick_random()
		"num": return rng.randf_range(-5.0, 600.0)
		"str": return ["", "a", "top", "left", "Hero", "strength", "global", "/tp 1 1", "x".repeat(300)].pick_random()
		"bool": return rng.randi() % 2 == 0
		"array": return [rng.randi_range(0, 20), rng.randi_range(0, 20)] if rng.randi() % 2 == 0 else []
		"dict": return {"a": rng.randi_range(0, 3)}
	return _junk(rng)


func test_fuzzed_commands_never_break_the_sim() -> void:
	var types := _client_messages()
	check(types.size() > 40, "the protocol lists its commands: %d" % types.size())
	types.erase(Protocol.HELLO) # a fuzzed hello is fine too, but it would restart the session each time
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261004
	var sent := 0
	for round in 6:
		var server := Players._server()
		var a := Players.Conn.new(server, "Alice", LOOK, "alice")
		var b := Players.Conn.new(server, "Bob", LOOK, "bob")
		if round % 2 == 1: # also while a fight is on
			var group: MonsterGroup = a.sim().get_map(1).actors.values().filter(func(x: SimActor) -> bool: return x is MonsterGroup)[0]
			a.send(Protocol.fight_attack(group.id))
			a.run(0.2)
		for i in 400:
			var msg := _fuzz_message(rng, types)
			# through JSON like the network: the numbers come back as floats
			var wire: Variant = JSON.parse_string(JSON.stringify(msg))
			if not wire is Dictionary:
				continue
			(a if i % 2 == 0 else b).backend.send(wire)
			sent += 1
			if i % 20 == 0:
				a.run(0.1)
				b.run(0.1)
		a.run(1.0)
		b.run(1.0)
		check(server.worlds.has("duo"), "the world is still there")
		check(a.sim().players.size() <= 2, "no phantom players")
		a.events.clear()
		b.events.clear()
		# the sim still answers a plain command after the storm
		a.send(Protocol.list_characters())
		a.run(0.3)
		check(not a.events.is_empty() or a.backend.player_id != 0, "still answering")
	check(sent > 2000, "fuzzed %d messages" % sent)


func test_garbage_on_the_wire_never_breaks_the_host() -> void:
	var rig := Rig.new(false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var texts := ["", "null", "[]", "[1,2", "{\"t\":", "{\"t\":null}", "{\"t\":[]}", "\"str\"", "12", "{\"t\":\"hello\"}", "{\"t\":\"hello\",\"v\":\"x\",\"world\":5}",
		"{\"t\":\"admin_cmd\",\"cmd\":{}}", "[".repeat(5000), "{\"a\":".repeat(1000), "\u0000\u0001\u0002", "{\"t\":\"ping\",\"t0\":\"x\"}"]
	for i in 3:
		var p := rig.raw()
		check(rig.open(p))
		for j in 40:
			if j % 5 == 4:
				var bytes := PackedByteArray()
				bytes.resize(rng.randi_range(1, 400))
				for k in bytes.size():
					bytes[k] = rng.randi() & 255
				p.send(bytes) # binary frames
			else:
				p.send_text(texts[rng.randi() % texts.size()])
		rig.run(1.0)
	rig.run(0.5)
	# a clean client still gets served
	var q := rig.raw()
	check(rig.open(q))
	q.send_text(JSON.stringify(Protocol.ping(5)))
	rig.run(0.5)
	check(rig.received(q).any(func(e: Dictionary) -> bool: return e["t"] == Protocol.PONG), "the host still answers")
	rig.shutdown()


# -- S.05c: costly commands, automatic ban, hashing off the main thread ----------------------------

func _login_and_wait(rig: Rig, p: WebSocketPeer, cmd: Dictionary) -> Dictionary:
	p.send_text(JSON.stringify(cmd))
	for k in 400:
		rig.run(0.05, false)
		for e in rig.received(p):
			if e["t"] == Protocol.LOGIN_OK or e["t"] == Protocol.LOGIN_ERROR:
				return e
		OS.delay_msec(2)
	return {}


func test_the_hashing_does_not_block_the_tick() -> void:
	var rig := Rig.new()
	(rig.host.auth.accounts as AccountStore).iterations = 400000 # ~0.4 s of hashing
	var p := rig.raw()
	check(rig.open(p))
	p.send_text(JSON.stringify(Protocol.register("slowhash", "secret1")))
	var polls := 0
	var t0 := Time.get_ticks_msec()
	var worst := 0
	var answer := {}
	while answer.is_empty() and Time.get_ticks_msec() - t0 < 10000:
		var t1 := Time.get_ticks_usec()
		rig.run(0.05, false)
		worst = maxi(worst, Time.get_ticks_usec() - t1)
		polls += 1
		for e in rig.received(p):
			if e["t"] == Protocol.LOGIN_OK:
				answer = e
		OS.delay_msec(2)
	check(not answer.is_empty(), "registered")
	check(polls > 3, "the host kept polling while the thread hashed: %d polls" % polls)
	check(worst < 150000, "no poll waited for the hash: worst %d us" % worst)
	check(rig.host.auth.accounts.check("slowhash", "secret1") == "", "the account is usable")
	rig.shutdown()


func test_costly_commands_are_limited_per_session() -> void:
	var rig := Rig.new(false)
	rig.host.costly_burst = 3.0
	rig.host.costly_per_sec = 0.5
	var p := rig.raw()
	check(rig.open(p))
	for i in 8:
		p.send_text(JSON.stringify(Protocol.chat_send("g", "hello %d" % i)))
	rig.run(0.3, false)
	var limited := _codes(rig.received(p)).count(ProtocolSecurity.E_RATE_LIMITED)
	eq(limited, 5, "three pass, five are refused")
	eq(p.get_ready_state(), WebSocketPeer.STATE_OPEN, "the connection stays")
	rig.run(4.0) # two tokens come back
	p.send_text(JSON.stringify(Protocol.chat_send("g", "again")))
	rig.run(0.3, false)
	check(not _codes(rig.received(p)).has(ProtocolSecurity.E_RATE_LIMITED), "served again")
	rig.shutdown()


func test_an_address_cut_several_times_is_banned_for_a_while() -> void:
	var pen := AddressPenalties.new()
	pen.max_cuts = 3
	pen.window_ms = 1000
	pen.ban_ms = 5000
	check(not pen.cut("1.2.3.4", 0))
	check(not pen.cut("1.2.3.4", 100))
	check(not pen.is_banned("1.2.3.4", 200))
	check(pen.cut("1.2.3.4", 200), "the third cut bans")
	check(pen.is_banned("1.2.3.4", 4000))
	check(not pen.is_banned("5.6.7.8", 4000), "another address is free")
	check(not pen.is_banned("1.2.3.4", 5300), "the ban ends")
	check(not pen.cut("9.9.9.9", 0))
	check(not pen.cut("9.9.9.9", 2000), "cuts far apart do not add up")
	check(not pen.cut("9.9.9.9", 4000))
	pen.enabled = false
	check(not pen.cut("9.9.9.9", 4001) and not pen.cut("9.9.9.9", 4002) and not pen.cut("9.9.9.9", 4003), "off")


func test_the_host_bans_an_address_it_keeps_cutting() -> void:
	var rig := Rig.new(false)
	rig.host.max_strikes = 3
	rig.host.penalties.max_cuts = 2
	rig.host.penalties.ban_ms = 60000
	for round in 2:
		var p := rig.raw()
		check(rig.open(p), "round %d connects" % round)
		for i in 200:
			p.send_text(JSON.stringify(Protocol.list_characters()))
		rig.run(0.5, false)
		check(rig.closed(p), "cut %d" % round)
	check(rig.host.penalties.is_banned("127.0.0.1", rig.virtual_ms), "banned")
	var refused := rig.host.refused_connections
	var p3 := rig.raw()
	rig.run(1.0)
	check(rig.host.refused_connections > refused, "the connection of a banned address is refused")
	check(not (p3.get_ready_state() == WebSocketPeer.STATE_OPEN), "and never opens")
	rig.run(61.0) # the ban ends
	var p4 := rig.raw()
	check(rig.open(p4), "welcome back")
	rig.shutdown()
