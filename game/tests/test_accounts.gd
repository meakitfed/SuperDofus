## Accounts of a server (roadmap S.02a): register / login over real WebSockets in this
## process (like test_net), one live connection per account, session tokens, and the
## password never stored. Hash rounds are lowered so the tests stay fast.
extends TestCase

const LOOK := "{1|120,2195||56}"
const STEP := 0.05
const SAVE_DIR := "user://test_accounts"


class Rig:
	var host := ServerHost.new()
	var clients: Array[Client] = []
	var virtual_ms := 0

	func _init(persistence := Persistence.new()) -> void:
		host.server.persistence = persistence
		host.server.sources["tiny"] = WorldSource.from_dicts(
			{"id": "tiny", "name": "Tiny", "start_map": 1, "start_cell": 300},
			[{"id": 1, "coords": [0, 0], "neighbors": {}}])
		var store := AccountStore.new(persistence)
		store.iterations = 1000
		host.auth = AuthService.new(store)
		host.listen(0, "127.0.0.1")

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

	## Sends one command and waits for the answer `type` (login_ok, login_error, error...).
	func ask(c: Client, cmd: Dictionary, type: String) -> Dictionary:
		c.backend.send(cmd)
		run(5.0, func() -> bool: return c.has(type))
		var got := c.take(type)
		return got[0] if not got.is_empty() else {}

	func close(c: Client) -> void:
		c.backend.close()
		run(1.0, func() -> bool: return host.connections < clients.size() - 1)
		clients.erase(c)

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


func test_register_then_login_and_play() -> void:
	var rig := Rig.new()
	var a := rig.client()
	var ok := rig.ask(a, Protocol.register("Jean", "secret1"), Protocol.LOGIN_OK)
	eq(str(ok.get("login")), "jean") # logins are case-insensitive, stored lowercase
	eq(str(ok.get("role")), "player")
	eq(str(ok.get("token")).length(), 64) # 32 bytes in hex
	eq(a.backend.token, str(ok.get("token")))
	rig.close(a)
	var b := rig.client()
	var again := rig.ask(b, Protocol.login("JEAN", "secret1"), Protocol.LOGIN_OK)
	check(not again.is_empty(), "the account logs in again, whatever the case of the login")
	check(str(again["token"]) != str(ok["token"]), "a new token for a new connection")
	b.backend.send(Protocol.hello("tiny", "Hero", LOOK))
	check(rig.run(5.0, func() -> bool: return b.has(Protocol.WELCOME)), "a logged-in account plays")
	eq(rig.host.server.worlds["tiny"].players.values()[0].character.account, "jean")
	rig.shutdown()


func test_wrong_password_and_unknown_login_are_the_same_refusal() -> void:
	var rig := Rig.new()
	var a := rig.client()
	rig.ask(a, Protocol.register("jean", "secret1"), Protocol.LOGIN_OK)
	rig.close(a)
	var b := rig.client()
	var bad := rig.ask(b, Protocol.login("jean", "wrong-password"), Protocol.LOGIN_ERROR)
	eq(str(bad["code"]), Protocol.E_BAD_CREDENTIALS)
	var unknown := rig.ask(b, Protocol.login("nobody", "secret1"), Protocol.LOGIN_ERROR)
	eq(str(unknown["code"]), Protocol.E_BAD_CREDENTIALS) # never says which of the two was wrong
	b.backend.send(Protocol.hello("tiny", "Hero", LOOK))
	var err := rig.ask(b, Protocol.hello("tiny", "Hero", LOOK), Protocol.ERROR)
	eq(str(err["code"]), Protocol.E_NOT_LOGGED_IN)
	check(rig.host.server.worlds.is_empty() or rig.host.server.worlds["tiny"].players.is_empty(), "nobody entered the world")
	rig.shutdown()


func test_second_connection_of_an_account_is_refused() -> void:
	var rig := Rig.new()
	var a := rig.client()
	rig.ask(a, Protocol.register("jean", "secret1"), Protocol.LOGIN_OK)
	var b := rig.client()
	var refused := rig.ask(b, Protocol.login("jean", "secret1"), Protocol.LOGIN_ERROR)
	eq(str(refused["code"]), Protocol.E_ALREADY_CONNECTED)
	var wrong := rig.ask(b, Protocol.login("jean", "not-the-password"), Protocol.LOGIN_ERROR)
	eq(str(wrong["code"]), Protocol.E_BAD_CREDENTIALS) # online status is not leaked without the password
	rig.close(a)
	var free := rig.ask(b, Protocol.login("jean", "secret1"), Protocol.LOGIN_OK)
	check(not free.is_empty(), "once the first connection ended, the account can log in")
	rig.shutdown()


func test_token_lives_with_its_connection() -> void:
	var rig := Rig.new()
	var a := rig.client()
	var ok := rig.ask(a, Protocol.register("jean", "secret1"), Protocol.LOGIN_OK)
	var token := str(ok["token"])
	eq(rig.host.auth.login_for_token(token), "jean")
	eq(rig.host.auth.login_for_token("0".repeat(64)), "")
	eq(rig.host.auth.login_for_token(""), "")
	rig.close(a)
	eq(rig.host.auth.login_for_token(token), "") # a dead connection's token is useless
	check(not rig.host.auth.is_online("jean"), "the account is free again")
	rig.shutdown()


