## Guilds (P3.06a): creation, invitations, ranks and rights, leaving and exclusion, and the
## audience of the /g chat channel. The rules of one guild are in shared/Guild, the messages
## in shared/ProtocolGuild. Nothing here knows Dofus.
##
## Persistence (the guild is shared state, so it never lives only in memory):
##   "guilds"        key "<world>/<id>"       Guild.to_dict()
##   "guild_members" key "<world>/<character>" {guild: id}   (the guild of a character)
##   "guild_names"   key "<world>/<name lower>" {guild: id}   (a name is unique in a world)
## Every command reads the documents again, changes them and writes them together
## (Persistence.commit), so that two worlds of a server sharing the store never work on a stale
## copy; only the invitations (one minute) are kept in memory.
## APPROX(P3.06a): two commands of two worlds on the same guild at the same instant are not
## serialised (the last write wins); the server's database (S.03) brings transactions.
class_name WorldGuild
extends WorldHandler

const GUILDS := "guilds"
const MEMBERS := "guild_members"
const NAMES := "guild_names"

## invitations: invited name -> {inviter name -> {guild (id), at (sim ms)}}
var invites := {}
## the character being disconnected: shown offline in the views pushed while it leaves
var _leaving := ""


func _world() -> String:
	return sim.world_id()


func _gkey(id: int) -> String:
	return "%s/%d" % [_world(), id]


## The guild of a character, null if it has none.
func guild_of(name: String) -> Guild:
	var id := int(sim.persistence.load_doc(MEMBERS, "%s/%s" % [_world(), name]).get("guild", 0))
	return load_guild(id) if id != 0 else null


func load_guild(id: int) -> Guild:
	var d := sim.persistence.load_doc(GUILDS, _gkey(id))
	return Guild.from_dict(d) if not d.is_empty() else null


## Writes of a guild and the index of its members; `gone` names members whose index goes.
func _writes(g: Guild, gone: Array = []) -> Array:
	var w: Array = [{"collection": GUILDS, "key": _gkey(g.id), "data": g.to_dict()},
			{"collection": NAMES, "key": "%s/%s" % [_world(), g.name.to_lower()], "data": {"guild": g.id}}]
	for m: Dictionary in g.members:
		w.append({"collection": MEMBERS, "key": "%s/%s" % [_world(), m["name"]], "data": {"guild": g.id}})
	for n: String in gone:
		w.append({"collection": MEMBERS, "key": "%s/%s" % [_world(), n], "data": null})
	return w


func on_command(p: PlayerActor, type: String, cmd: Dictionary) -> void:
	var err := ""
	match type:
		ProtocolGuild.GET:
			send_info(p)
		ProtocolGuild.CREATE:
			err = _create(p, str(cmd["name"]).strip_edges(), cmd["emblem"] as Dictionary)
		ProtocolGuild.INVITE:
			err = _invite(p, str(cmd["name"]))
		ProtocolGuild.ACCEPT:
			err = _accept(p, str(cmd["from"]))
		ProtocolGuild.DECLINE:
			err = _decline(p, str(cmd["from"]))
		ProtocolGuild.LEAVE:
			err = _leave(p)
		ProtocolGuild.KICK:
			err = _kick(p, str(cmd["name"]))
		ProtocolGuild.RANK:
			err = _rank(p, str(cmd["name"]), int(cmd["rank"]))
		ProtocolGuild.RIGHTS:
			err = _rights(p, str(cmd["name"]), cmd["rights"] as Array)
		ProtocolGuild.LEADER:
			err = _lead(p, str(cmd["name"]))
		ProtocolGuild.DISBAND:
			err = _disband(p)
	if err != "":
		p.outbox.append(Protocol.error(err, "", type))


func _create(p: PlayerActor, name: String, emblem: Dictionary) -> String:
	if guild_of(p.name) != null:
		return ProtocolGuild.E_ALREADY_IN_GUILD
	var err := Guild.name_error(name)
	if err == "":
		err = Guild.emblem_error(emblem)
	if err != "":
		return err
	if not sim.persistence.load_doc(NAMES, "%s/%s" % [_world(), name.to_lower()]).is_empty():
		return ProtocolGuild.E_GUILD_NAME_TAKEN
	var g := Guild.create(sim.persistence.next_uid("guild"), name, emblem, p.name, sim.clock.now_unix_ms())
	sim.persistence.commit(_writes(g))
	_push(g)
	return ""


