## Reconnection (roadmap S.02b): a cut in the middle of a fight, the return within the delay,
## the AI that takes over after it, expired tokens, the double connection that replaces an idle
## one. Real WebSockets on 127.0.0.1 in this process (like test_accounts), plus the sim rules
## through a LocalServer.
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
	var clients: Array[Client] = []
	var virtual_ms := 0

	func _init() -> void:
		var persistence := Persistence.new()
		host.server.persistence = persistence
		var tofu := {"look": "{4907|||130}", "name": "Tofu", "name_id": 5, "level": 1, "hp": 20, "ap": 4, "mp": 3, "xp": 10}
		host.server.sources["duo"] = WorldSource.from_dicts(
			{"id": "duo", "name": "Duo", "start_map": 1, "start_cell": 300, "wander_ms": [600000, 600000]},
			[{"id": 1, "coords": [0, 0], "neighbors": {"right": 2}, "groups": [{"name": "Tofu", "members": [tofu]}]},
			 {"id": 2, "coords": [1, 0], "neighbors": {"left": 1}}])
		var store := AccountStore.new(persistence)
		store.iterations = 1000
		host.auth = AuthService.new(store)
		host.ticks = func() -> int: return virtual_ms
		host.listen(0, "127.0.0.1")

	func sim() -> WorldSim:
		return host.server.world("duo")

	func client() -> Client:
		var c := Client.new(self)
		c.backend.connect_to("127.0.0.1:%d" % host.local_port())
		clients.append(c)
		return c

	func run(seconds: float, until := Callable()) -> bool:
		var done := 0.0
		while done < seconds:
			virtual_ms += int(STEP * 1000.0)
			host.poll(STEP)
			for c in clients:
				c.backend.poll(STEP)
			done += STEP
			if until.is_valid() and until.call():
				return true
		return not until.is_valid()

	func ask(c: Client, cmd: Dictionary, type: String) -> Dictionary:
		c.backend.send(cmd)
		run(5.0, func() -> bool: return c.has(type))
		var got := c.take(type)
		return got[0] if not got.is_empty() else {}

	## An account that plays Hero on the map, attacks the Tofu and is ready: the fight is on.
	func fighter(login := "jean") -> Client:
		var c := client()
		ask(c, Protocol.register(login, "secret1"), Protocol.LOGIN_OK)
		ask(c, Protocol.hello("duo", "Hero", LOOK), Protocol.MAP_ENTER)
		var group: MonsterGroup = sim().get_map(1).actors.values().filter(func(x: SimActor) -> bool: return x is MonsterGroup)[0]
		c.backend.send(Protocol.fight_attack(group.id))
		run(2.0, func() -> bool: return c.has(Protocol.FIGHT_START))
		c.backend.send(Protocol.fight_ready())
		run(2.0, func() -> bool: return c.has(Protocol.FIGHT_TURN))
		return c

	## The connection breaks without a logout (the client reports a lost network).
	func cut(c: Client) -> void:
		c.backend._fail("test cut")
		clients.erase(c)
		run(1.0, func() -> bool: return host.connections < clients.size() + 1)

	func shutdown() -> void:
		host.shutdown()


class Client:
	var backend := NetBackend.new()
	var events: Array = []

	func _init(rig: Rig) -> void:
		backend.validate_events = true
		backend.ticks = func() -> int: return rig.virtual_ms
		backend.event.connect(func(ev: Dictionary) -> void: events.append(ev))

	func has(type: String) -> bool:
		return events.any(func(e: Dictionary) -> bool: return e["t"] == type)

	func take(type: String) -> Array:
		var out := events.filter(func(e: Dictionary) -> bool: return e["t"] == type)
		events = events.filter(func(e: Dictionary) -> bool: return e["t"] != type)
		return out

	func types() -> Array:
		return events.map(func(e: Dictionary) -> String: return str(e["t"]))


static func _hero(sim: WorldSim) -> PlayerActor:
	return sim.players.values().filter(func(p: PlayerActor) -> bool: return p.name == "Hero")[0]


# -- the rules in the sim ---------------------------------------------------------------

