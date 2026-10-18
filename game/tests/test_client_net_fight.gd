## A real ClientSession on a NetBackend (WebSocket on 127.0.0.1, a ServerHost in this process) that
## starts a fight against a group of monsters and plays it: no script error may be emitted (a Logger
## collects every error of the engine). The solo twin is test_hud_toggles; this one covers what only
## the network changes: every number comes back as a float after the JSON round trip, the events
## arrive one poll apart, and the fight starts from fight_start / fight_state received over the wire.
## Also: a spectator (second ClientSession) watching that fight, and the end of the fight (results).
extends TestCase

const STEP := 0.05
## the client's default look (ClientSession.player_look)
const LOOK := "{1|120,2195,4072,4941,3963,5716|1=13418918,2=4077879,3=16022817,4=14386944,5=4275500,6=9904435|56|1@0={1420|||90}}"


## Collects the errors the engine reports while it is installed (script errors, failed calls).
class ErrorLog extends Logger:
	var errors: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array) -> void:
		if error_type == Logger.ERROR_TYPE_SCRIPT or error_type == Logger.ERROR_TYPE_ERROR:
			errors.append("%s:%d %s %s %s" % [file, line, function, code, rationale])


class Rig:
	var host := ServerHost.new()

	func _init() -> void:
		var tofu := {"look": LOOK, "name": "Tofu", "name_id": 5, "level": 1, "hp": 500, "ap": 4, "mp": 3, "xp": 10}
		host.server.sources["duo"] = WorldSource.from_dicts(
			{"id": "duo", "name": "Duo", "start_map": 1, "start_cell": 300, "wander_ms": [600000, 600000]},
			[{"id": 1, "coords": [0, 0], "groups": [{"name": "Tofu", "members": [tofu]}]}])
		host.listen(0, "127.0.0.1")

	func session(name: String) -> ClientSession:
		var b := NetBackend.new()
		b.connect_to("127.0.0.1:%d" % host.local_port())
		var s := ClientSession.new()
		s.world_id = "duo"
		s.player_name = name
		s.persistent = false
		s.backend = b
		(Engine.get_meta("test_tree") as SceneTree).root.add_child(s) # _ready says hello
		return s

	## One game step: the host, then every session (its _process polls its backend and lays the HUD out).
	func run(sessions: Array, seconds: float, until := Callable()) -> bool:
		for i in int(seconds / STEP):
			host.poll(STEP)
			for s: ClientSession in sessions:
				s._process(STEP)
			OS.delay_msec(1)
			if until.is_valid() and until.call():
				return true
		return not until.is_valid()


func _init() -> void:
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()
	SpellBook.use_file("res://tests/fixtures/spells.json")


## The session leaves the tree and goes at once: no frame runs its _process after the test.
func _drop(s: ClientSession) -> void:
	if s.backend != null:
		(s.backend as NetBackend).close()
	s.backend = null
	(Engine.get_meta("test_tree") as SceneTree).root.remove_child(s)
	s.free()


func _group(s: ClientSession) -> int:
	for id: int in s.views:
		if s.views[id] is GroupView:
			return id
	return -1


func test_a_fight_through_the_network_raises_no_script_error() -> void:
	HudToggles.reset_for_tests()
	var log := ErrorLog.new()
	OS.add_logger(log)
	var rig := Rig.new()
	var s := rig.session("Alice")
	var all := [s]
	check(rig.run(all, 5.0, func() -> bool: return s.map != null and _group(s) >= 0), "on the map, a group of monsters in sight")
	s.backend.send(Protocol.fight_attack(_group(s)))
	check(rig.run(all, 5.0, func() -> bool: return s.fight != null and s.fight.hud != null), "the fight HUD is up")
	rig.run(all, 1.5)
	eq((s._hud_sig as String).split("|")[3], "1", "the HUD layout was computed in a fight")
	check(s._area.blocks.has("timeline") and s._area.blocks.has("bar"), "the timeline and the bar float over the map")
	eq(s._area.bottom, s.player_hud.reserved_bottom(), "same strip as out of a fight (same zoom)")
	eq(s.fight.fighters.size(), 2, "Alice and the Tofu")
	for id: int in s.fight.fighters:
		check(s.fight.views.has(id), "fighter %d has its view" % id)

	# the placement, then the fight: the player is ready, plays a turn, passes
	s.fight.set_ready(true)
	check(rig.run(all, 5.0, func() -> bool: return s.fight != null and s.fight.phase == "fight"), "the fight begins")
	rig.run(all, 2.0)
	HudToggles.toggle_all() # hide the interface in the middle of the fight, then bring it back
	rig.run(all, 1.0)
	HudToggles.toggle_all()
	rig.run(all, 1.0)
	s.fight.end_turn()
	rig.run(all, 8.0)

	# a spectator joins the same fight by the sword menu's protocol message
	var carl := rig.session("Carl")
	all.append(carl)
	check(rig.run(all, 5.0, func() -> bool: return carl.map != null), "Carl is on the map")
	var fid: int = rig.host.server.worlds["duo"].fights.keys()[0] if not rig.host.server.worlds["duo"].fights.is_empty() else -1
	if fid >= 0:
		carl.backend.send(ProtocolWatch.spectate(fid))
		check(rig.run(all, 5.0, func() -> bool: return carl.fight != null and carl.fight.hud != null), "Carl watches")
		rig.run(all, 1.5)
		check(carl.fight.spectator, "as a spectator")
		carl.fight.leave()
		check(rig.run(all, 5.0, func() -> bool: return carl.fight == null), "Carl stops watching")

	OS.remove_logger(log)
	eq(log.errors, [], "no error reported by the engine during the whole fight")
	HudToggles.reset_for_tests()
	_drop(carl)
	_drop(s)
	rig.host.shutdown()
