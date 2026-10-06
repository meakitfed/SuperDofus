## One client connection, from hello to logout: first the account's character
## list for the chosen world (CharacterRoster), then one character playing in
## that world (WorldSim). The host authenticates the account and creates one
## GameSession per connection: LocalBackend in standalone, each WebSocket on
## the server (roadmap S.01/S.02), so the connection rules are written once.
##   hello{world}              -> characters{list}  (character selection)
##   hello{world, name, look}  -> welcome…  (tools and tests: plays `name`,
##                                creating it if needed with the same rules)
##   create / delete / select_character, list_characters: selection screen
class_name GameSession
extends RefCounted

var account := ""
## the account has the GM role (admin_cmd); the host decides
var gm := false
## a GM threw the player out (A1.01): the host drops the connection after sending the last events
var kicked := false
## world id -> WorldSim, or null if the world does not exist (the host decides)
var _worlds: Callable
## world chosen by hello (null before)
var sim: WorldSim
## the playing character's id in `sim`, -1 while choosing
var player_id := -1
## the world and character this session played last (S.02b: what a resume replays)
var last_world := ""
var last_name := ""
var _outbox: Array = []
var _seq := 0


func _init(p_account: String, worlds: Callable) -> void:
	account = p_account
	_worlds = worlds


func playing() -> bool:
	return sim != null and player_id >= 0


func handle(cmd: Dictionary) -> void:
	var type := str(cmd.get("t", ""))
	if type == Protocol.HELLO:
		_hello(cmd)
		return
	if playing():
		sim.handle(player_id, cmd)
		return
	var invalid := Protocol.validate(cmd, Protocol.C2S)
	if invalid != "" or sim == null:
		_error(cmd, Protocol.E_BAD_MESSAGE, invalid if invalid != "" else "hello first")
		return
	var err := ""
	match type:
		Protocol.LIST_CHARACTERS:
			pass
		Protocol.CREATE_CHARACTER:
			var name := str(cmd["name"])
			err = CharacterRoster.create(sim, account, name, cmd)
			if err == "":
				_outbox.append(Protocol.character_created(CharacterRoster.summaries(sim, account).filter(
						func(c: Dictionary) -> bool: return c["name"] == name)[0]))
		Protocol.DELETE_CHARACTER:
			err = CharacterRoster.delete(sim, account, str(cmd["name"]))
		Protocol.SELECT_CHARACTER:
			err = CharacterRoster.can_select(sim, account, str(cmd["name"]))
			if err == "":
				player_id = sim.connect_player(str(cmd["name"]), "", account)
				sim.players[player_id].gm = gm
				last_name = str(cmd["name"])
				return
		_:
			err = Protocol.E_NO_CHARACTER # a game command before choosing a character
	if err != "":
		_error(cmd, err)
	else:
		_outbox.append(CharacterRoster.characters_event(sim, account))


## Events for the client since the last call, numbered for this connection.
func drain() -> Array:
	var out := _outbox
	_outbox = []
	if playing():
		out.append_array(sim.drain(player_id))
		if sim.take_closed(player_id): # the sim ended this session (same character logged in elsewhere)
			player_id = -1
	for ev: Dictionary in out:
		if ev["t"] == Protocol.ERROR and ev.get("code") in [ProtocolAdmin.E_KICKED, ProtocolAdmin.E_BANNED] and player_id < 0:
			kicked = true
		_seq += 1
		ev["seq"] = _seq # sim.drain already hands out per-session copies
	return out


## The connection dropped without a logout (S.02b). A character in a fight stays in it, absent
## (WorldResume): true. Otherwise the character leaves the world, saved: false. Either way the
## session can `resume` later.
func detach() -> bool:
	if playing() and sim.resume.detach(player_id):
		return true
	close()
	return false


## A new connection takes this session over (S.02b). Replays what the client needs and returns
## the state for resume_ok: {world, name, playing, in_fight}. The events follow in `drain`:
## the fight as it is now when the character stayed in one, else a fresh connection of the same
## character (map and position come from the save), else the character list.
func resume() -> Dictionary:
	if sim != null and player_id >= 0 and not sim.players.has(player_id):
		player_id = -1 # the sim released it meanwhile (its fight ended)
	if playing():
		if not sim.resume.reattach(player_id):
			player_id = -1
	if not playing() and last_world != "":
		sim = _worlds.call(last_world)
		if sim != null and last_name != "" and CharacterRoster.can_select(sim, account, last_name) == "":
			player_id = sim.connect_player(last_name, "", account)
			sim.players[player_id].gm = gm
		elif sim != null:
			_outbox.append(CharacterRoster.characters_event(sim, account))
	return {"world": last_world, "name": last_name if playing() else "", "playing": playing(),
			"in_fight": playing() and sim.players[player_id].fight_id != 0}


## Logout: the character leaves the world (and is saved).
func close() -> void:
	if playing():
		sim.disconnect_player(player_id)
	player_id = -1
	sim = null


## An admin stopped the world this session plays in (S.04): the character leaves it, saved, and the
## client is told to pick a world again.
func world_closed() -> void:
	close()
	_outbox.append(Protocol.error(ProtocolCluster.E_WORLD_CLOSED, "", ""))
	last_name = ""
	last_world = ""


func _hello(cmd: Dictionary) -> void:
	close()
	var invalid := Protocol.validate(cmd, Protocol.C2S)
	if invalid != "":
		_error(cmd, Protocol.E_BAD_MESSAGE, invalid)
		return
	if int(cmd["v"]) != Protocol.VERSION:
		_error(cmd, Protocol.E_VERSION, "protocol %d, expected %d" % [int(cmd["v"]), Protocol.VERSION])
		return
	var world := str(cmd["world"])
	last_world = world
	last_name = ""
	sim = _worlds.call(world)
	if sim == null:
		_error(cmd, Protocol.E_UNKNOWN_WORLD, "unknown world " + world)
		return
	if account != "" and Sanctions.is_banned(sim.persistence, account): # A1.01
		sim = null
		_error(cmd, ProtocolAdmin.E_BANNED)
		return
	var name := str(cmd.get("name", ""))
	if name == "":
		_outbox.append(CharacterRoster.characters_event(sim, account))
		return
	var err := CharacterRoster.can_select(sim, account, name)
	if err != "" and CharacterRoster.find(sim, name) == "":
		err = CharacterRoster.create(sim, account, name)
	if err != "":
		_error(cmd, err)
		return
	player_id = sim.connect_player(name, str(cmd.get("look", "")), account)
	sim.players[player_id].gm = gm
	last_name = name


func _error(cmd: Dictionary, code: String, msg := "") -> void:
	var err := Protocol.error(code, msg, str(cmd.get("t", "")))
	if cmd.has("seq"):
		err["ref"] = int(cmd["seq"])
	_outbox.append(err)
