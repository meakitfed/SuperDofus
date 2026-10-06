## Connection and character selection (roadmap P1.01): an account's characters
## per world, Dofus name rules (namingrules), unique names, deletion, selection.
## Driven through LocalBackend -> GameSession, like a client.
extends TestCase


func _init() -> void:
	SpellBook.use_file("") # the real game data (other suites switch to test fixtures)


static func _world() -> WorldSource:
	return WorldSource.from_dicts(
		{"id": "lobby", "name": "Lobby", "start_map": 1, "start_cell": 300},
		[{"id": 1, "coords": [0, 0], "neighbors": {}}])


class Conn:
	var backend := LocalBackend.new()
	var events: Array = []

	func _init(server: LocalServer, account := "local") -> void:
		backend.server = server
		backend.account = account
		backend.event.connect(func(ev: Dictionary) -> void: events.append(ev))

	func send(cmd: Dictionary) -> void:
		backend.send(cmd)
		backend.poll(0.0)

	func take(type: String) -> Array:
		var out := events.filter(func(e: Dictionary) -> bool: return e["t"] == type)
		events = events.filter(func(e: Dictionary) -> bool: return e["t"] != type)
		return out

	func error_code() -> String:
		var errs := take(Protocol.ERROR)
		return str(errs[-1]["code"]) if not errs.is_empty() else ""

	func names() -> Array:
		var lists := take(Protocol.CHARACTERS)
		return (lists[-1]["list"] as Array).map(func(c: Dictionary) -> String: return str(c["name"])) if not lists.is_empty() else []


static func _server(store: Persistence = null) -> LocalServer:
	var s := LocalServer.new()
	s.sources["lobby"] = _world()
	if store != null:
		s.persistence = store
	return s


func test_player_names_follow_the_dofus_naming_rules() -> void:
	for ok in ["Ab", "Tester", "Jean-Luc", "Jean-luc-Pierre", "Abcdefghijklmnopqrst"]:
		check(NameRules.is_valid(ok), ok + " is valid")
	for bad in ["", "A", "jean", "JEAN", "Jean Luc", "Jean--Luc", "Jean-Luc-Pierre-Paul", "Jo3", "Élodie",
			"Abcdefghijklmnopqrstu"]:
		check(not NameRules.is_valid(bad), bad + " is refused")


func test_hello_without_a_name_lists_the_accounts_characters() -> void:
	var c := Conn.new(_server())
	c.send(Protocol.hello("lobby"))
	var lists := c.take(Protocol.CHARACTERS)
	eq(lists.size(), 1)
	eq((lists[0]["list"] as Array).size(), 0, "a new account has no character")
	eq(int(lists[0]["max"]), CharacterRoster.MAX_PER_WORLD)
	eq(str(lists[0]["world"]["id"]), "lobby")
	eq(c.take(Protocol.WELCOME).size(), 0, "nobody plays yet")
	c.send(Protocol.move(310))
	eq(c.error_code(), Protocol.E_NO_CHARACTER, "game commands wait for a character")


func test_create_then_refusals() -> void:
	var c := Conn.new(_server())
	c.send(Protocol.hello("lobby"))
	c.take(Protocol.CHARACTERS)
	c.send(Protocol.create_character("Bob"))
	var created := c.take(Protocol.CHARACTER_CREATED)
	eq(created.size(), 1)
	eq(str(created[0]["character"]["name"]), "Bob")
	eq(int(created[0]["character"]["level"]), 1)
	eq(int(created[0]["character"]["breed"]), 12)
	eq(str(created[0]["character"]["look"]).get_slice("|", 1), "120,2188", "breeds.maleLook body + first heads face")
	check(str(created[0]["character"]["look"]).get_slice("|", 2).begins_with("1=13418918,"), "breeds.maleColors")
	eq(c.names(), ["Bob"], "the updated list follows")
	c.send(Protocol.create_character("Jean-Luc"))
	c.send(Protocol.create_character("Jean-luc"))
	eq(c.error_code(), Protocol.E_NAME_TAKEN, "unique whatever the case")
	c.send(Protocol.create_character("b0b"))
	eq(c.error_code(), Protocol.E_BAD_NAME)
	c.send(Protocol.create_character("Ana", 19))
	eq(c.error_code(), Protocol.E_UNKNOWN_BREED, "spellvariants breed 19 has no breeds row")
	c.send({"t": Protocol.CREATE_CHARACTER})
	eq(c.error_code(), Protocol.E_BAD_MESSAGE)
	var female := Conn.new(_server())
	female.send(Protocol.hello("lobby"))
	female.send(Protocol.create_character("Mei", 12, 1))
	check(str(female.take(Protocol.CHARACTER_CREATED)[0]["character"]["look"]).begins_with("{1|121,2196|"), "breeds.femaleLook + heads")


