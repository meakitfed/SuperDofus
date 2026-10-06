## Automatic reconnection of the client (roadmap S.02c): NetBackend mends a cut by itself with
## resume{token}, tells how long it waits (net_reconnecting), gives up on a refused token, never
## comes back after close() or a removal. Real WebSockets on 127.0.0.1, virtual time (like
## test_resume).
extends TestCase

const Resume := preload("res://tests/test_resume.gd")


func _init() -> void:
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()
	SpellBook.use_file("res://tests/fixtures/spells.json")


## An account in a fight whose backend mends its own cuts.
static func _player(rig: Resume.Rig) -> Resume.Client:
	var c := rig.fighter()
	c.backend.auto_reconnect = true
	return c


## The network drops: the socket dies, no logout.
static func _cut(c: Resume.Client) -> void:
	c.backend._ws.close(4005, "network down")


func test_a_cut_is_mended_by_itself_and_the_state_replayed() -> void:
	var rig := Resume.Rig.new()
	var c := _player(rig)
	var token := c.backend.token
	c.events.clear()
	_cut(c)
	check(rig.run(3.0, func() -> bool: return c.has(ProtocolResume.NET_RECONNECTING)), "the cut is announced")
	var lost := c.take(ProtocolResume.NET_RECONNECTING)[0] as Dictionary
	eq([int(lost["attempt"]), int(lost["delay_ms"])], [1, 1000], "first try in 1 s")
	eq(c.backend.state, "reconnecting")
	check(c.backend.reconnecting)
	c.backend.send(Protocol.fight_end_turn()) # dropped: nothing is queued during the cut
	check(rig.run(10.0, func() -> bool: return c.has(ProtocolResume.RESUME_OK)), "the session is back")
	check(not c.backend.reconnecting and c.backend.state == "open", "open again")
	eq(c.backend.attempt, 0)
	eq(c.backend.token, token, "same session")
	check(rig.run(2.0, func() -> bool: return c.has(Protocol.FIGHT_TURN)), "the fight is replayed")
	check(c.has(Protocol.FIGHT_START) and c.has(Protocol.FIGHT_BEGIN), "from the start of the fight")
	eq(c.backend.schema_errors.size(), 0, "valid messages")
	var hero := Resume._hero(rig.sim())
	check(not hero.detached, "the fighter is attached again")
	rig.shutdown()


func test_the_waits_double_up_to_eight_seconds() -> void:
	var rig := Resume.Rig.new()
	var c := _player(rig)
	rig.host.shutdown() # nobody answers any more
	var seen: Array = []
	for step in 1800: # 90 s of virtual time (a try into the void waits for the connect timeout)
		rig.virtual_ms += 50
		c.backend.poll(0.05)
		for ev: Dictionary in c.take(ProtocolResume.NET_RECONNECTING):
			seen.append(int(ev["delay_ms"]))
	check(seen.size() >= 6, "several tries (%s)" % [seen])
	eq(seen.slice(0, 6), [1000, 2000, 4000, 8000, 8000, 8000], "1, 2, 4, 8, then 8 s")
	check(c.backend.reconnecting, "it keeps trying")


func test_a_refused_token_ends_the_backend_with_bad_token() -> void:
	var rig := Resume.Rig.new()
	rig.host.auth.park_ttl_ms = 500
	var c := _player(rig)
	_cut(c)
	check(rig.run(10.0, func() -> bool: return c.has(Protocol.LOGIN_ERROR)), "the token is refused")
	var err := c.take(Protocol.LOGIN_ERROR)[0] as Dictionary
	eq([str(err["code"]), str(err["cmd"])], [ProtocolResume.E_BAD_TOKEN, "resume"])
	eq(c.backend.state, "closed", "no more tries")
	eq(c.backend.failure, ProtocolResume.E_BAD_TOKEN)
	check(not c.backend.reconnecting and c.backend.token == "")
	c.take(ProtocolResume.NET_RECONNECTING) # the one of the cut
	rig.run(3.0)
	check(not c.has(ProtocolResume.NET_RECONNECTING), "and no new wait")
	rig.shutdown()


func test_close_never_reconnects() -> void:
	var rig := Resume.Rig.new()
	var c := _player(rig)
	c.backend.close()
	rig.run(3.0)
	eq(c.backend.state, "closed")
	check(not c.backend.reconnecting and not c.has(ProtocolResume.NET_RECONNECTING))
	eq(rig.host.auth.login_for_token(c.backend.token), "", "a clean logout ends the session")
	rig.shutdown()


func test_a_removed_player_does_not_come_back() -> void:
	var rig := Resume.Rig.new()
	var c := _player(rig)
	c.backend._ws.close(4003, "removed by a game master") # as _finish_kick does; the socket code decides
	c.backend._ws.poll()
	rig.run(2.0)
	check(not c.has(ProtocolResume.NET_RECONNECTING), "no reconnection after a removal")
	eq(c.backend.state, "closed")
	check(c.has(Protocol.ERROR), "a network error ends it")
	rig.shutdown()


func test_without_the_option_a_cut_is_final() -> void:
	var rig := Resume.Rig.new()
	var c := rig.fighter()
	_cut(c)
	rig.run(3.0)
	eq(c.backend.state, "closed")
	check(c.has(Protocol.ERROR) and not c.has(ProtocolResume.NET_RECONNECTING))
	rig.shutdown()


func test_before_login_nothing_is_retried() -> void:
	var rig := Resume.Rig.new()
	var c := rig.client()
	c.backend.auto_reconnect = true
	rig.run(1.0, func() -> bool: return c.backend.state == "open")
	_cut(c)
	rig.run(2.0)
	eq(c.backend.state, "closed", "no token, nothing to resume")
	rig.shutdown()


func test_the_banner_follows_the_events() -> void:
	var banner := ReconnectBanner.new()
	check(not banner.visible)
	banner.wait(2, 2000)
	check(banner.visible, "shown while waiting")
	check(banner._label.text.contains("essai 2"), banner._label.text)
	banner.clear()
	check(not banner.visible)
	banner.free()