func _invite(p: PlayerActor, name: String) -> String:
	var g := guild_of(p.name)
	if g == null:
		return ProtocolGuild.E_NOT_IN_GUILD
	var err := g.invite_error(p.name)
	if err != "":
		return err
	var target := sim.chat.find_player(name)
	if target == null or target == p:
		return Protocol.E_PLAYER_OFFLINE
	if guild_of(target.name) != null:
		return ProtocolGuild.E_ALREADY_IN_GUILD
	if sim.contacts.ignores(target, p):
		return "" # an ignored inviter is not heard, and not told (like the chat)
	if not invites.has(target.name):
		invites[target.name] = {}
	invites[target.name][p.name] = {"guild": g.id, "at": sim.now}
	target.outbox.append(ProtocolGuild.invited(p.name, g.name))
	return ""


## The guild id of a pending invitation from `from`, 0 if there is none (or it expired).
func _valid_invite(p: PlayerActor, from: String) -> int:
	var e: Dictionary = (invites.get(p.name, {}) as Dictionary).get(from, {})
	if e.is_empty() or sim.now - int(e["at"]) > Guild.INVITE_TTL_MS:
		return 0
	return int(e["guild"])


func _accept(p: PlayerActor, from: String) -> String:
	var id := _valid_invite(p, from)
	if id == 0:
		return ProtocolGuild.E_NO_GUILD_INVITATION
	(invites[p.name] as Dictionary).erase(from)
	var g := load_guild(id)
	# the inviter must still be there with the right to invite (it may have left or been demoted)
	if g == null or g.invite_error(from) == ProtocolGuild.E_GUILD_NO_RIGHT or g.index_of(from) < 0:
		return ProtocolGuild.E_NO_GUILD_INVITATION
	if guild_of(p.name) != null:
		return ProtocolGuild.E_ALREADY_IN_GUILD
	var err := g.add(p.name, sim.clock.now_unix_ms())
	if err != "":
		return err
	invites.erase(p.name)
	sim.persistence.commit(_writes(g))
	_push(g)
	return ""


func _decline(p: PlayerActor, from: String) -> String:
	if _valid_invite(p, from) == 0:
		return ProtocolGuild.E_NO_GUILD_INVITATION
	(invites[p.name] as Dictionary).erase(from)
	var inviter := sim.chat.find_player(from)
	if inviter != null:
		inviter.outbox.append(ProtocolGuild.declined(p.name))
	return ""


func _leave(p: PlayerActor) -> String:
	var g := guild_of(p.name)
	if g == null:
		return ProtocolGuild.E_NOT_IN_GUILD
	if g.leader() == p.name:
		if g.members.size() > 1:
			return ProtocolGuild.E_GUILD_LEADER
		return _disband(p) # the last member closes the door
	_remove(g, p.name, ProtocolGuild.REASON_LEFT)
	return ""


func _kick(p: PlayerActor, who: String) -> String:
	var g := guild_of(p.name)
	if g == null:
		return ProtocolGuild.E_NOT_IN_GUILD
	var name := _canon(g, who)
	var err := g.kick_error(p.name, name)
	if err != "":
		return err
	_remove(g, name, ProtocolGuild.REASON_KICKED)
	return ""


## The member of `g` called `who` (any case), `who` itself if there is none.
func _canon(g: Guild, who: String) -> String:
	for m: Dictionary in g.members:
		if str(m["name"]).to_lower() == who.strip_edges().to_lower():
			return str(m["name"])
	return who


## `name` leaves `g` (left or kicked): index and guild written, the member told if online.
func _remove(g: Guild, name: String, reason: String) -> void:
	g.remove(name)
	sim.persistence.commit(_writes(g, [name]))
	var q := sim.chat.find_player(name)
	if q != null:
		q.outbox.append(ProtocolGuild.left(reason))
		q.outbox.append(ProtocolGuild.info({}))
	_push(g)


func _rank(p: PlayerActor, who: String, rank: int) -> String:
	var g := guild_of(p.name)
	if g == null:
		return ProtocolGuild.E_NOT_IN_GUILD
	var name := _canon(g, who)
	var err := g.rank_error(p.name, name, rank)
	if err != "":
		return err
	g.set_rank(name, rank)
	sim.persistence.commit(_writes(g))
	_push(g)
	return ""


