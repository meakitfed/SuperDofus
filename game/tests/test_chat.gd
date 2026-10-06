## Chat (roadmap P3.02): the rules of shared/Chat (commands, cleaning, anti-flood), the routing
## of WorldChat by channel (map, world, private, fight), the journal, and the same flow over
## WebSockets (127.0.0.1) through NetBackend. Two to three LocalBackends share one LocalServer.
extends TestCase

const Players := preload("res://tests/test_players.gd")
const NetTests := preload("res://tests/test_net.gd")


func _init() -> void:
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()
	SpellBook.use_file("res://tests/fixtures/spells.json")


static func _msgs(c: Players.Conn) -> Array:
	return c.take(Protocol.CHAT_MSG)


## Alice and Bob on map 1, Carol on map 2 (a "duo" world), all run for a moment.
func _trio() -> Array:
	var server := Players._server()
	var a := Players.Conn.new(server, "Alice")
	var b := Players.Conn.new(server, "Bob")
	var c := Players.Conn.new(server, "Carol")
	var sim: WorldSim = server.worlds["duo"]
	sim.get_map(1).remove_actor(c.player()) # on the second map without walking there
	sim.enter_map(c.player(), sim.get_map(2), 300)
	Players._run([a, b, c], 0.2)
	for conn: Players.Conn in [a, b, c]:
		conn.events.clear()
	return [a, b, c]


# -- shared/Chat: pure rules ---------------------------------------------------

func test_commands_come_from_the_dofus_shortcuts() -> void:
	eq(Chat.shortcut(Chat.GENERAL), "/s", "chatchannels.shortcut")
	eq(Chat.shortcut(Chat.COMMERCE), "/b")
	eq(Chat.shortcut(Chat.RECRUITMENT), "/r")
	eq(Chat.shortcut(Chat.PRIVATE), "/w")
	eq(Chat.shortcut(Chat.GUILD), "/g")
	check(Chat.name_id(Chat.COMMERCE) > 0, "the channel name is an i18n id of the table")
	eq(Chat.parse("salut tout le monde"), {"channel": "general", "text": "salut tout le monde", "to": ""}, "plain text: the open tab")
	eq(Chat.parse("/b vends dofus", Chat.GENERAL), {"channel": "commerce", "text": "vends dofus", "to": ""})
	eq(Chat.parse("/r  groupe donjon ", Chat.GENERAL)["text"], "groupe donjon", "trimmed")
	eq(Chat.parse("/w Bob salut toi"), {"channel": "private", "to": "Bob", "text": "salut toi"})
	eq(Chat.parse("/w Bob"), {"channel": "private", "to": "Bob", "text": ""}, "a name and nothing to say")
	eq(Chat.parse("/whisper Bob yo")["channel"], "private", "English alias")
	eq(Chat.parse("salut", Chat.PRIVATE, "Bob"), {"channel": "private", "text": "salut", "to": "Bob"}, "the private tab keeps its correspondent")
	check(Chat.parse("/zzz hello").has("error"), "an unknown command is an error, not a message to everyone")


func test_text_is_cleaned_and_cut() -> void:
	eq(Chat.clean("  a\tb\nc\u0001d  "), "a b c d", "control characters become spaces, then trimmed")
	eq(Chat.clean("x".repeat(400)).length(), Chat.MAX_LENGTH, "cut to MAX_LENGTH")
	eq(Chat.clean("   "), "")


func test_flood_windows() -> void:
	var h := []
	for i in 5:
		eq(Chat.flood_wait(Chat.GENERAL, h, i * 1000), 0, "message %d allowed" % i)
		h.append(i * 1000)
	eq(Chat.flood_wait(Chat.GENERAL, h, 5000), 5, "the sixth must wait until the first leaves the 10 s window")
	eq(Chat.flood_wait(Chat.GENERAL, h, 10500), 0, "allowed again once it left")
	eq(Chat.flood_wait(Chat.COMMERCE, [1000], 2000), 59, "commerce: one a minute")
	eq(Chat.bucket(Chat.PRIVATE), Chat.bucket(Chat.GENERAL), "private shares the open limit")
	check(Chat.bucket(Chat.COMMERCE) != Chat.bucket(Chat.RECRUITMENT), "commerce and recruitment each have their own")


