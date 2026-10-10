## The network host of the game (roadmap S.01): a LocalServer (one WorldSim per
## world) behind a WebSocket transport. One text frame = one Protocol message
## (JSON), one connection = one GameSession, exactly like LocalBackend does for
## a single local client. It adds no game rule: it accepts sockets, feeds
## commands to the sessions, ticks the server and sends what the sessions drain.
## Nothing here knows which game a world runs.
##
## Driven by `poll(delta)` once per frame: src/server/main.gd for the real
## server (godot --headless), the tests for a server in the same process.
## Not used by sim/, shared/ or client/ (tests/test_architecture.gd).
class_name ServerHost
extends RefCounted

## a client that has not completed the WebSocket handshake after this long is dropped
const HANDSHAKE_TIMEOUT_MS := 5000
## largest accepted frame; anything bigger closes the connection
const MAX_FRAME_BYTES := 64 * 1024
## Rate limits (S.05). APPROX(S.05): no source (nothing Dofus): a token bucket per connection
## (a burst of 60 messages, then 30 per second: a client sends a few per second), a client
## that keeps going after `MAX_STRIKES` refused messages is cut, 16 connections per address
## (friends behind one box), and login / register attempts per address (30 then one per 2 s: each
## one costs ~0.1 s of hashing).
const RATE_BURST := 60.0
const RATE_PER_SEC := 30.0
const MAX_STRIKES := 20
const MAX_PER_ADDRESS := 16
const AUTH_BURST := 30.0
const AUTH_PER_SEC := 0.5
const MAX_QUEUED_AUTH := 8
const COSTLY_BURST := 10.0
const COSTLY_PER_SEC := 2.0
## a kicked player's socket stays open this long so that its client reads the reason first
const KICK_GRACE_MS := 300

class Conn:
	var peer: WebSocketPeer
	var session: GameSession
	var address := ""
	var born_ms := 0
	var opened := false
	## the account logged in on this connection ("" before login_ok; unused without `auth`)
	var login := ""
	var failures := 0
	## last time (host clock, ms) a packet came in: a connection silent for `idle_ms` can be replaced
	var last_rx_ms := 0
	## `_drop` ran: its session may already belong to another connection
	var dropped := false
	## kicked by a GM (A1.01): the host time (ms) at which the socket closes, 0 = not kicked
	var kick_at_ms := 0
	var limiter: RateLimiter
	## bucket of the costly commands (chat, admin) of this session (S.05c)
	var costly: RateLimiter
	## the password hashing of a login / register in progress, off the main thread (S.05c)
	var job: AuthJob
	## login / register / resume messages that came while `job` was hashing: handled in order
	var queued: Array = []
	## messages refused for rate since the bucket was last full enough
	var strikes := 0


static var _id_re := RegEx.create_from_string("^[A-Za-z0-9_-]{1,64}$")

var server := LocalServer.new()
## accounts with the GM role (admin_cmd) besides those whose document says so
var gm_accounts := PackedStringArray()
## Accounts (S.02a). Set = a connection must `login` (or `register`) before hello, and the
## account is its login. Null = open host (tests, tools): the account is "ip-<address>".
var auth: AuthService
## A second connection of an account (login or resume) replaces the first when that one has
## been silent this long (S.02b). APPROX(S.02b): 20 s = two pings of NetBackend (every 10 s)
var idle_ms := 20000
## the host's clock in ms; replaceable in tests
var ticks := Callable(Time, "get_ticks_msec")
## empty = any world that exists; else only these
var allowed_worlds := PackedStringArray()
## true once the cluster pinned the list (a stopped world must not reopen by itself, even when the list is empty)
var pin_allowed := false
## the worlds of this server and their start / stop (S.04)
var cluster := WorldCluster.new()
## number of live connections, for logs and tests
var connections: int:
	get:
		return _conns.size()

## Content API (C.02) on its own HTTP port; null until `listen_http`.
var http: HttpServer
## audit file of the GM commands (A1.01), null = none (tests, tools)
var audit: AuditLog
var content: ContentApi
## the published content folder the content API serves (C.07, ContentStore; set before `listen_http`)
var package_dir := ""
## admin routes (A1.01b): disabled while `admin.token` is empty
var admin := AdminApi.new()

## Every connected character is saved this often (S.03), 0 = never. APPROX(S.03): 5 min
var autosave_ms := 300000
## characters saved by the last periodic save (logs, tests)
var last_autosave_count := 0
var autosaves := 0

