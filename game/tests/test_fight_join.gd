## Joining a fight and watching one (roadmap P3.04): the swords on the map, a second player
## joining during the placement (8 per team), spectators who see everything and can do nothing,
## options (locked, party only, secret), fleeing while the others go on, shared rewards, and the
## same flow through NetBackends on 127.0.0.1.
extends TestCase

const Players := preload("res://tests/test_players.gd")
const NetTests := preload("res://tests/test_net.gd")


func _init() -> void:
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()
	SpellBook.use_file("res://tests/fixtures/spells.json")


func _conns(names: Array) -> Array:
	var server := Players._server()
	var out := []
	for n: String in names:
		out.append(Players.Conn.new(server, n, Players.LOOK, n.to_lower()))
	Players._run(out, 0.2)
	for c: Players.Conn in out:
		c.events.clear()
	return out


## The first of `t` attacks the group of map 1; everyone's events are drained. Returns the Fight.
func _start(t: Array) -> Fight:
	var a: Players.Conn = t[0]
	var group: MonsterGroup = a.sim().get_map(1).actors.values().filter(func(x: SimActor) -> bool: return x is MonsterGroup)[0]
	a.send(Protocol.fight_attack(group.id))
	Players._run(t, 0.2)
	return a.sim().fights.values()[0]


static func _codes(c: Players.Conn) -> Array:
	return c.take(Protocol.ERROR).map(func(e: Dictionary) -> String: return str(e["code"]))


static func _ints(a: Array) -> Array:
	return a.map(func(v: Variant) -> int: return int(v))


static func _swords(c: Players.Conn) -> Array:
	return c.take(Protocol.ACTOR_ADD).filter(func(e: Dictionary) -> bool: return e["actor"]["kind"] == "fight").map(func(e: Dictionary) -> Dictionary: return e["actor"])


# -- the swords on the map ------------------------------------------------------------

func test_a_fight_is_an_actor_of_the_map() -> void:
	var t := _conns(["Alice", "Bob", "Carl"])
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	var group: MonsterGroup = a.sim().get_map(1).actors.values().filter(func(x: SimActor) -> bool: return x is MonsterGroup)[0]
	var cell := group.cell
	a.send(Protocol.fight_attack(group.id))
	Players._run(t, 0.2)
	var swords := _swords(b)
	eq(swords.size(), 1, "Bob sees the swords appear")
	eq(int(swords[0]["id"]), a.sim().fights.keys()[0], "the actor id is the fight id")
	eq([_ints(swords[0]["teams"]), swords[0]["phase"], int(swords[0]["cell"])], [[1, 1], "placement", cell])
	check(Protocol.is_json_safe(swords[0]))


func test_a_newcomer_to_the_map_gets_the_swords() -> void:
	var server := Players._server()
	var a := Players.Conn.new(server, "Alice", Players.LOOK, "alice")
	var group: MonsterGroup = a.sim().get_map(1).actors.values().filter(func(x: SimActor) -> bool: return x is MonsterGroup)[0]
	a.send(Protocol.fight_attack(group.id))
	a.run(0.2)
	var c := Players.Conn.new(server, "Carl", Players.LOOK, "carl")
	var actors: Array = c.take(Protocol.MAP_ENTER)[0]["actors"]
	var kinds := actors.map(func(x: Dictionary) -> String: return str(x["kind"]))
	check(kinds.has("fight"), "the fight in progress is in map_enter")
	check(not kinds.has("monster_group"), "and the group is not")


func test_the_swords_go_when_the_fight_ends() -> void:
	var t := _conns(["Alice", "Bob"])
	var fight := _start(t)
	var id := fight.id
	(t[0] as Players.Conn).send(Protocol.fight_leave())
	Players._run(t, 0.3)
	var gone := (t[1] as Players.Conn).take(Protocol.ACTOR_REMOVE).map(func(e: Dictionary) -> int: return int(e["id"]))
	check(gone.has(id), "the swords are removed")


# -- joining --------------------------------------------------------------------------

