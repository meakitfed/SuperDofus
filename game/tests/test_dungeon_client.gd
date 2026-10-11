## The dungeon side of the client (P4.01f): DungeonModel without any node (entrances of the map,
## room, boss, end), the indicator's answers, and a real ClientSession on a LocalBackend that walks
## in through the entrance panel, sees the room counter and leaves.
extends TestCase

const Sim := preload("res://tests/test_dungeon_sim.gd")
## the client's default look (ClientSession.player_look)
const LOOK := "{1|120,2195,4072,4941,3963,5716|1=13418918,2=4077879,3=16022817,4=14386944,5=4275500,6=9904435|56|1@0={1420|||90}}"


func _init() -> void:
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()


class Sink:
	extends GameBackend
	var sent: Array = []

	func send(msg: Dictionary) -> void:
		sent.append(msg)


static func _map() -> Dictionary:
	return {"id": 1, "dungeons": [{"id": 7, "name": "Cour du Test", "min_level": 3}, {"id": 8, "name": "Cave", "min_level": 1}]}


func test_model_follows_the_events() -> void:
	var m := DungeonModel.new()
	m.on_map(_map())
	eq(m.entrances.size(), 2)
	check(not m.inside)
	eq(m.on_event(ProtocolDungeon.ROOM, ProtocolDungeon.room(7, 1, 3, false, "Salle 2")), "", "no toast for a room")
	m.on_map({"id": 11}) # the room map carries no dungeons
	check(m.inside and m.entrances.is_empty(), "inside, no entrance")
	eq([m.dungeon_name(), m.room_text()], ["Cour du Test", "Salle 2/3"])
	m.on_event(ProtocolDungeon.ROOM, ProtocolDungeon.room(7, 2, 3, true, "Boss"))
	eq(m.room_text(), "Salle du boss")
	eq(m.on_event(ProtocolDungeon.END, ProtocolDungeon.end(7, "won")), "Donjon terminé : victoire !")
	check(not m.inside)
	for reason: String in ProtocolDungeon.REASONS:
		check(DungeonModel.end_text(reason) != "", "text for " + reason)
	check(DungeonModel.end_text("defeat") != DungeonModel.end_text("left"))


func test_indicator_sends_enter_and_leave() -> void:
	var sink := Sink.new()
	var ind := DungeonIndicator.new()
	ind.setup(sink)
	check(not ind.visible, "nothing to show away from the door")
	ind.on_map(_map())
	check(ind.visible, "the door shows its dungeons")
	ind.enter(7)
	eq(sink.sent.back(), ProtocolDungeon.enter(7))
	ind.on_event(ProtocolDungeon.ROOM, ProtocolDungeon.room(7, 0, 3, false, "Salle 1"), null)
	ind.on_map({"id": 11})
	check(ind.visible and ind.model.inside)
	ind.leave()
	eq(sink.sent.back(), ProtocolDungeon.leave())
	ind.on_event(ProtocolDungeon.END, ProtocolDungeon.end(7, "left"), null)
	check(not ind.visible, "out: hidden again")
	ind.free()


func _tree() -> SceneTree:
	return Engine.get_meta("test_tree") as SceneTree


func test_session_walks_through_a_dungeon() -> void:
	var server := Sim._server()
	var b := LocalBackend.new()
	b.account = "dg"
	b.server = server
	var s := ClientSession.new()
	s.world_id = "dg"
	s.player_name = "Dora"
	s.persistent = false
	s.backend = b
	_tree().root.add_child(s)
	var run := func(seconds: float, until := Callable()) -> bool:
		for i in int(seconds / 0.05):
			server.tick(50)
			b.poll(0.05)
			if until.is_valid() and until.call():
				return true
		return not until.is_valid()
	run.call(0.5)
	check(s.map != null, "on the map")
	var me: PlayerActor = b.sim.players[s.you]
	me.character.level = 30
	b.sim.give_item(me, Sim.KEY)
	b.sim.teleport(me, 1, 300)
	check(run.call(2.0, func() -> bool: return s.player_hud.dungeon.model.entrances.size() == 2), "the door lists two dungeons")
	check(s.player_hud.dungeon.visible)
	s.player_hud.dungeon.enter(7)
	check(run.call(3.0, func() -> bool: return s.player_hud.dungeon.model.inside), "inside")
	var d := s.player_hud.dungeon
	eq([d.model.dungeon, d.model.room, d.model.total], [7, 0, 3])
	eq(d.model.room_text(), "Salle 1/3")
	check(s.map != null and s.map.id != 1, "in a room map")
	d.leave()
	check(run.call(3.0, func() -> bool: return not d.model.inside), "out")
	eq(d.model.last_reason, "left")
	run.call(0.5)
	check(s.map.id == 1 and d.visible, "back at the door")
	b.sim.dungeons.runs.clear()
	s.backend = null
	_tree().root.remove_child(s)
	s.free()
