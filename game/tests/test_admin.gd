## GM console (roadmap A1.01): the commands of WorldAdmin through LocalBackend (role, give,
## kamas, level, heal, say, who, kick, ban, mute), the audit trail, and the same flow through a
## ServerHost with accounts over WebSockets (127.0.0.1): kick and ban cut the real connection and
## the audit file holds every command.
extends TestCase

const Players := preload("res://tests/test_players.gd")
const Accounts := preload("res://tests/test_accounts.gd")

const LOOK := "{1|120,2195||56}"
const POTION := 683 # an item of game/data

var _conns: Array = []


func _init() -> void:
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()
	SpellBook.use_file("res://tests/fixtures/spells.json")


## A GM "Boss" and a player "Joe" (two accounts) in the duo world.
func _pair() -> Array:
	_conns = []
	var server := Players._server()
	var boss := Players.Conn.new(server, "Boss", LOOK, "boss")
	var joe := Players.Conn.new(server, "Joe", LOOK, "joe")
	joe.player().gm = false
	Players._run([boss, joe], 0.2)
	boss.events.clear()
	joe.events.clear()
	_conns = [boss, joe]
	return [boss, joe]


func _cmd(c: Players.Conn, what: String, args := []) -> void:
	c.send(Protocol.admin_cmd(what, args))
	Players._run(_conns, 0.1)


func _result(c: Players.Conn) -> Dictionary:
	var r := c.take(ProtocolAdmin.ADMIN_RESULT)
	return r[0] if not r.is_empty() else {}


## JSON hands numbers back as floats (rule 3 of the protocol)
func _ints(args: Array) -> Array:
	return args.map(func(x: Variant) -> Variant: return int(x) if x is float else x)


func _error(c: Players.Conn) -> String:
	var e := c.take(Protocol.ERROR)
	return str(e[0]["code"]) if not e.is_empty() else ""


# -- the commands ---------------------------------------------------------------

func test_protocol_messages_are_valid_and_json_safe() -> void:
	for msg: Dictionary in [ProtocolAdmin.admin_result("who", ["Boss", "Joe"]), ProtocolAdmin.announce("Boss", "salut")]:
		eq(Protocol.validate(Protocol.roundtrip(msg), Protocol.S2C), "", str(msg))
		check(Protocol.is_json_safe(msg))
	for code: String in ProtocolAdmin.ERROR_CODES:
		check(Protocol.ERROR_CODES.has(code) and ErrorTexts.TEXTS.has(code), "%s is a known error with a text" % code)
	eq(ProtocolAdmin.C2S, Protocol.C2S)
	eq(ProtocolAdmin.S2C, Protocol.S2C)
	eq(CommandLine.parse("/say bonjour, tout le monde"), Protocol.admin_cmd("say", ["bonjour,", "tout", "le", "monde"]), "a comma is text outside /tp")


func test_commands_need_the_gm_role_and_are_audited() -> void:
	var p := _pair()
	var boss: Players.Conn = p[0]
	var joe: Players.Conn = p[1]
	_cmd(joe, "kamas", ["1000"])
	eq(_error(joe), Protocol.E_NOT_GM, "a player cannot run GM commands")
	eq(joe.player().character.kamas, 0, "nothing changed")
	_cmd(joe, "kick", ["Boss"])
	eq(_error(joe), Protocol.E_NOT_GM)
	check(boss.sim().players.has(boss.backend.player_id), "Boss is still there")
	_cmd(boss, "kamas", ["5"])
	var log: Array = boss.sim().admin.audit_log
	eq(log.size(), 3, "every command is in the audit trail, refused or not")
	eq([log[0]["name"], log[0]["cmd"], log[0]["ok"], log[0]["code"]], ["Joe", "kamas", false, Protocol.E_NOT_GM])
	eq([log[2]["name"], log[2]["account"], log[2]["ok"]], ["Boss", "boss", true])
	check(int(log[2]["at"]) > 0 and log[2]["world"] == "duo", "dated and tied to its world")