func test_joining_during_the_placement() -> void:
	var t := _conns(["Alice", "Bob", "Carl"])
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	var c: Players.Conn = t[2]
	var fight := _start(t)
	b.events.clear()
	c.events.clear()
	b.send(ProtocolWatch.join(fight.id, 0))
	Players._run(t, 0.2)
	var start: Dictionary = b.take(Protocol.FIGHT_START)[0]
	eq([int(start["fight"]), int(start["you"])], [fight.id, b.backend.player_id])
	eq((start["fighters"] as Array).size(), 3, "Alice, Bob and the monster")
	check(b.take(Protocol.FIGHT_OPTIONS).size() == 1, "he gets the options")
	var joined: Dictionary = a.take(ProtocolWatch.JOINED)[0]
	eq(int(joined["fighter"]["id"]), b.backend.player_id, "Alice sees Bob join")
	eq(int(joined["fighter"]["team"]), 0)
	check(not (joined["order"] as Array).is_empty())
	eq(b.take(ProtocolWatch.JOINED).size(), 0, "Bob is not told of himself")
	var cells := (start["fighters"] as Array).filter(func(f: Dictionary) -> bool: return int(f["team"]) == 0).map(func(f: Dictionary) -> int: return int(f["cell"]))
	check(cells[0] != cells[1], "two different cells")
	check((fight.placement[0] as Array).has(fight.fighters[b.backend.player_id].cell), "on a placement cell")
	eq(b.player().fight_id, fight.id)
	check(not b.sim().get_map(1).actors.has(b.backend.player_id), "Bob left the map")
	check(c.take(Protocol.ACTOR_REMOVE).any(func(e: Dictionary) -> bool: return int(e["id"]) == b.backend.player_id), "Carl sees him go")
	# both ready: the fight begins and both can play
	a.send(Protocol.fight_ready())
	b.send(Protocol.fight_ready())
	Players._run(t, 0.2)
	eq(fight.phase, "fight")
	check(a.take(Protocol.FIGHT_BEGIN).size() == 1 and b.take(Protocol.FIGHT_BEGIN).size() == 1)
	eq(fight.order.size(), 3)


func test_the_placement_phase_is_the_only_time_to_join() -> void:
	var t := _conns(["Alice", "Bob"])
	var fight := _start(t)
	(t[0] as Players.Conn).send(Protocol.fight_ready())
	Players._run(t, 0.2)
	eq(fight.phase, "fight")
	(t[1] as Players.Conn).send(ProtocolWatch.join(fight.id, 0))
	Players._run(t, 0.2)
	eq(_codes(t[1]), [ProtocolWatch.E_FIGHT_STARTED])
	eq((t[1] as Players.Conn).player().fight_id, 0)
	check((t[1] as Players.Conn).sim().get_map(1).actors.has((t[1] as Players.Conn).backend.player_id), "he stays on the map")


func test_refusals() -> void:
	var t := _conns(["Alice", "Bob", "Carl"])
	var b: Players.Conn = t[1]
	b.send(ProtocolWatch.join(999, 0))
	b.send(ProtocolWatch.spectate(999))
	Players._run(t, 0.1)
	eq(_codes(b), [ProtocolWatch.E_NO_FIGHT, ProtocolWatch.E_NO_FIGHT])
	var fight := _start(t)
	b.send(ProtocolWatch.join(fight.id, 1))
	Players._run(t, 0.1)
	eq(_codes(b), [ProtocolWatch.E_BAD_TEAM], "the monsters' team is not for players")
	(t[0] as Players.Conn).send(Protocol.fight_option("locked", true))
	Players._run(t, 0.1)
	b.send(ProtocolWatch.join(fight.id, 0))
	Players._run(t, 0.1)
	eq(_codes(b), [Protocol.E_FIGHT_LOCKED])
	(t[0] as Players.Conn).send(Protocol.fight_option("locked", false))
	(t[0] as Players.Conn).send(Protocol.fight_option("party_only", true))
	Players._run(t, 0.1)
	b.send(ProtocolWatch.join(fight.id, 0))
	Players._run(t, 0.1)
	eq(_codes(b), [Protocol.E_FIGHT_PARTY_ONLY])
	# in the leader's group, the party-only fight opens
	(t[0] as Players.Conn).send(ProtocolParty.invite("Bob"))
	Players._run(t, 0.1)
	b.send(ProtocolParty.accept("Alice"))
	Players._run(t, 0.1)
	b.events.clear()
	b.send(ProtocolWatch.join(fight.id, 0))
	Players._run(t, 0.1)
	eq(b.take(Protocol.FIGHT_START).size(), 1, "a group member joins")
	# someone in a fight cannot join another one
	b.send(ProtocolWatch.join(fight.id, 0))
	Players._run(t, 0.1)
	eq(_codes(b), [Protocol.E_IN_FIGHT])


