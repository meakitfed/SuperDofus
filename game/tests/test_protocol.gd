## Protocol robustness: every message matches SCHEMA, survives JSON, invalid
## commands are refused with typed errors, envelopes are numbered, and the
## generated docs/PROTOCOL.md is up to date.
extends TestCase

const FightTests := preload("res://tests/test_fight.gd")


## One sample of every message, built with the Protocol builders.
static func _samples() -> Array:
	return [
		Protocol.hello("w", "Name", "{1}"), Protocol.move(3, true), Protocol.change_map("left"), Protocol.use_trigger(40), Protocol.admin_cmd("tp", ["1", "2"]), Protocol.use_zaap(), Protocol.zaap_travel(5), Protocol.set_save_point(), Protocol.npc_talk(7), Protocol.dialog_reply(1), Protocol.dialog_close(), Protocol.shop_buy(44, 2), Protocol.shop_sell(3, 1), Protocol.shop_close(), Protocol.bank_move(3, 2, "in"), Protocol.bank_kamas(10, "out"), Protocol.bank_close(),
		Protocol.fight_attack(4), Protocol.fight_move(5), Protocol.fight_cast(6, 7), Protocol.fight_end_turn(),
		Protocol.fight_leave(), Protocol.fight_place(8), Protocol.fight_ready(false), Protocol.fight_option("locked", true), Protocol.boost_stat("wisdom"), Protocol.boost_stat("strength", 10), Protocol.reset_stats(), Protocol.use_item(3), Protocol.equip(3, 7), Protocol.unequip(7), Protocol.destroy_item(3), Protocol.destroy_item(3, 2), Protocol.choose_variant(12815), Protocol.move_spell(12781, 3),
		Protocol.welcome(1, 2, {"id": "w"}), Protocol.map_enter({}, []), Protocol.actor_add({"id": 1}),
		Protocol.actor_remove(1), Protocol.actor_move(1, [1, 2], 3, false), Protocol.error(Protocol.E_NO_LOS, "", "fight_cast"),
		Protocol.player_stats({}), Protocol.inventory([{"uid": 1, "id": 468, "qty": 2, "effects": [[110, 12, 0, 0]]}]), Protocol.item_added({"uid": 1, "id": 468, "qty": 1, "effects": []}), Protocol.item_removed(1), Protocol.zaap_list(5, [{"map": 6, "cost": 10}], -1), Protocol.zaap_known(5), Protocol.dialog(7, {"text_id": 1, "replies": [{"id": 1, "text_id": 2}]}), Protocol.dialog_end({"type": "shop"}), Protocol.shop_open(7, [{"item": 44, "price": 700}], 10), Protocol.shop_end(), Protocol.bank_open(7, 1, 50, [{"uid": 1, "id": 44, "qty": 2, "effects": []}]), Protocol.bank_update(50, [{"uid": 1, "id": 44, "qty": 0, "effects": []}]), Protocol.bank_end(), Protocol.interactive_use(4, 6), Protocol.interactive_start(1, 4, 6, 3000), Protocol.interactive_end(1, 4, true), Protocol.interactive_state(4, false, 9000), Protocol.job_xp(10, 0, {"job": 2}), Protocol.quest_start({"id": 1}), Protocol.quest_update({"id": 1}, {"xp": 1}), Protocol.quest_complete(1, 2, {"xp": 1}), Protocol.quest_list([], [1]), Protocol.quest_abandon(7), Protocol.map_markers(1, [{"kind": "offer", "quest": 1, "npc": 2, "map": 1}]), Protocol.group_alert(3, 4), Protocol.use_phoenix(), Protocol.actor_look(3, ["{1|10||100}"]), Protocol.info(Protocol.I_ENERGY_LOST, [10]), Protocol.fight_start(1, 2, [], [], {"0": [], "1": []}, 30000),
		Protocol.fighter_placed(1, 2), Protocol.fighter_ready(1, true), Protocol.fight_begin([1, 2]), Protocol.fight_options({"locked": true}), Protocol.challenge_list([{"id": 33, "state": "running"}]), Protocol.challenge_update(33, "failed"),
		Protocol.fight_turn(1, 6, 3, 1000, []), Protocol.fighter_move(1, [1, 2], 0, 2, {"ap": 0, "mp": 1}),
		Protocol.spell_cast(1, 2, 3, 1, 3, [], true), Protocol.fight_end("win", 1000, []),
		Protocol.craft_open(20), Protocol.craft_set([{"item": 1, "qty": 2}]), Protocol.craft_do(2), Protocol.craft_close(),
		Protocol.craft_state(20, 2, {}, [], 0, 0, []), Protocol.craft_done(44, 2), Protocol.fm_apply(101, 7436),
		Protocol.fm_result(101, 7436, "fail", {"uid": 101, "id": 758, "qty": 1, "effects": [[125, 30, 0, 0]], "pos": -1, "reserve": 200}, [[125, 5]]),
		Protocol.hello("w"), Protocol.chat_send("private", "salut", "Bob"), Chat.message("general", "Alice", 1, "salut", 5), Protocol.ping(5), Protocol.pong(5, 99), Protocol.register("jean", "secret1"), Protocol.login("jean", "secret1"), Protocol.login_ok("t", "player", "jean"), Protocol.login_error(Protocol.E_BAD_CREDENTIALS, "login"), Protocol.list_characters(), Protocol.create_character("Bob", 12, 1),
		Protocol.delete_character("Bob"), Protocol.select_character("Bob"),
		Protocol.characters([{"name": "Bob", "level": 1, "breed": 12, "look": "{1}"}], 5, {"id": "w"}),
		Protocol.character_created({"name": "Bob", "level": 1, "breed": 12, "look": "{1}"}),
	]


