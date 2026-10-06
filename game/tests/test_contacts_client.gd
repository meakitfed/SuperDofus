## The social window of the client (P3.05b): the model fed by `contacts` / `contact_status`, the
## chat commands, the window rendering and what it sends, and over real sockets the lists the
## sim sends to a NetBackend, plus the filter of the group and exchange invitations of an
## ignored player (the sim stays silent, like the chat).
extends TestCase

const Accounts := preload("res://tests/test_accounts.gd")
const Players := preload("res://tests/test_players.gd")


func _init() -> void:
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()


class Sink:
	extends GameBackend
	var sent: Array = []

	func send(msg: Dictionary) -> void:
		sent.append(msg)


static func _friend(name: String, online: bool) -> Dictionary:
	return {"name": name, "online": online, "playing": name if online else "", "level": 12 if online else 0, "breed": 8 if online else -1}


static func _lists() -> Dictionary:
	return ProtocolContacts.contacts([_friend("Bob", true), _friend("Cleo", false)], [_friend("Dan", false)], [{"name": "Eve"}])


func test_the_model_follows_the_events() -> void:
	var m := ContactsModel.new()
	m.apply(_lists())
	eq([m.lists["friend"].size(), m.lists["enemy"].size(), m.lists["ignored"].size()], [2, 1, 1])
	eq(m.online_count(), 1)
	check(m.has(Contacts.IGNORED, "eve") and not m.has(Contacts.FRIEND, "Eve"))
	eq(m.status(ProtocolContacts.status("friend", "Cleo", true, "Cleo2", 30)), "Cleo est en ligne (Cleo2)")
	eq(m.online_count(), 2)
	eq(m.status(ProtocolContacts.status("friend", "Bob", false, "", 0)), "Bob s'est déconnecté")
	eq(m.online_count(), 1)


func test_chat_commands_become_messages() -> void:
	eq(ContactsModel.parse_command("/friend Bob"), ProtocolContacts.add("friend", "Bob"))
	eq(ContactsModel.parse_command("/IGNORE  Eve "), ProtocolContacts.add("ignored", "Eve"))
	eq(ContactsModel.parse_command("/unenemy Dan"), ProtocolContacts.remove("enemy", "Dan"))
	eq(ContactsModel.parse_command("/friend"), {}, "no name")
	eq(ContactsModel.parse_command("/w Bob salut"), {}, "not a contact command")


func test_the_window_shows_the_lists_and_sends_changes() -> void:
	var sink := Sink.new()
	var w := ContactsWindow.new()
	w.setup_window(sink)
	w.set_lists(_lists())
	eq(w._pages["friend"].get_child_count(), 2)
	eq(w._pages["ignored"].get_child_count(), 1)
	var row: HBoxContainer = w._pages["friend"].get_child(0)
	eq(row.get_meta("contact"), "Bob")
	var buttons := row.get_children().filter(func(n: Node) -> bool: return n is Button)
	eq(buttons.size(), 2, "an online friend: whisper and remove")
	eq((w._pages["friend"].get_child(1).get_children().filter(func(n: Node) -> bool: return n is Button)).size(), 1, "offline: remove only")
	var heard := []
	w.whisper.connect(func(n: String) -> void: heard.append(n))
	(buttons[0] as Button).pressed.emit()
	eq(heard, ["Bob"])
	(buttons[1] as Button).pressed.emit()
	eq(sink.sent[-1], ProtocolContacts.remove("friend", "Bob"))
	w._tabs.select(2)
	w._edit.text = " Fred "
	w.add_typed()
	eq(sink.sent[-1], ProtocolContacts.add("ignored", "Fred"))
	w.set_lists(ProtocolContacts.contacts([], [], []))
	eq(w._pages["friend"].get_child_count(), 1, "the empty line")
	w.free()


func _login(rig: Accounts.Rig, login: String, name: String) -> Accounts.Client:
	var c := rig.client()
	rig.ask(c, Protocol.register(login, "secret1"), Protocol.LOGIN_OK)
	c.backend.send(Protocol.hello("tiny", name, Players.LOOK))
	rig.run(5.0, func() -> bool: return c.has(Protocol.WELCOME))
	return c


func test_the_window_over_websocket_and_the_ignored_invitations() -> void:
	var rig := Accounts.Rig.new()
	var a := _login(rig, "alice", "Alice")
	var b := _login(rig, "bob", "Bob")
	rig.run(0.2)
	var w := ContactsWindow.new()
	w.setup_window(a.backend)
	w.open() # asks for the lists
	w._edit.text = "bob"
	w.add_typed()
	check(rig.run(2.0, func() -> bool: return a.has(ProtocolContacts.CONTACTS)), "the lists come back")
	for ev: Dictionary in a.take(ProtocolContacts.CONTACTS):
		w.set_lists(ev)
	eq(w.model.lists["friend"].size(), 1)
	eq([w.model.lists["friend"][0]["name"], w.model.lists["friend"][0]["online"]], ["Bob", true])
	# Bob ignores Alice: her invitations reach him neither as a group nor as an exchange
	b.backend.send(ProtocolContacts.add(Contacts.IGNORED, "Alice"))
	rig.run(0.5)
	a.take(Protocol.ERROR)
	a.backend.send(ProtocolParty.invite("Bob"))
	a.backend.send(ProtocolTrade.invite("Bob"))
	rig.run(1.0)
	eq(b.take(ProtocolParty.INVITED).size() + b.take(ProtocolTrade.INVITED).size(), 0, "nothing reaches Bob")
	eq(a.take(Protocol.ERROR).size(), 0, "Alice is not told")
	b.backend.send(ProtocolContacts.remove(Contacts.IGNORED, "Alice"))
	rig.run(0.5)
	a.backend.send(ProtocolParty.invite("Bob"))
	check(rig.run(2.0, func() -> bool: return b.has(ProtocolParty.INVITED)), "invitations pass again once removed")
	eq(a.backend.schema_errors.size() + b.backend.schema_errors.size(), 0, "every event matches the schema")
	w.free()
	rig.shutdown()