func test_an_account_has_a_limited_number_of_characters() -> void:
	var c := Conn.new(_server())
	c.send(Protocol.hello("lobby"))
	for n in ["Aa", "Bb", "Cc", "Dd", "Ee"]:
		c.send(Protocol.create_character(n))
	eq(c.take(Protocol.CHARACTER_CREATED).size(), CharacterRoster.MAX_PER_WORLD)
	c.send(Protocol.create_character("Ff"))
	eq(c.error_code(), Protocol.E_TOO_MANY_CHARACTERS)


func test_delete() -> void:
	var c := Conn.new(_server())
	c.send(Protocol.hello("lobby"))
	c.send(Protocol.create_character("Bob"))
	c.send(Protocol.create_character("Zoe"))
	c.events.clear()
	c.send(Protocol.delete_character("Nope"))
	eq(c.error_code(), Protocol.E_UNKNOWN_CHARACTER)
	c.send(Protocol.delete_character("Bob"))
	eq(c.names(), ["Zoe"])
	c.send(Protocol.create_character("Bob"))
	eq(c.take(Protocol.CHARACTER_CREATED).size(), 1, "the name is free again")


func test_select_enters_the_world() -> void:
	var c := Conn.new(_server())
	c.send(Protocol.hello("lobby"))
	c.send(Protocol.create_character("Bob"))
	c.events.clear()
	c.send(Protocol.select_character("Nope"))
	eq(c.error_code(), Protocol.E_UNKNOWN_CHARACTER)
	c.send(Protocol.select_character("Bob"))
	eq(c.take(Protocol.WELCOME).size(), 1)
	var stats := c.take(Protocol.PLAYER_STATS)
	eq(str(stats[0]["stats"]["name"]), "Bob")
	eq(int(stats[0]["stats"]["breed"]), 12)
	eq(c.take(Protocol.MAP_ENTER).size(), 1)
	c.send(Protocol.move(310))
	eq(c.take(Protocol.ERROR).size(), 0, "now game commands work")
	c.send(Protocol.hello("lobby"))
	eq(c.names(), ["Bob"], "a new hello goes back to the selection")
	eq(c.backend.server.worlds["lobby"].players.size(), 0, "and the character left the world")


func test_accounts_only_see_and_play_their_characters() -> void:
	var server := _server()
	var a := Conn.new(server, "acc1")
	var b := Conn.new(server, "acc2")
	a.send(Protocol.hello("lobby"))
	a.send(Protocol.create_character("Alice"))
	b.send(Protocol.hello("lobby"))
	eq(b.names(), [], "acc2 does not see Alice")
	b.send(Protocol.create_character("Alice"))
	eq(b.error_code(), Protocol.E_NAME_TAKEN, "names are unique across accounts")
	b.send(Protocol.select_character("Alice"))
	eq(b.error_code(), Protocol.E_UNKNOWN_CHARACTER)
	b.send(Protocol.delete_character("Alice"))
	eq(b.error_code(), Protocol.E_UNKNOWN_CHARACTER)
	b.send(Protocol.hello("lobby", "Alice", ""))
	eq(b.error_code(), Protocol.E_UNKNOWN_CHARACTER, "the quick hello follows the same rules")
	eq(b.take(Protocol.WELCOME).size(), 0)


func test_a_played_character_cannot_be_deleted() -> void:
	var server := _server()
	var game := Conn.new(server, "acc1")
	var menu := Conn.new(server, "acc1")
	game.send(Protocol.hello("lobby", "Alice", ""))
	eq(game.take(Protocol.WELCOME).size(), 1, "quick hello creates and plays")
	menu.send(Protocol.hello("lobby"))
	eq(menu.names(), ["Alice"])
	menu.send(Protocol.delete_character("Alice"))
	eq(menu.error_code(), Protocol.E_CHARACTER_IN_USE)
	var quick := Conn.new(server)
	quick.send(Protocol.hello("lobby", "x1", ""))
	eq(quick.error_code(), Protocol.E_BAD_NAME, "the quick hello checks the name too")


