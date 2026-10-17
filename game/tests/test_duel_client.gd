## The duel of the client (P3.10): DuelModel (no node: the challenges received, their expiry, the
## texts), the "Défier" entry of the player menu, the challenge card (Accepter / Refuser) and the
## whole flow with real ClientSessions on LocalBackends (card, both enter the fight on their own
## team, one gives up, the result window shows without any reward). The same messages over
## WebSockets are test_duel::test_duel_over_websocket.
extends TestCase


func _init() -> void:
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()
	SpellBook.use_file("res://tests/fixtures/spells.json")


func test_challenges_expire_and_repeat_as_one_card() -> void:
	var m := DuelModel.new()
	m.apply_requested("Alice", 1000)
	m.apply_requested("Alice", 2000)
	m.apply_requested("Carol", 2500)
	eq(m.invites.size(), 2, "the same challenger twice: one card")
	check(not m.expire(2000 + DuelModel.INVITE_MS - 1), "still valid")
	check(m.expire(2000 + DuelModel.INVITE_MS), "Alice's is gone")
	eq(m.invites.size(), 1)
	m.forget("Carol")
	check(m.invites.is_empty())
	for r: String in [ProtocolDuel.REASON_DECLINED, ProtocolDuel.REASON_EXPIRED]:
		check(DuelModel.end_text(r) != "", "a text for " + r)
	check(DuelModel.end_text(ProtocolDuel.REASON_DECLINED) != DuelModel.end_text(ProtocolDuel.REASON_EXPIRED))


func _tree() -> SceneTree:
	return Engine.get_meta("test_tree") as SceneTree


func _drop(s: ClientSession) -> void:
	s.backend = null
	_tree().root.remove_child(s)
	s.free()


func _session(server: LocalServer, name: String) -> ClientSession:
	var b := LocalBackend.new()
	b.account = name.to_lower()
	b.server = server
	var s := ClientSession.new()
	s.world_id = "duo"
	s.player_name = name
	s.persistent = false
	s.backend = b
	_tree().root.add_child(s)
	return s


func _run(server: LocalServer, sessions: Array, seconds: float, until := Callable()) -> bool:
	for i in int(seconds / 0.05):
		server.tick(50)
		for s: ClientSession in sessions:
			s.backend.poll(0.05)
		if until.is_valid() and until.call():
			return true
	return not until.is_valid()


func _world() -> LocalServer:
	var s := LocalServer.new()
	s.sources["duo"] = WorldSource.from_dicts(
		{"id": "duo", "name": "Duo", "start_map": 1, "start_cell": 300, "wander_ms": [600000, 600000]},
		[{"id": 1, "coords": [0, 0]}])
	return s


func _press(menu_owner: ClientSession, label: String) -> void:
	var menus := menu_owner.get_children().filter(func(n: Node) -> bool: return n is PopupMenu)
	var menu: PopupMenu = menus[-1]
	var index := -1
	for i in menu.item_count:
		if menu.get_item_text(i) == label:
			index = i
			check(not menu.is_item_disabled(i), "the entry %s is live" % label)
	check(index >= 0, "there is a %s entry" % label)
	menu.id_pressed.emit(menu.get_item_id(index))


func test_flow_through_the_client() -> void:
	var server := _world()
	var alice := _session(server, "Alice")
	var bob := _session(server, "Bob")
	var all := [alice, bob]
	_run(server, all, 1.0)
	check(_run(server, all, 2.0, func() -> bool: return alice.views.has(bob.you)), "Alice sees Bob")
	# the menu entry challenges; Bob declines the first time
	alice._others.menu(bob.you, Vector2(20, 20))
	_press(alice, "Défier")
	check(_run(server, all, 2.0, func() -> bool: return not bob.player_hud.duel_invites.model.invites.is_empty()), "Bob gets the challenge")
	eq(bob.player_hud.duel_invites.get_child_count(), 1, "one card")
	bob.player_hud.duel_invites.decline("Alice")
	_run(server, all, 0.3)
	eq(bob.player_hud.duel_invites.get_child_count(), 0, "the card is gone")
	check(alice.fight == null and bob.fight == null, "no fight")
	# the second time he accepts
	alice.backend.send(ProtocolDuel.request("Bob"))
	check(_run(server, all, 2.0, func() -> bool: return not bob.player_hud.duel_invites.model.invites.is_empty()), "second challenge")
	bob.player_hud.duel_invites.accept("Alice")
	check(_run(server, all, 2.0, func() -> bool: return alice.fight != null and bob.fight != null), "both enter the fight")
	eq([alice.fight.my_team(), bob.fight.my_team()], [0, 1], "each on its own team")
	eq(bob.player_hud.duel_invites.get_child_count(), 0, "no card in the fight")
	# Bob gives up: both get the result window, without any reward
	bob.backend.send(Protocol.fight_leave())
	check(_run(server, all, 2.0, func() -> bool: return alice.fight == null and bob.fight == null), "the fight is over")
	check(is_instance_valid(alice._result_window) and is_instance_valid(bob._result_window), "both see the result window")
	_drop(alice)
	_drop(bob)