func test_an_absent_player_passes_then_the_ai_plays() -> void:
	var server := Players._server()
	var a := Players.Conn.new(server, "Alice", Players.LOOK, "alice")
	var group: MonsterGroup = a.sim().get_map(1).actors.values().filter(func(x: SimActor) -> bool: return x is MonsterGroup)[0]
	a.send(Protocol.fight_attack(group.id))
	a.run(0.2)
	a.send(Protocol.fight_ready())
	a.run(0.2)
	var sim := a.sim()
	var fight: Fight = sim.fights.values()[0]
	var id := a.backend.player_id
	var f: Fighter = fight.fighters[id]
	check(sim.resume.detach(id), "a fighter stays when its connection drops")
	check(sim.players[id].detached)
	for i in 40: # 20 s: the absent player's turns are passed at once
		sim.tick(500)
		if fight.result != "":
			break
	eq(f.ai, false, "no AI before the delay")
	check(fight.fight_round > 1, "the rounds went on without the player")
	for i in 200: # past ABSENT_GRACE_MS
		sim.tick(500)
		if f.ai_takeover or fight.result != "":
			break
	check(f.ai_takeover or fight.result != "", "the AI took over after the delay")
	if fight.result == "":
		check(sim.resume.reattach(id), "the player is back")
		eq([f.ai, f.ai_takeover, f.absent_since], [false, false, -1], "and plays its own turns again")
		var t := sim.drain(id).map(func(e: Dictionary) -> String: return str(e["t"]))
		check(t.has(Protocol.WELCOME) and t.has(Protocol.FIGHT_START) and t.has(Protocol.FIGHT_TURN), "with the state of the fight")


func test_detach_outside_a_fight_keeps_nothing() -> void:
	var server := Players._server()
	var a := Players.Conn.new(server, "Alice", Players.LOOK, "alice")
	check(not a.sim().resume.detach(a.backend.player_id), "nothing to keep out of a fight")
	check(a.sim().players.has(a.backend.player_id), "detach itself changes nothing")
	check(not a.sim().resume.reattach(a.backend.player_id), "and there is nothing to take back")


func test_a_detached_player_is_released_when_the_fight_ends() -> void:
	var server := Players._server()
	var a := Players.Conn.new(server, "Alice", Players.LOOK, "alice")
	var group: MonsterGroup = a.sim().get_map(1).actors.values().filter(func(x: SimActor) -> bool: return x is MonsterGroup)[0]
	a.send(Protocol.fight_attack(group.id))
	a.run(0.2)
	var sim := a.sim()
	var id := a.backend.player_id
	check(sim.resume.detach(id))
	var fight: Fight = sim.fights.values()[0]
	fight.leave(fight.fighters[id], sim.now) # the only player: abandon
	sim.tick(50)
	check(not sim.players.has(id), "released once the fight is over (saved like a logout)")


# -- over real sockets ------------------------------------------------------------------

func test_cut_in_a_fight_then_resume_in_time() -> void:
	var rig := Rig.new()
	var a := rig.fighter()
	var token := a.backend.token
	var fight: Fight = rig.sim().fights.values()[0]
	rig.cut(a)
	var hero := _hero(rig.sim())
	check(hero.detached, "the hero stays in the world")
	check(rig.host.auth.is_parked("jean"), "the token waits")
	eq(rig.host.auth.login_for_token(token), "jean", "and is still valid")
	rig.run(3.0) # the fight goes on without the player
	var b := rig.client()
	var ok := rig.ask(b, ProtocolResume.resume(token), ProtocolResume.RESUME_OK)
	check(not ok.is_empty(), "the session is resumed")
	eq([str(ok["login"]), str(ok["token"])], ["jean", token])
	eq([str(ok["state"]["world"]), str(ok["state"]["name"]), bool(ok["state"]["playing"]), bool(ok["state"]["in_fight"])], ["duo", "Hero", true, true])
	check(rig.run(2.0, func() -> bool: return b.has(Protocol.FIGHT_TURN)), "the fight as it is now")
	var t := b.types()
	for need: String in [Protocol.WELCOME, Protocol.PLAYER_STATS, Protocol.INVENTORY, Protocol.FIGHT_START, Protocol.FIGHT_BEGIN]:
		check(t.has(need), "resume sends " + need)
	check(not hero.detached and rig.sim().players.has(hero.id), "the hero plays again")
	eq(rig.sim().fights.values()[0], fight, "the same fight")
	eq(b.backend.token, token)
	b.backend.send(Protocol.fight_end_turn())
	rig.run(0.5)
	eq(b.backend.schema_errors.size(), 0, "every event matches Protocol.SCHEMA")
	rig.shutdown()


