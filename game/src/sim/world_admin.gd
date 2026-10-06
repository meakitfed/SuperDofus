## GM commands (A1.01), a WorldSim handler: `admin_cmd{cmd, args}` for players with the GM role
## (PlayerActor.gm, granted by the host). The role is checked here, in the sim, so a modified
## client gains nothing and standalone and server behave the same. Each command is out of fight
## (the router sends fights elsewhere) and every one, accepted or refused, is written to the
## audit trail: kept in memory (`audit_log`, the last AUDIT_SIZE) and handed to `audit_sink`
## (the server host writes it to its audit file). Rules are ours (no Dofus data: a game master
## tool); nothing here is specific to a game.
##   tp · give <item> [qty] [player] · kamas <n> [player] · level <n> [player] · heal [player]
##   say <text> · who · kick <player> · ban <player> [reason] · unban <player|account>
##   mute <player> [minutes] · unmute <player> · reload
class_name WorldAdmin
extends WorldHandler

const AUDIT_SIZE := 200
## APPROX(A1.01): a mute without a duration lasts 10 minutes; ceiling one week
const MUTE_DEFAULT_MIN := 10
const MUTE_MAX_MIN := 7 * 24 * 60
const MAX_GIVE := 100000

## the last audit entries, oldest first: {at (unix ms), world, account, name, cmd, args, ok, code}
var audit_log: Array = []
## Callable(entry: Dictionary), set by the host: where the audit trail goes (file, database)
var audit_sink := Callable()
## extra text of the error being returned by the command running (cleared at each command)
var detail := ""


func on_cmd(p: PlayerActor, what: String, args: Array) -> void:
	detail = ""
	var err := Protocol.E_NOT_GM
	if p.gm:
		err = _run(p, what, args)
	_record(p, what, args, err)
	if err != "":
		p.outbox.append(Protocol.error(err, detail, Protocol.ADMIN_CMD))


## A command of the web admin (A1.02): nobody plays it, so it runs as a transient GM named `by`
## and the answer is returned instead of queued: {ok, code, detail, result (admin_result args)}.
## Audited like any other command. `tp` moves the named player (first argument) to the map.
func run_web(by: String, what: String, args: Array) -> Dictionary:
	detail = ""
	var p := PlayerActor.new()
	p.gm = true
	p.name = by
	p.character.account = by
	var err := ""
	if what == "tp":
		err = _tp_player(args)
	else:
		err = _run(p, what, args)
	_record(p, what, args, err)
	var result := []
	for ev: Dictionary in p.outbox:
		if str(ev.get("t", "")) == ProtocolAdmin.ADMIN_RESULT:
			result = ev.get("args", [])
	return {"ok": err == "", "code": err, "detail": detail, "result": result}


## tp <player> <map> [cell]: the connected player (out of fight) goes to the map.
func _tp_player(args: Array) -> String:
	if args.size() < 2:
		return _bad("tp <player> <map> [cell]")
	var t := _target(null, str(args[0]))
	if t == null:
		return Protocol.E_PLAYER_OFFLINE
	return sim.travel.admin_tp(t, args.slice(1))


## "" when done (admin_result sent), else the error code.
func _run(p: PlayerActor, what: String, args: Array) -> String:
	var a: Array[String] = []
	for x: Variant in args:
		# JSON hands numbers back as floats: 683 must not become "683.0" (a client may send numbers)
		a.append(str(int(x)) if x is float and is_equal_approx(x, roundf(x)) else str(x).strip_edges())
	match what:
		"tp":
			var err := sim.travel.admin_tp(p, a)
			if err == "":
				p.outbox.append(ProtocolAdmin.admin_result(what, []))
			return err
		"give":
			return _give(p, a)
		"kamas":
			return _kamas(p, a)
		"level":
			return _level(p, a)
		"heal":
			return _heal(p, a)
		"say":
			if a.is_empty():
				return _bad("say what?")
			var text := " ".join(a).left(Chat.MAX_LENGTH)
			for q: PlayerActor in sim.players.values():
				q.outbox.append(ProtocolAdmin.announce(p.name, text))
			return _done(p, what, [text])
		"who":
			var names := []
			for q: PlayerActor in sim.players.values():
				names.append(q.name)
			names.sort()
			return _done(p, what, names)
		"kick":
			return _kick(p, a)
		"ban":
			return _ban(p, a)
		"unban":
			return _unban(p, a)
		"mute":
			return _mute(p, a, false)
		"unmute":
			return _mute(p, a, true)
		"reload":
			# APPROX(A1.01): reloads the data tables (GameData: items, XP, tables) read by the rules; the
			# maps and worlds of a running sim stay as loaded (restart the server for those)
			GameData.clear_cache()
			return _done(p, what, [])
	detail = what
	return Protocol.E_UNKNOWN_COMMAND