func test_give_kamas_level_heal() -> void:
	var p := _pair()
	var boss: Players.Conn = p[0]
	var joe: Players.Conn = p[1]
	_cmd(boss, "give", [str(POTION), "3", "joe"])
	eq(_ints(_result(boss)["args"]), ["Joe", POTION, 3], "the result names who got what")
	eq(joe.take(Protocol.ITEM_ADDED).size(), 1, "Joe is told of the item")
	var qty := 0
	for it: Dictionary in joe.player().character.inventory.items.values():
		if int(it["id"]) == POTION:
			qty += int(it["qty"])
	eq(qty, 3)
	_cmd(boss, "give", ["99999999"])
	eq(_error(boss), Protocol.E_UNKNOWN_ITEM)
	_cmd(boss, "give", [str(POTION), "0"])
	eq(_error(boss), Protocol.E_BAD_MESSAGE, "a quantity of 0")
	_cmd(boss, "give", [str(POTION), "1", "Nobody"])
	eq(_error(boss), Protocol.E_PLAYER_OFFLINE)
	_cmd(boss, "kamas", ["1500", "Joe"])
	eq(joe.player().character.kamas, 1500)
	check(not joe.take(Protocol.PLAYER_STATS).is_empty(), "Joe's sheet is sent")
	_cmd(boss, "kamas", ["-5000", "Joe"])
	eq(joe.player().character.kamas, 0, "kamas never go below 0")
	_cmd(boss, "level", ["120", "Joe"])
	var c: Character = joe.player().character
	eq([c.level, c.xp, c.capital], [120, GameData.xp_floor(120), 5 * 119], "level 120: its XP, the capital of a fresh one")
	_cmd(boss, "level", ["9999"])
	eq(_error(boss), Protocol.E_BAD_MESSAGE)
	c.life = Energy.GHOST
	c.energy = 0
	c.set_hp(1, boss.sim().now)
	_cmd(boss, "heal", ["Joe"])
	eq([c.life, c.energy, c.hp_at(boss.sim().now) == c.max_hp()], [Energy.ALIVE, Energy.MAX, true], "a ghost is alive again, with full health and energy")
	var saved := boss.server.persistence.load_character("duo", "Joe")
	eq(int(saved["level"]), 120, "the change is persisted")


func test_say_who_and_unknown_commands() -> void:
	var p := _pair()
	var boss: Players.Conn = p[0]
	var joe: Players.Conn = p[1]
	_cmd(boss, "say", ["serveur", "redémarré", "bientôt"])
	eq(_result(boss)["cmd"], "say")
	var heard: Array = joe.take(ProtocolAdmin.ANNOUNCE)
	eq([heard.size(), heard[0]["from"], heard[0]["text"]], [1, "Boss", "serveur redémarré bientôt"], "everyone hears the announcement")
	_cmd(boss, "who")
	eq(_result(boss)["args"], ["Boss", "Joe"])
	_cmd(boss, "fly")
	eq(_error(boss), Protocol.E_UNKNOWN_COMMAND)
	_cmd(boss, "say")
	eq(_error(boss), Protocol.E_BAD_MESSAGE)
	_cmd(boss, "reload")
	eq(_result(boss)["cmd"], "reload")
	check(GameData.max_level() > 100, "the data comes back after a reload")
	eq(ChatPanel.admin_line("give", ["Joe", 683, 3]), "Joe reçoit l'objet 683 x3")
	eq(ChatPanel.admin_line("who", ["A", "B"]), "2 joueur(s) : A, B")
	eq(ChatPanel.admin_line("give", ["Joe", 683.0, 3.0]), "Joe reçoit l'objet 683 x3", "floats after JSON")
	eq(ChatPanel.admin_line("zzz", []), "/zzz : fait")


