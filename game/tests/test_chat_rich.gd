## Chat, the rest of P3.02c that needs no guild: emotes (rules, map broadcast, refusals), the team
## channel of a fight (/t reaches the speaker's team only), the pieces of a chat line (smiley icons,
## item links with their tooltip) and the same flows over WebSockets (127.0.0.1, NetBackend).
extends TestCase

const Players := preload("res://tests/test_players.gd")
const NetTests := preload("res://tests/test_net.gd")


func _init() -> void:
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()
	Emotes.clear_cache()
	SpellBook.use_file("res://tests/fixtures/spells.json")


func _pair() -> Array:
	var server := Players._server()
	var a := Players.Conn.new(server, "Alice", Players.LOOK, "alice")
	var b := Players.Conn.new(server, "Bob", Players.LOOK, "bob")
	Players._run([a, b], 0.2)
	for c: Players.Conn in [a, b]:
		c.events.clear()
	return [a, b]


func _duel(t: Array) -> Fight:
	(t[0] as Players.Conn).send(ProtocolDuel.request("Bob"))
	Players._run(t, 0.1)
	(t[1] as Players.Conn).send(ProtocolDuel.accept("Alice"))
	Players._run(t, 0.1)
	return (t[0] as Players.Conn).sim().fights.values()[0]


## a free emote (no quest gives it) and one that a quest gives
static func _free_emote() -> int:
	for k: Variant in GameData.table("emoticons"):
		if Emotes.usable(int(k), []):
			return int(k)
	return 0


static func _earned_emote() -> int:
	for k: Variant in Emotes.rewarded():
		var row := GameData.row("emoticons", int(k))
		if int(k) > 0 and not row.is_empty() and str(row["criterion"]) == "":
			return int(k)
	return 0


static func _usable_smiley() -> int:
	for k: Variant in GameData.table("smileys"):
		if Chat.smiley_usable(int(k)):
			return int(k)
	return 0


# -- rules and messages -----------------------------------------------------------------------

func test_emote_rules() -> void:
	var free := _free_emote()
	var earned := _earned_emote()
	check(free > 0 and earned > 0, "the tables have a free and an earned emote")
	check(Emotes.usable(free, []), "a free emote")
	check(not Emotes.usable(earned, []), "an emote a quest gives must be earned")
	check(Emotes.usable(earned, [earned]), "...and is usable once earned")
	check(not Emotes.usable(999999, []), "an unknown emote")
	check(Emotes.anim(free).begins_with("AnimEmote"), "emoticons.animName")


func test_messages_match_the_schema() -> void:
	eq(Protocol.validate(Protocol.roundtrip(ProtocolEmote.emote(1)), Protocol.C2S), "")
	eq(Protocol.validate(Protocol.roundtrip(ProtocolEmote.play(3, 1, "AnimEmoteSit", 1250)), Protocol.S2C), "")
	check(Protocol.ERROR_CODES.has(ProtocolEmote.E_UNKNOWN_EMOTE) and ErrorTexts.TEXTS.has(ProtocolEmote.E_UNKNOWN_EMOTE), "the error is listed and has its text")


# -- emotes through LocalBackend ---------------------------------------------------------------