func test_register_rules() -> void:
	var rig := Rig.new()
	var a := rig.client()
	eq(str(rig.ask(a, Protocol.register("ab", "secret1"), Protocol.LOGIN_ERROR)["code"]), Protocol.E_BAD_LOGIN)
	eq(str(rig.ask(a, Protocol.register("../etc", "secret1"), Protocol.LOGIN_ERROR)["code"]), Protocol.E_BAD_LOGIN)
	eq(str(rig.ask(a, Protocol.register("jean", "short"), Protocol.LOGIN_ERROR)["code"]), Protocol.E_BAD_LOGIN)
	rig.ask(a, Protocol.register("jean", "secret1"), Protocol.LOGIN_OK)
	var b := rig.client()
	eq(str(rig.ask(b, Protocol.register("Jean", "other-secret"), Protocol.LOGIN_ERROR)["code"]), Protocol.E_LOGIN_TAKEN)
	rig.host.auth.accounts.registration_open = false
	eq(str(rig.ask(b, Protocol.register("paul", "secret1"), Protocol.LOGIN_ERROR)["code"]), Protocol.E_REGISTRATION_CLOSED)
	rig.shutdown()


func test_too_many_wrong_passwords_cut_the_connection() -> void:
	var rig := Rig.new()
	var a := rig.client()
	rig.ask(a, Protocol.register("jean", "secret1"), Protocol.LOGIN_OK)
	rig.close(a)
	var b := rig.client()
	for i in AuthService.MAX_FAILURES:
		rig.ask(b, Protocol.login("jean", "guess-%d" % i), Protocol.LOGIN_ERROR)
	check(rig.run(3.0, func() -> bool: return b.backend.state == "closed"), "the connection is cut after the last failure")
	rig.shutdown()


func test_gm_role_comes_from_the_account_document() -> void:
	var rig := Rig.new()
	var a := rig.client()
	rig.ask(a, Protocol.register("boss", "secret1"), Protocol.LOGIN_OK)
	rig.close(a)
	check(rig.host.auth.accounts.set_role("boss", "gm"), "role set by hand")
	var b := rig.client()
	var ok := rig.ask(b, Protocol.login("boss", "secret1"), Protocol.LOGIN_OK)
	eq(str(ok["role"]), "gm")
	b.backend.send(Protocol.hello("tiny", "Chef", LOOK))
	rig.run(5.0, func() -> bool: return b.has(Protocol.WELCOME))
	check(rig.host.server.worlds["tiny"].players.values()[0].gm, "the session of a gm account is gm")
	rig.shutdown()


func test_the_password_is_never_written() -> void:
	var password := "S3cret-Pass-Phrase"
	_wipe(SAVE_DIR)
	var rig := Rig.new(FilePersistence.new(SAVE_DIR))
	var a := rig.client()
	rig.ask(a, Protocol.register("jean", password), Protocol.LOGIN_OK)
	a.backend.send(Protocol.hello("tiny", "Hero", LOOK))
	rig.run(3.0, func() -> bool: return a.has(Protocol.WELCOME))
	rig.shutdown() # saves the character
	var files := _files(SAVE_DIR)
	check(files.size() >= 2, "an account and a character were saved")
	var doc := JSON.parse_string(FileAccess.get_file_as_string(SAVE_DIR + "/accounts/jean.json")) as Dictionary
	check(doc.has("auth") and doc["auth"].has("hash") and doc["auth"].has("salt"), "salt and hash stored")
	for f in files:
		check(not FileAccess.get_file_as_string(f).contains(password), "no password in " + f)
	_wipe(SAVE_DIR)


func test_password_hash() -> void:
	var a := PasswordHash.make("secret1", 500)
	var b := PasswordHash.make("secret1", 500)
	check(a["salt"] != b["salt"] and a["hash"] != b["hash"], "a random salt: two hashes of one password differ")
	check(PasswordHash.verify("secret1", a), "right password")
	check(not PasswordHash.verify("secret2", a), "wrong password")
	check(not PasswordHash.verify("secret1", {}), "no record")
	check(PasswordHash.same("abc", "abc") and not PasswordHash.same("abc", "abd") and not PasswordHash.same("abc", "ab"), "comparison")
	check(PasswordHash.digest("x", "s", 10) != PasswordHash.digest("x", "s", 11), "the number of rounds counts")


func test_protocol_messages_have_a_schema() -> void:
	for msg: Dictionary in [Protocol.register("jean", "secret1"), Protocol.login("jean", "secret1")]:
		eq(Protocol.validate(msg, Protocol.C2S), "")
	for msg: Dictionary in [Protocol.login_ok("t", "player", "jean"), Protocol.login_error(Protocol.E_BAD_CREDENTIALS, "login")]:
		eq(Protocol.validate(msg, Protocol.S2C), "")


func _files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_files(dir.path_join(d)))
	return out


func _wipe(dir: String) -> void:
	for f in _files(dir):
		DirAccess.remove_absolute(f)
	for d in DirAccess.get_directories_at(dir):
		_wipe(dir.path_join(d))
		DirAccess.remove_absolute(dir.path_join(d))
	DirAccess.remove_absolute(dir)
