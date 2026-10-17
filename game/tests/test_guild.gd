## Guilds (roadmap P3.06a): the pure rules of shared/Guild, then creation, invitation, ranks,
## rights, exclusion, the /g channel and the persistence through several logged-in players
## (LocalBackend), and the same flow through two accounts over WebSockets on 127.0.0.1 (NetBackend).
extends TestCase

const Players := preload("res://tests/test_players.gd")
const Accounts := preload("res://tests/test_accounts.gd")

const EMBLEM := {"symbol": 1, "symbol_color": 0xFF0000, "bg": 2, "bg_color": 0x0000FF}


func _init() -> void:
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()
	SpellBook.use_file("res://tests/fixtures/spells.json")


func _conns(server: LocalServer, names: Array) -> Array:
	var out := []
	for n: String in names:
		out.append(Players.Conn.new(server, n, Players.LOOK, n.to_lower()))
	Players._run(out, 0.2)
	for c: Players.Conn in out:
		c.events.clear()
	return out


## The last guild_info of a connection (its `guild`), {"_none": true} if it received none.
static func _info(c: Players.Conn) -> Dictionary:
	var u := c.take(ProtocolGuild.INFO)
	return u[-1]["guild"] if not u.is_empty() else {"_none": true}


static func _codes(c: Players.Conn) -> Array:
	return c.take(Protocol.ERROR).map(func(e: Dictionary) -> String: return str(e["code"]))


static func _member(info: Dictionary, name: String) -> Dictionary:
	for m: Dictionary in info["members"]:
		if m["name"] == name:
			return m
	return {}


static func _ints(a: Array) -> Array:
	return a.map(func(v: Variant) -> int: return int(v))


static func _names(info: Dictionary) -> Array:
	return info["members"].map(func(m: Dictionary) -> String: return str(m["name"]))


## Alice founds "Les Gardiens"; the `joined` next names join it (trial rank); the others stay out.
func _guild(server: LocalServer, names: Array, joined: int) -> Array:
	var t := _conns(server, names)
	var a: Players.Conn = t[0]
	a.send(ProtocolGuild.create("Les Gardiens", EMBLEM))
	Players._run(t, 0.1)
	for i in range(1, joined):
		a.send(ProtocolGuild.invite(names[i]))
		Players._run(t, 0.1)
		(t[i] as Players.Conn).send(ProtocolGuild.accept("Alice"))
		Players._run(t, 0.1)
	for c: Players.Conn in t:
		c.events.clear()
	return t


# -- shared/Guild: pure rules ------------------------------------------------------------

func _pure() -> Guild:
	var g := Guild.create(7, "Les Gardiens", EMBLEM, "Alice", 1000)
	for n in ["Bob", "Cleo", "Dora"]:
		g.add(n, 2000)
	g.set_rank("Bob", Guild.RANK_OFFICER)
	g.set_rank("Cleo", Guild.RANK_INITIATE)
	return g


func test_the_leader_holds_every_right_and_a_newcomer_none() -> void:
	var g := _pure()
	for r: int in Guild.ALL_RIGHTS:
		check(g.has_right("Alice", r), "the leader has right %d" % r)
	check(not g.has_right("Dora", Guild.R_INVITE), "a trial member has none")
	check(g.has_right("Bob", Guild.R_KICK) and not g.has_right("Bob", Guild.R_MANAGE_RANKS), "an officer's default rights")
	eq(g.leader(), "Alice")
	check(not g.has_right("Nobody", Guild.R_KICK))


