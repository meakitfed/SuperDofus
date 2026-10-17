## Duels (P3.10): a player challenges another one of its map, who accepts or not; the accepted
## challenge starts a fight between the two (Fight.kind "duel", WorldFights.start_duel) where
## nothing is won or lost. The messages are in shared/ProtocolDuel. Only the pending challenges live
## here (nothing is persisted); the fight is an ordinary Fight.
## APPROX(P3.10): a duel is allowed on every map and between any levels (Dofus 3 blocks it on some maps
## through mapsinformation.m_flags bit 0, which our worlds do not all carry), see DECOUVERTES.
class_name WorldDuel
extends WorldHandler

## challenged name -> {challenger name -> sim ms}
var requests := {}


func on_command(p: PlayerActor, type: String, cmd: Dictionary) -> void:
	var err := ""
	match type:
		ProtocolDuel.REQUEST:
			err = _request(p, str(cmd["name"]))
		ProtocolDuel.ACCEPT:
			err = _accept(p, str(cmd["from"]))
		ProtocolDuel.DECLINE:
			err = _decline(p, str(cmd["from"]))
	if err != "":
		p.outbox.append(Protocol.error(err, "", type))


## Free to duel: not in a fight, not a ghost, no trade or other window open.
func _free(p: PlayerActor) -> String:
	if p.character.is_ghost():
		return Protocol.E_GHOST
	if p.fight_id != 0 or p.spectating != 0 or p.detached or sim.trade.in_trade(p) or p.dialog_npc != 0 \
			or p.shop_npc != 0 or p.bank_npc != 0 or p.market_open or not p.craft.is_empty() or not p.harvest.is_empty():
		return ProtocolDuel.E_DUEL_BUSY
	return ""


func _request(p: PlayerActor, name: String) -> String:
	var target := sim.chat.find_player(name)
	if target == null or target == p:
		return Protocol.E_PLAYER_OFFLINE
	var err := _free(p)
	if err != "":
		return err
	if target.map_id != p.map_id:
		return Protocol.E_NO_TARGET
	if _free(target) != "":
		return ProtocolDuel.E_DUEL_BUSY
	if sim.contacts.ignores(target, p):
		return "" # an ignored player is not heard, and not told (like the chat and the trade)
	if not requests.has(target.name):
		requests[target.name] = {}
	requests[target.name][p.name] = sim.now
	target.outbox.append(ProtocolDuel.requested(p.name))
	return ""


func _valid(p: PlayerActor, from: String) -> bool:
	var mine: Dictionary = requests.get(p.name, {})
	return mine.has(from) and sim.now - int(mine[from]) <= ProtocolDuel.INVITE_TTL_MS


func _accept(p: PlayerActor, from: String) -> String:
	if not _valid(p, from):
		return ProtocolDuel.E_NO_DUEL_REQUEST
	var challenger := sim.chat.find_player(from)
	(requests[p.name] as Dictionary).erase(from)
	if challenger == null or challenger.map_id != p.map_id:
		return ProtocolDuel.E_NO_DUEL_REQUEST
	if _free(p) != "" or _free(challenger) != "":
		return ProtocolDuel.E_DUEL_BUSY
	for n: String in [challenger.name, p.name]: # a player in a fight answers nothing more
		forget(n)
	sim.combat.start_duel(challenger, p, sim.get_map(p.map_id))
	return ""


func _decline(p: PlayerActor, from: String) -> String:
	if not _valid(p, from):
		return ProtocolDuel.E_NO_DUEL_REQUEST
	(requests[p.name] as Dictionary).erase(from)
	var challenger := sim.chat.find_player(from)
	if challenger != null:
		challenger.outbox.append(ProtocolDuel.end(ProtocolDuel.REASON_DECLINED))
	return ""


## Drops every challenge sent by or to `name`.
func forget(name: String) -> void:
	requests.erase(name)
	for target: String in requests:
		(requests[target] as Dictionary).erase(name)


func on_disconnect(p: PlayerActor) -> void:
	forget(p.name)


func tick() -> void:
	for target: String in requests.keys():
		var mine: Dictionary = requests[target]
		for from: String in mine.keys():
			if sim.now - int(mine[from]) > ProtocolDuel.INVITE_TTL_MS:
				mine.erase(from)
				var challenger := sim.chat.find_player(from)
				if challenger != null:
					challenger.outbox.append(ProtocolDuel.end(ProtocolDuel.REASON_EXPIRED))
		if mine.is_empty():
			requests.erase(target)
