## The client side of fights with several players (P3.04b): the swords on the map (also after the JSON
## round trip), the join / watch menu, a spectator view that can do nothing, fighter_joined /
## fighter_left in the view, and the end of a fight without a results window for a spectator or a
## runaway. The flow runs real ClientSessions on LocalBackends sharing one LocalServer; the same flow
## over WebSockets, at the protocol level, is test_fight_join::test_join_and_watch_over_websocket
## (a ClientSession on a NetBackend crashes the headless engine at exit: see the Journal).
extends TestCase

const Players := preload("res://tests/test_players.gd")
## the client's default look (ClientSession.player_look)
const LOOK := "{1|120,2195,4072,4941,3963,5716|1=13418918,2=4077879,3=16022817,4=14386944,5=4275500,6=9904435|56|1@0={1420|||90}}"


func _init() -> void:
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()
	SpellBook.use_file("res://tests/fixtures/spells.json")


static func _sword(teams := [1, 1], phase := "placement", options := {}) -> Dictionary:
	return {"id": 7, "kind": "fight", "name": "Combat", "cell": 300, "dir": 1, "looks": [], "teams": teams, "phase": phase, "options": options}


func test_the_swords_read_the_actor() -> void:
	var s := FightSwords.new()
	s.setup(_sword([2.0, 3.0])) # numbers come back as floats after a JSON round trip
	eq(s.teams, [2, 3])
	eq(s.fight_id, 7)
	check(s.contains(s.position + Vector2(0, -20)), "a click on the blades")
	check(not s.contains(s.position + Vector2(200, 0)), "not far away")
	check(s.can_join() and s.can_watch(), "an open fight in placement")
	s.free()


func test_what_the_menu_allows() -> void:
	var s := FightSwords.new()
	s.setup(_sword([1, 1], "fight"))
	check(not s.can_join(), "the placement is over")
	check(s.can_watch())
	s.free()
	s = FightSwords.new()
	s.setup(_sword([1, 1], "placement", {"locked": true, "secret": true}))
	check(not s.can_join(), "locked")
	check(not s.can_watch(), "no spectators")
	s.free()


func _tree() -> SceneTree:
	return Engine.get_meta("test_tree") as SceneTree


## The session leaves the tree and goes at once: no frame runs its _process after the test.
func _drop(s: ClientSession) -> void:
	s.backend = null
	_tree().root.remove_child(s)
	s.free()


func _session(server: LocalServer, name: String) -> ClientSession:
	var b := LocalBackend.new()
	b.account = name.to_lower() # one account holds a few characters only: each its own
	b.server = server
	var s := ClientSession.new()
	s.world_id = "duo"
	s.player_name = name
	s.persistent = false
	s.backend = b
	_tree().root.add_child(s) # _ready says hello
	return s


## Runs the server, Alice's connection and the sessions until `until` is true or `seconds` of game time passed.
func _run(server: LocalServer, alice: Players.Conn, sessions: Array, seconds: float, until := Callable()) -> bool:
	for i in int(seconds / 0.05):
		server.tick(50)
		alice.backend.poll(0.05)
		for s: ClientSession in sessions:
			s.backend.poll(0.05)
		if until.is_valid() and until.call():
			return true
	return not until.is_valid()


## The entry `index` of the menu the swords just opened, pressed.
func _press(s: ClientSession, sw: FightSwords, index: int) -> void:
	var before := s.get_children().filter(func(n: Node) -> bool: return n is PopupMenu).size()
	sw.menu(s, Vector2(20, 20))
	var menus := s.get_children().filter(func(n: Node) -> bool: return n is PopupMenu)
	eq(menus.size(), before + 1, "the menu opens")
	var m: PopupMenu = menus[-1]
	eq(m.get_item_text(m.get_item_index(index)), ["Rejoindre", "Regarder"][index])
	m.id_pressed.emit(index)


## A world with one group, all looks complete: a sprite with a short or unknown look crashes the engine at exit.
func _world() -> LocalServer:
	var tofu := {"look": LOOK, "name": "Tofu", "name_id": 5, "level": 1, "hp": 500, "ap": 4, "mp": 3, "xp": 10}
	var s := LocalServer.new()
	s.sources["duo"] = WorldSource.from_dicts(
		{"id": "duo", "name": "Duo", "start_map": 1, "start_cell": 300, "wander_ms": [600000, 600000]},
		[{"id": 1, "coords": [0, 0], "groups": [{"name": "Tofu", "members": [tofu]}]}])
	return s