func test_a_longer_cut_hands_the_fighter_to_the_ai() -> void:
	var rig := Rig.new()
	var a := rig.fighter()
	var token := a.backend.token
	var hero := _hero(rig.sim())
	var fight: Fight = rig.sim().fights.values()[0]
	var f: Fighter = fight.fighters[hero.id]
	rig.cut(a)
	var took := false
	for i in 400: # up to 200 s of game time with nobody connected
		rig.virtual_ms += 500
		rig.host.poll(0.5)
		if f.ai_takeover:
			took = true
			break
		if fight.result != "":
			break
	check(took or fight.result != "", "the AI took the absent fighter after the delay")
	check(not f.ai_takeover or f.ai, "an AI-driven fighter plays by itself")
	var b := rig.client()
	var ok := rig.ask(b, ProtocolResume.resume(token), ProtocolResume.RESUME_OK)
	check(not ok.is_empty(), "the player can still come back")
	if fight.result == "":
		eq([f.ai, f.ai_takeover], [false, false], "and takes its fighter back")
		check(bool(ok["state"]["in_fight"]))
	else:
		check(bool(ok["state"]["playing"]) and not bool(ok["state"]["in_fight"]), "the fight ended meanwhile: back on the map")
		check(rig.run(1.0, func() -> bool: return b.has(Protocol.MAP_ENTER)), "with the map")
	rig.shutdown()


func test_resume_outside_a_fight_replays_the_character() -> void:
	var rig := Rig.new()
	var a := rig.client()
	var ok := rig.ask(a, Protocol.register("jean", "secret1"), Protocol.LOGIN_OK)
	rig.ask(a, Protocol.hello("duo", "Hero", LOOK), Protocol.MAP_ENTER)
	rig.cut(a)
	check(rig.sim().players.is_empty(), "out of a fight, nobody is kept in the world")
	var b := rig.client()
	var r := rig.ask(b, ProtocolResume.resume(str(ok["token"])), ProtocolResume.RESUME_OK)
	eq([bool(r["state"]["playing"]), bool(r["state"]["in_fight"]), str(r["state"]["name"])], [true, false, "Hero"])
	check(rig.run(2.0, func() -> bool: return b.has(Protocol.MAP_ENTER)), "the map comes back")
	check(b.has(Protocol.WELCOME) and b.has(Protocol.PLAYER_STATS))
	eq(rig.sim().players.size(), 1)
	rig.shutdown()


func test_resume_before_choosing_a_character_gives_the_list() -> void:
	var rig := Rig.new()
	var a := rig.client()
	var ok := rig.ask(a, Protocol.register("jean", "secret1"), Protocol.LOGIN_OK)
	rig.ask(a, Protocol.hello("duo"), Protocol.CHARACTERS)
	rig.cut(a)
	var b := rig.client()
	var r := rig.ask(b, ProtocolResume.resume(str(ok["token"])), ProtocolResume.RESUME_OK)
	eq([bool(r["state"]["playing"]), str(r["state"]["world"])], [false, "duo"])
	check(rig.run(2.0, func() -> bool: return b.has(Protocol.CHARACTERS)), "the character list again")
	rig.shutdown()


func test_an_expired_token_is_refused() -> void:
	var rig := Rig.new()
	rig.host.auth.park_ttl_ms = 5000
	var a := rig.fighter()
	var token := a.backend.token
	rig.cut(a)
	rig.run(6.0) # past the token's life
	eq(rig.host.auth.login_for_token(token), "", "the token died")
	check(rig.sim().players.is_empty(), "and its character left the world")
	var b := rig.client()
	var err := rig.ask(b, ProtocolResume.resume(token), Protocol.LOGIN_ERROR)
	eq([str(err["code"]), str(err["cmd"])], [ProtocolResume.E_BAD_TOKEN, "resume"])
	var again := rig.ask(b, Protocol.login("jean", "secret1"), Protocol.LOGIN_OK)
	check(not again.is_empty(), "the password still opens a new session")
	check(str(again["token"]) != token)
	rig.shutdown()


func test_a_clean_logout_ends_the_session() -> void:
	var rig := Rig.new()
	var a := rig.fighter()
	var token := a.backend.token
	a.backend.close() # code 1000: the player leaves on purpose
	rig.run(1.0, func() -> bool: return rig.host.connections == 0)
	eq(rig.host.auth.login_for_token(token), "", "no resume after a logout")
	check(rig.sim().players.is_empty())
	rig.shutdown()


