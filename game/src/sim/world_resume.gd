## Reconnection of a player who was in a fight (roadmap S.02b), a WorldSim handler.
## When the connection of a fighter drops, the player is not removed: it stays in its fight,
## absent (Fight.set_absent: it passes its turns, then the AI plays for it after
## Fight.ABSENT_GRACE_MS). If it comes back in time (`reattach`), it gets the state again and
## plays on. Once its fight is over, a detached player is released like a normal logout
## (saved; rewards are already given). Out of a fight nothing is kept: the host replays the
## connection of the same character (the map and the position are in the save).
class_name WorldResume
extends WorldHandler


## The connection of `id` dropped. True if the player stays (in a fight, as a fighter);
## false: nothing is kept, the caller disconnects it as usual.
func detach(id: int) -> bool:
	var p: PlayerActor = sim.players.get(id)
	if p == null or p.fight_id == 0 or p.spectating != 0 or not sim.fights.has(p.fight_id):
		return false
	var fight: Fight = sim.fights[p.fight_id]
	var f: Fighter = fight.fighters.get(p.id)
	if f == null or f.left:
		return false
	sim.jobs.cancel_harvest(p)
	p.detached = true
	fight.set_absent(f, sim.now)
	return true


## The player is back on a new connection: stale events are dropped and the whole state is sent
## again (what connect_player sends, then the fight as it is now). False if the player is gone.
func reattach(id: int) -> bool:
	var p: PlayerActor = sim.players.get(id)
	if p == null or not p.detached:
		return false
	p.detached = false
	p.outbox.clear()
	var fight: Fight = sim.fights.get(p.fight_id)
	if fight == null:
		sim.disconnect_player(id)
		return false
	var f: Fighter = fight.fighters[p.id]
	fight.set_present(f)
	p.outbox.append(Protocol.welcome(p.id, sim.now, sim.world_summary()))
	p.outbox.append(Protocol.player_stats(p.character.public_dict(sim.now)))
	p.outbox.append(Protocol.inventory(p.character.inventory.to_array()))
	p.outbox.append(Protocol.quest_list(sim.quests.views(p), sim.quests.finished(p)))
	# S.05b: the snapshot is its team's view too (an invisible enemy has no cell)
	p.outbox.append(FightVisibility.view(Protocol.fight_start(fight.id, p.id, fight.fighters_dicts(), fight.order,
			fight.placement_dict(), fight.placement_end), fight, f.team))
	if not fight.challenges.is_empty():
		p.outbox.append(Protocol.challenge_list(fight.challenges))
	p.outbox.append(Protocol.fight_options(fight.options))
	var cur := fight.current()
	if fight.phase == "fight" and cur != null:
		p.outbox.append(Protocol.fight_begin(fight.order))
		p.outbox.append(Protocol.fight_turn(cur.id, cur.ap, cur.mp, fight.turn_end, []))
	return true


## Whether `id` is a detached player still in the world.
func is_detached(id: int) -> bool:
	var p: PlayerActor = sim.players.get(id)
	return p != null and p.detached


## Each tick: a detached player whose fight is over is released.
func tick() -> void:
	for p: PlayerActor in sim.players.values():
		if p.detached and p.fight_id == 0:
			sim.disconnect_player(p.id)