func test_join_watch_and_leave_through_the_client() -> void:
	var server := _world()
	var alice := Players.Conn.new(server, "Alice", LOOK, "alice")
	var bob := _session(server, "Bob")
	var carl := _session(server, "Carl")
	var all := [bob, carl]
	_run(server, alice, all, 1.0)
	check(bob.map != null and carl.map != null, "both sessions are on the map")
	var group: int = alice.sim().get_map(1).actors.values().filter(func(x: SimActor) -> bool: return x is MonsterGroup)[0].id
	alice.send(Protocol.fight_attack(group))
	var has_swords := func() -> bool: return bob.views.values().any(func(v: Node) -> bool: return v is FightSwords) \
			and carl.views.values().any(func(v: Node) -> bool: return v is FightSwords)
	check(_run(server, alice, all, 3.0, has_swords), "both see the swords")
	var fid: int = alice.sim().fights.keys()[0]
	var sw: FightSwords = bob.views[fid]
	eq([sw.teams, sw.phase], [[1, 1], "placement"])
	check(not bob.views.values().any(func(v: Node) -> bool: return v is GroupView), "the group is gone")
	check(bob._swords_at(sw.position + Vector2(0, -20)) == sw, "the session finds them under the mouse")

	# Carl watches: a read only view of the fight
	_press(carl, carl.views[fid], 1)
	check(_run(server, alice, all, 3.0, func() -> bool: return carl.fight != null), "Carl is watching")
	check(carl.fight.spectator, "as a spectator")
	eq(carl.fight.fighters.size(), 2, "Alice and the Tofu")
	eq(carl.fight.phase, "placement")
	check(not carl.fight.hud.spell_bar.visible and not carl.fight.hud.get("_main_button").visible, "no spell bar, no ready button")
	carl.fight.end_turn()
	carl.fight._click(carl.fight.placement[0][0])
	_run(server, alice, all, 0.3)
	check(carl.fight != null, "a spectator sends nothing: the view stays")

	# Bob joins in the placement: he fights, Carl sees him arrive
	_press(bob, sw, 0)
	check(_run(server, alice, all, 3.0, func() -> bool: return bob.fight != null), "Bob joins")
	check(not bob.fight.spectator and bob.fight.you == bob.you, "he is a fighter")
	eq(bob.fight.fighters.size(), 3)
	check(_run(server, alice, all, 3.0, func() -> bool: return carl.fight.fighters.size() == 3), "the spectator sees the newcomer")
	check(carl.fight.views.has(bob.you) and carl.fight.order.has(bob.you), "on the map and in the timeline")

	# both ready: Carl sees the fight begin
	alice.send(Protocol.fight_ready())
	bob.fight.set_ready(true)
	check(_run(server, alice, all, 3.0, func() -> bool: return carl.fight.phase == "fight"), "Carl sees the fight begin")

	# Bob flees: no results window, back on the map; Carl sees him go
	bob.fight.leave()
	check(_run(server, alice, all, 3.0, func() -> bool: return bob.fight == null), "Bob is out of the fight")
	check(not is_instance_valid(bob._result_window), "no results window for a runaway")
	check(_run(server, alice, all, 3.0, func() -> bool: return not carl.fight.fighters[bob.you]["alive"]), "Carl sees him leave: he no longer fights")
	_run(server, alice, all, 1.0, func() -> bool: return bob.views.has(fid))
	check(bob.views.has(bob.you) and bob.views.has(fid), "Bob is back on the map, the swords are there")

	# Carl leaves the audience: no window either, back on the map
	carl.fight.leave()
	check(_run(server, alice, all, 3.0, func() -> bool: return carl.fight == null), "Carl stops watching")
	check(not is_instance_valid(carl._result_window), "no results window for a spectator")
	check(carl._actors.visible, "the map is shown again")
	_run(server, alice, all, 1.0, func() -> bool: return carl.views.has(carl.you))
	check(carl.views.has(carl.you), "Carl is back on the map")
	_drop(bob)
	_drop(carl)