func test_hierarchy_decides_who_may_act_on_whom() -> void:
	var g := _pure()
	eq(g.kick_error("Bob", "Cleo"), "", "an officer excludes an initiate")
	eq(g.kick_error("Bob", "Alice"), ProtocolGuild.E_GUILD_NO_RIGHT, "never above oneself")
	eq(g.kick_error("Bob", "Bob"), ProtocolGuild.E_GUILD_NO_RIGHT, "nor at the same rank")
	eq(g.kick_error("Cleo", "Dora"), ProtocolGuild.E_GUILD_NO_RIGHT, "no right to kick")
	eq(g.kick_error("Alice", "Zed"), ProtocolGuild.E_NOT_IN_GUILD)
	eq(g.rank_error("Bob", "Dora", Guild.RANK_INITIATE), "", "a lower rank than one's own")
	eq(g.rank_error("Bob", "Dora", Guild.RANK_OFFICER), ProtocolGuild.E_GUILD_NO_RIGHT, "not as high as one's own")
	eq(g.rank_error("Alice", "Dora", Guild.RANK_OFFICER), "", "the leader makes officers")
	eq(g.rank_error("Alice", "Dora", Guild.RANK_LEADER), ProtocolGuild.E_BAD_RANK, "the leader's rank passes by guild_leader")
	eq(g.rank_error("Alice", "Dora", 9), ProtocolGuild.E_BAD_RANK)


func test_rights_are_granted_within_what_one_holds() -> void:
	var g := _pure()
	eq(g.rights_error("Bob", "Dora", [Guild.R_INVITE]), ProtocolGuild.E_GUILD_NO_RIGHT, "an officer cannot manage rights")
	eq(g.rights_error("Alice", "Bob", [Guild.R_MANAGE_RANKS]), "", "the leader grants any right below itself")
	g.set_rights("Bob", [Guild.R_MANAGE_RANKS, Guild.R_INVITE])
	eq(g.rights_error("Bob", "Dora", [Guild.R_INVITE]), "", "now Bob manages rights of lower members")
	eq(g.rights_error("Bob", "Dora", [Guild.R_KICK]), ProtocolGuild.E_GUILD_NO_RIGHT, "but only rights he holds")
	eq(g.rights_error("Bob", "Dora", [999]), ProtocolGuild.E_BAD_RIGHT)
	eq(g.rights_error("Bob", "Alice", [Guild.R_INVITE]), ProtocolGuild.E_GUILD_NO_RIGHT)


func test_a_new_rank_brings_its_default_rights() -> void:
	var g := _pure()
	g.set_rights("Cleo", [Guild.R_INVITE])
	g.set_rank("Cleo", Guild.RANK_OFFICER)
	eq(g.member("Cleo")["rights"], Guild.DEFAULT_RIGHTS[Guild.RANK_OFFICER])
	g.hand_over("Bob")
	eq([g.leader(), g.member("Alice")["rank"], g.members[0]["name"]], ["Bob", Guild.RANK_OFFICER, "Bob"])


func test_names_and_emblems_are_checked() -> void:
	eq(Guild.name_error("Les Gardiens"), "")
	eq(Guild.name_error("ab"), ProtocolGuild.E_BAD_GUILD_NAME, "too short")
	eq(Guild.name_error("Bad1"), ProtocolGuild.E_BAD_GUILD_NAME, "digits")
	eq(Guild.emblem_error(EMBLEM), "")
	eq(Guild.emblem_error({"symbol": 1}), ProtocolGuild.E_BAD_EMBLEM, "fields missing")
	eq(Guild.emblem_error({"symbol": 1, "symbol_color": -1, "bg": 1, "bg_color": 0}), ProtocolGuild.E_BAD_EMBLEM)
	eq(Guild.emblem_error({"symbol": 99999, "symbol_color": 0, "bg": 1, "bg_color": 0}), ProtocolGuild.E_BAD_EMBLEM, "unknown symbol")


func test_a_damaged_document_reads_without_crashing() -> void:
	var g := Guild.from_dict({"id": 3, "name": "X", "members": [{"name": "A", "rank": 99, "rights": [1, "x", 1000]}, 4, {"rank": 1}]})
	eq(g.members.size(), 1)
	eq([g.members[0]["rank"], g.members[0]["rights"]], [Guild.RANK_TRIAL, [1]])
	eq(Guild.from_dict({}).members, [])


# -- the sim, through LocalBackend ---------------------------------------------------------

