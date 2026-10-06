## Network hosting (roadmap S.01): a ServerHost listens on 127.0.0.1 in this very
## process, NetBackend clients play through real WebSockets. Time is virtual
## (each pump = one step, no sleeping) except in test_clock_with_the_real_clock.
extends TestCase

const LOOK := "{1|120,2195||56}"
const STEP := 0.05


## A host and its clients, pumped together.
class Rig:
	static func _world() -> WorldSource:
		return WorldSource.from_dicts(
			{"id": "tiny", "name": "Tiny", "start_map": 1, "start_cell": 300},
			[{"id": 1, "coords": [0, 0], "neighbors": {"right": 2}},
			 {"id": 2, "coords": [1, 0], "neighbors": {"left": 1}}])

	var host := ServerHost.new()
	var clients: Array[Client] = []
	var virtual_ms := 0
	var real_time := false

	func _init() -> void:
		host.server.sources["tiny"] = _world()
		host.listen(0, "127.0.0.1")

	func client(world := "tiny", name := "Tester") -> Client:
		var c := Client.new(self)
		c.backend.connect_to("127.0.0.1:%d" % host.local_port())
		if world != "":
			c.backend.send(Protocol.hello(world, name, LOOK))
		clients.append(c)
		return c

	## Pumps until `until` is true (true at once if empty) or `seconds` of game time passed.
	func run(seconds: float, until := Callable()) -> bool:
		var done := 0.0
		var last := Time.get_ticks_msec()
		while done < seconds:
			var step := STEP
			if real_time:
				OS.delay_msec(5)
				var now := Time.get_ticks_msec()
				step = (now - last) / 1000.0
				last = now
			virtual_ms += int(step * 1000.0)
			host.poll(step)
			for c in clients:
				c.backend.poll(step)
			done += step
			if until.is_valid() and until.call():
				return true
		return not until.is_valid()

	func sim() -> WorldSim:
		return host.server.worlds["tiny"]

	func sim_of(world: String) -> WorldSim:
		return host.server.worlds[world]


class Client:
	var backend := NetBackend.new()
	var events: Array = []
	var you := -1

	func _init(rig: Rig) -> void:
		backend.validate_events = true
		if not rig.real_time:
			backend.ticks = func() -> int: return rig.virtual_ms
		backend.event.connect(func(ev: Dictionary) -> void:
			events.append(ev)
			if ev["t"] == Protocol.WELCOME:
				you = int(ev["you"]))

	func has(type: String) -> bool:
		return events.any(func(e: Dictionary) -> bool: return e["t"] == type)

	func take(type: String) -> Array:
		var out := events.filter(func(e: Dictionary) -> bool: return e["t"] == type)
		events = events.filter(func(e: Dictionary) -> bool: return e["t"] != type)
		return out


func test_exploration_over_websocket() -> void:
	var rig := Rig.new()
	var c := rig.client()
	check(rig.run(5.0, func() -> bool: return c.has(Protocol.MAP_ENTER)), "welcome and map_enter arrive")
	eq(c.backend.state, "open")
	check(c.you > 0, "welcome carries our id")
	eq(int(c.take(Protocol.MAP_ENTER)[0]["map"]["id"]), 1)
	var edge := 20 * 14 + 13
	c.backend.send(Protocol.move(edge))
	check(rig.run(5.0, func() -> bool: return c.has(Protocol.ACTOR_MOVE)), "our walk is broadcast")
	rig.run(15.0)
	eq(rig.sim().players[c.you].cell, edge, "walked to the map edge")
	c.take(Protocol.MAP_ENTER)
	c.backend.send(Protocol.change_map("right"))
	check(rig.run(5.0, func() -> bool: return c.has(Protocol.MAP_ENTER)), "entered the neighbour map")
	eq(int(c.take(Protocol.MAP_ENTER)[0]["map"]["id"]), 2)
	c.backend.send(Protocol.move(293))
	rig.run(0.5)
	eq(c.take(Protocol.ERROR).size(), 0, "no error during the exploration")
	eq(c.backend.schema_errors.size(), 0, "every event matches Protocol.SCHEMA: %s" % [c.backend.schema_errors])
	c.backend.close()
	rig.run(1.0)
	eq(rig.sim().players.size(), 0, "closing the socket logs the character out")
	rig.host.shutdown()


