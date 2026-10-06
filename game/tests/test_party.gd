## Groups (roadmap P3.03): the rules of shared/Party, the invitations and the roster of
## WorldParty (accept, decline, expiry, leave, exclusion, leader, disconnection), the position
## of the members, following the leader across maps, the XP bonus of two humans, and the same
## flow through two NetBackends on 127.0.0.1.
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


## Alice invites, Bob accepts; every event queue is emptied afterwards.
func _pair() -> Array:
	var t := _conns(["Alice", "Bob"])
	_join(t[0], t[1], t)
	for c: Players.Conn in t:
		c.events.clear()
	return t


func _join(leader: Players.Conn, member: Players.Conn, all: Array) -> void:
	leader.send(ProtocolParty.invite(member.player().name))
	Players._run(all, 0.1)
	member.send(ProtocolParty.accept(leader.player().name))
	Players._run(all, 0.1)


static func _last(c: Players.Conn) -> Dictionary:
	var u := c.take(ProtocolParty.UPDATE)
	return u[-1]["party"] if not u.is_empty() else {}


static func _names(party: Dictionary) -> Array:
	return (party["members"] as Array).map(func(m: Dictionary) -> String: return str(m["name"]))


static func _codes(c: Players.Conn) -> Array:
	return c.take(Protocol.ERROR).map(func(e: Dictionary) -> String: return str(e["code"]))


# -- shared/Party: pure rules ---------------------------------------------------

func test_the_group_holds_eight_and_the_leader_is_first() -> void:
	var p := Party.create(1, "A", "B")
	eq(p.leader(), "A")
	for i in 6:
		eq(p.add("M%d" % i), "")
	check(p.is_full(), "8 members")
	eq(p.add("Z"), ProtocolParty.E_PARTY_FULL)
	eq(p.add("A"), ProtocolParty.E_ALREADY_IN_PARTY)
	p.remove("A")
	eq(p.leader(), "B", "the next member in line leads")
	eq(p.can_kick("A", "B"), ProtocolParty.E_NOT_PARTY_LEADER)
	eq(p.can_kick("B", "B"), Protocol.E_NO_TARGET, "not oneself")
	eq(p.can_kick("B", "M0"), "")
	eq(p.promote("B", "M1"), "")
	eq(p.leader(), "M1")
	check(not Party.create(2, "A", "B").is_dissolved())
	var duo := Party.create(3, "A", "B")
	duo.remove("B")
	check(duo.is_dissolved(), "one member is no group")


func test_messages_are_in_the_schema() -> void:
	eq(ProtocolParty.C2S, Protocol.C2S)
	eq(ProtocolParty.S2C, Protocol.S2C)
	var up := ProtocolParty.update({"id": 1, "leader": "A", "members": []})
	eq(Protocol.validate(up, Protocol.S2C), "")
	eq(Protocol.validate(ProtocolParty.invite("Bob"), Protocol.C2S), "")
	check(Protocol.validate({"t": ProtocolParty.INVITE}, Protocol.C2S).contains("name"), "a name is required")
	check(Protocol.validate(ProtocolParty.invited("A"), Protocol.C2S) != "", "an event is no command")
	check(Protocol.is_json_safe(Protocol.roundtrip(up)))
	for code: String in ProtocolParty.ERROR_CODES:
		check(Protocol.ERROR_CODES.has(code) and ErrorTexts.TEXTS.has(code), "%s is listed and has its text" % code)


# -- invitations and roster -----------------------------------------------------

func test_invite_accept_makes_a_group_of_two() -> void:
	var t := _conns(["Alice", "Bob"])
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	a.send(ProtocolParty.invite("bob"))
	Players._run(t, 0.1)
	eq(b.take(ProtocolParty.INVITED)[0]["from"], "Alice", "Bob is invited (any case)")
	check(a.take(ProtocolParty.UPDATE).is_empty(), "no group yet")
	b.send(ProtocolParty.accept("Alice"))
	Players._run(t, 0.1)
	for c: Players.Conn in t:
		var party := _last(c)
		eq(_names(party), ["Alice", "Bob"], "everyone gets the roster, the leader first")
		eq(party["leader"], "Alice")
	check(a.sim().party.party_of("Alice") == a.sim().party.party_of("Bob"), "one Party for both")