var _next_autosave_ms := -1
## the limits above, settable (tests, a server that wants other values)
var rate_burst := RATE_BURST
var rate_per_sec := RATE_PER_SEC
var max_strikes := MAX_STRIKES
var max_per_address := MAX_PER_ADDRESS
var auth_burst := AUTH_BURST
var auth_per_sec := AUTH_PER_SEC
## costly commands (chat_send, admin_cmd) per session (S.05c). APPROX(S.05c): burst 10 then 2 per
## second, no source (the chat has its own anti-flood, shared/Chat; this one protects the host)
var costly_burst := COSTLY_BURST
var costly_per_sec := COSTLY_PER_SEC
## an address cut several times is banned for a while (S.05c)
var penalties := AddressPenalties.new()
var _auth_limits := {} # address -> RateLimiter of its login / register attempts
## refused (rate limit, address cap) since the start, for logs and tests
var refused_rate := 0
var refused_connections := 0
var _tcp := TCPServer.new()
var _conns: Array[Conn] = []
var _parked := {} # login -> GameSession of a dropped connection, waiting for a resume (S.02b)
var _acc_ms := 0.0
var _start_ms := Time.get_ticks_msec()


func _init() -> void:
	cluster.host = self


## The audit trail of the GM commands (A1.01) goes to this file, for every world.
func set_audit_log(log: AuditLog) -> void:
	audit = log
	server.audit_sink = log.append


## Starts listening (port 0 = any free port: see local_port). "*" = every interface.
func listen(port: int, bind := "*") -> Error:
	return _tcp.listen(port, bind)


func local_port() -> int:
	return _tcp.get_local_port()


## Starts the content API (C.02) on a second port (0 = any free port: see http_port). It
## answers only to sessions logged in through `auth`.
func listen_http(port: int, bind := "*", threaded := false) -> Error:
	http = HttpServer.new()
	content = ContentApi.new()
	content.store = package_dir
	content.auth = auth
	content.allowed_worlds = allowed_worlds
	admin.host = self
	cluster.sync_content()
	http.handler = _route
	http.main_routes = _needs_game_thread
	http.main_handler = _route
	var err := http.listen(port, bind)
	if err == OK and threaded:
		http.start_thread() # downloads never wait for the tick of the game, nor slow it down
	return err


## The routes that change the simulation (admin) run on the game thread; the content is static files.
func _needs_game_thread(req: HttpServer.Request) -> bool:
	return admin.handles(req.path.get_slice("?", 0))


## One handler for the HTTP port: /admin/* to the admin API, the rest to the content API.
func _route(req: HttpServer.Request) -> HttpServer.Response:
	return admin.handle(req) if admin.handles(req.path) else content.handle(req)


## world id -> players connected now (listed by the content API, which runs on its own thread).
func _players() -> Dictionary:
	var out := {}
	for id: String in server.worlds:
		out[id] = (server.worlds[id] as WorldSim).players.size()
	return out


func http_port() -> int:
	return http.local_port() if http != null else 0


## Loads the worlds up front (a bad id is found at startup, not at the first player).
## Returns the ids that do not exist.
func preload_worlds(ids: PackedStringArray) -> PackedStringArray:
	allowed_worlds = ids
	var missing := PackedStringArray()
	for id in ids:
		if server.world(id) == null:
			missing.append(id)
	return missing