func test_errors_come_back_with_their_seq() -> void:
	var rig := Rig.new()
	var c := rig.client()
	rig.run(1.0, func() -> bool: return c.has(Protocol.MAP_ENTER))
	c.backend.send(Protocol.move(9999))
	rig.run(1.0, func() -> bool: return c.has(Protocol.ERROR))
	var errs := c.take(Protocol.ERROR)
	eq(errs.size(), 1)
	eq(errs[0]["code"], Protocol.E_BAD_CELL)
	check(int(errs[0]["ref"]) > 1, "ref = seq of the refused command")
	rig.host.shutdown()


func test_unknown_world_and_allowed_list() -> void:
	var rig := Rig.new()
	var c := rig.client("nowhere")
	rig.run(1.0, func() -> bool: return c.has(Protocol.ERROR))
	eq(c.take(Protocol.ERROR)[0]["code"], Protocol.E_UNKNOWN_WORLD)
	rig.host.allowed_worlds = PackedStringArray(["other"])
	var d := rig.client("tiny")
	rig.run(1.0, func() -> bool: return d.has(Protocol.ERROR))
	eq(d.take(Protocol.ERROR)[0]["code"], Protocol.E_UNKNOWN_WORLD, "a world outside --world is refused")
	rig.host.shutdown()


func test_two_clients_share_the_world() -> void:
	var rig := Rig.new()
	var a := rig.client("tiny", "Alice")
	rig.run(1.0, func() -> bool: return a.has(Protocol.MAP_ENTER))
	var b := rig.client("tiny", "Bob")
	check(rig.run(2.0, func() -> bool: return a.take(Protocol.ACTOR_ADD).any(
			func(e: Dictionary) -> bool: return e["actor"]["name"] == "Bob")), "Alice sees Bob arrive")
	eq(rig.sim().players.size(), 2)
	a.take(Protocol.ACTOR_MOVE)
	b.backend.send(Protocol.move(310))
	check(rig.run(2.0, func() -> bool: return a.has(Protocol.ACTOR_MOVE)), "Alice sees Bob move")
	rig.host.shutdown()


## P3.01 over real sockets: look, name, class and level of the other, its walks, its
## departure through an exit and its disconnection; nothing private on Bob's wire.
func test_players_see_each_other_over_websocket() -> void:
	var rig := Rig.new()
	var a := rig.client("tiny", "Alice")
	rig.run(1.0, func() -> bool: return a.has(Protocol.MAP_ENTER))
	var b := rig.client("tiny", "Bob")
	rig.run(2.0, func() -> bool: return b.has(Protocol.MAP_ENTER))
	var present: Array = (b.take(Protocol.MAP_ENTER)[0]["actors"] as Array).filter(func(x: Dictionary) -> bool: return x["name"] == "Alice")
	eq(present.size(), 1, "Bob's map_enter has Alice")
	eq(present[0]["kind"], "player")
	check(int(present[0]["level"]) >= 1 and present[0].has("breed") and not (present[0]["looks"] as Array).is_empty(), "with her level, class and look")
	var edge := 20 * 14 + 13
	a.take(Protocol.ACTOR_MOVE)
	b.backend.send(Protocol.move(edge))
	check(rig.run(2.0, func() -> bool: return a.has(Protocol.ACTOR_MOVE)), "Alice sees Bob walk")
	rig.run(15.0)
	b.backend.send(Protocol.change_map("right"))
	check(rig.run(2.0, func() -> bool: return a.take(Protocol.ACTOR_REMOVE).any(
			func(e: Dictionary) -> bool: return int(e["id"]) == b.you)), "Alice sees Bob leave through the exit")
	rig.run(0.5)
	b.backend.close()
	rig.run(1.0)
	eq(rig.sim().players.size(), 1)
	eq(a.backend.schema_errors.size(), 0, "every event matches Protocol.SCHEMA")
	var others := a.events.filter(func(e: Dictionary) -> bool: return not e["t"] in [Protocol.PLAYER_STATS, Protocol.INVENTORY, Protocol.QUEST_LIST])
	var wire := JSON.stringify(others)
	check(not wire.contains("ip-127.0.0.1") and not wire.contains("kamas"), "no account or kamas of Bob outside Alice's own sheet")
	rig.host.shutdown()