func test_members_carry_their_position_and_life() -> void:
	var t := _conns(["Alice", "Bob"])
	_join(t[0], t[1], t)
	var party := _last(t[1])
	var me: Dictionary = (party["members"] as Array)[0]
	eq(int(me["id"]), t[0].backend.player_id)
	eq([int(me["map"]), int(me["cell"]), me["fight"]], [1, t[0].player().cell, false])
	eq((me["coords"] as Array).map(func(v: Variant) -> int: return int(v)), [0, 0], "the world coordinates of the map")
	check(int(me["max_hp"]) > 0 and int(me["hp"]) > 0 and int(me["level"]) >= 1 and me.has("breed"))
	check(Protocol.is_json_safe(party))


func test_refusals() -> void:
	var t := _conns(["Alice", "Bob", "Carl"])
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	var c: Players.Conn = t[2]
	a.send(ProtocolParty.invite("Nobody"))
	a.send(ProtocolParty.invite("Alice"))
	Players._run(t, 0.1)
	eq(_codes(a), [Protocol.E_PLAYER_OFFLINE, Protocol.E_PLAYER_OFFLINE], "nobody, and not oneself")
	b.send(ProtocolParty.accept("Alice"))
	b.send(ProtocolParty.leave())
	b.send(ProtocolParty.kick("Alice"))
	b.send(ProtocolParty.leader("Alice"))
	b.send(ProtocolParty.follow("Alice"))
	Players._run(t, 0.1)
	eq(_codes(b), [ProtocolParty.E_NO_INVITATION, ProtocolParty.E_NOT_IN_PARTY, ProtocolParty.E_NOT_IN_PARTY,
			ProtocolParty.E_NOT_IN_PARTY, ProtocolParty.E_NOT_IN_PARTY])
	_join(a, b, t)
	for x: Players.Conn in t:
		x.events.clear()
	b.send(ProtocolParty.invite("Carl"))
	c.send(ProtocolParty.invite("Alice"))
	a.send(ProtocolParty.invite("Bob"))
	Players._run(t, 0.1)
	eq(_codes(b), [ProtocolParty.E_NOT_PARTY_LEADER], "only the leader invites")
	eq(_codes(c), [ProtocolParty.E_ALREADY_IN_PARTY], "Alice is in a group")
	eq(_codes(a), [ProtocolParty.E_ALREADY_IN_PARTY], "so is Bob")
	b.send(ProtocolParty.kick("Alice"))
	b.send(ProtocolParty.leader("Bob"))
	Players._run(t, 0.1)
	eq(_codes(b), [ProtocolParty.E_NOT_PARTY_LEADER, ProtocolParty.E_NOT_PARTY_LEADER], "exclude and promote: the leader only")


func test_decline_and_expiry() -> void:
	var t := _conns(["Alice", "Bob"])
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	a.send(ProtocolParty.invite("Bob"))
	Players._run(t, 0.1)
	b.send(ProtocolParty.decline("Alice"))
	Players._run(t, 0.1)
	eq(a.take(ProtocolParty.DECLINED)[0]["name"], "Bob", "the inviter is told")
	b.send(ProtocolParty.accept("Alice"))
	Players._run(t, 0.1)
	eq(_codes(b), [ProtocolParty.E_NO_INVITATION], "a declined invitation is gone")
	a.send(ProtocolParty.invite("Bob"))
	Players._run(t, 0.1)
	a.server.tick(Party.INVITE_TTL_MS + 1000)
	Players._run(t, 0.1)
	b.send(ProtocolParty.accept("Alice"))
	Players._run(t, 0.1)
	eq(_codes(b), [ProtocolParty.E_NO_INVITATION], "an invitation expires")
	check(a.sim().party.invites.is_empty(), "and is forgotten")