func test_the_map_sees_an_emote() -> void:
	var server := Players._server()
	var a := Players.Conn.new(server, "Alice")
	var b := Players.Conn.new(server, "Bob")
	var c := Players.Conn.new(server, "Carol")
	var sim: WorldSim = server.worlds["duo"]
	sim.get_map(1).remove_actor(c.player())
	sim.enter_map(c.player(), sim.get_map(2), 300)
	var t := [a, b, c]
	Players._run(t, 0.2)
	for x: Players.Conn in t:
		x.events.clear()
	var free := _free_emote()
	a.send(ProtocolEmote.emote(free))
	Players._run(t, 0.1)
	for who: Players.Conn in [a, b]:
		var ev: Array = who.take(ProtocolEmote.EMOTE_PLAY)
		eq(ev.size(), 1, "the map sees it")
		eq([int(ev[0]["actor"]), int(ev[0]["emote"]), str(ev[0]["anim"])], [a.player().id, free, Emotes.anim(free)])
	eq(c.take(ProtocolEmote.EMOTE_PLAY).size(), 0, "another map does not")
	a.send(ProtocolEmote.emote(_earned_emote()))
	a.send(ProtocolEmote.emote(999999))
	Players._run(t, 0.1)
	var codes: Array = a.take(Protocol.ERROR).map(func(e: Dictionary) -> String: return str(e["code"]))
	eq(codes, [ProtocolEmote.E_UNKNOWN_EMOTE, ProtocolEmote.E_UNKNOWN_EMOTE], "not earned, unknown")
	a.player().character.emotes.append(_earned_emote())
	a.send(ProtocolEmote.emote(_earned_emote()))
	Players._run(t, 0.1)
	eq(a.take(ProtocolEmote.EMOTE_PLAY).size(), 1, "an earned emote is played")


func test_no_emote_in_a_fight() -> void:
	var t := _pair()
	_duel(t)
	(t[0] as Players.Conn).send(ProtocolEmote.emote(_free_emote()))
	Players._run(t, 0.1)
	var codes: Array = (t[0] as Players.Conn).take(Protocol.ERROR).map(func(e: Dictionary) -> String: return str(e["code"]))
	eq(codes, [Protocol.E_IN_FIGHT])
	eq((t[1] as Players.Conn).take(ProtocolEmote.EMOTE_PLAY).size(), 0)


# -- team channel ------------------------------------------------------------------------------

func test_team_channel_reaches_the_speakers_team_only() -> void:
	var t := _pair()
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	var fight := _duel(t)
	a.take(Protocol.CHAT_MSG)
	b.take(Protocol.CHAT_MSG)
	a.send(Protocol.chat_send(Chat.TEAM, "on les aura"))
	Players._run(t, 0.1)
	eq(a.take(Protocol.CHAT_MSG).size(), 1, "the speaker hears its own team channel")
	eq(b.take(Protocol.CHAT_MSG).size(), 0, "the other team does not")
	a.send(Protocol.chat_send(Chat.GENERAL, "gl"))
	Players._run(t, 0.1)
	eq(b.take(Protocol.CHAT_MSG).size(), 1, "general is still heard by every fighter")
	# Bob joins Alice's team: now he hears
	fight.fighters[b.player().id].team = 0
	a.send(Protocol.chat_send(Chat.TEAM, "ensemble"))
	Players._run(t, 0.1)
	eq(b.take(Protocol.CHAT_MSG).size(), 1, "a teammate hears")
	# out of a fight the channel does not exist
	var t2 := _pair()
	(t2[0] as Players.Conn).send(Protocol.chat_send(Chat.TEAM, "seul"))
	Players._run(t2, 0.1)
	eq(str((t2[0] as Players.Conn).take(Protocol.ERROR)[0]["code"]), Protocol.E_NOT_IN_FIGHT)


# -- the client: pieces of a line, smiley icons, item tooltip ----------------------------------

func test_a_chat_line_is_cut_in_pieces() -> void:
	var p := ChatLog.pieces("a {smiley:3} b {item:683} {item:9} {smiley:99}", [683], [3])
	eq(p, [{"text": "a "}, {"smiley": 3}, {"text": " b "}, {"item": 683}, {"text": " {item:9} {smiley:99}"}], "only what the sim kept")
	eq(ChatLog.pieces("rien", [], []), [{"text": "rien"}])


