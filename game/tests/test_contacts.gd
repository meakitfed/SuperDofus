## Friends, enemies, ignored (roadmap P3.05): the pure rules of shared/Contacts, the lists of an
## account through Persistence, the connection notices, the ignore filter of the chat, and the
## same flow through two logged-in accounts over WebSockets on 127.0.0.1.
extends TestCase

const Players := preload("res://tests/test_players.gd")
const Accounts := preload("res://tests/test_accounts.gd")


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


static func _lists(c: Players.Conn) -> Dictionary:
	var u := c.take(ProtocolContacts.CONTACTS)
	return u[-1] if not u.is_empty() else {}


static func _names(list: Array) -> Array:
	return list.map(func(e: Dictionary) -> String: return str(e["name"]))


static func _codes(c: Players.Conn) -> Array:
	return c.take(Protocol.ERROR).map(func(e: Dictionary) -> String: return str(e["code"]))


# -- shared/Contacts: pure rules -------------------------------------------------------

func test_a_player_is_on_one_list_at_a_time() -> void:
	var book := Contacts.empty()
	eq(Contacts.add(book, Contacts.FRIEND, "bob", "Bob", "alice"), "")
	eq(Contacts.add(book, Contacts.FRIEND, "bob", "Bob", "alice"), ProtocolContacts.E_CONTACT_EXISTS)
	eq(Contacts.add(book, Contacts.IGNORED, "bob", "Bob", "alice"), "", "moving Bob to the ignored")
	eq([Contacts.list_of(book, Contacts.FRIEND).size(), Contacts.list_of(book, Contacts.IGNORED).size()], [0, 1])
	eq(Contacts.add(book, Contacts.ENEMY, "alice", "Alice2", "alice"), ProtocolContacts.E_CONTACT_SELF, "another character of one's own account")
	eq(Contacts.add(book, "bff", "x", "X", "alice"), ProtocolContacts.E_BAD_CONTACT_KIND)
	check(Contacts.remove(book, Contacts.IGNORED, "BOB"), "removal ignores the case")
	check(not Contacts.remove(book, Contacts.IGNORED, "Bob"), "not there any more")
	check(Contacts.is_empty(book))


func test_lists_are_capped() -> void:
	var book := Contacts.empty()
	for i in Contacts.MAX_PER_LIST:
		eq(Contacts.add(book, Contacts.FRIEND, "a%d" % i, "N%d" % i, "me"), "")
	eq(Contacts.add(book, Contacts.FRIEND, "late", "Late", "me"), ProtocolContacts.E_CONTACT_FULL)
	eq(Contacts.add(book, Contacts.ENEMY, "late", "Late", "me"), "", "the other lists have their own room")


func test_a_damaged_document_reads_as_empty_lists() -> void:
	var book := Contacts.normalize({"friends": "oops", "enemies": [{"name": "X"}, 3, {"account": "a", "name": "A"}], "ignored": null})
	eq([book["friends"].size(), book["enemies"].size(), book["ignored"].size()], [0, 1, 0])
	eq(Contacts.normalize(7), Contacts.empty())


# -- lists of an account ----------------------------------------------------------------

func test_add_list_and_remove() -> void:
	var t := _conns(Players._server(), ["Alice", "Bob", "Cleo"])
	var a: Players.Conn = t[0]
	a.send(ProtocolContacts.add(Contacts.FRIEND, "bob"))
	a.send(ProtocolContacts.add(Contacts.ENEMY, "Cleo"))
	Players._run(t, 0.1)
	var l := _lists(a)
	eq(_names(l["friends"]), ["Bob"], "the name is the character's, whatever the case typed")
	eq(_names(l["enemies"]), ["Cleo"])
	var bob: Dictionary = l["friends"][0]
	eq([bob["online"], bob["playing"], int(bob["level"])], [true, "Bob", 1])
	a.send(ProtocolContacts.add(Contacts.FRIEND, "Nobody"))
	a.send(ProtocolContacts.add(Contacts.FRIEND, "Alice"))
	a.send(ProtocolContacts.add(Contacts.FRIEND, "Bob"))
	a.send(ProtocolContacts.remove(Contacts.IGNORED, "Bob"))
	a.send(ProtocolContacts.add("pal", "Bob"))
	Players._run(t, 0.1)
	eq(_codes(a), [ProtocolContacts.E_CONTACT_UNKNOWN, ProtocolContacts.E_CONTACT_SELF, ProtocolContacts.E_CONTACT_EXISTS,
			ProtocolContacts.E_CONTACT_UNKNOWN, ProtocolContacts.E_BAD_CONTACT_KIND])
	a.send(ProtocolContacts.remove(Contacts.FRIEND, "bob"))
	a.send(ProtocolContacts.get_lists())
	Players._run(t, 0.1)
	var after := a.take(ProtocolContacts.CONTACTS)
	eq(_names(after[-1]["friends"]), [], "removed")
	eq(after.size(), 2, "one answer per command")