func test_eight_per_team() -> void:
	var fight := Fight.new(1, MapData.new(), 3, func(_ev: Dictionary) -> void: pass)
	fight.placement = {0: [], 1: [301]}
	for i in 10:
		(fight.placement[0] as Array).append(300 + 14 * i)
	var foe := Fighter.new()
	foe.id = 99
	foe.team = 1
	foe.cell = 301
	fight.add_fighter(foe)
	fight.start_placement(0)
	for i in 8:
		var f := Fighter.new()
		f.id = i + 1
		f.player_id = i + 1
		eq(fight.join(f, 0, 300), "", "fighter %d joins" % (i + 1))
	eq(fight.team_size(0), 8)
	var ninth := Fighter.new()
	ninth.id = 9
	eq(fight.join(ninth, 0, 300), ProtocolWatch.E_FIGHT_FULL, "the ninth does not")
	var cells := {}
	for f: Fighter in fight.fighters.values():
		cells[f.cell] = true
	eq(cells.size(), 9, "everyone has a cell of their own")
	# one leaves: room again
	(fight.fighters[3] as Fighter).left = true
	eq(fight.join(ninth, 0, 300), "")
	eq(fight.join(Fighter.new(), 1, 300), ProtocolWatch.E_BAD_TEAM)


# -- spectators -----------------------------------------------------------------------

func test_a_spectator_sees_everything_and_can_do_nothing() -> void:
	var t := _conns(["Alice", "Bob", "Carl"])
	var a: Players.Conn = t[0]
	var c: Players.Conn = t[2]
	var fight := _start(t)
	c.events.clear()
	c.send(ProtocolWatch.spectate(fight.id))
	Players._run(t, 0.2)
	var w: Dictionary = c.take(ProtocolWatch.WATCH)[0]
	eq([int(w["fight"]), w["phase"], int(w["turn"])], [fight.id, "placement", -1])
	eq((w["fighters"] as Array).size(), 2)
	check(c.take(Protocol.FIGHT_START).is_empty(), "a spectator is not a fighter")
	check(not c.sim().get_map(1).actors.has(c.backend.player_id), "he is off the map")
	eq(c.player().spectating, fight.id)
	# he gets the events, from the placement on
	a.send(Protocol.fight_ready())
	Players._run(t, 0.2)
	check(c.take(Protocol.FIGHTER_READY).size() == 1, "he sees Alice get ready")
	check(c.take(Protocol.FIGHT_BEGIN).size() == 1, "and the fight begin")
	check(c.take(Protocol.FIGHT_TURN).size() >= 1, "and the first turn")
	# nothing else is allowed
	for cmd: Dictionary in [Protocol.move(320), Protocol.fight_ready(), Protocol.fight_end_turn(), Protocol.fight_move(300),
			Protocol.fight_attack(1), ProtocolWatch.join(fight.id, 0), ProtocolWatch.spectate(fight.id)]:
		c.send(cmd)
	Players._run(t, 0.2)
	eq(_codes(c), [ProtocolWatch.E_SPECTATING, ProtocolWatch.E_SPECTATING, ProtocolWatch.E_SPECTATING, ProtocolWatch.E_SPECTATING,
			ProtocolWatch.E_SPECTATING, ProtocolWatch.E_SPECTATING, ProtocolWatch.E_SPECTATING])
	eq(fight.team_size(0), 1, "he did not join")
	# chat still works
	c.send(Protocol.chat_send("general", "bien joue"))
	Players._run(t, 0.2)
	eq(_codes(c), [])
	# he can leave and is back on the map
	c.send(Protocol.fight_leave())
	Players._run(t, 0.2)
	check(c.take(Protocol.MAP_ENTER).size() == 1, "back on the map")
	eq(c.player().spectating, 0)
	check(fight.spectators.is_empty())
	check(c.sim().get_map(1).actors.has(c.backend.player_id))
	a.events.clear()


