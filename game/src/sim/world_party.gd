## Groups (P3.03): invitations, the leader, exclusion, following the leader and the
## position of the members. The rules of one group are in shared/Party; the messages in
## shared/ProtocolParty. Nothing here knows Dofus, and nothing is persisted: a group lives
## as long as its members are connected (leaving the game leaves the group, as in Dofus).
## The XP bonus of a group needs no code here: a fight's rewards count its human fighters
## (FightRewards, FightXp.GROUP_BONUS); P3.04 lets a group fight together.
class_name WorldParty
extends WorldHandler

## the groups: id -> Party, and the group of a character: name -> Party
var parties := {}
var of := {}
## invitations: invited name -> {inviter name -> sim ms}
var invites := {}
## who follows whom: name -> name of a member of its group
var follows := {}
## the last party_update sent to each member (name -> JSON): only a change is sent again
var _sent := {}
var _next_push := 0


## One of the party_* commands of a player (already validated against the schema).
func on_command(p: PlayerActor, type: String, cmd: Dictionary) -> void:
	var err := ""
	match type:
		ProtocolParty.INVITE:
			err = _invite(p, str(cmd["name"]))
		ProtocolParty.ACCEPT:
			err = _accept(p, str(cmd["from"]))
		ProtocolParty.DECLINE:
			err = _decline(p, str(cmd["from"]))
		ProtocolParty.LEAVE:
			err = ProtocolParty.E_NOT_IN_PARTY if not of.has(p.name) else _remove(p.name, ProtocolParty.REASON_LEFT)
		ProtocolParty.KICK:
			err = _kick(p, str(cmd["name"]))
		ProtocolParty.LEADER:
			err = _lead(p, str(cmd["name"]))
		ProtocolParty.FOLLOW:
			err = _follow(p, str(cmd["name"]))
	if err != "":
		p.outbox.append(Protocol.error(err, "", type))


func party_of(name: String) -> Party:
	return of.get(name)


func _invite(p: PlayerActor, name: String) -> String:
	var target := sim.chat.find_player(name)
	if target == null or target == p:
		return Protocol.E_PLAYER_OFFLINE
	var mine: Party = of.get(p.name)
	if mine != null and mine.leader() != p.name:
		return ProtocolParty.E_NOT_PARTY_LEADER
	if of.has(target.name):
		return ProtocolParty.E_ALREADY_IN_PARTY
	if mine != null and mine.is_full():
		return ProtocolParty.E_PARTY_FULL
	if sim.contacts.ignores(target, p):
		return "" # P3.05b: an ignored inviter is not heard, and not told (like the chat)
	if not invites.has(target.name):
		invites[target.name] = {}
	invites[target.name][p.name] = sim.now
	target.outbox.append(ProtocolParty.invited(p.name))
	return ""


## The inviter that is still there and may still lead: a pending invitation is only good
## while it lives (Party.INVITE_TTL_MS).
func _valid_invite(p: PlayerActor, from: String) -> bool:
	var mine: Dictionary = invites.get(p.name, {})
	return mine.has(from) and sim.now - int(mine[from]) <= Party.INVITE_TTL_MS


func _accept(p: PlayerActor, from: String) -> String:
	if not _valid_invite(p, from):
		return ProtocolParty.E_NO_INVITATION
	var inviter := sim.chat.find_player(from)
	var party: Party = of.get(from)
	if inviter == null or (party != null and party.leader() != from):
		(invites[p.name] as Dictionary).erase(from)
		return ProtocolParty.E_NO_INVITATION
	if of.has(p.name):
		return ProtocolParty.E_ALREADY_IN_PARTY
	if party == null:
		party = Party.create(sim.alloc_id(), from, p.name)
		parties[party.id] = party
		of[from] = party
	else:
		var err := party.add(p.name)
		if err != "":
			return err
	of[p.name] = party
	invites.erase(p.name)
	_push(party)
	return ""


func _decline(p: PlayerActor, from: String) -> String:
	if not _valid_invite(p, from):
		return ProtocolParty.E_NO_INVITATION
	(invites[p.name] as Dictionary).erase(from)
	var inviter := sim.chat.find_player(from)
	if inviter != null:
		inviter.outbox.append(ProtocolParty.declined(p.name))
	return ""