func _rights(p: PlayerActor, who: String, rights: Array) -> String:
	var g := guild_of(p.name)
	if g == null:
		return ProtocolGuild.E_NOT_IN_GUILD
	var name := _canon(g, who)
	var err := g.rights_error(p.name, name, rights)
	if err != "":
		return err
	g.set_rights(name, rights)
	sim.persistence.commit(_writes(g))
	_push(g)
	return ""


func _lead(p: PlayerActor, who: String) -> String:
	var g := guild_of(p.name)
	if g == null:
		return ProtocolGuild.E_NOT_IN_GUILD
	var name := _canon(g, who)
	if g.leader() != p.name:
		return ProtocolGuild.E_GUILD_NO_RIGHT
	if g.index_of(name) < 0 or name == p.name:
		return ProtocolGuild.E_NOT_IN_GUILD
	g.hand_over(name)
	sim.persistence.commit(_writes(g))
	_push(g)
	return ""


func _disband(p: PlayerActor) -> String:
	var g := guild_of(p.name)
	if g == null:
		return ProtocolGuild.E_NOT_IN_GUILD
	if g.leader() != p.name:
		return ProtocolGuild.E_GUILD_NO_RIGHT
	var gone: Array = g.members.map(func(m: Dictionary) -> String: return str(m["name"]))
	var w: Array = [{"collection": GUILDS, "key": _gkey(g.id), "data": null},
			{"collection": NAMES, "key": "%s/%s" % [_world(), g.name.to_lower()], "data": null}]
	for n: String in gone:
		w.append({"collection": MEMBERS, "key": "%s/%s" % [_world(), n], "data": null})
	sim.persistence.commit(w)
	for n: String in gone:
		var q := sim.chat.find_player(n)
		if q != null:
			q.outbox.append(ProtocolGuild.left(ProtocolGuild.REASON_DISBANDED))
			q.outbox.append(ProtocolGuild.info({}))
	return ""


# -- views ------------------------------------------------------------------------------

## The guild as the client sees it, for the member `viewer` ({} for no guild).
func view(g: Guild, viewer: String) -> Dictionary:
	var members: Array = []
	for m: Dictionary in g.members:
		var q := sim.chat.find_player(str(m["name"])) if str(m["name"]) != _leaving else null
		members.append({"name": m["name"], "rank": m["rank"], "rights": m["rights"], "online": q != null,
				"level": q.character.level if q != null else 0, "breed": q.character.breed if q != null else -1})
	var me := g.member(viewer)
	return {"id": g.id, "name": g.name, "emblem": g.emblem.duplicate(), "members": members,
			"you": {"rank": int(me.get("rank", 0)), "rights": me.get("rights", [])}}


func send_info(p: PlayerActor) -> void:
	var g := guild_of(p.name)
	p.outbox.append(ProtocolGuild.info(view(g, p.name) if g != null else {}))


## The new state of `g` to every member online (but `except`).
func _push(g: Guild, except: PlayerActor = null) -> void:
	for m: Dictionary in g.members:
		var q := sim.chat.find_player(str(m["name"]))
		if q != null and q != except:
			q.outbox.append(ProtocolGuild.info(view(g, q.name)))


func on_connect(p: PlayerActor) -> void:
	var g := guild_of(p.name)
	if g != null:
		_push(g)


func on_disconnect(p: PlayerActor) -> void:
	for target: String in invites.keys():
		(invites[target] as Dictionary).erase(p.name)
	invites.erase(p.name)
	var g := guild_of(p.name)
	if g != null:
		_leaving = p.name
		_push(g, p)
		_leaving = ""


func tick() -> void:
	for target: String in invites.keys():
		var mine: Dictionary = invites[target]
		for from: String in mine.keys():
			if sim.now - int((mine[from] as Dictionary)["at"]) > Guild.INVITE_TTL_MS:
				mine.erase(from)
		if mine.is_empty():
			invites.erase(target)


## Fills `out` with the players online of the guild of `p`; false if it has none (/g refused).
func audience(p: PlayerActor, out: Array) -> bool:
	var g := guild_of(p.name)
	if g == null:
		return false
	for m: Dictionary in g.members:
		var q := sim.chat.find_player(str(m["name"]))
		if q != null:
			out.append(q)
	return true
