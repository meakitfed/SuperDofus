## Trade between two players (P3.11): invitations, the open trade, the double validation and
## the atomic exchange. The rules are in shared/TradeRules, the messages in shared/ProtocolTrade;
## nothing here knows Dofus and nothing of a trade is persisted (a trade lives as long as both
## are connected, on one map, out of fight). The exchange is all or nothing: everything is
## checked again at the double validation, then the two characters are written in one
## Persistence.commit. Every opened trade (done or not) leaves an audit entry.
class_name WorldTrade
extends WorldHandler

const LOG_SIZE := 200

## name -> TradeSession (both names of a trade point to the same one)
var sessions := {}
## invitations: invited name -> {inviter name -> sim ms}
var invites := {}
## the audit trail of the opened trades, oldest first: {at (unix ms), world, account, name, cmd
## "trade", args [other], ok, code, with, with_account, gave: {name: {items: [{id, qty}], kamas}}}
var log: Array = []


## One of the trade_* commands of a player (already validated against the schema).
func on_command(p: PlayerActor, type: String, cmd: Dictionary) -> void:
	var err := ""
	match type:
		ProtocolTrade.INVITE:
			err = _invite(p, str(cmd["name"]))
		ProtocolTrade.ACCEPT:
			err = _accept(p, str(cmd["from"]))
		ProtocolTrade.DECLINE:
			err = _decline(p, str(cmd["from"]))
		ProtocolTrade.SET:
			err = _on_set(p, cmd["items"], int(cmd["kamas"]))
		ProtocolTrade.READY:
			err = _on_ready(p)
		ProtocolTrade.CANCEL:
			err = ProtocolTrade.E_NOT_IN_TRADE if not sessions.has(p.name) else _end(sessions[p.name], ProtocolTrade.REASON_CANCELLED)
	if err != "":
		p.outbox.append(Protocol.error(err, "", type))


func in_trade(p: PlayerActor) -> bool:
	return sessions.has(p.name)


## Free to trade: not in a fight, not a ghost, no other window open (dialog, shop, bank, workshop, harvest).
func _free(p: PlayerActor) -> String:
	if p.character.is_ghost():
		return Protocol.E_GHOST
	if p.fight_id != 0 or p.spectating != 0 or p.detached or sessions.has(p.name) or p.dialog_npc != 0 \
			or p.shop_npc != 0 or p.bank_npc != 0 or not p.craft.is_empty() or not p.harvest.is_empty():
		return ProtocolTrade.E_TRADE_BUSY
	return ""


func _invite(p: PlayerActor, name: String) -> String:
	var target := sim.chat.find_player(name)
	if target == null or target == p:
		return Protocol.E_PLAYER_OFFLINE
	var err := _free(p)
	if err != "":
		return err
	if target.map_id != p.map_id:
		return Protocol.E_NO_TARGET
	if _free(target) != "":
		return ProtocolTrade.E_TRADE_BUSY
	if sim.contacts.ignores(target, p):
		return "" # P3.05b: an ignored player is not heard, and not told (like the chat)
	if not invites.has(target.name):
		invites[target.name] = {}
	invites[target.name][p.name] = sim.now
	target.outbox.append(ProtocolTrade.invited(p.name))
	return ""


func _valid_invite(p: PlayerActor, from: String) -> bool:
	var mine: Dictionary = invites.get(p.name, {})
	return mine.has(from) and sim.now - int(mine[from]) <= TradeRules.INVITE_TTL_MS


func _accept(p: PlayerActor, from: String) -> String:
	if not _valid_invite(p, from):
		return ProtocolTrade.E_NO_TRADE_INVITATION
	var inviter := sim.chat.find_player(from)
	(invites[p.name] as Dictionary).erase(from)
	if inviter == null or inviter.map_id != p.map_id:
		return ProtocolTrade.E_NO_TRADE_INVITATION
	if _free(p) != "" or _free(inviter) != "":
		return ProtocolTrade.E_TRADE_BUSY
	var s := TradeSession.create(inviter.name, p.name)
	sessions[inviter.name] = s
	sessions[p.name] = s
	for n: String in [inviter.name, p.name]: # no other invitation holds once one trade is open
		invites.erase(n)
		for target: String in invites:
			(invites[target] as Dictionary).erase(n)
	inviter.outbox.append(ProtocolTrade.open(p.name, p.id))
	p.outbox.append(ProtocolTrade.open(inviter.name, inviter.id))
	_push(s)
	return ""