func test_a_late_spectator_gets_the_state_of_the_fight() -> void:
	var t := _conns(["Alice", "Bob"])
	var fight := _start(t)
	(t[0] as Players.Conn).send(Protocol.fight_ready())
	Players._run(t, 0.2)
	(t[1] as Players.Conn).send(ProtocolWatch.spectate(fight.id))
	Players._run(t, 0.2)
	var w: Dictionary = (t[1] as Players.Conn).take(ProtocolWatch.WATCH)[0]
	eq(w["phase"], "fight")
	eq(int(w["turn"]), fight.current().id)
	eq(int(w["end"]), fight.turn_end)
	eq((w["order"] as Array).size(), 2)


func test_a_secret_fight_has_no_spectators() -> void:
	var t := _conns(["Alice", "Bob"])
	var fight := _start(t)
	(t[0] as Players.Conn).send(Protocol.fight_option("secret", true))
	Players._run(t, 0.1)
	(t[1] as Players.Conn).send(ProtocolWatch.spectate(fight.id))
	Players._run(t, 0.1)
	eq(_codes(t[1]), [Protocol.E_FIGHT_SECRET])
	check(fight.spectators.is_empty())
	check((t[1] as Players.Conn).sim().get_map(1).actors.has((t[1] as Players.Conn).backend.player_id))


func test_spectators_go_back_when_the_fight_ends() -> void:
	var t := _conns(["Alice", "Bob"])
	var fight := _start(t)
	var b: Players.Conn = t[1]
	b.send(ProtocolWatch.spectate(fight.id))
	Players._run(t, 0.2)
	b.events.clear()
	(t[0] as Players.Conn).send(Protocol.fight_leave())
	Players._run(t, 0.3)
	var end: Dictionary = b.take(Protocol.FIGHT_END)[0]
	eq(end["result"], "abandon")
	eq((end["rewards"] as Array).size(), 0, "nothing to win by watching")
	check(b.take(Protocol.MAP_ENTER).size() == 1)
	eq(b.player().spectating, 0)


func test_a_spectator_who_disconnects_leaves_the_audience() -> void:
	var t := _conns(["Alice", "Bob"])
	var fight := _start(t)
	(t[1] as Players.Conn).send(ProtocolWatch.spectate(fight.id))
	Players._run(t, 0.2)
	var b_sim: WorldSim = (t[1] as Players.Conn).sim()
	b_sim.disconnect_player((t[1] as Players.Conn).backend.player_id)
	check(fight.spectators.is_empty())
	(t[0] as Players.Conn).send(Protocol.fight_leave())
	Players._run([t[0]], 0.2)
	eq(b_sim.fights.size(), 0)


# -- two fighters ---------------------------------------------------------------------

func test_one_flees_the_others_go_on() -> void:
	var t := _conns(["Alice", "Bob"])
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	var fight := _start(t)
	b.send(ProtocolWatch.join(fight.id, 0))
	Players._run(t, 0.2)
	a.send(Protocol.fight_ready())
	b.send(Protocol.fight_ready())
	Players._run(t, 0.2)
	a.events.clear()
	b.events.clear()
	b.send(Protocol.fight_leave())
	Players._run(t, 0.3)
	eq(fight.result, "", "the fight goes on")
	check(a.sim().fights.has(fight.id))
	var left: Dictionary = a.take(ProtocolWatch.LEFT)[0]
	eq(int(left["id"]), b.backend.player_id)
	var end: Dictionary = b.take(Protocol.FIGHT_END)[0]
	eq([end["result"], (end["rewards"] as Array).size()], ["abandon", 0], "Bob leaves with nothing")
	eq(b.player().fight_id, 0)
	check(b.sim().get_map(1).actors.has(b.backend.player_id), "he is back on the map")
	eq(fight.team_size(0), 1)
	check(not fight.order.has(b.backend.player_id) or not fight.fighters[b.backend.player_id].alive)
	# Alice can still win: the rewards are hers alone
	for f: Fighter in fight.fighters.values():
		if f.team == 1:
			f.alive = false
			f.hp = 0
	fight._check_end()
	Players._run(t, 0.3)
	var done: Dictionary = a.take(Protocol.FIGHT_END)[0]
	eq(done["result"], "win")
	eq((done["rewards"] as Array).size(), 1)
	eq(b.take(Protocol.FIGHT_END).size(), 0, "nothing more for Bob")