func test_creating_a_guild() -> void:
	var t := _conns(Players._server(), ["Alice", "Bob"])
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	a.send(ProtocolGuild.create("x", EMBLEM))
	a.send(ProtocolGuild.create("Les Gardiens", {"symbol": 1}))
	Players._run(t, 0.1)
	eq(_codes(a), [ProtocolGuild.E_BAD_GUILD_NAME, ProtocolGuild.E_BAD_EMBLEM])
	a.send(ProtocolGuild.create("Les Gardiens", EMBLEM))
	Players._run(t, 0.1)
	var info := _info(a)
	eq([info["name"], int(info["emblem"]["symbol"]), int(info["emblem"]["bg_color"]), int(info["you"]["rank"])], ["Les Gardiens", 1, 255, Guild.RANK_LEADER])
	eq(info["members"].size(), 1)
	a.send(ProtocolGuild.create("Autre", EMBLEM))
	b.send(ProtocolGuild.create("les gardiens", EMBLEM))
	Players._run(t, 0.1)
	eq(_codes(a), [ProtocolGuild.E_ALREADY_IN_GUILD])
	eq(_codes(b), [ProtocolGuild.E_GUILD_NAME_TAKEN], "unique in the world, whatever the case")
	b.send(ProtocolGuild.get_guild())
	Players._run(t, 0.1)
	eq(_info(b), {}, "Bob has no guild")


func test_invitation_accept_and_decline() -> void:
	var server := Players._server()
	var t := _conns(server, ["Alice", "Bob", "Cleo"])
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	var c: Players.Conn = t[2]
	a.send(ProtocolGuild.invite("Bob"))
	Players._run(t, 0.1)
	eq(_codes(a), [ProtocolGuild.E_NOT_IN_GUILD], "no guild yet")
	a.send(ProtocolGuild.create("Les Gardiens", EMBLEM))
	a.send(ProtocolGuild.invite("Nobody"))
	a.send(ProtocolGuild.invite("Bob"))
	a.send(ProtocolGuild.invite("Cleo"))
	Players._run(t, 0.1)
	eq(_codes(a), [Protocol.E_PLAYER_OFFLINE])
	var inv: Dictionary = b.take(ProtocolGuild.INVITED)[0]
	eq([inv["from"], inv["guild"]], ["Alice", "Les Gardiens"])
	b.send(ProtocolGuild.accept("Alice"))
	c.send(ProtocolGuild.decline("Alice"))
	c.send(ProtocolGuild.accept("Alice"))
	Players._run(t, 0.1)
	eq(a.take(ProtocolGuild.DECLINED)[0]["name"], "Cleo")
	eq(_codes(c), [ProtocolGuild.E_NO_GUILD_INVITATION], "a declined invitation is gone")
	for conn: Players.Conn in [a, b]:
		eq(_names(_info(conn)), ["Alice", "Bob"], "both see the new member")
	var sim: WorldSim = server.worlds["duo"]
	var bob := _member(sim.guild.view(sim.guild.guild_of("Bob"), "Bob"), "Bob")
	eq([int(bob["rank"]), bob["rights"], bob["online"], int(bob["level"])], [Guild.RANK_TRIAL, [], true, 1], "joins as a trial member")
	b.send(ProtocolGuild.create("Autre", EMBLEM))
	a.send(ProtocolGuild.invite("Bob"))
	Players._run(t, 0.1)
	eq(_codes(b), [ProtocolGuild.E_ALREADY_IN_GUILD])
	eq(_codes(a), [ProtocolGuild.E_ALREADY_IN_GUILD], "one cannot invite a guild member")


func test_an_invitation_expires_and_needs_the_right() -> void:
	var server := Players._server()
	var t := _guild(server, ["Alice", "Bob", "Dora"], 2)
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	var d: Players.Conn = t[2]
	b.send(ProtocolGuild.invite("Dora"))
	Players._run(t, 0.1)
	eq(_codes(b), [ProtocolGuild.E_GUILD_NO_RIGHT], "a trial member cannot invite")
	a.send(ProtocolGuild.invite("Dora"))
	Players._run(t, 0.1)
	var sim: WorldSim = server.worlds["duo"]
	sim.now += Guild.INVITE_TTL_MS + 1000
	d.send(ProtocolGuild.accept("Alice"))
	Players._run(t, 0.1)
	eq(_codes(d), [ProtocolGuild.E_NO_GUILD_INVITATION], "one minute")


