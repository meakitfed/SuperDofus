## Joining a fight and watching one (P3.04, WorldSim handler). A fight started on a map is a
## `FightActor` of that map (the swords). A player of the map may join it during the placement
## (the players' team, 8 at most, unless the fight is locked or party-only) or watch it (unless it is
## secret): a spectator gets every event of the fight and can do nothing but leave. Nothing here is
## specific to a game: the fight itself is `Fight`.
## APPROX(P3.04): a spectator sees the fight like a team without sight of the invisible (no seat on
## either side); a player who disconnects leaves the fight (counts as dead, no reward) instead of
## passing its turns then being played by the AI (Dofus), see ROADMAP.
class_name WorldFightWatch
extends WorldHandler

## fight id -> FightActor on the map
var _actors := {}
## fight id -> the last state() broadcast
var _sent := {}


## A fight starts on `map` where the monsters were (`cell`).
func on_fight_started(fight: Fight, map: MapInstance, cell: int) -> void:
	var a := FightActor.new()
	a.id = fight.id
	a.name = "Combat"
	a.fight = fight
	a.cell = cell
	_actors[fight.id] = a
	_sent[fight.id] = a.state()
	map.add_actor(a, sim.now)


## Each tick: the swords change when the teams, the phase or the options do.
func tick() -> void:
	for fid: int in _actors:
		var a: FightActor = _actors[fid]
		var st := a.state()
		if st != _sent[fid]:
			_sent[fid] = st
			var map := sim.get_map(a.map_id)
			if map != null:
				map.broadcast(Protocol.actor_add(a.to_dict(sim.now)))


## The fight is over: its swords go away, the spectators go back to the map.
func on_fight_finished(fight: Fight, map: MapInstance) -> void:
	var a: FightActor = _actors.get(fight.id)
	if a != null:
		map.remove_actor(a)
	_actors.erase(fight.id)
	_sent.erase(fight.id)
	for pid: int in fight.spectators:
		var p: PlayerActor = sim.players.get(pid)
		if p == null:
			continue
		p.spectating = 0
		p.outbox.append(Protocol.fight_end(fight.result, sim.now - fight.started_at, []))
		sim.enter_map(p, sim.get_map(p.map_id), map.data.nearest_walkable(p.return_cell))
	fight.spectators.clear()


## fight_join / fight_spectate, from a player of the map who is not in a fight.
func on_command(p: PlayerActor, map: MapInstance, type: String, cmd: Dictionary) -> void:
	var a: FightActor = _actors.get(int(cmd.get("fight", -1)))
	if a == null or a.map_id != map.data.id:
		p.outbox.append(Protocol.error(ProtocolWatch.E_NO_FIGHT, "", type))
		return
	var err := _join(p, map, a.fight, int(cmd.get("team", 0))) if type == ProtocolWatch.JOIN else _spectate(p, map, a.fight)
	if err != "":
		p.outbox.append(Protocol.error(err, "", type))


func _join(p: PlayerActor, map: MapInstance, fight: Fight, team: int) -> String:
	if p.character.is_ghost():
		return Protocol.E_GHOST
	var err := fight.join_error(_in_leaders_party(p, fight))
	if err != "":
		return err
	p.settle(sim.now)
	var pf := sim.combat.player_fighter(p)
	err = fight.join(pf, team, p.cell)
	if err != "":
		return err
	p.return_cell = p.cell
	map.remove_actor(p)
	p.fight_id = fight.id
	sim.trade.cancel_for(p, ProtocolTrade.REASON_FIGHT)
	p.outbox.append(FightVisibility.view(Protocol.fight_start(fight.id, pf.id, fight.fighters_dicts(), fight.order,
			fight.placement_dict(), fight.placement_end), fight, team))
	p.outbox.append(Protocol.fight_options(fight.options))
	if not fight.challenges.is_empty():
		p.outbox.append(Protocol.challenge_list(fight.challenges))
	tell_others(fight, ProtocolWatch.joined(pf.to_dict(), fight.order), p.id)
	return ""


func _spectate(p: PlayerActor, map: MapInstance, fight: Fight) -> String:
	var err := fight.spectate(p.id)
	if err != "":
		return err
	p.settle(sim.now)
	p.return_cell = p.cell
	map.remove_actor(p)
	p.spectating = fight.id
	p.outbox.append(FightVisibility.view(fight.watch_dict(), fight, -1)) # S.05b: no seat, no sight of the invisible
	return ""


## A spectator stops watching (fight_leave): back on the map where it stood.
func stop(p: PlayerActor) -> void:
	var fight: Fight = sim.fights.get(p.spectating)
	p.spectating = 0
	if fight != null:
		fight.spectators.erase(p.id)
	var map := sim.get_map(p.map_id)
	p.outbox.append(Protocol.fight_end("", 0, []))
	sim.enter_map(p, map, map.data.nearest_walkable(p.return_cell))


## The player who fled a fight the others go on with is back on the map (no reward).
func after_command(p: PlayerActor, fight: Fight) -> void:
	var f: Fighter = fight.fighters.get(p.id)
	if f == null or not f.left or p.fight_id != fight.id:
		return
	p.fight_id = 0
	p.outbox.append(Protocol.fight_end("abandon", sim.now - fight.started_at, []))
	var map := sim.get_map(p.map_id)
	sim.enter_map(p, map, map.data.nearest_walkable(p.return_cell))
	sim.save_player(p)


## `ev` to the fighters (their team's view) and the spectators, but not to `except_id`.
func tell_others(fight: Fight, ev: Dictionary, except_id: int) -> void:
	for f: Fighter in fight.fighters.values():
		if f.player_id >= 0 and f.player_id != except_id and sim.players.has(f.player_id):
			(sim.players[f.player_id] as PlayerActor).outbox.append(ev)
	for pid: int in fight.spectators:
		if pid != except_id and sim.players.has(pid):
			(sim.players[pid] as PlayerActor).outbox.append(ev)


## Whether `p` is in the same group as the fight's leader (the party_only option).
func _in_leaders_party(p: PlayerActor, fight: Fight) -> bool:
	var lead := fight.leader()
	var lp: PlayerActor = sim.players.get(lead.player_id) if lead != null else null
	if lp == null:
		return false
	var party := sim.party.party_of(p.name)
	return party != null and party == sim.party.party_of(lp.name)