func test_an_offline_friend_is_found_in_the_saves_and_shown_offline() -> void:
	var server := Players._server()
	var t := _conns(server, ["Alice", "Bob"])
	var b: Players.Conn = t[1]
	b.backend.close()
	t.erase(b)
	Players._run(t, 0.1)
	var a: Players.Conn = t[0]
	a.send(ProtocolContacts.add(Contacts.FRIEND, "bob"))
	Players._run(t, 0.1)
	var f: Dictionary = _lists(a)["friends"][0]
	eq([f["name"], f["online"], f["playing"], int(f["level"]), int(f["breed"])], ["Bob", false, "", 0, -1])


func test_the_lists_follow_the_account_to_its_next_session() -> void:
	var server := Players._server()
	var t := _conns(server, ["Alice", "Bob"])
	var a: Players.Conn = t[0]
	a.send(ProtocolContacts.add(Contacts.IGNORED, "Bob"))
	a.send(ProtocolContacts.add(Contacts.FRIEND, "Alice2")) # nobody
	Players._run(t, 0.1)
	a.backend.close()
	t.erase(a)
	Players._run(t, 0.1)
	var again := Players.Conn.new(server, "Alice", Players.LOOK, "alice")
	Players._run([again, t[0]], 0.2)
	eq(_names(_lists(again)["ignored"]), ["Bob"], "sent at connection, since the account has a contact")
	var solo := Players.Conn.new(server, "Dora", Players.LOOK, "dora")
	Players._run([solo], 0.2)
	eq(_lists(solo), {}, "an account with no contact is told nothing")


# -- notices ----------------------------------------------------------------------------

func test_a_friend_is_told_of_a_connection_and_a_disconnection() -> void:
	var server := Players._server()
	var t := _conns(server, ["Alice"])
	var a: Players.Conn = t[0]
	a.send(ProtocolContacts.add(Contacts.FRIEND, "Bob"))
	Players._run(t, 0.1)
	a.events.clear() # Bob is not known yet: nothing happened
	var b := Players.Conn.new(server, "Bob", Players.LOOK, "bob")
	t.append(b)
	Players._run(t, 0.2)
	eq(_lists(b), {}, "Bob has no contact of his own")
	var on := a.take(ProtocolContacts.STATUS)
	eq(on.size(), 0, "the add above failed (Bob had never played): no notice")
	a.send(ProtocolContacts.add(Contacts.FRIEND, "Bob"))
	Players._run(t, 0.1)
	a.events.clear()
	b.backend.close()
	t.erase(b)
	Players._run(t, 0.2)
	var off: Dictionary = a.take(ProtocolContacts.STATUS)[0]
	eq([off["kind"], off["name"], off["online"], off["playing"]], [Contacts.FRIEND, "Bob", false, ""])
	var b2 := Players.Conn.new(server, "Bob", Players.LOOK, "bob")
	t.append(b2)
	Players._run(t, 0.2)
	var back: Dictionary = a.take(ProtocolContacts.STATUS)[0]
	eq([back["name"], back["online"], back["playing"], int(back["level"])], ["Bob", true, "Bob", 1])


func test_enemies_and_ignored_are_not_announced() -> void:
	var server := Players._server()
	var t := _conns(server, ["Alice", "Bob"])
	var a: Players.Conn = t[0]
	a.send(ProtocolContacts.add(Contacts.ENEMY, "Bob"))
	Players._run(t, 0.1)
	a.events.clear()
	(t[1] as Players.Conn).backend.close()
	t.remove_at(1)
	Players._run(t, 0.2)
	eq(a.take(ProtocolContacts.STATUS).size(), 0)


# -- ignore filter ------------------------------------------------------------------------

func test_an_ignored_player_is_not_heard_on_any_channel() -> void:
	var server := Players._server()
	var t := _conns(server, ["Alice", "Bob", "Cleo"])
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	var c: Players.Conn = t[2]
	a.send(ProtocolContacts.add(Contacts.IGNORED, "Bob"))
	Players._run(t, 0.1)
	a.events.clear()
	b.send(Protocol.chat_send("general", "salut tout le monde"))
	b.send(Protocol.chat_send("private", "psst", "Alice"))
	Players._run(t, 0.2)
	eq(a.take(Protocol.CHAT_MSG).size(), 0, "Alice hears neither the map nor the whisper")
	eq(_codes(b), [], "Bob is not told he is ignored")
	eq(b.take(Protocol.CHAT_MSG).size(), 2, "Bob still sees his own lines")
	check(c.take(Protocol.CHAT_MSG).size() >= 1, "the others hear him")
	c.send(Protocol.chat_send("general", "coucou"))
	Players._run(t, 0.2)
	eq(a.take(Protocol.CHAT_MSG).size(), 1, "Alice hears the others")
	a.send(ProtocolContacts.remove(Contacts.IGNORED, "Bob"))
	Players._run(t, 0.1)
	b.send(Protocol.chat_send("private", "pardon", "Alice"))
	Players._run(t, 0.2)
	eq(a.take(Protocol.CHAT_MSG).size(), 1, "heard again once removed")
	check(server.worlds["duo"].chat.log.size() >= 3, "the moderation journal keeps what an ignored player said")