func test_every_builder_matches_the_schema_after_json() -> void:
	var covered := {}
	for msg: Dictionary in _samples():
		var dir: String = Protocol.SCHEMA[msg["t"]][0]
		eq(Protocol.validate(msg, dir), "", "%s as built" % msg["t"])
		check(Protocol.is_json_safe(msg), "%s is JSON-safe" % msg["t"])
		eq(Protocol.validate(Protocol.roundtrip(msg), dir), "", "%s after JSON (ints became floats)" % msg["t"])
		covered[msg["t"]] = true
	for type: String in Protocol.SCHEMA:
		check(covered.has(type), "no builder sample for %s" % type)


func test_validate_rejects_bad_messages() -> void:
	check(Protocol.validate({"t": "nope"}) != "", "unknown type")
	check(Protocol.validate({"cell": 3}) != "", "no type")
	check(Protocol.validate({"t": Protocol.MOVE, "run": false}) != "", "missing field")
	check(Protocol.validate({"t": Protocol.MOVE, "cell": "3", "run": false}) != "", "string instead of int")
	check(Protocol.validate({"t": Protocol.MOVE, "cell": 3.5, "run": false}) != "", "non-integral number")
	check(Protocol.validate(Protocol.move(3), Protocol.S2C) != "", "wrong direction")
	var m := Protocol.move(3)
	m["seq"] = "x"
	check(Protocol.validate(m) != "", "bad seq")
	m["seq"] = 4.0
	m["extra"] = {"future": true}
	eq(Protocol.validate(m, Protocol.C2S), "", "integral float seq and extra fields are fine")
	var err := Protocol.error(Protocol.E_NO_LOS)
	eq(Protocol.validate(err), "", "ref is optional")
	err["ref"] = "1"
	check(Protocol.validate(err) != "", "ref must be an int")