func _give(p: PlayerActor, a: Array[String]) -> String:
	if a.is_empty() or not a[0].is_valid_int():
		return _bad("give <item> [qty] [player]")
	var qty := int(a[1]) if a.size() > 1 and a[1].is_valid_int() else 1
	var who := a[2] if a.size() > 2 else (a[1] if a.size() > 1 and not a[1].is_valid_int() else "")
	if qty < 1 or qty > MAX_GIVE:
		return _bad("quantity 1-%d" % MAX_GIVE)
	if GameData.item(int(a[0])).is_empty():
		detail = a[0]
		return Protocol.E_UNKNOWN_ITEM
	var t := _target(p, who)
	if t == null:
		return Protocol.E_PLAYER_OFFLINE
	sim.give_item(t, int(a[0]), qty)
	sim.save_player(t)
	return _done(p, "give", [t.name, int(a[0]), qty])


func _kamas(p: PlayerActor, a: Array[String]) -> String:
	if a.is_empty() or not a[0].is_valid_int():
		return _bad("kamas <amount> [player]")
	var t := _target(p, a[1] if a.size() > 1 else "")
	if t == null:
		return Protocol.E_PLAYER_OFFLINE
	t.character.kamas = clampi(t.character.kamas + int(a[0]), 0, 2000000000)
	_refresh(t)
	return _done(p, "kamas", [t.name, t.character.kamas])


## level n: the level, the XP of that level, the capital of a fresh character of that level
## (CAPITAL_PER_LEVEL per level, stats reset) and full health.
func _level(p: PlayerActor, a: Array[String]) -> String:
	if a.is_empty() or not a[0].is_valid_int() or int(a[0]) < 1 or int(a[0]) > GameData.max_level():
		return _bad("level 1-%d" % GameData.max_level())
	var t := _target(p, a[1] if a.size() > 1 else "")
	if t == null:
		return Protocol.E_PLAYER_OFFLINE
	var c := t.character
	c.reset_stats(sim.now)
	c.level = int(a[0])
	c.xp = GameData.xp_floor(c.level)
	c.capital = Character.CAPITAL_PER_LEVEL * (c.level - 1)
	c.set_hp(c.max_hp(), sim.now)
	_refresh(t)
	return _done(p, "level", [t.name, c.level])


## heal: full health and energy; a ghost comes back to life (it re-enters its map so that
## the others see it alive).
func _heal(p: PlayerActor, a: Array[String]) -> String:
	var t := _target(p, a[0] if not a.is_empty() else "")
	if t == null:
		return Protocol.E_PLAYER_OFFLINE
	var was_ghost := t.character.is_ghost()
	t.character.life = Energy.ALIVE
	t.character.energy = Energy.MAX
	t.character.set_hp(t.character.max_hp(), sim.now)
	if was_ghost:
		t.settle(sim.now)
		sim.teleport(t, t.map_id, t.cell)
	_refresh(t)
	return _done(p, "heal", [t.name])


func _kick(p: PlayerActor, a: Array[String]) -> String:
	var t := _named(p, a)
	if t == null:
		return Protocol.E_PLAYER_OFFLINE
	sim.kick_player(t)
	return _done(p, "kick", [t.name])


