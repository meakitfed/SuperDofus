## The client side of a game server (roadmap S.01): GameBackend over a WebSocket,
## one JSON text frame per Protocol message. The client cannot tell it from
## LocalBackend. Network trouble never throws: a refused, lost or timed-out
## connection becomes one `error{code: network}` event, and `state` says where
## the connection is (connecting, open, closed).
##
## Clock: time_ms() is the server's game clock (the `t0` of movements), estimated
## with ping / pong: each sample gives offset = server_ms + rtt / 2 - local time;
## the offset is the median of the last SAMPLES, measured again every
## PING_EVERY_MS and after every `hello` (the clock is the one of the chosen world).
##
## Automatic reconnection (S.02c), opt-in with `auto_reconnect`: once an account is logged in
## (token known), a cut (not close(), not a removal by the server) does not end the backend. State
## becomes "reconnecting", an event `net_reconnecting{attempt, delay_ms}` says when the next try
## comes (RETRY_MS: 1, 2, 4, 8 s, then every 8 s), each try opens a new socket and sends
## `resume{token}` first. `resume_ok` ends it (the server then replays the state); a refused token
## (bad_token...) ends the backend with `failure` = the code and the login_error event; the commands
## sent meanwhile are dropped (the server replays the current state, nothing is queued).
class_name NetBackend
extends GameBackend

const SAMPLES := 5
const PING_EVERY_MS := 10000
const CONNECT_TIMEOUT_MS := 8000
const DEFAULT_PORT := 7777
const RETRY_MS := [1000, 2000, 4000, 8000]
## close codes after which the server does not want the client back (replaced by another
## connection, removed by a game master)
const NO_RETRY_CODES := [4001, 4003]

## "connecting" | "open" | "closed" | "reconnecting" (between two tries of a reconnection)
var state := "closed"
## reconnect by itself after a cut (S.02c)
var auto_reconnect := false
## true from the cut until resume_ok (or the end of the backend); attempt = tries made so far
var reconnecting := false
var attempt := 0
## checks every event against Protocol.SCHEMA; violations are listed here (tests)
var validate_events := false
var schema_errors: PackedStringArray = []
## why the connection ended, "" while it lives or after close()
var failure := ""
## the session token and role of the account, from login_ok ("" before)
var token := ""
var role := ""
## local monotonic clock in ms; replaceable in tests
var ticks := Callable(Time, "get_ticks_msec")

var _ws := WebSocketPeer.new()
var _address := ""
var _out: Array = []
var _events: Array = []
var _started_ms := 0
var _was_open := false
var _closing := false
var _offsets: Array[int] = []
var _rtt := -1
var _epoch_ms := 0
var _next_ping_ms := 0
var _last_time := 0
var _retry_at_ms := 0


## "host", "host:port" or "ws://host:port": starts connecting, never blocks.
func connect_to(address: String) -> void:
	_address = address.strip_edges()
	var url := _address
	if not url.contains("://"):
		url = "ws://" + url
	if not _host_part(url).contains(":"):
		url += ":%d" % DEFAULT_PORT
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 4 * 1024 * 1024
	failure = ""
	_closing = false
	_was_open = false
	_started_ms = ticks.call()
	var err := _ws.connect_to_url(url)
	if err != OK:
		_fail("bad address %s (%s)" % [_address, error_string(err)])
		return
	state = "connecting"


func send(cmd: Dictionary) -> void:
	if state == "closed" or (reconnecting and str(cmd.get("t", "")) != ProtocolResume.RESUME):
		return
	var msg := _stamp(cmd)
	if str(msg.get("t", "")) == Protocol.HELLO:
		_restart_clock() # the clock to follow is the one of the world this hello chooses
	_out.append(msg)
	if str(msg.get("t", "")) == Protocol.HELLO:
		_queue_pings(3)


func poll(_delta: float) -> void:
	if state == "reconnecting":
		if ticks.call() >= _retry_at_ms:
			_try_again()
		_emit_events()
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			if ticks.call() - _started_ms > CONNECT_TIMEOUT_MS:
				_fail("no answer from %s" % _address)
		WebSocketPeer.STATE_OPEN:
			if not _was_open:
				_was_open = true
				state = "open"
				_next_ping_ms = ticks.call() + PING_EVERY_MS
				if reconnecting:
					_out.push_front(ProtocolResume.resume(token)) # first on the new connection
				_queue_pings(3)
			_flush_out()
			if ticks.call() >= _next_ping_ms:
				_next_ping_ms = ticks.call() + PING_EVERY_MS
				_queue_pings(1)
			while _ws.get_available_packet_count() > 0:
				_receive(_ws.get_packet().get_string_from_utf8())
		WebSocketPeer.STATE_CLOSING, WebSocketPeer.STATE_CLOSED:
			while _ws.get_available_packet_count() > 0: # what the server sent before closing (a kick's reason)
				_receive(_ws.get_packet().get_string_from_utf8())
			if _ws.get_ready_state() == WebSocketPeer.STATE_CLOSED and state != "closed" and not _closing:
				_fail("connection %s (%s)" % ["lost" if _was_open else "refused by " + _address,
						_ws.get_close_reason() if _ws.get_close_reason() != "" else "code %d" % _ws.get_close_code()])
	_emit_events()