class Session:
	var backend := LocalBackend.new()
	var events: Array = []

	func _init() -> void:
		backend.sources["arena"] = FightTests._world()
		backend.event.connect(func(ev: Dictionary) -> void: events.append(ev))

	func send(cmd: Dictionary) -> void:
		backend.send(cmd)
		backend.poll(0.0)

	func take(type: String) -> Array:
		var out := events.filter(func(e: Dictionary) -> bool: return e["t"] == type)
		events = events.filter(func(e: Dictionary) -> bool: return e["t"] != type)
		return out


func test_the_sim_refuses_invalid_commands_with_typed_errors() -> void:
	var s := Session.new()
	s.send(Protocol.hello("arena", "Tester", "{1|120,2195||56}"))
	s.events.clear()
	s.send({"t": Protocol.MOVE, "cell": "far"})
	var errs := s.take(Protocol.ERROR)
	eq(errs.size(), 1)
	eq(str(errs[0]["code"]), Protocol.E_BAD_MESSAGE)
	eq(str(errs[0]["cmd"]), Protocol.MOVE)
	eq(int(errs[0]["ref"]), 2, "ref = seq of the refused command (hello was 1)")
	s.send({"t": "dance"})
	eq(str(s.take(Protocol.ERROR)[0]["code"]), Protocol.E_BAD_MESSAGE, "unknown type")
	s.send(Protocol.change_map("left"))
	var no_exit := s.take(Protocol.ERROR)
	eq(str(no_exit[0]["code"]), Protocol.E_NO_EXIT, "rule errors are typed too")
	eq(int(no_exit[0]["ref"]), 4)
	s.send(Protocol.boost_stat("luck"))
	eq(str(s.take(Protocol.ERROR)[0]["code"]), Protocol.E_UNKNOWN_STAT)
	s.send(Protocol.hello("arena", "Tester", ""))
	check(s.take(Protocol.WELCOME).size() == 1, "a new hello reconnects")


func test_hello_checks_version_and_world() -> void:
	var s := Session.new()
	var old := Protocol.hello("arena", "Tester", "")
	old["v"] = Protocol.VERSION - 1
	s.send(old)
	var err := s.take(Protocol.ERROR)
	eq(str(err[0]["code"]), Protocol.E_VERSION)
	eq(int(err[0]["ref"]), 1)
	eq(s.take(Protocol.WELCOME).size(), 0)
	s.send(Protocol.hello("nowhere", "Tester", ""))
	eq(str(s.take(Protocol.ERROR)[0]["code"]), Protocol.E_UNKNOWN_WORLD)
	s.send(Protocol.hello("arena", "Tester", ""))
	var w := s.take(Protocol.WELCOME)
	eq(int(w[0]["v"]), Protocol.VERSION, "welcome answers the version")


func test_events_are_numbered_per_session() -> void:
	var s := Session.new()
	s.send(Protocol.hello("arena", "Tester", ""))
	s.send(Protocol.move(300))
	s.backend.poll(1.0)
	var seqs := s.events.map(func(e: Dictionary) -> int: return int(e["seq"]))
	check(seqs.size() >= 3)
	for i in seqs.size():
		eq(seqs[i], i + 1, "consecutive from 1")


func test_a_whole_fight_only_sends_schema_valid_events() -> void:
	LocalBackend.schema_errors.clear()
	var c := FightTests.Client.new(FightTests._world())
	c.start_fight()
	c.run(8.0, 0.1) # monsters play
	for m: Fighter in c.monsters():
		m.hp = 0
		m.alive = false
	c.fight()._check_end()
	c.run(0.5)
	eq(Array(LocalBackend.schema_errors), [], "every event matched Protocol.SCHEMA")


func test_protocol_doc_is_up_to_date() -> void:
	var path := ProjectSettings.globalize_path("res://../docs/PROTOCOL.md").simplify_path()
	eq(FileAccess.get_file_as_string(path), ProtocolDoc.describe(),
			"docs/PROTOCOL.md is stale: godot --headless --path game -s res://tools/protocol_doc.gd")