func _kick(p: PlayerActor, name: String) -> String:
	var party: Party = of.get(p.name)
	if party == null:
		return ProtocolParty.E_NOT_IN_PARTY
	var member := name_in(party, name)
	var err := party.can_kick(p.name, member)
	if err != "":
		return err
	return _remove(member, ProtocolParty.REASON_KICKED)


func _lead(p: PlayerActor, name: String) -> String:
	var party: Party = of.get(p.name)
	if party == null:
		return ProtocolParty.E_NOT_IN_PARTY
	var err := party.promote(p.name, name_in(party, name))
	if err == "":
		_push(party)
	return err


func _follow(p: PlayerActor, name: String) -> String:
	var party: Party = of.get(p.name)
	if party == null:
		return ProtocolParty.E_NOT_IN_PARTY
	if name == "":
		follows.erase(p.name)
	else:
		var member := name_in(party, name)
		if member == p.name or not party.has(member):
			return Protocol.E_NO_TARGET
		follows[p.name] = member
	_push(party)
	return ""


## The member of `party` called `name` in any case ("" if none).
func name_in(party: Party, name: String) -> String:
	for m: String in party.members:
		if m.to_lower() == name.strip_edges().to_lower():
			return m
	return ""


## `name` is out (left, excluded: `reason` is what it is told; "" = it is gone, tell nobody).
## A group left with one member dissolves.
func _remove(name: String, reason: String) -> String:
	var party: Party = of.get(name)
	if party == null:
		return ""
	party.remove(name)
	_forget(name)
	_tell(name, reason)
	if party.is_dissolved():
		for m: String in party.members.duplicate():
			_forget(m)
			_tell(m, ProtocolParty.REASON_DISSOLVED)
		parties.erase(party.id)
	else:
		_push(party)
	return ""


func _forget(name: String) -> void:
	of.erase(name)
	_sent.erase(name)
	follows.erase(name)
	for f: String in follows.keys():
		if follows[f] == name:
			follows.erase(f)


func _tell(name: String, reason: String) -> void:
	var q := sim.chat.find_player(name)
	if q != null and reason != "":
		q.outbox.append(ProtocolParty.left(reason))


## A player leaves the world: out of its group, its invitations void.
func on_disconnect(p: PlayerActor) -> void:
	_remove(p.name, "")
	invites.erase(p.name)
	for target: String in invites:
		(invites[target] as Dictionary).erase(p.name)


## A member changed map by a teleport (`from_map` = the one it left): the members following
## it that were with it, out of fight, join it. APPROX(P3.03): they are placed next to the
## leader at once (Dofus walks the follower to the exit and across the maps).
func on_moved(p: PlayerActor, from_map: int) -> void:
	if p.map_id == from_map:
		return
	for f: String in follows.keys():
		if follows.get(f) != p.name:
			continue
		var q := sim.chat.find_player(f)
		if q != null and q.fight_id == 0 and q.map_id == from_map and not q.character.is_ghost():
			sim.teleport(q, p.map_id, sim.get_map(p.map_id).data.nearest_walkable(p.cell))


func tick() -> void:
	if sim.now < _next_push:
		return
	_next_push = sim.now + 1000
	for target: String in invites.keys():
		var mine: Dictionary = invites[target]
		for from: String in mine.keys():
			if sim.now - int(mine[from]) > Party.INVITE_TTL_MS:
				mine.erase(from)
		if mine.is_empty():
			invites.erase(target)
	for party: Party in parties.values():
		_push(party)


## Sends the group to the members that do not have its current state.
func _push(party: Party) -> void:
	var members: Array = []
	for name: String in party.members:
		var q := sim.chat.find_player(name)
		if q != null:
			members.append(_member(q))
	for m: Dictionary in members:
		var q := sim.chat.find_player(str(m["name"]))
		var view := {"id": party.id, "leader": party.leader(), "follow": follows.get(q.name, ""), "members": members}
		var key := JSON.stringify(view)
		if _sent.get(q.name, "") != key:
			_sent[q.name] = key
			q.outbox.append(ProtocolParty.update(view))


func _member(q: PlayerActor) -> Dictionary:
	var map := sim.get_map(q.map_id)
	var coords := [map.data.coords.x, map.data.coords.y] if map != null else [0, 0]
	return {"id": q.id, "name": q.name, "level": q.character.level, "breed": q.character.breed,
			"hp": q.character.hp_at(sim.now), "max_hp": q.character.max_hp(), "map": q.map_id,
			"coords": coords, "cell": q.cell, "fight": q.fight_id != 0}