func _decline(p: PlayerActor, from: String) -> String:
	if not _valid_invite(p, from):
		return ProtocolTrade.E_NO_TRADE_INVITATION
	(invites[p.name] as Dictionary).erase(from)
	var inviter := sim.chat.find_player(from)
	if inviter != null:
		inviter.outbox.append(ProtocolTrade.end(ProtocolTrade.REASON_DECLINED))
	return ""


## trade_set: the new offer of `p` (the previous one is replaced, the validations fall).
## The bag of the other must be able to carry it (the bag of `p` is checked at the validation).
func _on_set(p: PlayerActor, lines: Array, kamas: int) -> String:
	var s: TradeSession = sessions.get(p.name)
	if s == null:
		return ProtocolTrade.E_NOT_IN_TRADE
	var items := TradeRules.normalize(lines)
	if items.has("err"):
		return str(items["err"])
	var c := p.character
	var err := TradeRules.offer_error(c.inventory.items, c.kamas, items, kamas)
	if err != "":
		return err
	var q := sim.chat.find_player(s.other(p.name))
	var theirs := q.character
	err = TradeRules.weight_error(theirs.weight(), theirs.max_weight(), TradeRules.weight_of(theirs.inventory.items, s.items_of(q.name)),
			TradeRules.weight_of(c.inventory.items, items))
	if err != "":
		return err
	s.set_offer(p.name, items, kamas)
	_push(s)
	return ""


func _on_ready(p: PlayerActor) -> String:
	var s: TradeSession = sessions.get(p.name)
	if s == null:
		return ProtocolTrade.E_NOT_IN_TRADE
	var err := _check(s)
	if err != "":
		return err
	s.ready[p.name] = true
	if s.both_ready():
		return _commit(s)
	_push(s)
	return ""


## "" if the two offers can be exchanged now: each side still holds what it offers and both
## bags can carry what they receive.
func _check(s: TradeSession) -> String:
	var pa := sim.chat.find_player(s.a)
	var pb := sim.chat.find_player(s.b)
	if pa == null or pb == null:
		return Protocol.E_PLAYER_OFFLINE
	for p: PlayerActor in [pa, pb]:
		var bad := TradeRules.offer_error(p.character.inventory.items, p.character.kamas, s.items_of(p.name), s.kamas_of(p.name))
		if bad != "":
			return bad
	var wa := TradeRules.weight_of(pa.character.inventory.items, s.items_of(s.a))
	var wb := TradeRules.weight_of(pb.character.inventory.items, s.items_of(s.b))
	var err := TradeRules.weight_error(pa.character.weight(), pa.character.max_weight(), wa, wb)
	if err == "":
		err = TradeRules.weight_error(pb.character.weight(), pb.character.max_weight(), wb, wa)
	return err


## The double validation: checked again, then the exchange, all or nothing.
func _commit(s: TradeSession) -> String:
	var err := _check(s)
	if err != "":
		return _end(s, ProtocolTrade.REASON_FAILED, err)
	var pa := sim.chat.find_player(s.a)
	var pb := sim.chat.find_player(s.b)
	var gave := {}
	var moved := {}
	for p: PlayerActor in [pa, pb]: # everything is out of the givers' bags first
		moved[p.name] = []
		for uid: int in s.items_of(p.name):
			var it := p.character.inventory.get_item(uid).duplicate(true)
			var qty := int(s.items_of(p.name)[uid])
			var left := p.character.inventory.remove(uid, qty)
			p.outbox.append(Protocol.item_added(left) if not left.is_empty() else Protocol.item_removed(uid))
			it["qty"] = qty
			moved[p.name].append(it)
		gave[p.name] = {"items": (moved[p.name] as Array).map(func(it: Dictionary) -> Dictionary: return {"id": int(it["id"]), "qty": int(it["qty"])}),
				"kamas": s.kamas_of(p.name)}
	for pair: Array in [[pa, pb], [pb, pa]]:
		var giver: PlayerActor = pair[0]
		var taker: PlayerActor = pair[1]
		for it: Dictionary in moved[giver.name]:
			var stack := taker.character.inventory.add(int(it["id"]), int(it["qty"]), it["effects"], sim.items.new_item_uid, int(it.get("reserve", 0)))
			taker.outbox.append(Protocol.item_added(stack))
		giver.character.kamas -= s.kamas_of(giver.name)
		taker.character.kamas += s.kamas_of(giver.name)
	sim.persistence.commit([sim.character_write(pa), sim.character_write(pb)])
	for p: PlayerActor in [pa, pb]:
		p.outbox.append(Protocol.player_stats(p.character.public_dict(sim.now)))
		sim.quests.event(p, {"kind": "item"})
	_record(s, true, "", gave)
	return _close(s, ProtocolTrade.REASON_DONE, "")