func test_mute_blocks_chat_until_it_ends_or_is_lifted() -> void:
	var p := _pair()
	var boss: Players.Conn = p[0]
	var joe: Players.Conn = p[1]
	_cmd(boss, "mute", ["Joe", "5"])
	eq(_ints(_result(boss)["args"]), ["Joe", 5])
	joe.send(Protocol.chat_send(Chat.GENERAL, "coucou"))
	Players._run([boss, joe], 0.2)
	var err: Dictionary = joe.take(Protocol.ERROR)[0]
	eq(str(err["code"]), ProtocolAdmin.E_MUTED)
	check(int(str(err["msg"])) > 290, "the wait is in seconds (%s)" % err["msg"])
	check(boss.take(Protocol.CHAT_MSG).is_empty(), "nobody heard it")
	joe.send(Protocol.chat_send(Chat.PRIVATE, "psst", "Boss"))
	Players._run([boss, joe], 0.2)
	eq(str(joe.take(Protocol.ERROR)[0]["code"]), ProtocolAdmin.E_MUTED, "private messages too")
	boss.server.clock.advance(6 * 60000)
	joe.send(Protocol.chat_send(Chat.GENERAL, "me revoilà"))
	Players._run([boss, joe], 0.2)
	check(not boss.take(Protocol.CHAT_MSG).is_empty(), "the mute ended by itself")
	_cmd(boss, "mute", ["Joe"])
	eq(_ints(_result(boss)["args"]), ["Joe", WorldAdmin.MUTE_DEFAULT_MIN], "ten minutes by default")
	_cmd(boss, "unmute", ["Joe"])
	joe.send(Protocol.chat_send(Chat.GENERAL, "libre"))
	Players._run([boss, joe], 0.2)
	check(not boss.take(Protocol.CHAT_MSG).is_empty(), "unmute lifts it")
	_cmd(boss, "mute", ["Joe", "0"])
	eq(_error(boss), Protocol.E_BAD_MESSAGE, "minutes 1 to a week")


func test_kick_and_ban_end_the_session_and_ban_holds() -> void:
	var p := _pair()
	var boss: Players.Conn = p[0]
	var joe: Players.Conn = p[1]
	var sim := boss.sim()
	_cmd(boss, "kick", ["Nobody"])
	eq(_error(boss), Protocol.E_PLAYER_OFFLINE)
	_cmd(boss, "kick", ["joe"])
	Players._run([boss, joe], 0.2)
	eq(_result(boss)["args"], ["Joe"])
	check(joe.take(Protocol.ERROR).any(func(e: Dictionary) -> bool: return e["code"] == ProtocolAdmin.E_KICKED), "Joe is told")
	check(joe.backend.session.kicked, "the session is marked for the host")
	check(not sim.players.has(joe.backend.player_id) and sim.players.size() == 1, "Joe left the world")
	check(not boss.server.persistence.load_character("duo", "Joe").is_empty(), "his character was saved")
	# a kick is not a ban: he can come back
	var back := Players.Conn.new(boss.server, "Joe", LOOK, "joe")
	check(back.events.any(func(e: Dictionary) -> bool: return e["t"] == Protocol.WELCOME), "welcome back")
	_cmd(boss, "ban", ["Boss"])
	eq(_error(boss), Protocol.E_BAD_MESSAGE, "a GM cannot ban itself")
	_cmd(boss, "ban", ["Ghost"])
	eq(_error(boss), Protocol.E_UNKNOWN_CHARACTER, "no such character")
	_cmd(boss, "ban", ["Joe", "insultes", "répétées"])
	Players._run([boss, back], 0.2)
	check(back.take(Protocol.ERROR).any(func(e: Dictionary) -> bool: return e["code"] == ProtocolAdmin.E_BANNED), "a connected player is thrown out")
	eq(Sanctions.ban_of(boss.server.persistence, "joe")["reason"], "insultes répétées")
	eq(Sanctions.ban_of(boss.server.persistence, "joe")["by"], "Boss")
	var again := Players.Conn.new(boss.server, "Joe", LOOK, "joe")
	check(again.events.any(func(e: Dictionary) -> bool: return e["t"] == Protocol.ERROR and e["code"] == ProtocolAdmin.E_BANNED), "the banned account cannot hello")
	check(not again.events.any(func(e: Dictionary) -> bool: return e["t"] == Protocol.WELCOME))
	var other := Players.Conn.new(boss.server, "Joe2", LOOK, "joe") # a new character of the account is no way round
	check(not other.events.any(func(e: Dictionary) -> bool: return e["t"] == Protocol.WELCOME), "nor a new character")
	_cmd(boss, "unban", ["Joe"]) # by character name, Joe being offline
	eq(_result(boss)["args"], ["Joe"])
	var free := Players.Conn.new(boss.server, "Joe", LOOK, "joe")
	check(free.events.any(func(e: Dictionary) -> bool: return e["t"] == Protocol.WELCOME), "unbanned: he plays again")
	_cmd(boss, "unban", ["Joe"])
	eq(_error(boss), Protocol.E_UNKNOWN_CHARACTER, "not banned any more")
	check(not Sanctions.is_banned(boss.server.persistence, "joe") and not boss.server.persistence.load_account("joe").has("sanction"), "no trace left in the account")