func test_clock_converges_to_the_servers() -> void:
	var rig := Rig.new()
	rig.run(3.0) # the world exists and has been ticking for a while
	var c := rig.client()
	eq(c.backend.time_ms(), 0, "no clock before the first pong")
	rig.run(1.0)
	var gap := absi(c.backend.time_ms() - rig.sim().now)
	check(gap <= 100, "client clock within 100 ms of the server's (gap %d)" % gap)
	rig.run(25.0) # pings repeat: still in step
	gap = absi(c.backend.time_ms() - rig.sim().now)
	check(gap <= 100, "still in step after 25 s (gap %d)" % gap)
	var before := c.backend.time_ms()
	rig.run(0.2)
	check(c.backend.time_ms() >= before, "the clock never goes back")
	rig.host.shutdown()


func test_clock_with_the_real_clock() -> void:
	var rig := Rig.new()
	rig.real_time = true
	rig.run(0.5)
	var c := rig.client()
	rig.run(1.0)
	var gap := absi(c.backend.time_ms() - rig.sim().now)
	check(gap <= 60, "real clock: gap %d ms" % gap)
	check(c.backend.rtt_ms() >= 0, "rtt measured")
	rig.host.shutdown()


func test_refused_connection_is_an_error_event() -> void:
	var probe := TCPServer.new()
	probe.listen(0, "127.0.0.1")
	var port := probe.get_local_port()
	probe.stop() # nothing listens there any more
	var rig := Rig.new()
	var c := Client.new(rig)
	c.backend.connect_to("127.0.0.1:%d" % port)
	c.backend.send(Protocol.hello("tiny", "Tester", LOOK))
	rig.clients.append(c)
	check(rig.run(10.0, func() -> bool: return c.has(Protocol.ERROR)), "an error event, no exception")
	var err: Dictionary = c.take(Protocol.ERROR)[0]
	eq(err["code"], Protocol.E_NETWORK)
	eq(c.backend.state, "closed")
	check(c.backend.failure != "", "the reason is kept: " + c.backend.failure)
	c.backend.send(Protocol.move(5)) # sending on a closed backend is silent
	c.backend.poll(0.05)
	rig.host.shutdown()


func test_server_stop_is_an_error_event() -> void:
	var rig := Rig.new()
	var c := rig.client()
	rig.run(2.0, func() -> bool: return c.has(Protocol.MAP_ENTER))
	rig.host.shutdown()
	check(rig.run(5.0, func() -> bool: return c.has(Protocol.ERROR)), "the cut is reported")
	eq(c.take(Protocol.ERROR)[0]["code"], Protocol.E_NETWORK)
	eq(c.backend.state, "closed")
	eq(rig.sim().players.size(), 0, "shutdown logged the character out (saved)")


func test_garbage_frames_are_refused_not_fatal() -> void:
	var rig := Rig.new()
	var ws := WebSocketPeer.new()
	ws.connect_to_url("ws://127.0.0.1:%d" % rig.host.local_port())
	var texts: Array = []
	var sent := false
	for i in 200:
		rig.host.poll(STEP)
		ws.poll()
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN and not sent:
			sent = true
			ws.send_text("this is not json")
			ws.send_text("[1,2]")
			ws.send_text(JSON.stringify({"t": "ping", "t0": 5}))
		while ws.get_available_packet_count() > 0:
			texts.append(ws.get_packet().get_string_from_utf8())
		if texts.size() >= 3:
			break
		OS.delay_msec(2)
	eq(texts.size(), 3, "two errors and a pong: %s" % [texts])
	if texts.size() == 3:
		eq(JSON.parse_string(texts[0])["code"], Protocol.E_BAD_MESSAGE)
		eq(JSON.parse_string(texts[2])["t"], Protocol.PONG)
	eq(rig.host.connections, 1, "the connection stays up")
	ws.close()
	rig.host.shutdown()


func test_address_forms() -> void:
	var rig := Rig.new()
	for form: String in ["127.0.0.1:%d", "ws://127.0.0.1:%d", "  127.0.0.1:%d  "]:
		var c := Client.new(rig)
		rig.clients.append(c)
		c.backend.connect_to(form % rig.host.local_port())
		check(rig.run(3.0, func() -> bool: return c.backend.state == "open"), "connects with " + form)
		c.backend.close()
	rig.host.shutdown()