func test_protocol_messages_are_valid_and_json_safe() -> void:
	var send := Protocol.chat_send("private", "salut", "Bob")
	eq(Protocol.validate(Protocol.roundtrip(send), Protocol.C2S), "")
	check(Protocol.validate({"t": "chat_send", "channel": "general"}, Protocol.C2S) != "", "text is required")
	var msg := Chat.message("private", "Alice", 3, "salut", 1234, "Bob")
	eq(Protocol.validate(Protocol.roundtrip(msg), Protocol.S2C), "")
	check(Protocol.is_json_safe(msg))
	check(not Chat.message("general", "A", 1, "x", 0).has("to"), "no recipient outside private")


# -- the sim: routing by channel ----------------------------------------------

func test_general_reaches_the_map_only() -> void:
	var t := _trio()
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	var c: Players.Conn = t[2]
	a.send(Protocol.chat_send(Chat.GENERAL, "  bonjour\tla map "))
	Players._run(t, 0.1)
	var got := _msgs(b)
	eq(got.size(), 1, "Bob, on the same map, hears")
	eq(str(got[0]["text"]), "bonjour la map", "cleaned")
	eq(str(got[0]["from"]), "Alice")
	eq(int(got[0]["from_id"]), a.backend.player_id, "the speaker's actor id (the bubble)")
	eq(_msgs(a).size(), 1, "Alice sees herself")
	eq(_msgs(c).size(), 0, "Carol, on another map, does not")


func test_commerce_and_recruitment_reach_the_world() -> void:
	var t := _trio()
	var a: Players.Conn = t[0]
	var c: Players.Conn = t[2]
	a.send(Protocol.chat_send(Chat.GENERAL, "/b vends peau de bouftou"))
	a.send(Protocol.chat_send(Chat.GENERAL, "/r cherche guilde"))
	Players._run(t, 0.1)
	var got := _msgs(c)
	eq(got.size(), 2, "Carol hears both from another map")
	eq([str(got[0]["channel"]), str(got[1]["channel"])], ["commerce", "recruitment"], "the shortcut chose the channel")
	eq(str(got[0]["text"]), "vends peau de bouftou", "without the command")


func test_private_message_and_its_echo() -> void:
	var t := _trio()
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	var c: Players.Conn = t[2]
	a.send(Protocol.chat_send(Chat.GENERAL, "/w carol coucou"))
	Players._run(t, 0.1)
	var got := _msgs(c)
	eq(got.size(), 1, "Carol (any map, any case of the name) gets it")
	eq([str(got[0]["channel"]), str(got[0]["from"]), str(got[0]["to"])], ["private", "Alice", "Carol"])
	var echo := _msgs(a)
	eq(echo.size(), 1, "Alice gets the echo")
	eq(str(echo[0]["to"]), "Carol", "'To Carol : ...'")
	eq(_msgs(b).size(), 0, "Bob hears nothing")
	c.send(Protocol.chat_send(Chat.PRIVATE, "salut", "Alice"))
	Players._run(t, 0.1)
	eq(_msgs(a).size(), 1, "the reply")


func test_private_message_to_an_offline_player() -> void:
	var t := _trio()
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	a.send(Protocol.chat_send(Chat.PRIVATE, "tu es la ?", "Zorg"))
	Players._run(t, 0.1)
	var errs := a.take(Protocol.ERROR)
	eq(errs.size(), 1)
	eq(str(errs[0]["code"]), Protocol.E_PLAYER_OFFLINE, "nobody of that name")
	eq(str(errs[0]["cmd"]), Protocol.CHAT_SEND)
	b.backend.close() # Bob logs out: he becomes unreachable too
	a.send(Protocol.chat_send(Chat.PRIVATE, "bob ?", "Bob"))
	a.send(Protocol.chat_send(Chat.PRIVATE, "moi ?", "Alice"))
	Players._run([a], 0.1)
	eq(a.take(Protocol.ERROR).size(), 2, "a logged-out player and yourself are refused")
	eq(_msgs(a).size(), 0, "no echo of a message that went nowhere")