func test_a_player_who_disconnects_does_not_end_the_fight() -> void:
	var t := _conns(["Alice", "Bob"])
	var fight := _start(t)
	(t[1] as Players.Conn).send(ProtocolWatch.join(fight.id, 0))
	Players._run(t, 0.2)
	(t[1] as Players.Conn).sim().disconnect_player((t[1] as Players.Conn).backend.player_id)
	check((t[0] as Players.Conn).sim().fights.has(fight.id), "Alice's fight is still there")
	eq(fight.result, "")
	eq(fight.team_size(0), 1)
	(t[0] as Players.Conn).send(Protocol.fight_ready())
	Players._run([t[0]], 0.2)
	eq(fight.phase, "fight", "the one who left no longer holds the placement")


func test_two_players_share_the_rewards() -> void:
	var t := _conns(["Alice", "Bob"])
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	var fight := _start(t)
	b.send(ProtocolWatch.join(fight.id, 0))
	Players._run(t, 0.2)
	a.send(Protocol.fight_ready())
	b.send(Protocol.fight_ready())
	Players._run(t, 0.2)
	a.events.clear()
	b.events.clear()
	for f: Fighter in fight.fighters.values():
		if f.team == 1:
			f.alive = false
			f.hp = 0
	fight._check_end()
	Players._run(t, 0.3)
	var ea: Dictionary = a.take(Protocol.FIGHT_END)[0]
	var eb: Dictionary = b.take(Protocol.FIGHT_END)[0]
	eq([ea["result"], eb["result"]], ["win", "win"])
	eq((ea["rewards"] as Array).size(), 2, "both are in the result")
	eq((eb["rewards"] as Array).size(), 2)
	for r: Dictionary in ea["rewards"]:
		check(int(r["xp_gained"]) > 0, "each gets XP")
	eq(a.player().fight_id, 0)
	eq(b.player().fight_id, 0)
	check(a.sim().get_map(1).actors.has(a.backend.player_id) and a.sim().get_map(1).actors.has(b.backend.player_id), "both back on the map")


func test_the_group_bonus_makes_two_players_win_more() -> void:
	# FightXp.GROUP_BONUS (luaformulas 99): the same monsters give more XP in total to two humans
	var xp := {}
	for n in [1, 2]:
		var names := ["Alice"] if n == 1 else ["Alice", "Bob"]
		var t := _conns(names)
		var fight := _start(t)
		if n == 2:
			(t[1] as Players.Conn).send(ProtocolWatch.join(fight.id, 0))
			Players._run(t, 0.2)
		for f: Fighter in fight.fighters.values():
			if f.team == 1:
				f.alive = false
				f.hp = 0
		fight.result = "win"
		var gains := FightRewards.compute(fight)
		var total := 0
		for g: Dictionary in gains.values():
			total += int(g["xp"])
		xp[n] = total
	check(xp[1] > 0)
	check(xp[2] > xp[1], "two players get more XP than one (%d vs %d)" % [xp[2], xp[1]])


# -- the schema and the protocol --------------------------------------------------------

func test_messages_match_the_schema() -> void:
	eq(ProtocolWatch.C2S, Protocol.C2S)
	eq(ProtocolWatch.S2C, Protocol.S2C)
	eq(Protocol.validate(ProtocolWatch.join(5, 0), Protocol.C2S), "")
	eq(Protocol.validate(ProtocolWatch.spectate(5), Protocol.C2S), "")
	check(Protocol.validate({"t": ProtocolWatch.JOIN, "fight": 1}, Protocol.C2S).contains("team"), "team is required")
	eq(Protocol.validate(ProtocolWatch.joined({"id": 1}, [1]), Protocol.S2C), "")
	eq(Protocol.validate(ProtocolWatch.left(1, []), Protocol.S2C), "")
	var w := ProtocolWatch.watch(1, [], [], "fight", {}, 0, -1, {"locked": false}, [])
	eq(Protocol.validate(w, Protocol.S2C), "")
	check(Protocol.is_json_safe(w))
	check(Protocol.validate(ProtocolWatch.joined({}, []), Protocol.C2S) != "", "an event is not a command")
	for code: String in ProtocolWatch.ERROR_CODES:
		check(Protocol.ERROR_CODES.has(code), code + " is a known error")
		check(ErrorTexts.TEXTS.has(code), code + " has a text")


