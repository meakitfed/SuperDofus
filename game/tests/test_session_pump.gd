## The client's event queue (ClientSession._pump): a fight sequence that ends before _dispatch returns
## (a fight_turn whose effects play instantly) must not leave the queue blocked for good, otherwise every
## player of the fight is frozen until they reconnect.
extends TestCase

## the client's default look (ClientSession.player_look)
const LOOK := "{1|120,2195,4072,4941,3963,5716|1=13418918,2=4077879,3=16022817,4=14386944,5=4275500,6=9904435|56|1@0={1420|||90}}"


func _init() -> void:
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()
	SpellBook.use_file("res://tests/fixtures/spells.json")


func _tree() -> SceneTree:
	return Engine.get_meta("test_tree") as SceneTree


func _world() -> LocalServer:
	var tofu := {"look": LOOK, "name": "Tofu", "name_id": 5, "level": 1, "hp": 500, "ap": 4, "mp": 3, "xp": 10}
	var s := LocalServer.new()
	s.sources["pump"] = WorldSource.from_dicts(
		{"id": "pump", "name": "Pump", "start_map": 1, "start_cell": 300, "wander_ms": [600000, 600000]},
		[{"id": 1, "coords": [0, 0], "groups": [{"name": "Tofu", "members": [tofu]}]}])
	return s


func _run(server: LocalServer, s: ClientSession, seconds: float, until: Callable) -> bool:
	for i in int(seconds / 0.05):
		server.tick(50)
		s.backend.poll(0.05)
		if until.call():
			return true
	return false


func test_a_sequence_ending_at_once_does_not_block_the_queue() -> void:
	var server := _world()
	var b := LocalBackend.new()
	b.account = "bob"
	b.server = server
	var s := ClientSession.new()
	s.world_id = "pump"
	s.player_name = "Bob"
	s.persistent = false
	s.backend = b
	_tree().root.add_child(s)
	check(_run(server, s, 2.0, func() -> bool: return s.map != null), "Bob is on the map")
	var group: int = server.worlds["pump"].get_map(1).actors.values().filter(func(x: SimActor) -> bool: return x is MonsterGroup)[0].id
	s.backend.send(Protocol.fight_attack(group))
	check(_run(server, s, 3.0, func() -> bool: return s.fight != null), "the fight starts")
	s.fight.set_ready(true)
	check(_run(server, s, 3.0, func() -> bool: return s.fight.phase == "fight" and s.fight.current >= 0), "the fight begins")

	# a turn of Bob with one light effect: it plays without waiting
	var end: int = b.time_ms() + 30000
	s._on_event({"t": Protocol.FIGHT_TURN, "id": s.you, "ap": 6, "mp": 3, "end": end,
			"effects": [{"kind": "buff_end", "target": s.you, "buff": 999}]})
	check(not s._blocked, "the queue is not blocked after an instant sequence")
	# and the events behind it still go through
	s._on_event({"t": Protocol.FIGHT_TURN, "id": s.you, "ap": 5, "mp": 2, "end": end + 1000, "effects": []})
	eq(s.fight.turn_end, end + 1000, "the next event is applied")

	s.backend = null
	_tree().root.remove_child(s)
	s.free()