func test_channels_and_commands_that_do_not_exist() -> void:
	var t := _trio()
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	a.send(Protocol.chat_send(Chat.GUILD, "salut la guilde"))
	a.send(Protocol.chat_send("nonsense", "x"))
	a.send(Protocol.chat_send(Chat.GENERAL, "/zzz hello"))
	a.send(Protocol.chat_send(Chat.GENERAL, "/b")) # nothing to say: ignored
	a.send(Protocol.chat_send(Chat.GENERAL, "   "))
	Players._run(t, 0.1)
	var codes: Array = a.take(Protocol.ERROR).map(func(e: Dictionary) -> String: return str(e["code"]))
	eq(codes, [Protocol.E_CHANNEL_UNAVAILABLE, Protocol.E_CHANNEL_UNAVAILABLE, Protocol.E_UNKNOWN_COMMAND], "guild waits for its lot; the typo is not sent to everyone")
	eq(_msgs(b).size(), 0, "nothing was said")
	a.send(Protocol.chat_send(Chat.TEAM, "team ?"))
	Players._run(t, 0.1)
	eq(str(a.take(Protocol.ERROR)[0]["code"]), Protocol.E_NOT_IN_FIGHT, "the team channel is the fight's")


func test_anti_flood() -> void:
	var t := _trio()
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	for i in 7:
		a.send(Protocol.chat_send(Chat.GENERAL, "spam %d" % i))
	Players._run(t, 0.1)
	eq(_msgs(b).size(), 5, "five get through")
	var errs := a.take(Protocol.ERROR)
	eq(errs.size(), 2, "the other two are refused")
	eq(str(errs[0]["code"]), Protocol.E_CHAT_FLOOD)
	check(int(str(errs[0]["msg"])) >= 1, "the refusal says how long to wait")
	Players._run(t, 10.5)
	a.send(Protocol.chat_send(Chat.GENERAL, "de retour"))
	Players._run(t, 0.1)
	eq(_msgs(b).size(), 1, "speaking again after the window")
	# commerce has its own, longer limit and does not use the general quota
	a.send(Protocol.chat_send(Chat.COMMERCE, "un"))
	a.send(Protocol.chat_send(Chat.COMMERCE, "deux"))
	Players._run(t, 0.1)
	eq(_msgs(b).size(), 1, "one commerce message a minute")
	eq(str(a.take(Protocol.ERROR)[0]["code"]), Protocol.E_CHAT_FLOOD)
	Players._run(t, 60.0)
	a.send(Protocol.chat_send(Chat.COMMERCE, "trois"))
	Players._run(t, 0.1)
	eq(_msgs(b).size(), 1, "and again after a minute")


func test_fight_chat_stays_among_the_fighters() -> void:
	var t := _trio()
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	var group := -1
	for act: SimActor in a.sim().get_map(1).actors.values():
		if act is MonsterGroup:
			group = act.id
	a.send(Protocol.fight_attack(group))
	Players._run(t, 0.2)
	check(a.player().fight_id != 0, "Alice is fighting")
	for conn: Players.Conn in t:
		conn.events.clear()
	a.send(Protocol.chat_send(Chat.GENERAL, "on se bat"))
	a.send(Protocol.chat_send(Chat.TEAM, "go"))
	b.send(Protocol.chat_send(Chat.GENERAL, "tu te bats ?"))
	a.send(Protocol.chat_send(Chat.COMMERCE, "vends en plein combat"))
	Players._run(t, 0.1)
	eq(_msgs(a).size(), 3, "Alice hears her own general and team messages and her commerce message, not Bob's reply")
	var bob := _msgs(b)
	eq(bob.map(func(m: Dictionary) -> String: return str(m["channel"])), ["commerce", "general"], "Bob only gets the world channel (and his own words)")