func poll(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_accept()
	if http != null:
		content.sync_state(auth, allowed_worlds, pin_allowed, _players()) # the owner may set them after listen_http
		http.poll()
	for conn in _conns.duplicate():
		_read(conn)
	_finish_jobs()
	if auth != null:
		for key in auth.expire(ticks.call()): # a parked session nobody came for: logout
			(_parked[key] as GameSession).close()
			_parked.erase(key)
	_acc_ms += delta * 1000.0
	var step := int(_acc_ms)
	_acc_ms -= step
	server.tick(step)
	_autosave()
	for conn in _conns.duplicate():
		_write(conn)
	admin.metrics.record_tick(Time.get_ticks_usec() - t0)


## Answers the logins whose hashing is done (S.05c).
func _finish_jobs() -> void:
	for conn in _conns.duplicate():
		var job: AuthJob = conn.job
		if job == null or not job.is_done():
			continue
		job.finish()
		conn.job = null
		if conn.dropped or conn.peer.get_ready_state() != WebSocketPeer.STATE_OPEN or conn.login != "":
			continue
		_finish_login(conn, job)
		job.password = ""
		while not conn.queued.is_empty() and conn.login == "" and conn.job == null and not conn.dropped 				and conn.peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			var next: Dictionary = conn.queued.pop_front()
			_login(conn, next, str(next["t"])) # the next attempt (it may start another job)


func _autosave() -> void:
	if autosave_ms <= 0:
		return
	var now: int = ticks.call()
	if _next_autosave_ms < 0:
		_next_autosave_ms = now + autosave_ms
	elif now >= _next_autosave_ms:
		_next_autosave_ms = now + autosave_ms
		last_autosave_count = server.save_all()
		autosaves += 1


## Clean stop: every character leaves its world (and is saved), sockets close.
func shutdown() -> void:
	_tcp.stop()
	if http != null:
		http.shutdown()
	for conn in _conns:
		if conn.job != null:
			conn.job.finish()
			conn.job = null
		_release(conn)
		conn.peer.close(1001, "server stopping")
		conn.peer.poll()
	_conns.clear()
	for session: GameSession in _parked.values():
		session.close()
	_parked.clear()


func _accept() -> void:
	while _tcp.is_connection_available():
		var stream := _tcp.take_connection()
		var address := stream.get_connected_host()
		if penalties.is_banned(address, ticks.call()): # S.05c: cut too many times lately
			stream.disconnect_from_host()
			refused_connections += 1
			continue
		if _conns.filter(func(c: Conn) -> bool: return c.address == address).size() >= max_per_address:
			stream.disconnect_from_host() # too many connections from one address (S.05)
			refused_connections += 1
			continue
		var conn := Conn.new()
		conn.limiter = RateLimiter.new(rate_burst, rate_per_sec)
		conn.costly = RateLimiter.new(costly_burst, costly_per_sec)
		conn.peer = WebSocketPeer.new()
		conn.peer.inbound_buffer_size = MAX_FRAME_BYTES * 2
		conn.peer.outbound_buffer_size = 4 * 1024 * 1024
		conn.address = address
		conn.born_ms = ticks.call()
		conn.last_rx_ms = conn.born_ms
		# without `auth` the account is the player's address (APPROX(S.02a): two friends behind the
		# same address would share their characters); with it, the session is made at login_ok
		var account := "" if auth != null else "ip-" + conn.address
		conn.session = GameSession.new(account, _world)
		conn.session.gm = gm_accounts.has(account)
		if conn.peer.accept_stream(stream) != OK:
			continue
		_conns.append(conn)


func _world(id: String) -> WorldSim:
	if _id_re.search(id) == null: # an id comes from the network: never a path
		return null
	if (pin_allowed or not allowed_worlds.is_empty()) and not allowed_worlds.has(id):
		return null
	return server.world(id)


static func is_world_id(id: String) -> bool:
	return _id_re.search(id) != null


## Every session playing in `sim` (live connections and parked ones) leaves it, saved, and is told
## `world_closed`. Returns how many. Used when an admin stops a world (WorldCluster).
func close_world_sessions(sim: WorldSim) -> int:
	var n := 0
	for conn in _conns:
		if conn.session.sim == sim:
			conn.session.world_closed()
			n += 1
	for key: String in _parked.keys():
		var session: GameSession = _parked[key]
		if session.sim == sim:
			session.world_closed()
			n += 1
	return n


func _read(conn: Conn) -> void:
	if conn.kick_at_ms > 0:
		_finish_kick(conn)
		return
	conn.peer.poll()
	match conn.peer.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			if ticks.call() - conn.born_ms > HANDSHAKE_TIMEOUT_MS:
				_drop(conn)
		WebSocketPeer.STATE_OPEN:
			conn.opened = true
			while conn.peer.get_available_packet_count() > 0:
				var packet := conn.peer.get_packet()
				conn.last_rx_ms = ticks.call()
				if packet.size() > MAX_FRAME_BYTES:
					conn.peer.close(1009, "frame too big")
					break
				_receive(conn, packet.get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			_drop(conn)


func _receive(conn: Conn, text: String) -> void:
	if not _allow(conn):
		return
	var cmd: Variant = JSON.parse_string(text)
	if not cmd is Dictionary:
		_send(conn, Protocol.error(Protocol.E_BAD_MESSAGE, "not a JSON object", ""))
		return
	if str(cmd.get("t", "")) == Protocol.PING:
		if Protocol.validate(cmd, Protocol.C2S) == "":
			# server_ms is the clock movements are timed on: the player's world, else uptime
			var sim := conn.session.sim
			_send(conn, Protocol.pong(int(cmd["t0"]), sim.now if sim != null else Time.get_ticks_msec() - _start_ms))
		return
	if auth != null:
		var type := str(cmd.get("t", ""))
		if type == Protocol.REGISTER or type == Protocol.LOGIN:
			_login(conn, cmd, type)
			return
		if type == ProtocolResume.RESUME:
			_resume(conn, cmd)
			return
		if conn.login == "":
			_send(conn, Protocol.error(Protocol.E_NOT_LOGGED_IN, "login first", type))
			return
	if str(cmd.get("t", "")) == ProtocolCluster.SERVER_LIST:
		_send(conn, ProtocolCluster.servers(cluster.list()))
		return
	var kind := str(cmd.get("t", ""))
	if (kind == Protocol.CHAT_SEND or kind == Protocol.ADMIN_CMD) and not conn.costly.take(ticks.call()):
		refused_rate += 1 # S.05c: a costly command too often: refused, the connection stays
		_send(conn, Protocol.error(ProtocolSecurity.E_RATE_LIMITED, "too many " + kind, kind))
		return
	conn.session.handle(cmd)


## Spends one token of the connection's bucket. Empty = the message is dropped with
## error{rate_limited}; a client that goes on is cut.
func _allow(conn: Conn) -> bool:
	if conn.limiter.take(ticks.call()):
		if conn.strikes > 0 and conn.limiter.tokens() > rate_burst / 2.0:
			conn.strikes = 0
		return true
	refused_rate += 1
	conn.strikes += 1
	if conn.strikes == 1 or conn.strikes >= max_strikes:
		_send(conn, Protocol.error(ProtocolSecurity.E_RATE_LIMITED, "too many messages", ""))
	if conn.strikes >= max_strikes and conn.peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		conn.peer.close(1008, "rate limit")
		penalties.cut(conn.address, ticks.call())
	return false


## One login / register / resume attempt of this address (hashing is expensive).
func _auth_allowed(conn: Conn) -> bool:
	var limiter: RateLimiter = _auth_limits.get(conn.address)
	if limiter == null:
		limiter = RateLimiter.new(auth_burst, auth_per_sec)
		_auth_limits[conn.address] = limiter
	if _auth_limits.size() > 4096: # forget idle addresses
		_auth_limits = {conn.address: limiter}
	return limiter.take(ticks.call())


## register / login: answers login_ok or login_error, and makes the connection's session.
func _login(conn: Conn, cmd: Dictionary, type: String) -> void:
	if Protocol.validate(cmd, Protocol.C2S) != "":
		_send(conn, Protocol.login_error(Protocol.E_BAD_MESSAGE, type))
		return
	if conn.login != "": # one account per connection: log out (close) to change
		_send(conn, Protocol.login_error(Protocol.E_ALREADY_CONNECTED, type))
		return
	if conn.job != null: # the previous attempt of this connection is still being hashed: wait for it
		if conn.queued.size() >= MAX_QUEUED_AUTH:
			_send(conn, Protocol.login_error(Protocol.E_TOO_MANY_ATTEMPTS, type))
		else:
			conn.queued.append(cmd)
		return
	if not _auth_allowed(conn):
		_send(conn, Protocol.login_error(Protocol.E_TOO_MANY_ATTEMPTS, type))
		return
	var job := AuthJob.new()
	job.type = type
	job.login = str(cmd["login"])
	job.password = str(cmd["password"])
	job.iterations = auth.accounts.iterations
	if type == Protocol.REGISTER:
		var err := auth.accounts.register_precheck(job.login, job.password)
		if err != "": # refused without hashing
			_refuse(conn, err, type)
			return
	else:
		job.record = auth.accounts.credentials(job.login).duplicate(true)
	conn.job = job
	job.start() # the hashing (~0.1 s) runs in a thread; `_finish_jobs` answers when it is done


## The hashing of a login / register is done: the rest of the login, on the main thread.
func _finish_login(conn: Conn, job: AuthJob) -> void:
	var type := job.type
	var r: AuthService.Result
	if type == Protocol.REGISTER:
		r = auth.register(job.login, job.password, job.prepared)
	else:
		r = auth.login_checked(job.login, job.ok)
		if not r.ok and r.code == Protocol.E_ALREADY_CONNECTED and _evict_idle(AccountStore.normalize(job.login)): # the password was right
			r = auth.login_checked(job.login, job.ok)
	if not r.ok:
		_refuse(conn, r.code, type)
		return
	conn.login = r.login
	auth.accounts.note_seen(r.login, conn.address)
	if gm_accounts.has(r.login): # the role announced to the client is the one the session really has
		r.role = AccountStore.ROLE_GM
	var parked := _parked.has(r.login)
	conn.session = _take_session(r)
	_send(conn, Protocol.login_ok(r.token, r.role, r.login))
	if parked: # the password gave the dropped session back: the client is brought up to date as for a resume
		_send(conn, ProtocolResume.resume_ok(r.token, r.role, r.login, conn.session.resume()))


## resume{token}: takes over the session a dropped connection left (S.02b): resume_ok, then the
## events of the current state.
func _resume(conn: Conn, cmd: Dictionary) -> void:
	if Protocol.validate(cmd, Protocol.C2S) != "":
		_send(conn, Protocol.login_error(Protocol.E_BAD_MESSAGE, ProtocolResume.RESUME))
		return
	if conn.login != "":
		_send(conn, Protocol.login_error(Protocol.E_ALREADY_CONNECTED, ProtocolResume.RESUME))
		return
	if not _auth_allowed(conn):
		_send(conn, Protocol.login_error(Protocol.E_TOO_MANY_ATTEMPTS, ProtocolResume.RESUME))
		return
	var token := str(cmd["token"])
	var r := auth.resume(token)
	if not r.ok and r.code == Protocol.E_ALREADY_CONNECTED and _evict_idle(auth.login_for_token(token)):
		r = auth.resume(token)
	if not r.ok:
		_refuse(conn, r.code, ProtocolResume.RESUME)
		return
	conn.login = r.login
	auth.accounts.note_seen(r.login, conn.address)
	if gm_accounts.has(r.login):
		r.role = AccountStore.ROLE_GM
	conn.session = _take_session(r)
	var state := conn.session.resume()
	_send(conn, ProtocolResume.resume_ok(r.token, r.role, r.login, state))


## The session of a connection that just logged in: the one a dropped connection left, else new.
func _take_session(r: AuthService.Result) -> GameSession:
	var session: GameSession = _parked.get(r.login)
	_parked.erase(r.login)
	if session == null:
		session = GameSession.new(r.login, _world)
	session.gm = r.role == AccountStore.ROLE_GM or gm_accounts.has(r.login)
	return session


## A refused login / resume: the error, and the connection is cut after too many bad guesses.
func _refuse(conn: Conn, code: String, type: String) -> void:
	_send(conn, Protocol.login_error(code, type))
	if code == Protocol.E_BAD_CREDENTIALS or code == ProtocolResume.E_BAD_TOKEN:
		conn.failures += 1
		if conn.failures >= AuthService.MAX_FAILURES:
			_send(conn, Protocol.login_error(Protocol.E_TOO_MANY_ATTEMPTS, type))
			conn.peer.close(1008, "too many attempts")
			penalties.cut(conn.address, ticks.call())


## The live connection of `login` is dropped (its session is parked) if it has been silent for
## `idle_ms`: the owner of the token or password is back and the old connection is dead.
func _evict_idle(login_name: String) -> bool:
	for old in _conns:
		if old.login == login_name and ticks.call() - old.last_rx_ms >= idle_ms:
			old.peer.close(4001, "replaced by a new connection")
			old.peer.poll()
			_drop(old)
			return true
	return false


## The socket of a player a GM kicked or banned (its session already ended, nothing parked): it
## closes once the grace time let the client read the reason.
func _finish_kick(conn: Conn) -> void:
	conn.peer.poll()
	if conn.peer.get_ready_state() == WebSocketPeer.STATE_OPEN and ticks.call() < conn.kick_at_ms:
		return
	if conn.peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		conn.peer.close(4003, "removed by a game master")
		conn.peer.poll()
	_conns.erase(conn)


func _release(conn: Conn) -> void:
	conn.session.close()
	if auth != null and conn.login != "":
		auth.release(conn.login)
		conn.login = ""


func _write(conn: Conn) -> void:
	if conn.peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	for ev: Dictionary in conn.session.drain():
		_send(conn, ev)
	if conn.session.kicked: # a GM threw the player out (A1.01): logout, no parked session
		conn.session.kicked = false
		conn.dropped = true
		conn.kick_at_ms = ticks.call() + KICK_GRACE_MS
		_release(conn)


func _send(conn: Conn, msg: Dictionary) -> void:
	if conn.peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		conn.peer.send_text(JSON.stringify(msg))


## The connection is gone. Closed on purpose (code 1000, NetBackend.close) = logout. Cut or
## evicted = the session is parked (S.02b): a character in a fight stays in it, absent, and the
## token stays valid for AuthService.park_ttl_ms.
func _drop(conn: Conn) -> void:
	if conn.dropped:
		return
	conn.dropped = true
	if conn.job != null: # a thread still hashes for this connection: wait for it, drop the answer
		conn.job.finish()
		conn.job = null
	if auth != null and conn.login != "" and conn.peer.get_close_code() != 1000:
		conn.session.detach()
		auth.park(conn.login, ticks.call())
		_parked[conn.login] = conn.session
		conn.login = ""
	else:
		_release(conn)
	_conns.erase(conn)