## Ends the trade: both are told, and it is audited (an opened trade always is).
func _end(s: TradeSession, reason: String, code := "") -> String:
	_record(s, false, reason if code == "" else code, {})
	return _close(s, reason, code)


func _close(s: TradeSession, reason: String, code: String) -> String:
	sessions.erase(s.a)
	sessions.erase(s.b)
	for n: String in [s.a, s.b]:
		var q := sim.chat.find_player(n)
		if q != null:
			q.outbox.append(ProtocolTrade.end(reason, code))
	return ""


## Ends the trade of `p` if it has one (`reason`: ProtocolTrade.REASON_*).
func cancel_for(p: PlayerActor, reason: String) -> void:
	if sessions.has(p.name):
		_end(sessions[p.name], reason)


## A player leaves the world: its trade is cancelled, its invitations void.
func on_disconnect(p: PlayerActor) -> void:
	cancel_for(p, ProtocolTrade.REASON_DISCONNECTED)
	invites.erase(p.name)
	for target: String in invites:
		(invites[target] as Dictionary).erase(p.name)


func tick() -> void:
	for target: String in invites.keys():
		var mine: Dictionary = invites[target]
		for from: String in mine.keys():
			if sim.now - int(mine[from]) > TradeRules.INVITE_TTL_MS:
				mine.erase(from)
				var inviter := sim.chat.find_player(from)
				if inviter != null:
					inviter.outbox.append(ProtocolTrade.end(ProtocolTrade.REASON_EXPIRED))
		if mine.is_empty():
			invites.erase(target)


func _push(s: TradeSession) -> void:
	for n: String in [s.a, s.b]:
		var q := sim.chat.find_player(n)
		if q != null:
			q.outbox.append(ProtocolTrade.update(_view(s, n), _view(s, s.other(n))))


## The offer of `name`: the stacks offered (qty = the offered part), the kamas, the validation.
func _view(s: TradeSession, name: String) -> Dictionary:
	var p := sim.chat.find_player(name)
	var out: Array = []
	var uids: Array = s.items_of(name).keys()
	uids.sort()
	for uid: int in uids:
		var it: Dictionary = p.character.inventory.get_item(uid).duplicate(true) if p != null else {}
		if not it.is_empty():
			it["qty"] = int(s.items_of(name)[uid])
			out.append(it)
	return {"items": out, "kamas": s.kamas_of(name), "ready": bool(s.ready[name])}


func _record(s: TradeSession, ok: bool, code: String, gave: Dictionary) -> void:
	var pa := sim.chat.find_player(s.a)
	var pb := sim.chat.find_player(s.b)
	var entry := {"at": sim.clock.now_unix_ms(), "world": sim.world_id(), "account": pa.character.account if pa != null else "",
			"name": s.a, "cmd": "trade", "args": [s.b], "ok": ok, "code": code, "with": s.b,
			"with_account": pb.character.account if pb != null else "", "gave": gave}
	log.append(entry)
	if log.size() > LOG_SIZE:
		log = log.slice(log.size() - LOG_SIZE)
	if sim.admin.audit_sink.is_valid():
		sim.admin.audit_sink.call(entry.duplicate(true))