func test_leave_hands_the_lead_on_then_dissolves() -> void:
	var t := _conns(["Alice", "Bob", "Carl"])
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	var c: Players.Conn = t[2]
	_join(a, b, t)
	_join(a, c, t)
	eq(_names(_last(c)), ["Alice", "Bob", "Carl"], "joining order")
	for x: Players.Conn in t:
		x.events.clear()
	a.send(ProtocolParty.leave())
	Players._run(t, 0.1)
	eq(a.take(ProtocolParty.LEFT)[0]["reason"], "left")
	var party := _last(c)
	eq([party["leader"], _names(party)], ["Bob", ["Bob", "Carl"]], "Bob leads now")
	check(a.sim().party.party_of("Alice") == null)
	b.events.clear()
	c.send(ProtocolParty.leave())
	Players._run(t, 0.1)
	eq(c.take(ProtocolParty.LEFT)[0]["reason"], "left")
	eq(b.take(ProtocolParty.LEFT)[0]["reason"], "dissolved", "a group of one is dissolved")
	check(a.sim().party.parties.is_empty() and a.sim().party.of.is_empty())


func test_the_leader_excludes_and_promotes() -> void:
	var t := _conns(["Alice", "Bob", "Carl"])
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	var c: Players.Conn = t[2]
	_join(a, b, t)
	_join(a, c, t)
	for x: Players.Conn in t:
		x.events.clear()
	a.send(ProtocolParty.kick("Carl"))
	Players._run(t, 0.1)
	eq(c.take(ProtocolParty.LEFT)[0]["reason"], "kicked")
	eq(_names(_last(b)), ["Alice", "Bob"])
	a.send(ProtocolParty.leader("Bob"))
	Players._run(t, 0.1)
	var party := _last(a)
	eq([party["leader"], _names(party)], ["Bob", ["Bob", "Alice"]], "the new leader is first")
	a.send(ProtocolParty.invite("Carl"))
	Players._run(t, 0.1)
	eq(_codes(a), [ProtocolParty.E_NOT_PARTY_LEADER], "Alice is no longer the leader")
	b.send(ProtocolParty.invite("Carl"))
	Players._run(t, 0.1)
	c.send(ProtocolParty.accept("Bob"))
	Players._run(t, 0.1)
	eq(_names(_last(c)), ["Bob", "Alice", "Carl"], "the new leader recruits")


func test_a_group_is_full_at_eight() -> void:
	var names := ["Anna", "Bert", "Cleo", "Dino", "Edna", "Finn", "Gina", "Hugo", "Iris"]
	var t := _conns(names)
	for i in range(1, 8):
		_join(t[0], t[i], t)
	eq(_names(_last(t[7])).size(), 8)
	t[0].events.clear()
	t[0].send(ProtocolParty.invite("Iris"))
	Players._run(t, 0.1)
	eq(_codes(t[0]), [ProtocolParty.E_PARTY_FULL])


func test_disconnecting_leaves_the_group() -> void:
	var t := _pair()
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	a.server.worlds["duo"].disconnect_player(b.backend.player_id)
	Players._run([a], 0.1)
	eq(a.take(ProtocolParty.LEFT)[0]["reason"], "dissolved", "Alice is alone")
	check(a.sim().party.of.is_empty())


func test_the_roster_follows_the_members() -> void:
	var t := _pair()
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	Players._run(t, 1.2)
	b.events.clear()
	a.send(Protocol.move(Players.EDGE))
	Players._run(t, 8.0)
	a.send(Protocol.change_map("right"))
	Players._run(t, 1.5)
	var me: Dictionary = (_last(b)["members"] as Array)[0]
	eq([int(me["map"]), int(me["coords"][0]), int(me["coords"][1])], [2, 1, 0], "Bob sees Alice on the next map")


func test_following_the_leader_across_maps() -> void:
	var t := _pair()
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	b.send(ProtocolParty.follow("Alice"))
	Players._run(t, 0.1)
	eq(_last(b)["follow"], "Alice", "the update says whom you follow")
	check(_last(a).get("follow", "") == "", "Alice follows nobody")
	a.send(Protocol.move(Players.EDGE))
	Players._run(t, 8.0)
	a.send(Protocol.change_map("right"))
	Players._run(t, 0.3)
	eq(a.player().map_id, 2)
	eq(b.player().map_id, 2, "Bob came along")
	check(b.take(Protocol.MAP_ENTER).any(func(e: Dictionary) -> bool: return int(e["map"]["id"]) == 2), "with its map_enter")
	b.send(ProtocolParty.follow(""))
	Players._run(t, 0.1)
	eq(_last(b)["follow"], "", "following stops")


