## Duels between two players (roadmap P3.10): the messages, the challenge (request, accept, decline,
## expiry, refusals), the fight of kind duel (two teams of one player, nothing won or lost: no XP,
## no kamas, no energy, no death, HP given back) through two LocalBackends, and the same flow over
## WebSockets (two NetBackends on 127.0.0.1).
extends TestCase

const Players := preload("res://tests/test_players.gd")
const NetTests := preload("res://tests/test_net.gd")


func _init() -> void:
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()
	SpellBook.use_file("res://tests/fixtures/spells.json")


func _pair() -> Array:
	var server := Players._server()
	var a := Players.Conn.new(server, "Alice", Players.LOOK, "alice")
	var b := Players.Conn.new(server, "Bob", Players.LOOK, "bob")
	Players._run([a, b], 0.2)
	for c: Players.Conn in [a, b]:
		c.events.clear()
	return [a, b]


## Alice challenges Bob, who accepts: the duel is on. Returns the Fight.
func _open(t: Array) -> Fight:
	(t[0] as Players.Conn).send(ProtocolDuel.request("Bob"))
	Players._run(t, 0.1)
	(t[1] as Players.Conn).send(ProtocolDuel.accept("Alice"))
	Players._run(t, 0.1)
	return (t[0] as Players.Conn).sim().fights.values()[0]


static func _codes(c: Players.Conn) -> Array:
	return c.take(Protocol.ERROR).map(func(e: Dictionary) -> String: return str(e["code"]))


static func _ends(c: Players.Conn) -> Array:
	return c.take(ProtocolDuel.END).map(func(e: Dictionary) -> String: return str(e["reason"]))


func test_messages_match_the_schema() -> void:
	eq(ProtocolDuel.C2S, Protocol.C2S)
	eq(ProtocolDuel.S2C, Protocol.S2C)
	for m: Dictionary in [ProtocolDuel.request("Bob"), ProtocolDuel.accept("A"), ProtocolDuel.decline("A")]:
		eq(Protocol.validate(Protocol.roundtrip(m), Protocol.C2S), "", str(m))
	for m: Dictionary in [ProtocolDuel.requested("A"), ProtocolDuel.end("declined")]:
		eq(Protocol.validate(Protocol.roundtrip(m), Protocol.S2C), "", str(m))
	check(Protocol.validate(ProtocolDuel.requested("A"), Protocol.C2S) != "", "an event is no command")
	for code: String in ProtocolDuel.ERROR_CODES:
		check(Protocol.ERROR_CODES.has(code) and ErrorTexts.TEXTS.has(code), "%s is listed and has its text" % code)


func test_accepting_a_challenge_starts_a_duel_of_two_teams() -> void:
	var t := _pair()
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	a.send(ProtocolDuel.request("Bob"))
	Players._run(t, 0.1)
	eq(b.take(ProtocolDuel.REQUESTED).map(func(e: Dictionary) -> String: return str(e["from"])), ["Alice"], "Bob is challenged")
	check(a.sim().fights.is_empty(), "no fight before the answer")
	b.send(ProtocolDuel.accept("Alice"))
	Players._run(t, 0.1)
	var fight: Fight = a.sim().fights.values()[0]
	eq(fight.kind, Fight.KIND_DUEL)
	eq([a.player().fight_id, b.player().fight_id], [fight.id, fight.id])
	var sa: Dictionary = a.take(Protocol.FIGHT_START)[0]
	var sb: Dictionary = b.take(Protocol.FIGHT_START)[0]
	eq([int(sa["you"]), int(sb["you"])], [a.backend.player_id, b.backend.player_id], "each one its own fighter")
	var teams := {}
	for f: Dictionary in sa["fighters"]:
		teams[int(f["id"])] = int(f["team"])
	eq([teams[a.backend.player_id], teams[b.backend.player_id]], [0, 1], "the challenger is team 0, the challenged team 1")
	eq(teams.size(), 2, "only the two of them")
	check(fight.options["locked"], "nobody joins a duel")
	fight.options["locked"] = false # even unlocked by its leader
	eq(fight.join_error(true), Protocol.E_FIGHT_LOCKED)
	eq(fight.join_error(false, true), "", "but it can be watched")
	var map := a.sim().get_map(1)
	check(not map.actors.has(a.backend.player_id) and not map.actors.has(b.backend.player_id), "both left the map")
	check((fight.placement[0] as Array).has(fight.fighters[a.backend.player_id].cell) and (fight.placement[1] as Array).has(fight.fighters[b.backend.player_id].cell), "each on its own placement cells")
	# both ready: the fight begins, and a player plays each turn
	a.send(Protocol.fight_ready())
	b.send(Protocol.fight_ready())
	Players._run(t, 0.2)
	eq(fight.phase, "fight")
	check(a.take(Protocol.FIGHT_BEGIN).size() == 1 and b.take(Protocol.FIGHT_BEGIN).size() == 1)
	check(not fight.current().ai, "no AI plays")