func test_bad_tokens_are_refused_and_guessing_is_cut() -> void:
	var rig := Rig.new()
	var a := rig.client()
	for i in AuthService.MAX_FAILURES - 1:
		var err := rig.ask(a, ProtocolResume.resume("0".repeat(64)), Protocol.LOGIN_ERROR)
		eq(str(err["code"]), ProtocolResume.E_BAD_TOKEN)
	rig.ask(a, ProtocolResume.resume("1".repeat(64)), Protocol.LOGIN_ERROR)
	check(rig.run(3.0, func() -> bool: return rig.host.connections == 0), "five wrong tokens cut the connection")
	rig.shutdown()


func test_resume_needs_a_server_with_accounts() -> void:
	var rig := Rig.new()
	rig.host.auth = null
	var a := rig.client()
	a.backend.send(ProtocolResume.resume("0".repeat(64)))
	rig.run(1.0)
	check(not a.has(ProtocolResume.RESUME_OK), "an open host has no sessions to resume")
	rig.shutdown()


# -- double connection ------------------------------------------------------------------

func test_a_live_connection_is_not_replaced_while_it_is_active() -> void:
	var rig := Rig.new()
	var a := rig.fighter()
	var b := rig.client()
	var refused := rig.ask(b, ProtocolResume.resume(a.backend.token), Protocol.LOGIN_ERROR)
	eq(str(refused["code"]), Protocol.E_ALREADY_CONNECTED)
	var refused2 := rig.ask(b, Protocol.login("jean", "secret1"), Protocol.LOGIN_ERROR)
	eq(str(refused2["code"]), Protocol.E_ALREADY_CONNECTED)
	check(not _hero(rig.sim()).detached, "the first connection is untouched")
	rig.shutdown()


func test_an_idle_connection_is_replaced_by_the_token() -> void:
	var rig := Rig.new()
	var a := rig.fighter()
	var token := a.backend.token
	rig.clients.erase(a) # its machine froze: no more pings, no more packets
	rig.run(rig.host.idle_ms / 1000.0 + 1.0)
	var b := rig.client()
	var ok := rig.ask(b, ProtocolResume.resume(token), ProtocolResume.RESUME_OK)
	check(not ok.is_empty(), "the token replaces the idle connection")
	check(bool(ok["state"]["in_fight"]), "the fight comes along")
	check(rig.run(2.0, func() -> bool: return b.has(Protocol.FIGHT_TURN)))
	eq(rig.host.connections, 1, "one connection left")
	var hero := _hero(rig.sim())
	check(not hero.detached)
	rig.shutdown()


func test_an_idle_connection_is_replaced_by_the_password() -> void:
	var rig := Rig.new()
	var a := rig.fighter()
	var token := a.backend.token
	rig.clients.erase(a)
	rig.run(rig.host.idle_ms / 1000.0 + 1.0)
	var b := rig.client()
	var ok := rig.ask(b, Protocol.login("jean", "secret1"), Protocol.LOGIN_OK)
	check(not ok.is_empty(), "a login replaces the idle connection too")
	eq(str(ok["token"]), token, "the session and its token are given to the owner")
	check(rig.run(2.0, func() -> bool: return b.has(ProtocolResume.RESUME_OK)), "the dropped session comes with it")
	var r: Dictionary = b.take(ProtocolResume.RESUME_OK)[0]
	check(bool(r["state"]["in_fight"]), "the fight comes back")
	check(rig.run(2.0, func() -> bool: return b.has(Protocol.FIGHT_TURN)))
	rig.shutdown()


# -- protocol ---------------------------------------------------------------------------

func test_resume_messages_match_the_schema() -> void:
	for msg: Dictionary in [ProtocolResume.resume("ab"), ProtocolResume.resume_ok("ab", "player", "jean", {"world": "duo"})]:
		eq(Protocol.validate(JSON.parse_string(JSON.stringify(msg)) as Dictionary), "", msg["t"])
	eq(Protocol.validate(ProtocolResume.resume("ab"), Protocol.C2S), "")
	eq(Protocol.validate(ProtocolResume.resume_ok("a", "b", "c", {}), Protocol.S2C), "")
	check(Protocol.validate({"t": "resume"}) != "", "the token is required")
	check(Protocol.ERROR_CODES.has(ProtocolResume.E_BAD_TOKEN) and ErrorTexts.TEXTS.has(ProtocolResume.E_BAD_TOKEN))
	eq(ProtocolResume.C2S, Protocol.C2S)
	eq(ProtocolResume.S2C, Protocol.S2C)