func test_ping_is_in_the_schema() -> void:
	eq(Protocol.validate(Protocol.ping(5), Protocol.C2S), "")
	eq(Protocol.validate(Protocol.pong(5, 99), Protocol.S2C), "")
	check(Protocol.validate({"t": "ping"}, Protocol.C2S) != "", "t0 is required")


## Bug "after two enemy deaths, one enemy stopped playing": the last enemy, hurt, ran into a corner
## and then ended every turn without doing anything. Played over the wire: the survivor keeps acting.
func test_the_last_hurt_enemy_in_a_corner_keeps_playing() -> void:
	var rig := Rig.new()
	var member := {"look": "{4907|||130}", "name": "Tofu", "level": 3, "hp": 100, "ap": 4, "mp": 3}
	rig.host.server.sources["arena"] = WorldSource.from_dicts(
		{"id": "arena", "name": "Arena", "start_map": 1, "start_cell": 300, "wander_ms": [600000, 600000]},
		[{"id": 1, "coords": [0, 0], "groups": [{"name": "Tofus", "members": [member, member, member]}]}])
	var c := rig.client("arena")
	rig.run(3.0, func() -> bool: return c.has(Protocol.MAP_ENTER))
	var group := -1
	for a: Dictionary in c.take(Protocol.MAP_ENTER)[0]["actors"]:
		if a["kind"] == "monster_group":
			group = int(a["id"])
	check(group >= 0, "a group on the map")
	c.backend.send(Protocol.fight_attack(group))
	rig.run(3.0, func() -> bool: return c.has(Protocol.FIGHT_START))
	c.backend.send(Protocol.fight_ready())
	rig.run(3.0, func() -> bool: return c.has(Protocol.FIGHT_BEGIN))
	var fight: Fight = rig.host.server.worlds["arena"].fights.values()[0]
	var foes := fight.fighters.values().filter(func(f: Fighter) -> bool: return f.team == 1)
	eq(foes.size(), 3)
	for i in 2: # two deaths
		(foes[i] as Fighter).alive = false
		(foes[i] as Fighter).hp = 0
	var last: Fighter = foes[2]
	var shot := {"ap": 3, "range": [2, 5], "range_boost": false, "los": false, "in_line": false, "need_free_cell": false,
			"need_taken_cell": false, "per_turn": 9, "per_target": 9, "cooldown": 0, "initial_cooldown": 0, "crit": 0,
			"area": {"shape": "point", "size": 0}, "crit_effects": [], "effects": [{"target": "enemies", "min": 5, "max": 5,
			"duration": 0, "delay": 0, "mask": "", "kind": "damage", "element": "neutral", "area": {"shape": "point", "size": 0}}]}
	last.own_spells = {9002: shot}
	last.spells = [9002]
	last.ai_profile = "" # read again from these spells
	last.cell = 0 # a corner: running away is impossible
	(fight.fighters[c.you] as Fighter).cell = MapGeometry.from_iso(MapGeometry.to_iso(300) + Vector2i(5, 5)) # the player is nearer to the middle: every cell it can reach is nearer to him
	last.hp = 10 # hurt enough to run (cautious: below 30 %)
	var acts := {"n": 0}
	var play := func() -> bool:
		for ev: Dictionary in c.events:
			if ev["t"] == Protocol.FIGHT_TURN and int(ev["id"]) == c.you:
				c.backend.send(Protocol.fight_end_turn())
			elif (ev["t"] == Protocol.FIGHTER_MOVE and int(ev["id"]) == last.id) or (ev["t"] == Protocol.SPELL_CAST and int(ev["caster"]) == last.id):
				acts["n"] += 1
				acts["turns"] = last.flee_turns
		c.events.clear()
		return acts["n"] > 0
	check(rig.run(120.0, play), "the survivor moves or casts instead of ending its turns doing nothing")
	check(int(acts.get("turns", 99)) <= 1, "and right away, not after %s turns of running" % acts.get("turns"))
	eq(c.backend.schema_errors.size(), 0, "every event matches Protocol.SCHEMA: %s" % [c.backend.schema_errors])
	c.backend.close()
	rig.host.shutdown()
