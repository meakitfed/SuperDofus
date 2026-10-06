## Standalone mode: the whole game (WorldSim) runs inside the client process.
## It behaves like a network backend on purpose: commands are applied on the
## next poll and events arrive through the same signal, so client code written
## against it works unchanged with a remote server.
## serialize_messages (on by default) JSON-roundtrips every message, like a
## real network hop: anything non-serializable fails here, not in production.
##
## The game is hosted by a LocalServer. By default each backend creates its own
## (from seed / sources / persistence / clock below) and ticks it; set `server`
## to share one between several backends (multiplayer tests, bots): whoever
## created it then calls server.tick().
class_name LocalBackend
extends GameBackend

var serialize_messages := true
## checks every event against Protocol.SCHEMA (a sim bug fails the tests here)
var validate_events := true
## schema violations seen by any LocalBackend (tests assert it stays empty)
static var schema_errors: PackedStringArray = []
var seed := 1
## world id -> WorldSource override (tests, generated worlds); default: worlds/<id>
var sources := {}
## where characters are saved: memory by default, FilePersistence for the real game
var persistence := Persistence.new()
var clock := Clock.new()
## account this connection plays as (standalone: one local account)
var account := "local"
## standalone: the local player is a game master (admin_cmd: tp…)
var gm := true
var server: LocalServer
## the connection (character selection, then the character in its world)
var session: GameSession
## the world being played, null while choosing a character
var sim: WorldSim:
	get:
		return session.sim if session != null and session.playing() else null
var player_id: int:
	get:
		return session.player_id if session != null else -1

var _owns_server := false
var _commands: Array = []
var _acc_ms := 0.0


func send(cmd: Dictionary) -> void:
	_commands.append(_wire(_stamp(cmd)))


func poll(delta: float) -> void:
	for cmd: Dictionary in _commands:
		_apply(cmd)
	_commands.clear()
	if _owns_server:
		_acc_ms += delta * 1000.0
		var step := int(_acc_ms)
		_acc_ms -= step
		server.tick(step)
	_flush()


func time_ms() -> int:
	return session.sim.now if session != null and session.sim != null else 0


func close() -> void:
	if session != null:
		session.close()


func _apply(cmd: Dictionary) -> void:
	if server == null:
		server = LocalServer.new()
		server.seed = seed
		server.sources = sources
		server.persistence = persistence
		server.clock = clock
		_owns_server = true
	if session == null:
		session = GameSession.new(account, server.world)
		session.gm = gm
	session.handle(cmd)


func _flush() -> void:
	if session == null:
		return
	for ev: Dictionary in session.drain():
		if validate_events:
			var invalid := Protocol.validate(ev, Protocol.S2C)
			if invalid != "":
				schema_errors.append(invalid)
				push_error("LocalBackend: event does not match Protocol.SCHEMA: " + invalid)
		event.emit(_wire(ev))


func _wire(msg: Dictionary) -> Dictionary:
	if not serialize_messages:
		return msg
	assert(Protocol.is_json_safe(msg), "message is not JSON-safe: %s" % [msg])
	return Protocol.roundtrip(msg)