func test_ranks_rights_and_exclusion() -> void:
	var server := Players._server()
	var t := _guild(server, ["Alice", "Bob", "Cleo"], 3)
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	var c: Players.Conn = t[2]
	b.send(ProtocolGuild.kick("Cleo"))
	b.send(ProtocolGuild.rank("Cleo", Guild.RANK_INITIATE))
	Players._run(t, 0.1)
	eq(_codes(b), [ProtocolGuild.E_GUILD_NO_RIGHT, ProtocolGuild.E_GUILD_NO_RIGHT], "a trial member can do nothing")
	a.send(ProtocolGuild.rank("bob", Guild.RANK_OFFICER)) # the name is matched in any case
	Players._run(t, 0.1)
	var info := _info(c)
	eq(int(_member(info, "Bob")["rank"]), Guild.RANK_OFFICER)
	eq(_ints(_member(info, "Bob")["rights"]), Guild.DEFAULT_RIGHTS[Guild.RANK_OFFICER], "the officer's default rights")
	eq(_ints(_info(b)["you"]["rights"]), Guild.DEFAULT_RIGHTS[Guild.RANK_OFFICER], "Bob sees his own rights")
	b.send(ProtocolGuild.rank("Cleo", Guild.RANK_OFFICER))
	b.send(ProtocolGuild.rights("Cleo", [Guild.R_INVITE]))
	b.send(ProtocolGuild.kick("Alice"))
	Players._run(t, 0.1)
	eq(_codes(b), [ProtocolGuild.E_GUILD_NO_RIGHT, ProtocolGuild.E_GUILD_NO_RIGHT, ProtocolGuild.E_GUILD_NO_RIGHT])
	a.send(ProtocolGuild.rights("Cleo", [Guild.R_INVITE, Guild.R_INVITE, Guild.R_RECRUIT]))
	a.send(ProtocolGuild.rights("Cleo", [999]))
	a.send(ProtocolGuild.rank("Cleo", 1))
	Players._run(t, 0.1)
	eq(_codes(a), [ProtocolGuild.E_BAD_RIGHT, ProtocolGuild.E_BAD_RANK])
	eq(_ints(_member(_info(c), "Cleo")["rights"]), [Guild.R_RECRUIT, Guild.R_INVITE], "sorted, without doubles")
	b.send(ProtocolGuild.kick("Cleo"))
	Players._run(t, 0.1)
	eq(c.take(ProtocolGuild.LEFT)[0]["reason"], ProtocolGuild.REASON_KICKED)
	eq(c.take(ProtocolGuild.INFO)[-1]["guild"], {}, "Cleo is told she has no guild any more")
	eq(_info(a)["members"].size(), 2)
	c.send(ProtocolGuild.invite("Alice"))
	Players._run(t, 0.1)
	eq(_codes(c), [ProtocolGuild.E_NOT_IN_GUILD])


func test_leaving_handing_over_and_disbanding() -> void:
	var server := Players._server()
	var t := _guild(server, ["Alice", "Bob", "Cleo"], 3)
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	var c: Players.Conn = t[2]
	a.send(ProtocolGuild.leave())
	b.send(ProtocolGuild.leader("Cleo"))
	Players._run(t, 0.1)
	eq(_codes(a), [ProtocolGuild.E_GUILD_LEADER], "the leader hands over before leaving")
	eq(_codes(b), [ProtocolGuild.E_GUILD_NO_RIGHT], "only the leader hands over")
	a.send(ProtocolGuild.leader("Bob"))
	Players._run(t, 0.1)
	var info := _info(c)
	eq([info["members"][0]["name"], int(_member(info, "Alice")["rank"])], ["Bob", Guild.RANK_OFFICER], "Bob leads, Alice is an officer")
	a.send(ProtocolGuild.leave())
	Players._run(t, 0.1)
	eq(a.take(ProtocolGuild.LEFT)[0]["reason"], ProtocolGuild.REASON_LEFT)
	eq(_info(b)["members"].size(), 2)
	c.send(ProtocolGuild.disband())
	Players._run(t, 0.1)
	eq(_codes(c), [ProtocolGuild.E_GUILD_NO_RIGHT])
	b.send(ProtocolGuild.disband())
	Players._run(t, 0.1)
	for conn: Players.Conn in [b, c]:
		eq(conn.take(ProtocolGuild.LEFT)[0]["reason"], ProtocolGuild.REASON_DISBANDED)
	var sim: WorldSim = server.worlds["duo"]
	check(sim.guild.guild_of("Bob") == null and sim.guild.guild_of("Cleo") == null, "the index is gone")
	a.send(ProtocolGuild.create("Les Gardiens", EMBLEM))
	Players._run(t, 0.1)
	eq(_info(a)["name"], "Les Gardiens", "the name is free again")