func test_sanctions_keep_the_rest_of_the_account() -> void:
	var store := Persistence.new()
	store.save_account("jean", {"auth": {"role": "player"}, "bank": {"kamas": 7}})
	Sanctions.ban(store, "jean", "x", "Boss", 1000)
	Sanctions.mute(store, "jean", 5000)
	var doc := store.load_account("jean")
	eq([doc["auth"]["role"], doc["bank"]["kamas"]], ["player", 7], "credentials and bank untouched")
	eq(Sanctions.mute_left_ms(store, "jean", 2000), 3000)
	eq(Sanctions.mute_left_ms(store, "jean", 9000), 0)
	check(Sanctions.unban(store, "jean") and not Sanctions.unban(store, "jean"))
	Sanctions.mute(store, "jean", 0)
	eq(store.load_account("jean").has("sanction"), false)


# -- over WebSockets, with accounts and the audit file -----------------------------

func _login(rig: Accounts.Rig, login: String, name: String) -> Accounts.Client:
	var c := rig.client()
	rig.ask(c, Protocol.login(login, "secret1"), Protocol.LOGIN_OK)
	c.backend.send(Protocol.hello("tiny", name, LOOK))
	rig.run(5.0, func() -> bool: return c.has(Protocol.WELCOME))
	return c


func _ws_cmd(rig: Accounts.Rig, c: Accounts.Client, what: String, args := []) -> void:
	c.events.clear()
	c.backend.send(Protocol.admin_cmd(what, args))
	rig.run(3.0, func() -> bool: return c.has(ProtocolAdmin.ADMIN_RESULT) or c.has(Protocol.ERROR))