# -- the same over WebSockets ----------------------------------------------------------

func test_join_and_watch_over_websocket() -> void:
	var rig := NetTests.Rig.new()
	var tofu := {"look": "{4907|||130}", "name": "Tofu", "name_id": 5, "level": 1, "hp": 500, "ap": 4, "mp": 3, "xp": 10}
	rig.host.server.sources["brawl"] = WorldSource.from_dicts(
		{"id": "brawl", "name": "Brawl", "start_map": 1, "start_cell": 300, "wander_ms": [600000, 600000]},
		[{"id": 1, "coords": [0, 0], "groups": [{"name": "Tofu", "members": [tofu]}]}])
	var a := rig.client("brawl", "Alice")
	rig.run(2.0, func() -> bool: return a.has(Protocol.MAP_ENTER))
	var b := rig.client("brawl", "Bob")
	rig.run(2.0, func() -> bool: return b.has(Protocol.MAP_ENTER))
	var c := rig.client("brawl", "Carl")
	rig.run(2.0, func() -> bool: return c.has(Protocol.MAP_ENTER))
	var world: WorldSim = rig.host.server.worlds["brawl"]
	var group: int = world.get_map(1).actors.values().filter(func(x: SimActor) -> bool: return x is MonsterGroup)[0].id
	a.backend.send(Protocol.fight_attack(group))
	check(rig.run(3.0, func() -> bool: return b.events.any(func(e: Dictionary) -> bool: return e["t"] == Protocol.ACTOR_ADD and e["actor"]["kind"] == "fight")), "Bob sees the swords through the server")
	var sword: Dictionary = b.take(Protocol.ACTOR_ADD).filter(func(e: Dictionary) -> bool: return e["actor"]["kind"] == "fight")[0]["actor"]
	var fid := int(sword["id"])
	eq((sword["teams"] as Array).map(func(v: Variant) -> int: return int(v)), [1, 1], "counts survive the JSON")
	b.backend.send(ProtocolWatch.join(fid, 0))
	check(rig.run(3.0, func() -> bool: return b.has(Protocol.FIGHT_START)), "Bob joins")
	check(rig.run(3.0, func() -> bool: return a.has(ProtocolWatch.JOINED)), "Alice is told")
	var joined: Dictionary = a.take(ProtocolWatch.JOINED)[0]
	eq(int(joined["fighter"]["id"]), b.you, "ids are ints after the round trip")
	c.backend.send(ProtocolWatch.spectate(fid))
	check(rig.run(3.0, func() -> bool: return c.has(ProtocolWatch.WATCH)), "Carl watches")
	var w: Dictionary = c.take(ProtocolWatch.WATCH)[0]
	eq([int(w["fight"]), w["phase"], int(w["turn"])], [fid, "placement", -1])
	eq((w["fighters"] as Array).size(), 3)
	a.backend.send(Protocol.fight_ready())
	b.backend.send(Protocol.fight_ready())
	check(rig.run(3.0, func() -> bool: return c.has(Protocol.FIGHT_BEGIN)), "the spectator sees the fight begin")
	c.backend.send(Protocol.move(320))
	check(rig.run(3.0, func() -> bool: return c.has(Protocol.ERROR)), "and cannot act")
	eq(str(c.take(Protocol.ERROR)[0]["code"]), ProtocolWatch.E_SPECTATING)
	c.backend.send(Protocol.fight_leave())
	check(rig.run(3.0, func() -> bool: return c.has(Protocol.MAP_ENTER)), "he leaves the audience")
	b.backend.send(Protocol.fight_leave())
	check(rig.run(3.0, func() -> bool: return b.has(Protocol.FIGHT_END)), "Bob flees")
	check(world.fights.size() == 1, "the fight goes on for Alice")
	a.backend.send(Protocol.fight_leave())
	check(rig.run(3.0, func() -> bool: return a.has(Protocol.FIGHT_END)), "Alice abandons")
	eq(world.fights.size(), 0)
	eq(a.backend.schema_errors.size() + b.backend.schema_errors.size() + c.backend.schema_errors.size(), 0, "every event matches the schema")
	rig.host.shutdown()