func _emit_events() -> void:
	var events := _events
	_events = []
	for ev: Dictionary in events:
		event.emit(ev)


## The server's game clock, in ms. 0 until the first pong.
func time_ms() -> int:
	if _offsets.is_empty():
		return 0
	_last_time = maxi(_last_time, int(ticks.call()) + _median())
	return _last_time


## Round-trip time of the last pong in ms, -1 before any.
func rtt_ms() -> int:
	return _rtt


func close() -> void:
	_closing = true
	state = "closed"
	failure = ""
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.close(1000, "bye")
		_ws.poll()
	elif _ws.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		_ws.close()


func _receive(text: String) -> void:
	var ev: Variant = JSON.parse_string(text)
	if not ev is Dictionary:
		return
	if str(ev.get("t", "")) == Protocol.PONG:
		_on_pong(ev)
		return
	if str(ev.get("t", "")) == Protocol.LOGIN_OK or str(ev.get("t", "")) == ProtocolResume.RESUME_OK:
		token = str(ev.get("token", ""))
		role = str(ev.get("role", ""))
	if str(ev.get("t", "")) == ProtocolResume.RESUME_OK:
		reconnecting = false
		attempt = 0
	if reconnecting and str(ev.get("t", "")) == Protocol.LOGIN_ERROR:
		if str(ev.get("code", "")) == Protocol.E_ALREADY_CONNECTED: # the old connection is not seen as dead yet: later
			_lose("session still held by the old connection")
			return
		reconnecting = false # bad_token...: the session is gone, the player logs in again
		failure = str(ev.get("code", ""))
		token = ""
		state = "closed"
		_ws.close(1000, "session refused")
	if validate_events:
		var invalid := Protocol.validate(ev, Protocol.S2C)
		if invalid != "":
			schema_errors.append(invalid)
	_events.append(ev)


func _on_pong(pong: Dictionary) -> void:
	var sent := int(pong["t0"])
	if sent < _epoch_ms: # answers a ping sent before the last hello: another world's clock
		return
	var now: int = ticks.call()
	_rtt = now - sent
	var offset := int(pong["server_ms"]) + _rtt / 2 - now
	_offsets.append(offset)
	if _offsets.size() > SAMPLES:
		_offsets.pop_front()


func _median() -> int:
	var sorted := _offsets.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


func _restart_clock() -> void:
	_offsets.clear()
	_last_time = 0
	_epoch_ms = ticks.call()
	_next_ping_ms = _epoch_ms + PING_EVERY_MS


## Pings are numbered when they leave (t0 = local clock then), not when queued.
func _queue_pings(count: int) -> void:
	for i in count:
		_out.append({"t": Protocol.PING, "t0": -1})


func _flush_out() -> void:
	for msg: Dictionary in _out:
		if str(msg["t"]) == Protocol.PING:
			msg["t0"] = ticks.call()
		_ws.send_text(JSON.stringify(msg))
	_out.clear()


## A connection that was logged in is cut: wait, then try again (S.02c).
func _lose(reason: String) -> void:
	_out.clear()
	_ws.close(4000, "connection lost") # never 1000: the server keeps the session for the resume
	reconnecting = true
	attempt += 1
	var delay: int = RETRY_MS[mini(attempt - 1, RETRY_MS.size() - 1)]
	_retry_at_ms = ticks.call() + delay
	state = "reconnecting"
	failure = ""
	_events.append({"t": ProtocolResume.NET_RECONNECTING, "attempt": attempt, "delay_ms": delay, "reason": reason})


## The wait is over: a new socket; `resume{token}` leaves first once it is open.
func _try_again() -> void:
	reconnecting = true
	connect_to(_address)


func _fail(reason: String) -> void:
	if auto_reconnect and token != "" and not _closing and not NO_RETRY_CODES.has(_ws.get_close_code()):
		_lose(reason)
		return
	reconnecting = false
	failure = reason
	state = "closed"
	_out.clear()
	_ws.close(4000, "connection failed") # not 1000: the server keeps the session for a resume (S.02b)
	_events.append(Protocol.error(Protocol.E_NETWORK, reason, ""))


static func _host_part(url: String) -> String:
	var rest := url.get_slice("://", 1)
	return rest.get_slice("/", 0)
