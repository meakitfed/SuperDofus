## Chat (P3.02): routes chat_send to the players of its channel, applies the anti-flood and
## keeps a journal of what was said (moderation, GM console A1.01). The rules are in
## shared/Chat; nothing here knows Dofus. Everything stays in memory: a chat message is
## never persisted (a private message to someone offline is refused, as in Dofus).
class_name WorldChat
extends WorldHandler

## the last messages, oldest first: {at (sim ms), unix_ms, channel, from, to, text}
var log: Array = []


func on_chat_send(p: PlayerActor, channel: String, text: String, to: String) -> void:
	var line := Chat.parse(text, channel, to)
	if line.has("error"):
		p.outbox.append(Protocol.error(Protocol.E_UNKNOWN_COMMAND, str(line["word"]), Protocol.CHAT_SEND))
		return
	channel = str(line["channel"])
	to = str(line["to"])
	text = str(line["text"])
	if not channel in Chat.AVAILABLE:
		p.outbox.append(Protocol.error(Protocol.E_CHANNEL_UNAVAILABLE, channel, Protocol.CHAT_SEND))
		return
	var muted := Sanctions.mute_left_ms(sim.persistence, p.character.account, sim.clock.now_unix_ms())
	if muted > 0: # a GM silenced the account (A1.01): nothing is said, not even a private message
		p.outbox.append(Protocol.error(ProtocolAdmin.E_MUTED, str(ceili(muted / 1000.0)), Protocol.CHAT_SEND))
		return
	if text == "":
		return # nothing to say (a bare "/b", an empty box)
	var recipients: Array = []
	if channel == Chat.PRIVATE:
		var target := find_player(to)
		if target == null or target == p:
			p.outbox.append(Protocol.error(Protocol.E_PLAYER_OFFLINE, to, Protocol.CHAT_SEND))
			return
		recipients = [target]
		to = target.name
	else:
		var err := _audience(p, channel, recipients)
		if err != "":
			p.outbox.append(Protocol.error(err, "", Protocol.CHAT_SEND))
			return
	var bucket := Chat.bucket(channel)
	var history := Chat.trim(p.chat_sent.get(bucket, []), channel, sim.now)
	var wait := Chat.flood_wait(channel, history, sim.now)
	if wait > 0:
		p.outbox.append(Protocol.error(Protocol.E_CHAT_FLOOD, str(wait), Protocol.CHAT_SEND))
		return
	history.append(sim.now)
	p.chat_sent[bucket] = history
	var links: Array = Chat.link_ids(text).filter(func(id: int) -> bool: return not GameData.item(id).is_empty())
	var msg := Chat.message(channel, p.name, p.id, text, sim.now, to, links)
	if channel == Chat.PRIVATE:
		p.outbox.append(msg) # the echo "À Bob : …"
	for r: PlayerActor in recipients:
		if not sim.contacts.ignores(r, p): # P3.05: an ignored speaker is not heard (and not told)
			r.outbox.append(msg)
	log.append({"at": sim.now, "unix_ms": sim.clock.now_unix_ms(), "channel": channel, "from": p.name, "to": to, "text": text})
	if log.size() > Chat.LOG_SIZE:
		log = log.slice(log.size() - Chat.LOG_SIZE)


## The player of that name (any case) who is connected, null if none.
func find_player(name: String) -> PlayerActor:
	var lower := name.strip_edges().to_lower()
	if lower == "":
		return null
	for q: PlayerActor in sim.players.values():
		if q.name.to_lower() == lower:
			return q
	return null


## Fills `out` with who hears `channel` from `p`; returns an error code, "" if fine.
func _audience(p: PlayerActor, channel: String, out: Array) -> String:
	match channel:
		Chat.GENERAL:
			# in a fight: its fighters only (APPROX(P3.02): spectators hear nobody yet, P3.04)
			for q: PlayerActor in sim.players.values():
				if (p.fight_id != 0 and q.fight_id == p.fight_id) or (p.fight_id == 0 and q.fight_id == 0 and q.map_id == p.map_id):
					out.append(q)
		Chat.TEAM:
			if p.fight_id == 0:
				return Protocol.E_NOT_IN_FIGHT
			# APPROX(P3.02): one team per fight for now (a player against monsters): same as general
			for q: PlayerActor in sim.players.values():
				if q.fight_id == p.fight_id:
					out.append(q)
		Chat.GROUP: # P3.03: the members of the speaker's party
			var party := sim.party.party_of(p.name)
			if party == null:
				return Protocol.E_CHANNEL_UNAVAILABLE
			for q: PlayerActor in sim.players.values():
				if party.has(q.name):
					out.append(q)
		_: # commerce, recruitment: the whole world
			out.append_array(sim.players.values())
	return ""