func _ban(p: PlayerActor, a: Array[String]) -> String:
	if a.is_empty():
		return _bad("ban <player> [reason]")
	var account := _account_of(a[0])
	if account == "":
		detail = a[0]
		return Protocol.E_UNKNOWN_CHARACTER
	if account == p.character.account:
		return _bad("not yourself")
	Sanctions.ban(sim.persistence, account, " ".join(a.slice(1)), p.name, sim.clock.now_unix_ms())
	for q: PlayerActor in sim.players.values().duplicate():
		if q.character.account == account:
			sim.kick_player(q, ProtocolAdmin.E_BANNED)
	return _done(p, "ban", [a[0]])


func _unban(p: PlayerActor, a: Array[String]) -> String:
	if a.is_empty():
		return _bad("unban <player or account>")
	var account := a[0] if Sanctions.is_banned(sim.persistence, a[0]) else _account_of(a[0])
	if account == "" or not Sanctions.unban(sim.persistence, account):
		detail = a[0]
		return Protocol.E_UNKNOWN_CHARACTER
	return _done(p, "unban", [a[0]])


## mute <player> [minutes] / unmute <player>: the account cannot chat (WorldChat).
func _mute(p: PlayerActor, a: Array[String], lift: bool) -> String:
	if a.is_empty():
		return _bad("mute <player> [minutes]")
	var minutes := MUTE_DEFAULT_MIN
	if a.size() > 1:
		if not a[1].is_valid_int() or int(a[1]) < 1 or int(a[1]) > MUTE_MAX_MIN:
			return _bad("minutes 1-%d" % MUTE_MAX_MIN)
		minutes = int(a[1])
	var account := _account_of(a[0])
	if account == "":
		detail = a[0]
		return Protocol.E_UNKNOWN_CHARACTER
	Sanctions.mute(sim.persistence, account, 0 if lift else sim.clock.now_unix_ms() + minutes * 60000)
	return _done(p, "unmute" if lift else "mute", [a[0]] if lift else [a[0], minutes])


## The account of a character of this world (connected or saved), "" if unknown.
func _account_of(name: String) -> String:
	var q := sim.chat.find_player(name)
	if q != null:
		return q.character.account
	var saved := sim.persistence.load_character(sim.world_id(), name.strip_edges())
	return str(saved.get("account", ""))


## The connected player a command names (first argument), null if none (error: not connected).
func _named(p: PlayerActor, a: Array[String]) -> PlayerActor:
	if a.is_empty():
		_bad("player name needed")
		return null
	var t := sim.chat.find_player(a[0])
	detail = a[0]
	return t


## The target: the player of that name (any case), the GM itself when the name is empty; null if
## not connected or in a fight (a GM changes characters out of fight only).
func _target(p: PlayerActor, name: String) -> PlayerActor:
	var t := p if name == "" else sim.chat.find_player(name)
	detail = name
	if t != null and t.fight_id != 0:
		return null
	return t


## After a change to a character: its sheet is sent and it is saved.
func _refresh(t: PlayerActor) -> void:
	t.outbox.append(Protocol.player_stats(t.character.public_dict(sim.now)))
	sim.save_player(t)


func _done(p: PlayerActor, what: String, args: Array) -> String:
	p.outbox.append(ProtocolAdmin.admin_result(what, args))
	return ""


func _bad(why: String) -> String:
	detail = why
	return Protocol.E_BAD_MESSAGE


func _record(p: PlayerActor, what: String, args: Array, err: String) -> void:
	var entry := {"at": sim.clock.now_unix_ms(), "world": sim.world_id(), "account": p.character.account,
			"name": p.name, "cmd": what, "args": args.duplicate(), "ok": err == "", "code": err}
	audit_log.append(entry)
	if audit_log.size() > AUDIT_SIZE:
		audit_log = audit_log.slice(audit_log.size() - AUDIT_SIZE)
	if audit_sink.is_valid():
		audit_sink.call(entry.duplicate(true))