func test_the_last_member_leaving_closes_the_guild() -> void:
	var server := Players._server()
	var t := _conns(server, ["Alice"])
	var a: Players.Conn = t[0]
	a.send(ProtocolGuild.create("Les Gardiens", EMBLEM))
	a.send(ProtocolGuild.leave())
	Players._run(t, 0.1)
	eq(a.take(ProtocolGuild.LEFT)[0]["reason"], ProtocolGuild.REASON_DISBANDED)
	eq(server.worlds["duo"].persistence.list_keys(WorldGuild.GUILDS), PackedStringArray())


# -- chat /g ---------------------------------------------------------------------------------

func test_the_guild_channel() -> void:
	var server := Players._server()
	var t := _guild(server, ["Alice", "Bob", "Cleo", "Dora"], 3)
	var a: Players.Conn = t[0]
	var c: Players.Conn = t[2]
	var d: Players.Conn = t[3]
	a.send(Protocol.chat_send("guild", "bonjour la guilde"))
	a.send(Protocol.chat_send("general", "/g re-bonjour"))
	Players._run(t, 0.1)
	eq(_codes(a), [])
	var heard := c.take(Protocol.CHAT_MSG)
	eq(heard.map(func(m: Dictionary) -> String: return str(m["channel"]) + ":" + str(m["text"])), ["guild:bonjour la guilde", "guild:re-bonjour"])
	eq(d.take(Protocol.CHAT_MSG).size(), 0, "a player outside the guild hears nothing")
	d.send(Protocol.chat_send("guild", "et moi ?"))
	Players._run(t, 0.1)
	eq(_codes(d), [Protocol.E_CHANNEL_UNAVAILABLE], "no guild, no /g")


# -- persistence: the guild outlives the session --------------------------------------------

func test_members_find_their_guild_again_and_the_others_see_them_come_and_go() -> void:
	var server := Players._server()
	var t := _guild(server, ["Alice", "Bob"], 2)
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	b.backend.close()
	t.erase(b)
	Players._run(t, 0.2)
	check(not _member(_info(a), "Bob")["online"], "Alice is told Bob left")
	var b2 := Players.Conn.new(server, "Bob", Players.LOOK, "bob")
	t.append(b2)
	Players._run(t, 0.2)
	var info := _info(b2)
	eq([info["name"], _names(info), int(info["you"]["rank"])], ["Les Gardiens", ["Alice", "Bob"], Guild.RANK_TRIAL], "Bob's guild is back at connection")
	check(_member(_info(a), "Bob")["online"], "and Alice sees him online")
	# a new server on the same store (a restart) still has the guild
	var sim2 := WorldSim.new(server.worlds["duo"].source, 1, server.worlds["duo"].persistence)
	check(sim2.guild.guild_of("Alice") != null and sim2.guild.guild_of("Bob") != null, "read from the store, not from memory")
	eq(sim2.guild.guild_of("Alice").emblem, EMBLEM)


func test_an_excluded_offline_member_is_out_at_next_connection() -> void:
	var server := Players._server()
	var t := _guild(server, ["Alice", "Bob"], 2)
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	b.backend.close()
	t.erase(b)
	Players._run(t, 0.2)
	a.send(ProtocolGuild.kick("Bob"))
	Players._run(t, 0.1)
	eq(_codes(a), [], "excluding an offline member works (the guild holds names)")
	var b2 := Players.Conn.new(server, "Bob", Players.LOOK, "bob")
	t.append(b2)
	Players._run(t, 0.2)
	eq(b2.take(ProtocolGuild.INFO).size(), 0, "no guild, nothing sent")