func test_a_follower_in_fight_stays() -> void:
	var t := _pair()
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	b.send(ProtocolParty.follow("Alice"))
	Players._run(t, 0.1)
	b.player().fight_id = 99 # busy in a fight (only the field matters here)
	a.sim().teleport(a.player(), 2, 300)
	eq(b.player().map_id, 1, "a fighter does not follow")
	b.player().fight_id = 0


func test_follow_ends_with_membership() -> void:
	var t := _pair()
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	b.send(ProtocolParty.follow("Alice"))
	Players._run(t, 0.1)
	b.send(ProtocolParty.leave())
	Players._run(t, 0.1)
	check(a.sim().party.follows.is_empty(), "nobody follows once out")
	a.sim().teleport(a.player(), 2, 300)
	eq(b.player().map_id, 1)


# -- XP: the group bonus -----------------------------------------------------------

func test_two_humans_earn_the_group_bonus() -> void:
	var alone := FightXp.group_xp(1000.0, 10, 10, 1, true)
	var duo := FightXp.group_xp(1000.0, 10, 12, 2, true)
	eq(alone, 1000, "GROUP_BONUS[0] = 1")
	eq(duo, int(floor(1000.0 * 1.1)), "luaformulas 99: two humans = ×1.1 (monsters 10 vs players 12 levels: no level malus)")
	eq(FightXp.group_xp(1000.0, 10, 12, 8, true), int(floor(1000.0 * 4.7)), "eight humans")
	eq(FightXp.group_xp(1000.0, 10, 12, 2, false), 250, "a defeat: a quarter, no bonus")


# -- the same over WebSockets --------------------------------------------------------

func test_group_over_websocket() -> void:
	var rig := NetTests.Rig.new()
	var a := rig.client("tiny", "Alice")
	rig.run(2.0, func() -> bool: return a.has(Protocol.MAP_ENTER))
	var b := rig.client("tiny", "Bob")
	rig.run(2.0, func() -> bool: return b.has(Protocol.MAP_ENTER))
	a.backend.send(ProtocolParty.invite("Bob"))
	check(rig.run(2.0, func() -> bool: return b.has(ProtocolParty.INVITED)), "Bob is invited through the server")
	b.backend.send(ProtocolParty.accept("Alice"))
	var both := func() -> bool: return a.has(ProtocolParty.UPDATE) and b.has(ProtocolParty.UPDATE)
	check(rig.run(2.0, both), "both get the group")
	var party: Dictionary = b.take(ProtocolParty.UPDATE)[-1]["party"]
	eq([party["leader"], _names(party)], ["Alice", ["Alice", "Bob"]])
	check(int((party["members"] as Array)[1]["id"]) == b.you and int(party["id"]) > 0, "ids survive the JSON round trip as ints")
	b.backend.send(ProtocolParty.accept("Nobody"))
	check(rig.run(2.0, func() -> bool: return b.has(Protocol.ERROR)), "an error comes back")
	var err: Dictionary = b.take(Protocol.ERROR)[0]
	eq([str(err["code"]), err.has("ref")], [ProtocolParty.E_NO_INVITATION, true])
	a.take(ProtocolParty.UPDATE)
	b.backend.send(ProtocolParty.follow("Alice"))
	check(rig.run(2.0, func() -> bool: return b.has(ProtocolParty.UPDATE)), "following is told")
	eq(b.take(ProtocolParty.UPDATE)[-1]["party"]["follow"], "Alice")
	var edge := 20 * 14 + 13
	a.backend.send(Protocol.move(edge))
	rig.run(15.0)
	a.backend.send(Protocol.change_map("right"))
	rig.run(1.0)
	eq(int(rig.sim().players[b.you].map_id), 2, "Bob follows Alice over the server too")
	b.backend.send(ProtocolParty.leave())
	check(rig.run(2.0, func() -> bool: return a.has(ProtocolParty.LEFT)), "the group dissolves")
	eq(a.take(ProtocolParty.LEFT)[0]["reason"], "dissolved")
	eq(a.backend.schema_errors.size() + b.backend.schema_errors.size(), 0, "every event matches the schema")
	rig.host.shutdown()