func test_a_duel_gains_and_loses_nothing() -> void:
	var t := _pair()
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	var kamas := [a.player().character.kamas, b.player().character.kamas]
	var energy := [a.player().character.energy, b.player().character.energy]
	var xp := [a.player().character.xp, b.player().character.xp]
	var hp_before: int = b.player().character.hp_at(b.sim().now)
	var fight := _open(t)
	a.send(Protocol.fight_ready())
	b.send(Protocol.fight_ready())
	Players._run(t, 0.2)
	# side by side, both nearly dead: the one who plays kills the other
	var fa: Fighter = fight.fighters[a.backend.player_id]
	var fb: Fighter = fight.fighters[b.backend.player_id]
	fb.cell = FightRules.neighbors4(fa.cell).filter(func(x: int) -> bool: return fight.map.is_fight_walkable(x))[0]
	fa.hp = 1
	fb.hp = 1
	var winner: Players.Conn = a if fight.current() == fa else b
	var foe: Fighter = fb if winner == a else fa
	var loser: Players.Conn = b if winner == a else a
	winner.send(Protocol.fight_cast(1, foe.cell))
	Players._run(t, 0.3)
	check(a.sim().fights.is_empty(), "the duel is over")
	var we: Dictionary = winner.take(Protocol.FIGHT_END)[0]
	var le: Dictionary = loser.take(Protocol.FIGHT_END)[0]
	eq([we["result"], le["result"]], ["win", "lose"], "each told from its own side")
	eq([(we["rewards"] as Array).size(), (le["rewards"] as Array).size()], [0, 0], "no reward")
	eq([a.player().fight_id, b.player().fight_id], [0, 0])
	var map := a.sim().get_map(1)
	check(map.actors.has(a.backend.player_id) and map.actors.has(b.backend.player_id), "both are back on the map")
	eq([a.player().character.kamas, b.player().character.kamas], kamas)
	eq([a.player().character.energy, b.player().character.energy], energy, "no energy lost")
	eq([a.player().character.xp, b.player().character.xp], xp)
	check(not a.player().character.is_ghost() and not b.player().character.is_ghost(), "nobody is a ghost")
	eq(loser.player().character.hp_at(loser.sim().now), hp_before, "the HP are what they were")
	eq(winner.player().character.hp_at(winner.sim().now), hp_before, "also for the winner")


func test_giving_up_a_duel_loses_it_without_a_penalty() -> void:
	var t := _pair()
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	var energy: int = a.player().character.energy
	_open(t)
	a.take(Protocol.FIGHT_START)
	b.send(Protocol.fight_leave()) # the challenged one gives up
	Players._run(t, 0.2)
	eq([str(a.take(Protocol.FIGHT_END)[0]["result"]), str(b.take(Protocol.FIGHT_END)[0]["result"])], ["win", "lose"])
	eq(a.player().character.energy, energy)
	check(b.sim().fights.is_empty(), "the fight is gone")
	eq(b.player().fight_id, 0)


func test_a_disconnection_gives_the_duel_to_the_other() -> void:
	var t := _pair()
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	_open(t)
	a.take(Protocol.FIGHT_START)
	b.take(Protocol.FIGHT_START)
	a.sim().disconnect_player(a.backend.player_id)
	Players._run(t, 0.2)
	eq(str(b.take(Protocol.FIGHT_END)[0]["result"]), "win", "Bob wins")
	eq(b.player().fight_id, 0)
	check(not b.player().character.is_ghost(), "and he is free")


func test_declining_expiring_and_refusals() -> void:
	var t := _pair()
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	# declined
	a.send(ProtocolDuel.request("Bob"))
	Players._run(t, 0.1)
	b.send(ProtocolDuel.decline("Alice"))
	Players._run(t, 0.1)
	eq(_ends(a), ["declined"])
	b.send(ProtocolDuel.accept("Alice"))
	Players._run(t, 0.1)
	eq(_codes(b), [ProtocolDuel.E_NO_DUEL_REQUEST], "a declined challenge is gone")
	b.send(ProtocolDuel.decline("Nobody"))
	Players._run(t, 0.1)
	eq(_codes(b), [ProtocolDuel.E_NO_DUEL_REQUEST])
	# expired
	a.send(ProtocolDuel.request("Bob"))
	Players._run(t, 0.1)
	a.server.tick(ProtocolDuel.INVITE_TTL_MS + 1000)
	Players._run(t, 0.1)
	eq(_ends(a), ["expired"])
	b.send(ProtocolDuel.accept("Alice"))
	Players._run(t, 0.1)
	eq(_codes(b), [ProtocolDuel.E_NO_DUEL_REQUEST], "an expired challenge cannot be accepted")
	# offline, oneself, another map
	a.send(ProtocolDuel.request("Nobody"))
	a.send(ProtocolDuel.request("Alice"))
	Players._run(t, 0.1)
	eq(_codes(a), [Protocol.E_PLAYER_OFFLINE, Protocol.E_PLAYER_OFFLINE])
	b.sim().teleport(b.player(), 2, 300)
	Players._run(t, 0.1)
	a.send(ProtocolDuel.request("Bob"))
	Players._run(t, 0.1)
	eq(_codes(a), [Protocol.E_NO_TARGET], "the challenged player must be on the same map")
	# a challenge does not follow a player who left the map
	b.sim().teleport(b.player(), 1, 300)
	a.send(ProtocolDuel.request("Bob"))
	Players._run(t, 0.1)
	b.sim().teleport(b.player(), 2, 300)
	b.send(ProtocolDuel.accept("Alice"))
	Players._run(t, 0.1)
	eq(_codes(b), [ProtocolDuel.E_NO_DUEL_REQUEST])
	check(a.sim().fights.is_empty(), "no duel")


