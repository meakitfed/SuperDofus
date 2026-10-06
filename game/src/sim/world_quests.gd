## Quests (P2.03), a WorldSim handler: what the sim tells QuestEngine and what it sends back.
class_name WorldQuests
extends WorldHandler

## true while QuestEngine is re-reading the player's map (apply_changes)
var _rechecking := false


## The views of the quests under way (Protocol quest_list).
func views(p: PlayerActor) -> Array:
	var quests := sim.source.get_quests()
	var out := []
	for id: int in p.character.quests.active:
		if quests.has(id):
			out.append(QuestEngine.view(quests, p.character.quests, id))
	return out


## The finished quests as the client lists them: [{id, name_id}] (name_id 0 when the world does not have the quest).
func finished(p: PlayerActor) -> Array:
	var quests := sim.source.get_quests()
	return p.character.quests.finished.map(func(id: int) -> Dictionary:
		return {"id": id, "name_id": int(quests[id]["name_id"]) if quests.has(id) else 0})


## quest_start action of a reply: the NPC offered it (QuestEngine.offers), so it begins now.
func start_quest(p: PlayerActor, id: int) -> void:
	var quests := sim.source.get_quests()
	var npc: SimActor = sim.get_map(p.map_id).actors.get(p.dialog_npc)
	if not npc is NpcActor or not QuestEngine.offers(quests, p.character.quests, (npc as NpcActor).npc_id, p.character.criteria_values(), day()).has(id):
		return
	apply_changes(p, QuestEngine.start(quests, p.character.quests, id, owned.bind(p)))


## Today, in days since 1970 (the sim's Clock).
func day() -> int:
	return floori(float(sim.clock.now_unix_ms()) / 86400000.0)


## quest_abandon: gives up a quest under way (QuestLog.abandon), sends the quest log again.
func abandon(p: PlayerActor, id: int) -> void:
	if not p.character.quests.abandon(id):
		return
	p.outbox.append(Protocol.quest_list(views(p), finished(p)))
	sim.save_player(p)
	send_markers(p)


## map_markers of the player's map: the NPCs that offer a quest and the places the quests under way point to.
func send_markers(p: PlayerActor) -> void:
	var quests := sim.source.get_quests()
	var map := sim.get_map(p.map_id)
	if quests.is_empty() or map == null:
		return
	var npcs_here := []
	for a: SimActor in map.actors.values():
		if a is NpcActor:
			npcs_here.append((a as NpcActor).npc_id)
	p.outbox.append(Protocol.map_markers(map.data.id, QuestEngine.markers(quests, p.character.quests, map.data.id, npcs_here,
			p.character.criteria_values(), day())))


func owned(item: int, p: PlayerActor) -> int:
	return p.character.inventory.bag_count(item)


## Reports a game event to the quests under way. True when something moved.
func event(p: PlayerActor, ev: Dictionary) -> bool:
	var quests := sim.source.get_quests()
	if quests.is_empty() or p.character.quests.active.is_empty():
		return false
	var changes := QuestEngine.on_event(quests, p.character.quests, ev, owned.bind(p))
	apply_changes(p, changes)
	return not changes.is_empty()


## Sends what QuestEngine changed: items handed in are taken, a finished step gives its rewards.
func apply_changes(p: PlayerActor, changes: Array) -> void:
	var quests := sim.source.get_quests()
	var log := p.character.quests
	var gave := false
	for c: Dictionary in changes:
		var id := int(c["quest"])
		for it: Array in c["consume"]:
			for t: Dictionary in p.character.inventory.take(int(it[0]), int(it[1])):
				p.outbox.append(Protocol.item_added(t["left"]) if not (t["left"] as Dictionary).is_empty() else Protocol.item_removed(int(t["uid"])))
		match str(c["kind"]):
			"start":
				if log.is_active(id):
					p.outbox.append(Protocol.quest_start(QuestEngine.view(quests, log, id)))
			"update":
				if log.is_active(id):
					p.outbox.append(Protocol.quest_update(QuestEngine.view(quests, log, id)))
			"step":
				var given := give_rewards(p, c["reward"])
				p.outbox.append(Protocol.quest_update(QuestEngine.view(quests, log, id), given))
				gave = true
			"finish":
				log.finished_day[id] = day()
				p.outbox.append(Protocol.quest_complete(id, int(quests[id]["name_id"]), give_rewards(p, c["reward"])))
				gave = true
	if gave or not changes.is_empty():
		p.outbox.append(Protocol.player_stats(p.character.public_dict(sim.now)))
		sim.save_player(p)
		send_markers(p)
	if gave: # the rewards are items too: they may finish an objective (a quest asking for what another gives)
		event(p, {"kind": "item"})
	if not changes.is_empty() and not _rechecking:
		# an objective that just became active may be satisfied where the player stands (a map to reach)
		_rechecking = true
		var here := sim.get_map(p.map_id)
		if here != null and p.fight_id == 0:
			event(p, {"kind": "map", "map": here.data.id, "subarea": here.data.subarea})
		_rechecking = false


## XP, kamas, items, emotes, titles and spells of a finished step (QuestEngine.rewards).
func give_rewards(p: PlayerActor, reward: Dictionary) -> Dictionary:
	var r := QuestEngine.rewards(reward, p.character.level)
	p.character.gain_xp(int(r["xp"]), sim.now)
	p.character.kamas += int(r["kamas"])
	for it: Array in r["items"]:
		sim.items.give_item(p, int(it[0]), int(it[1]), false)
	for pair: Array in [["emotes", p.character.emotes], ["titles", p.character.titles], ["spells", p.character.quest_spells]]:
		for v: int in r[pair[0]]:
			if not (pair[1] as Array).has(v):
				(pair[1] as Array).append(v)
	for j: int in r["jobs"]:
		p.character.jobs.learn(j) # queststeprewards.jobsReward: the job is taught (P2.05b)
	return r