func test_the_journal_keeps_what_was_said() -> void:
	var t := _trio()
	var a: Players.Conn = t[0]
	a.send(Protocol.chat_send(Chat.GENERAL, "un"))
	a.send(Protocol.chat_send(Chat.PRIVATE, "deux", "Bob"))
	a.send(Protocol.chat_send(Chat.PRIVATE, "perdu", "Zorg")) # refused: not logged
	Players._run(t, 0.1)
	var log: Array = a.sim().chat.log
	eq(log.size(), 2, "only what was delivered")
	eq([log[0]["channel"], log[0]["from"], log[0]["text"]], ["general", "Alice", "un"])
	eq([log[1]["to"], log[1]["text"]], ["Bob", "deux"])
	check(int(log[1]["unix_ms"]) > 0, "dated with the real clock")
	for i in Chat.LOG_SIZE + 10:
		a.sim().chat.log.append({"text": str(i)})
	a.send(Protocol.chat_send(Chat.COMMERCE, "x"))
	Players._run(t, 0.1)
	eq(a.sim().chat.log.size(), Chat.LOG_SIZE, "the journal is bounded")


# -- the client's view ---------------------------------------------------------

func test_chat_lines_are_escaped_and_labelled() -> void:
	var line := ChatPanel.line_for(Chat.message("general", "Alice", 1, "[b]gras[/b]", 0), "Bob")
	check(line.contains("Alice : ") and not line.contains("[b]gras"), "brackets are escaped: no BBCode from a player")
	check(ChatPanel.line_for(Chat.message("private", "Alice", 1, "x", 0, "Bob"), "Bob").contains("De Alice"), "received")
	check(ChatPanel.line_for(Chat.message("private", "Bob", 2, "x", 0, "Alice"), "Bob").contains("À Alice"), "sent")
	eq(ChatPanel.tab_title(Chat.GENERAL), "Général", "the Dofus name of the channel")


# -- the same over WebSockets --------------------------------------------------

func test_chat_over_websocket() -> void:
	var rig := NetTests.Rig.new()
	var a := rig.client("tiny", "Alice")
	rig.run(2.0, func() -> bool: return a.has(Protocol.MAP_ENTER))
	var b := rig.client("tiny", "Bob")
	rig.run(2.0, func() -> bool: return b.has(Protocol.MAP_ENTER))
	a.events.clear()
	b.events.clear()
	a.backend.send(Protocol.chat_send(Chat.GENERAL, "salut Bob"))
	check(rig.run(2.0, func() -> bool: return b.has(Protocol.CHAT_MSG)), "Bob hears Alice through the server")
	var got: Dictionary = b.take(Protocol.CHAT_MSG)[0]
	eq([str(got["from"]), str(got["text"]), int(got["from_id"]) == a.you], ["Alice", "salut Bob", true])
	b.backend.send(Protocol.chat_send(Chat.GENERAL, "/w Alice psst"))
	var private := func() -> bool: return a.events.any(func(e: Dictionary) -> bool: return e["t"] == Protocol.CHAT_MSG and e["channel"] == "private")
	check(rig.run(2.0, private), "the command is parsed by the server")
	var pm: Dictionary = a.take(Protocol.CHAT_MSG).filter(func(m: Dictionary) -> bool: return m["channel"] == "private")[0]
	eq([str(pm["from"]), str(pm["to"]), str(pm["text"])], ["Bob", "Alice", "psst"])
	a.backend.send(Protocol.chat_send(Chat.PRIVATE, "ou es-tu", "Nobody"))
	check(rig.run(2.0, func() -> bool: return a.has(Protocol.ERROR)), "an offline target is refused")
	var err: Dictionary = a.take(Protocol.ERROR)[0]
	eq(str(err["code"]), Protocol.E_PLAYER_OFFLINE)
	check(err.has("ref"), "the refusal carries the seq of the command")
	for i in 6:
		a.backend.send(Protocol.chat_send(Chat.COMMERCE, "x%d" % i))
	rig.run(1.0)
	check(a.take(Protocol.ERROR).any(func(e: Dictionary) -> bool: return e["code"] == Protocol.E_CHAT_FLOOD), "the anti-flood works on the server")
	eq(a.backend.schema_errors.size(), 0, "every event matches Protocol.SCHEMA")
	eq(b.backend.schema_errors.size(), 0)
	rig.host.shutdown()