# -- over WebSockets, two accounts ------------------------------------------------------------

func _login(rig: Accounts.Rig, login: String, name: String) -> Accounts.Client:
	var c := rig.client()
	rig.ask(c, Protocol.register(login, "secret1"), Protocol.LOGIN_OK)
	c.backend.send(Protocol.hello("tiny", name, Players.LOOK))
	check(rig.run(15.0, func() -> bool: return c.has(Protocol.WELCOME)), "%s is in the world" % name)
	return c


func test_guild_over_websocket() -> void:
	var rig := Accounts.Rig.new()
	var a := _login(rig, "alice", "Alice")
	var b := _login(rig, "bob", "Bob")
	rig.run(0.2)
	a.take(Protocol.ERROR)
	a.backend.send(ProtocolGuild.create("Les Gardiens", EMBLEM))
	check(rig.run(2.0, func() -> bool: return a.has(ProtocolGuild.INFO)), "the guild comes back ")
	var info: Dictionary = a.take(ProtocolGuild.INFO)[-1]["guild"]
	eq([info["name"], int(info["emblem"]["symbol_color"]), int(info["you"]["rank"])], ["Les Gardiens", 0xFF0000, Guild.RANK_LEADER], "numbers come back as floats: int() on read")
	a.backend.send(ProtocolGuild.invite("bob"))
	check(rig.run(2.0, func() -> bool: return b.has(ProtocolGuild.INVITED)), "Bob is invited")
	b.backend.send(ProtocolGuild.accept("Alice"))
	check(rig.run(2.0, func() -> bool: return b.has(ProtocolGuild.INFO) and a.has(ProtocolGuild.INFO)), "both get the guild")
	a.take(ProtocolGuild.INFO)
	b.take(ProtocolGuild.INFO)
	a.backend.send(Protocol.chat_send("guild", "salut la guilde"))
	check(rig.run(2.0, func() -> bool: return b.has(Protocol.CHAT_MSG)), "Bob hears the guild channel")
	eq(b.take(Protocol.CHAT_MSG)[0]["channel"], "guild")
	a.backend.send(ProtocolGuild.rank("Bob", Guild.RANK_OFFICER))
	check(rig.run(2.0, func() -> bool: return b.has(ProtocolGuild.INFO)), "Bob is promoted")
	var mine: Dictionary = b.take(ProtocolGuild.INFO)[-1]["guild"]["you"]
	eq([int(mine["rank"]), (mine["rights"] as Array).has(float(Guild.R_KICK))], [Guild.RANK_OFFICER, true])
	b.backend.send(ProtocolGuild.kick("Alice"))
	check(rig.run(2.0, func() -> bool: return b.has(Protocol.ERROR)), "an officer cannot exclude the leader")
	eq(b.take(Protocol.ERROR)[0]["code"], ProtocolGuild.E_GUILD_NO_RIGHT)
	a.take(ProtocolGuild.INFO)
	rig.close(b)
	check(rig.run(2.0, func() -> bool: return a.has(ProtocolGuild.INFO)), "Alice is told Bob left")
	check(not _member(a.take(ProtocolGuild.INFO)[-1]["guild"], "Bob")["online"])
	var b2 := rig.client()
	rig.ask(b2, Protocol.login("bob", "secret1"), Protocol.LOGIN_OK)
	b2.backend.send(Protocol.hello("tiny", "Bob", Players.LOOK))
	check(rig.run(3.0, func() -> bool: return b2.has(ProtocolGuild.INFO)), "Bob's guild is there when he returns")
	eq(b2.take(ProtocolGuild.INFO)[-1]["guild"]["name"], "Les Gardiens")
	eq(a.backend.schema_errors.size() + b.backend.schema_errors.size() + b2.backend.schema_errors.size(), 0, "every event matches the schema")
	rig.shutdown()
