## The life of the fight view inside a ClientSession (split out of client_session.gd): it starts when
## the sim sends `fight_start` (you fight, also after joining one in placement, P3.04) or
## `fight_watch` (you watch, read only), follows `fighter_joined` / `fighter_left`, and ends with
## `fight_end` (results window for a fighter; none for a spectator, a runaway or a plain leave).
class_name FightFlow
extends RefCounted

var _s: ClientSession


func _init(session: ClientSession) -> void:
	_s = session


func handle(t: String, ev: Dictionary) -> void:
	match t:
		Protocol.FIGHT_START:
			_begin(ev, false)
		ProtocolWatch.WATCH:
			_watch(ev)
		ProtocolWatch.JOINED:
			if _s.fight != null:
				_s.fight.on_joined(ev["fighter"], ev["order"])
		ProtocolWatch.LEFT:
			if _s.fight != null:
				_s.fight.on_left(int(ev["id"]), ev["order"])
		Protocol.FIGHT_END:
			_end(ev)


## `fight_watch`: the state of a fight we do not play, as a fight_start without a fighter of ours.
func _watch(ev: Dictionary) -> void:
	var start := {"you": -1, "fighters": ev["fighters"], "order": ev["order"], "phase": ev["phase"],
			"placement": ev["placement"], "end": ev["end"]}
	_begin(start, true)
	var f := _s.fight
	f.current = int(ev["turn"])
	f.turn_end = int(ev["end"])
	f.timer_total = maxi(1, f.turn_end - _s.backend.time_ms())
	f.options = ev["options"]
	f.challenges = ev["challenges"]
	f.hud.refresh_options()
	f.hud.set_challenges()
	f.hud.refresh()
	_s.show_banner("Vous regardez le combat", 1.5)


func _begin(ev: Dictionary, spectator: bool) -> void:
	if _s._pending.kind in [PendingAction.Kind.EXIT, PendingAction.Kind.INTERACTIVE]:
		_s._pending.clear()
	_s._map_view.preview = []
	_s._actors.visible = false
	var fight := FightView.new()
	fight.spectator = spectator
	_s.fight = fight
	_s.add_child(fight)
	_s.move_child(fight, _s._world_sort.get_index()) # team discs under the entities, above the ground
	fight.sequence_done.connect(_s._on_sequence_done)
	fight.bar = _s.player_hud.stats.get("bar", [])
	fight.setup(_s.backend, _s.map, _s._map_view, _s._hud_layer, _s._world_sort, ev)
	if is_instance_valid(_s._result_window):
		_s._result_window.queue_free()
	if not spectator:
		_s.show_banner("Placement", 1.2)


func _end(ev: Dictionary) -> void:
	var result := str(ev["result"])
	var fight := _s.fight
	if fight != null:
		# a spectator, a runaway (`abandon`) or a plain leave (`""`) has nothing to be rewarded for
		if not fight.spectator and result not in ["", "abandon"]:
			var names := {}
			for id: int in fight.fighters:
				names[id] = fight.fighter_name(id) if id != fight.you else _s.player_name
			_s._result_window = FightResultWindow.new()
			_s._hud_layer.add_child(_s._result_window)
			var shown := ev.duplicate()
			shown["challenges"] = fight.challenges
			_s._result_window.setup_result(shown, fight.fighters, names, fight.you)
		elif fight.spectator and result != "":
			_s.show_banner("Combat terminé", 2.0)
		elif result == "abandon":
			_s.show_banner("Combat abandonné", 2.0)
		fight.close()
		_s.fight = null
	else:
		_s.show_banner({"win": "Victoire !", "lose": "Défaite…", "abandon": "Combat abandonné"}.get(result, result), 2.0)
	_s._actors.visible = true