func test_console_over_websocket_with_audit_file() -> void:
	var audit_path := "user://test_admin/audit.jsonl"
	DirAccess.remove_absolute(audit_path)
	var rig := Accounts.Rig.new()
	rig.host.ticks = func() -> int: return rig.virtual_ms # virtual time: the kick's grace time passes with the rig
	rig.host.set_audit_log(AuditLog.new(audit_path))
	var store: AccountStore = rig.host.auth.accounts
	store.register("boss", "secret1")
	store.set_role("boss", AccountStore.ROLE_GM) # the role is the account's: read at login
	store.register("joe", "secret1")
	var boss := _login(rig, "boss", "Boss")
	var joe := _login(rig, "joe", "Joe")
	_ws_cmd(rig, joe, "kamas", ["10"])
	eq(str(joe.take(Protocol.ERROR)[0]["code"]), Protocol.E_NOT_GM, "the role comes from the account, not from the client")
	_ws_cmd(rig, boss, "who")
	eq((boss.take(ProtocolAdmin.ADMIN_RESULT)[0]["args"] as Array).size(), 2, "who: both are there")
	_ws_cmd(rig, boss, "kamas", ["250", "Joe"])
	eq(int(boss.take(ProtocolAdmin.ADMIN_RESULT)[0]["args"][1]), 250)
	var sim: WorldSim = rig.host.server.worlds["tiny"]
	eq(sim.players.values().filter(func(q: PlayerActor) -> bool: return q.name == "Joe")[0].character.kamas, 250)
	# kick: Joe's real connection is cut, and he can log in again
	_ws_cmd(rig, boss, "kick", ["Joe"])
	check(rig.run(3.0, func() -> bool: return joe.backend.state != "open"), "the socket of the kicked player closes")

	check(joe.events.any(func(e: Dictionary) -> bool: return e["t"] == Protocol.ERROR and e["code"] == ProtocolAdmin.E_KICKED), "he got the reason first")
	eq(sim.players.size(), 1, "Joe left the world")
	rig.clients.erase(joe)
	var joe2 := rig.client()
	check(not rig.ask(joe2, Protocol.login("joe", "secret1"), Protocol.LOGIN_OK).is_empty(), "a kick is not a ban: the account logs in again")
	joe2.backend.send(Protocol.hello("tiny", "Joe", LOOK))
	rig.run(3.0, func() -> bool: return joe2.has(Protocol.WELCOME))
	# ban: cut at once, then refused at login
	_ws_cmd(rig, boss, "ban", ["Joe", "test"])
	check(rig.run(3.0, func() -> bool: return joe2.backend.state != "open"), "the banned player's socket closes")
	rig.clients.erase(joe2)
	var joe3 := rig.client()
	var refused := rig.ask(joe3, Protocol.login("joe", "secret1"), Protocol.LOGIN_ERROR)
	eq(str(refused.get("code")), ProtocolAdmin.E_BANNED, "login_error banned")
	var wrong := rig.ask(joe3, Protocol.login("joe", "nope-nope"), Protocol.LOGIN_ERROR)
	eq(str(wrong.get("code")), Protocol.E_BAD_CREDENTIALS, "banned status is not leaked without the password")
	_ws_cmd(rig, boss, "unban", ["joe"])
	check(not rig.ask(joe3, Protocol.login("joe", "secret1"), Protocol.LOGIN_OK).is_empty(), "unban: back in")
	eq(boss.backend.schema_errors.size(), 0, "every event matches Protocol.SCHEMA")
	# the audit file: one line per command, in order, refused ones included
	var lines := rig.host.audit.read_all()
	eq(lines.map(func(e: Dictionary) -> String: return str(e["cmd"])), ["kamas", "who", "kamas", "kick", "ban", "unban"], "every command is in the file")
	eq([lines[0]["name"], lines[0]["ok"], lines[0]["code"]], ["Joe", false, Protocol.E_NOT_GM])
	eq([lines[4]["account"], lines[4]["args"], lines[4]["ok"]], ["boss", ["Joe", "test"], true])
	check(not FileAccess.get_file_as_string(audit_path).contains("secret1"), "no password in the audit")
	rig.shutdown()
	DirAccess.remove_absolute(audit_path)


## Found by the trial on a real server (docs/ESSAI_SERVEUR.md): a client that sends numbers (not
## strings) in `args` got bad_message, because JSON returns 250 as 250.0 and "250.0" is no integer.
## The role announced by login_ok is also the GM one when the host grants it (--gm).
func test_numeric_args_and_the_role_announced_to_a_gm_account() -> void:
	var rig := Accounts.Rig.new()
	rig.host.ticks = func() -> int: return rig.virtual_ms
	rig.host.gm_accounts = PackedStringArray(["boss"])
	var store: AccountStore = rig.host.auth.accounts
	store.register("boss", "secret1")
	store.register("joe", "secret1")
	var boss := rig.client()
	var ok := rig.ask(boss, Protocol.login("boss", "secret1"), Protocol.LOGIN_OK)
	eq(str(ok.get("role")), AccountStore.ROLE_GM, "login_ok says gm for an account of --gm")
	eq(boss.backend.role, AccountStore.ROLE_GM)
	boss.backend.send(Protocol.hello("tiny", "Boss", LOOK))
	rig.run(5.0, func() -> bool: return boss.has(Protocol.WELCOME))
	var joe := _login(rig, "joe", "Joe")
	eq(joe.backend.role, "player", "the other account stays a player")
	_ws_cmd(rig, boss, "kamas", [250, "Joe"])
	check(boss.has(ProtocolAdmin.ADMIN_RESULT), "numbers in args are accepted over JSON: %s" % [boss.events])
	var sim: WorldSim = rig.host.server.worlds["tiny"]
	eq(sim.players.values().filter(func(q: PlayerActor) -> bool: return q.name == "Joe")[0].character.kamas, 250)
	_ws_cmd(rig, boss, "give", [POTION, 2, "Joe"])
	check(joe.has(Protocol.ITEM_ADDED), "give with numeric item and quantity")
	rig.shutdown()
