## Achievements (P2.12a), a WorldSim handler, on for the worlds whose world.json says "achievements": true (like "challenges"): the events of the sim move the counters of the character, the newly
## obtained achievements give their rewards and tell the client (rules: Achievements).
class_name WorldAchievements
extends WorldHandler

var _busy := false


## Reports a game event (same events as WorldQuests.event, plus {kind: "quest", quest}). True when one was obtained.
func event(p: PlayerActor, ev: Dictionary) -> bool:
	if _busy or not bool(sim.info.get("achievements", false)) or Achievements.defs().is_empty():
		return false
	_busy = true # the rewards (items, XP) raise events of their own: they are read in the same loop
	var ch := p.character
	Achievements.count_event(ch.achievements, ev)
	var any := false
	var day := floori(float(sim.clock.now_unix_ms()) / 86400000.0)
	while true:
		var values := ch.criteria_values()
		var before := Achievements.with_state(values, ch.achievements)
		var got := Achievements.check(ch.achievements, values, day)
		if got.is_empty():
			break
		any = true
		# each reward is read as it was before the first of this round was marked (their own "Ob!" rows hold)
		for id: int in got:
			var reward := Achievements.rewards(id, before, ch.level)
			var gave := sim.quests.apply_rewards(p, reward)
			var a: Dictionary = Achievements.defs()[id]
			p.outbox.append(ProtocolAchievement.unlocked(id, int(a["name_id"]), int(a["points"]), Achievements.points(ch.achievements), gave))
		p.outbox.append(Protocol.player_stats(ch.public_dict(sim.now)))
	if any:
		sim.save_player(p)
	_busy = false
	return any


## achievement_open: the state of the character's achievements.
func send_list(p: PlayerActor) -> void:
	p.outbox.append(ProtocolAchievement.list(Achievements.view(p.character.achievements, p.character.criteria_values())))