func test_busy_players_cannot_duel() -> void:
	var t := _pair()
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	# in a trade
	a.send(ProtocolTrade.invite("Bob"))
	Players._run(t, 0.1)
	b.send(ProtocolTrade.accept("Alice"))
	Players._run(t, 0.1)
	a.send(ProtocolDuel.request("Bob"))
	Players._run(t, 0.1)
	eq(_codes(a), [ProtocolDuel.E_DUEL_BUSY], "no duel during a trade")
	a.send(ProtocolTrade.cancel())
	Players._run(t, 0.1)
	# in a duel: no second one, no trade
	_open(t)
	a.take(Protocol.FIGHT_START)
	a.send(ProtocolDuel.request("Bob"))
	b.send(ProtocolTrade.invite("Alice"))
	Players._run(t, 0.1)
	eq(_codes(a), [Protocol.E_IN_FIGHT], "a fighter only sends the commands of the fight")
	eq(_codes(b), [Protocol.E_IN_FIGHT])
	# a third player cannot challenge a fighter
	var c := Players.Conn.new(a.server, "Carl", Players.LOOK, "carl")
	t.append(c)
	Players._run(t, 0.2)
	c.events.clear()
	c.send(ProtocolDuel.request("Alice"))
	Players._run(t, 0.1)
	eq(_codes(c), [ProtocolDuel.E_DUEL_BUSY])


# -- the same over WebSockets ----------------------------------------------------------------

func test_duel_over_websocket() -> void:
	var rig := NetTests.Rig.new()
	var a := rig.client("tiny", "Alice")
	rig.run(2.0, func() -> bool: return a.has(Protocol.MAP_ENTER))
	var b := rig.client("tiny", "Bob")
	rig.run(2.0, func() -> bool: return b.has(Protocol.MAP_ENTER))
	var sim := rig.sim()
	var kamas: int = sim.players[b.you].character.kamas
	a.backend.send(ProtocolDuel.request("Bob"))
	check(rig.run(2.0, func() -> bool: return b.has(ProtocolDuel.REQUESTED)), "Bob is challenged through the server")
	b.backend.send(ProtocolDuel.accept("Alice"))
	check(rig.run(2.0, func() -> bool: return a.has(Protocol.FIGHT_START) and b.has(Protocol.FIGHT_START)), "both enter the duel")
	var sb: Dictionary = b.take(Protocol.FIGHT_START)[0]
	eq(int(sb["you"]), b.you, "ids survive the JSON round trip as ints")
	var teams := (sb["fighters"] as Array).map(func(f: Dictionary) -> int: return int(f["team"]))
	teams.sort()
	eq(teams, [0, 1])
	a.backend.send(Protocol.fight_ready())
	b.backend.send(Protocol.fight_ready())
	check(rig.run(2.0, func() -> bool: return a.has(Protocol.FIGHT_BEGIN) and b.has(Protocol.FIGHT_BEGIN)), "the fight begins")
	b.backend.send(Protocol.fight_leave())
	check(rig.run(2.0, func() -> bool: return a.has(Protocol.FIGHT_END) and b.has(Protocol.FIGHT_END)), "the duel ends for both")
	eq([a.take(Protocol.FIGHT_END)[0]["result"], b.take(Protocol.FIGHT_END)[0]["result"]], ["win", "lose"])
	eq(sim.players[b.you].character.kamas, kamas, "nothing lost")
	eq(sim.fights.size(), 0)
	# a refusal comes back with its ref, a decline reaches the challenger
	a.backend.send(ProtocolDuel.accept("Bob"))
	check(rig.run(2.0, func() -> bool: return a.has(Protocol.ERROR)), "an error comes back")
	var err: Dictionary = a.take(Protocol.ERROR)[0]
	eq([str(err["code"]), err.has("ref")], [ProtocolDuel.E_NO_DUEL_REQUEST, true])
	a.backend.send(ProtocolDuel.request("Bob"))
	rig.run(0.5)
	b.backend.send(ProtocolDuel.decline("Alice"))
	check(rig.run(2.0, func() -> bool: return a.has(ProtocolDuel.END)), "Alice learns of the refusal")
	eq(a.backend.schema_errors.size() + b.backend.schema_errors.size(), 0, "every event matches the schema: %s" % [a.backend.schema_errors])
	rig.host.shutdown()