func test_saves_from_before_accounts_are_claimed() -> void:
	var store := Persistence.new()
	store.save_character("lobby", "Old", {"name": "Old", "level": 7})
	var c := Conn.new(_server(store), "acc1")
	c.send(Protocol.hello("lobby"))
	var list: Array = c.take(Protocol.CHARACTERS)[0]["list"]
	eq(list.size(), 1)
	eq(int(list[0]["level"]), 7)
	c.send(Protocol.select_character("Old"))
	c.backend.close()
	eq(str(store.load_character("lobby", "Old")["account"]), "acc1", "owned from now on")


func test_every_breed_builds_a_dofus_look() -> void:
	var breeds := LookBuilder.breeds()
	eq(breeds.size(), 19, "18 classes + Forgelance (breeds)")
	for row: Dictionary in breeds:
		var breed := int(row["id"])
		for sex in 2:
			var look := LookBuilder.build(breed, sex)
			var p := LookBuilder.parse(look)
			check(not p.is_empty(), "%s parses" % look)
			eq(p.get("bone"), 1, "player bone")
			eq((p.get("skins", []) as Array).size(), 2, "%d/%d: body + face skins" % [breed, sex])
			eq(p["skins"][1], int(LookBuilder.faces(breed, sex)[0]["skins"]), "first face of heads")
			eq((p["colors"] as Dictionary).size(), LookBuilder.default_colors(breed, sex).size(), "one color per breed color")
			check(int(p["scale"]) > 0, "scale from breeds look")
			check(LookBuilder.bodies(breed, sex).size() >= 1 and LookBuilder.faces(breed, sex).size() >= 4,
					"%d/%d has creation choices" % [breed, sex])


func test_look_choices_are_checked() -> void:
	eq(LookBuilder.check(12, 0), "")
	eq(LookBuilder.check(99, 0), Protocol.E_UNKNOWN_BREED)
	eq(LookBuilder.check(12, 2), Protocol.E_BAD_LOOK)
	eq(LookBuilder.check(12, 0, 112, 184), "", "retro body + face 4.2")
	eq(LookBuilder.check(12, 0, 2), Protocol.E_BAD_LOOK, "an Iop body")
	eq(LookBuilder.check(12, 0, 113), Protocol.E_BAD_LOOK, "the female body")
	eq(LookBuilder.check(12, 0, 0, 622), Protocol.E_BAD_LOOK, "payable face (new_age)")
	eq(LookBuilder.check(12, 0, 0, 0, [1, 2, 3, 4, 5, 6, 7]), Protocol.E_BAD_LOOK, "too many colors")
	eq(LookBuilder.check(12, 0, 0, 0, [0x1000000]), Protocol.E_BAD_LOOK)
	eq(LookBuilder.check(12, 0, 0, 0, [-1, 0xFF0000]), "")
	eq(LookBuilder.build(12, 0, 112, 184, [0xFF0000, -1]),
			"{1|5883,2195|1=16711680,2=5329968,3=9904435,4=3423523,5=14533780,6=9904435|57}")


func test_create_with_choices() -> void:
	var c := Conn.new(_server())
	c.send(Protocol.hello("lobby"))
	eq((c.take(Protocol.CHARACTERS)[0]["breeds"] as Array).map(func(b: Variant) -> int: return int(b)),
			LookBuilder.breeds().map(func(b: Dictionary) -> int: return int(b["id"])), "every class (P1.03), decided by the game")
	c.send(Protocol.create_character("Bob", 12, 0, 112, 184, [0xFF0000]))
	var look := str(c.take(Protocol.CHARACTER_CREATED)[0]["character"]["look"])
	eq(look.get_slice("|", 1), "5883,2195")
	check(look.get_slice("|", 2).begins_with("1=16711680,2=5329968"))
	c.send(Protocol.create_character("Zoe", 12, 0, 0, 622))
	eq(c.error_code(), Protocol.E_BAD_LOOK)
	c.send(Protocol.select_character("Bob"))
	c.backend.close()
	var saved := c.backend.server.persistence.load_character("lobby", "Bob")
	eq([int(saved["body"]), int(saved["head"])], [112, 184], "choices kept for later relooking")