func test_ignoring_holds_for_every_character_of_the_account() -> void:
	var server := Players._server()
	var a := Players.Conn.new(server, "Alice", Players.LOOK, "alice")
	var b := Players.Conn.new(server, "Bob", Players.LOOK, "bob")
	var t := [a, b]
	Players._run(t, 0.2)
	a.send(ProtocolContacts.add(Contacts.IGNORED, "Bob"))
	Players._run(t, 0.1)
	b.backend.close()
	t.erase(b)
	var b2 := Players.Conn.new(server, "Bobby", Players.LOOK, "bob") # another character of the same account
	t.append(b2)
	Players._run(t, 0.2)
	a.events.clear()
	b2.send(Protocol.chat_send("general", "c'est moi"))
	Players._run(t, 0.2)
	eq(a.take(Protocol.CHAT_MSG).size(), 0, "the ignore names the account, not the character")


# -- over WebSockets, two accounts ------------------------------------------------------------

func _login(rig: Accounts.Rig, login: String, name: String) -> Accounts.Client:
	var c := rig.client()
	rig.ask(c, Protocol.register(login, "secret1"), Protocol.LOGIN_OK)
	c.backend.send(Protocol.hello("tiny", name, Players.LOOK))
	rig.run(5.0, func() -> bool: return c.has(Protocol.WELCOME))
	return c


func test_contacts_over_websocket() -> void:
	var rig := Accounts.Rig.new()
	var a := _login(rig, "alice", "Alice")
	a.backend.send(ProtocolContacts.add(Contacts.FRIEND, "Bob"))
	check(rig.run(2.0, func() -> bool: return a.has(Protocol.ERROR)), "Bob never played: refused")
	eq(a.take(Protocol.ERROR)[0]["code"], ProtocolContacts.E_CONTACT_UNKNOWN)
	var b := _login(rig, "bob", "Bob")
	rig.run(0.2)
	a.backend.send(ProtocolContacts.add(Contacts.FRIEND, "bob"))
	check(rig.run(2.0, func() -> bool: return a.has(ProtocolContacts.CONTACTS)), "the lists come back")
	var friends: Array = a.take(ProtocolContacts.CONTACTS)[-1]["friends"]
	eq([friends[0]["name"], friends[0]["online"], int(friends[0]["level"])], ["Bob", true, 1])
	b.backend.send(ProtocolContacts.add(Contacts.IGNORED, "Alice"))
	rig.run(0.5)
	b.take(ProtocolContacts.CONTACTS)
	a.backend.send(Protocol.chat_send("general", "tu m'entends ?"))
	b.backend.send(Protocol.chat_send("general", "oui"))
	rig.run(1.0)
	eq(b.take(Protocol.CHAT_MSG).size(), 1, "Bob only sees his own line: he ignores Alice")
	eq(a.take(Protocol.CHAT_MSG).size() >= 2, true, "Alice hears Bob and herself")
	a.take(ProtocolContacts.STATUS)
	rig.close(b)
	check(rig.run(2.0, func() -> bool: return a.has(ProtocolContacts.STATUS)), "Alice is told Bob left")
	var st: Dictionary = a.take(ProtocolContacts.STATUS)[0]
	eq([st["name"], st["online"], int(st["level"])], ["Bob", false, 0])
	var b2 := rig.client()
	rig.ask(b2, Protocol.login("bob", "secret1"), Protocol.LOGIN_OK)
	b2.backend.send(Protocol.hello("tiny", "Bob", Players.LOOK))
	rig.run(2.0, func() -> bool: return a.has(ProtocolContacts.STATUS) and b2.has(ProtocolContacts.CONTACTS))
	eq(a.take(ProtocolContacts.STATUS)[0]["online"], true, "and that he is back")
	eq(_names(b2.take(ProtocolContacts.CONTACTS)[0]["ignored"]), ["Alice"], "Bob's list came back with his account")
	eq(a.backend.schema_errors.size() + b.backend.schema_errors.size() + b2.backend.schema_errors.size(), 0, "every event matches the schema")
	rig.shutdown()


# -- S.05c: the ignore filter does not reread the account document for every message ----------------

func test_the_ignore_filter_caches_the_book_for_a_short_while() -> void:
	var server := Players._server()
	var t := _conns(server, ["Alice", "Bob"])
	var sim: WorldSim = server.worlds["duo"]
	var contacts: WorldContacts = sim.contacts
	var key := "alice"
	var before := contacts.cached_book(key)
	# another writer (another world of the server) changes the document behind the cache
	var doc := sim.persistence.load_account(Bank.account_key(key))
	doc["contacts"] = {"friends": [], "enemies": [], "ignored": [{"account": "bob", "name": "Bob"}]}
	sim.persistence.save_account(Bank.account_key(key), doc)
	eq(contacts.cached_book(key), before, "still the cached book inside the delay")
	sim.now += WorldContacts.CACHE_MS + 1
	eq(Contacts.list_of(contacts.cached_book(key), Contacts.IGNORED).size(), 1, "read again after the delay")
	check(t.size() == 2)