func test_the_log_writes_icons_and_links() -> void:
	var log := ChatLog.new()
	var smiley := _usable_smiley()
	var item := int(GameData.item_ids()[0])
	var ev := {"t": Protocol.CHAT_MSG, "channel": "general", "from": "Alice", "from_id": 1, "text": "yo {smiley:%d} [b] {item:%d}" % [smiley, item], "at": 0, "smileys": [smiley], "links": [item]}
	log.write("Alice", ev, Color.WHITE)
	var text := log.get_parsed_text()
	check(text.begins_with("Alice : yo "), "head and text: " + text)
	check(text.contains("[b]"), "a player's brackets stay text")
	check(text.contains("[" + ChatPanel.item_name(item) + "]"), "the item link shows the item's name")
	check(not text.contains("{item"), "no raw link")
	# hovering the link asks for the item tooltip, leaving it takes it away
	check(log._make_custom_tooltip("") == null, "no tooltip off a link")
	log._on_hover_started("item:%d" % item)
	eq(log.hovered_item, item)
	var tip := log._make_custom_tooltip(log.tooltip_text)
	check(tip != null and tip is Control, "the item tooltip")
	if tip != null:
		(tip as Node).free()
	log._on_hover_ended("item:%d" % item)
	eq([log.hovered_item, log.tooltip_text], [0, ""])
	log.free()


func test_the_emote_command_finds_its_emote() -> void:
	var free := _free_emote()
	eq(ChatPanel.emote_id(str(free)), free, "a bare id")
	eq(ChatPanel.emote_id("999999"), 0, "an unknown id")
	eq(ChatPanel.emote_id(""), 0)


# -- the same over WebSockets ------------------------------------------------------------------

func test_emotes_and_team_chat_over_websocket() -> void:
	var rig := NetTests.Rig.new()
	var a := rig.client("tiny", "Alice")
	rig.run(2.0, func() -> bool: return a.has(Protocol.MAP_ENTER))
	var b := rig.client("tiny", "Bob")
	rig.run(2.0, func() -> bool: return b.has(Protocol.MAP_ENTER))
	a.events.clear()
	b.events.clear()
	var free := _free_emote()
	a.backend.send(ProtocolEmote.emote(free))
	check(rig.run(2.0, func() -> bool: return b.has(ProtocolEmote.EMOTE_PLAY)), "Bob sees the emote through the server")
	var ev: Dictionary = b.take(ProtocolEmote.EMOTE_PLAY)[0]
	eq([int(ev["actor"]) == a.you, int(ev["emote"]), str(ev["anim"])], [true, free, Emotes.anim(free)], "ints survive JSON")
	a.backend.send(ProtocolEmote.emote(999999))
	check(rig.run(2.0, func() -> bool: return a.has(Protocol.ERROR)), "an unknown emote is refused")
	var err: Dictionary = a.take(Protocol.ERROR)[0]
	eq([str(err["code"]), err.has("ref")], [ProtocolEmote.E_UNKNOWN_EMOTE, true])
	# a duel, then /t
	a.backend.send(ProtocolDuel.request("Bob"))
	rig.run(2.0, func() -> bool: return b.has(ProtocolDuel.REQUESTED))
	b.backend.send(ProtocolDuel.accept("Alice"))
	check(rig.run(2.0, func() -> bool: return a.has(Protocol.FIGHT_START) and b.has(Protocol.FIGHT_START)), "the duel starts")
	a.events.clear()
	b.events.clear()
	a.backend.send(Protocol.chat_send(Chat.GENERAL, "/t equipe"))
	check(rig.run(2.0, func() -> bool: return a.has(Protocol.CHAT_MSG)), "the /t command is parsed by the server")
	var msg: Dictionary = a.take(Protocol.CHAT_MSG)[0]
	eq([str(msg["channel"]), str(msg["text"])], ["team", "equipe"])
	rig.run(0.5)
	eq(b.take(Protocol.CHAT_MSG).size(), 0, "the other team hears nothing through the server")
	eq(a.backend.schema_errors.size() + b.backend.schema_errors.size(), 0, "every event matches the schema: %s" % [a.backend.schema_errors])


func test_the_bubble_text_has_no_markers() -> void:
	var ev := {"text": "a {smiley:3} b {item:9}", "smileys": [3], "links": []}
	eq(ChatPanel.plain_text(ev), "a ☺ b {item:9}")
