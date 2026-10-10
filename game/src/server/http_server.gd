## A small HTTP/1.1 server on TCPServer (roadmap C.02): persistent connections (keep-alive, one request
## after the other), files streamed by blocks of 512 KB. Written by hand because the game
## port speaks WebSocket (docs/ARCHITECTURE.md: two ports) and Godot has no HTTP server.
## It knows nothing about content or accounts: a `handler(request) -> Response` decides.
##
## Two ways to drive it:
##  - `poll()` from the owner's loop (tests, tools): everything runs in that call, on that thread;
##  - `start_thread()` (the game server): its own I/O thread serves the connections in a tight loop, so a
##    download never waits for the 30 FPS tick of the game and never slows it down. `handler` then runs on
##    that thread and must be thread-safe; the routes `main_routes(req)` accepts go to the owner's thread
##    instead (`main_handler`, run by `poll()`), because they touch the simulation.
class_name HttpServer
extends RefCounted

const MAX_HEAD_BYTES := 16 * 1024
const MAX_CONNECTIONS := 256
## after a request the I/O thread keeps polling this long before it sleeps: the next request of a download comes
## within a round trip, and a sleep would add its whole duration to that
const SPIN_USEC := 4000
## a connection that neither sends nor receives for this long is closed (a long download is not idle)
const IDLE_TIMEOUT_MS := 30000
## largest accepted request body (A1.02: the JSON of an admin action); a bigger one gets 413
const MAX_BODY_BYTES := 16 * 1024
const BLOCK := 512 * 1024
## blocks sent to one connection per pass (several connections share the thread)
const BLOCKS_PER_POLL := 8

const REASONS := {200: "OK", 206: "Partial Content", 400: "Bad Request", 401: "Unauthorized",
		404: "Not Found", 405: "Method Not Allowed", 409: "Conflict", 416: "Range Not Satisfiable",
		413: "Payload Too Large", 431: "Request Header Fields Too Large", 500: "Internal Server Error", 503: "Service Unavailable"}


class Request:
	var method := ""
	var path := ""
	## lower-case names
	var headers := {}
	var address := ""
	## the body of a POST (Content-Length bytes), empty otherwise
	var body := PackedByteArray()

	func header(name: String) -> String:
		return str(headers.get(name.to_lower(), ""))


class Response:
	var status := 200
	var headers := {}
	var body := PackedByteArray()
	## when set, the body is `file_length` bytes of this file from `file_offset` (streamed)
	var file_path := ""
	var file_offset := 0
	var file_length := 0

	static func text(code: int, message: String) -> Response:
		var r := Response.new()
		r.status = code
		r.headers["Content-Type"] = "text/plain; charset=utf-8"
		r.body = message.to_utf8_buffer()
		return r

	static func json(code: int, data: Variant) -> Response:
		var r := Response.new()
		r.status = code
		r.headers["Content-Type"] = "application/json"
		r.body = JSON.stringify(data).to_utf8_buffer()
		return r


## A request the owner's thread answers (thread mode)
class Job:
	var request: Request
	var response: Response


class Conn:
	var stream: StreamPeerTCP
	var address := ""
	var buf := PackedByteArray()
	## last time something moved on this connection
	var born_ms := 0
	var responded := false
	## the owner's thread is building the answer
	var job: Job
	var keep_alive := false
	var pending := PackedByteArray() # bytes read from the file, not yet sent
	var head_sent := false
	var head := PackedByteArray()
	var response: Response
	var file: FileAccess
	var remaining := 0


## Set by the owner: Callable(Request) -> Response.
var handler := Callable()
## thread mode: Callable(Request) -> bool, the routes that must run on the owner's thread, and the
## Callable(Request) -> Response that answers them (called from `poll`)
var main_routes := Callable()
var main_handler := Callable()
var connections: int:
	get:
		return _conns.size()

var _tcp := TCPServer.new()
var _conns: Array[Conn] = []
var _thread: Thread
var _quit := false
var _lock := Mutex.new()
var _jobs: Array[Job] = []


func listen(port: int, bind := "*") -> Error:
	return _tcp.listen(port, bind)


func local_port() -> int:
	return _tcp.get_local_port()


## Serves the connections on a thread of its own from now on; `poll()` then only answers `main_routes`.
func start_thread() -> void:
	if _thread != null:
		return
	_quit = false
	_thread = Thread.new()
	_thread.start(_run)


func is_threaded() -> bool:
	return _thread != null


func shutdown() -> void:
	if _thread != null:
		_quit = true
		_thread.wait_to_finish()
		_thread = null
	_tcp.stop()
	for c in _conns:
		_close(c)
	_conns.clear()


func _run() -> void:
	var last_move := Time.get_ticks_usec()
	while not _quit:
		if _pump():
			last_move = Time.get_ticks_usec()
		elif Time.get_ticks_usec() - last_move > SPIN_USEC:
			OS.delay_msec(1) # nothing for a while: sleep (Windows rounds a sleep up to ~1 to 15 ms, which is what the spin avoids)


## The owner's loop: without a thread it serves everything, with one it answers the routes kept for it.
func poll() -> void:
	if _thread == null:
		_pump()
		return
	_lock.lock()
	var jobs := _jobs
	_jobs = []
	_lock.unlock()
	for job in jobs:
		var r: Variant = main_handler.call(job.request) if main_handler.is_valid() else null
		job.response = r if r is Response else Response.text(500, "no response")


## One pass over the listening socket and every connection; true when something moved.
func _pump() -> bool:
	var moved := false
	while _tcp.is_connection_available():
		moved = true
		var stream := _tcp.take_connection()
		if _conns.size() >= MAX_CONNECTIONS:
			stream.disconnect_from_host()
			continue
		stream.set_no_delay(true)
		var c := Conn.new()
		c.stream = stream
		c.address = stream.get_connected_host()
		c.born_ms = Time.get_ticks_msec()
		_conns.append(c)
	for c in _conns.duplicate():
		if _step(c):
			moved = true
	return moved


func _step(c: Conn) -> bool:
	c.stream.poll()
	var status := c.stream.get_status()
	if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
		_drop(c)
		return true
	if status != StreamPeerTCP.STATUS_CONNECTED:
		return false
	var now := Time.get_ticks_msec()
	if now - c.born_ms > IDLE_TIMEOUT_MS:
		_drop(c)
		return true
	var moved := false
	if c.job != null:
		if c.job.response == null:
			return false
		_respond(c, c.job.response)
		c.job = null
		moved = true
	elif not c.responded:
		var n := c.stream.get_available_bytes()
		if n > 0:
			c.buf.append_array(c.stream.get_data(n)[1])
			c.born_ms = now
			moved = true
		var end := _head_end(c.buf)
		if end == -1:
			if c.buf.size() > MAX_HEAD_BYTES:
				_respond(c, Response.text(431, "headers too large"))
			return moved
		var head_text := c.buf.slice(0, end).get_string_from_utf8()
		var want := _body_length(head_text)
		if want > MAX_BODY_BYTES:
			_respond(c, Response.text(413, "body too large"))
		elif c.buf.size() < end + 4 + want:
			return moved # the body is still coming
		else:
			var body := c.buf.slice(end + 4, end + 4 + want)
			c.buf = c.buf.slice(end + 4 + want)
			var answer: Variant = _answer(c, head_text, body)
			if answer == null:
				return true # handed to the owner's thread: c.job is waiting
			_respond(c, answer)
		moved = true
	if c.responded and _send(c):
		moved = true
	return moved


## The answer to a request, or null when the owner's thread builds it (thread mode, `main_routes`).
func _answer(c: Conn, head_text: String, body := PackedByteArray()) -> Variant:
	var lines := head_text.split("\r\n")
	var first := lines[0].split(" ")
	if first.size() != 3 or not first[2].begins_with("HTTP/"):
		return Response.text(400, "bad request line")
	var req := Request.new()
	req.method = first[0]
	req.path = first[1]
	req.address = c.address
	req.body = body
	for i in range(1, lines.size()):
		var colon := lines[i].find(":")
		if colon > 0:
			req.headers[lines[i].substr(0, colon).strip_edges().to_lower()] = lines[i].substr(colon + 1).strip_edges()
	c.keep_alive = first[2] == "HTTP/1.1" and req.header("connection").to_lower() != "close"
	if not handler.is_valid():
		return Response.text(503, "no handler")
	if _thread != null and main_routes.is_valid() and main_routes.call(req):
		var job := Job.new()
		job.request = req
		c.job = job
		_lock.lock()
		_jobs.append(job)
		_lock.unlock()
		return null
	var r: Variant = handler.call(req)
	return r if r is Response else Response.text(500, "no response")


func _respond(c: Conn, r: Response) -> void:
	c.responded = true
	c.response = r
	var length := r.file_length if r.file_path != "" else r.body.size()
	var text := "HTTP/1.1 %d %s\r\n" % [r.status, REASONS.get(r.status, "Status")]
	var headers := r.headers.duplicate()
	headers["Content-Length"] = str(length)
	headers["Connection"] = "keep-alive" if c.keep_alive else "close"
	if not headers.has("Cache-Control"):
		headers["Cache-Control"] = "no-store" if not headers.has("ETag") else "private"
	for k: String in headers:
		text += "%s: %s\r\n" % [k, headers[k]]
	c.head = (text + "\r\n").to_utf8_buffer()
	if r.file_path != "":
		c.file = FileAccess.open(r.file_path, FileAccess.READ)
		if c.file == null:
			c.head = "HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".to_utf8_buffer()
			c.remaining = 0
			c.keep_alive = false
		else:
			c.file.seek(r.file_offset)
			c.remaining = length
	else:
		c.pending = r.body


## Sends what the sockets take; true when bytes left. An answer that is over either ends the connection
## or, with keep-alive, readies it for the next request.
func _send(c: Conn) -> bool:
	var moved := false
	for _i in BLOCKS_PER_POLL:
		if not c.head_sent:
			var sent := _put(c, c.head)
			c.head = c.head.slice(sent)
			moved = moved or sent > 0
			if not c.head.is_empty():
				return moved
			c.head_sent = true
		if c.pending.is_empty() and c.remaining > 0 and c.file != null:
			c.pending = c.file.get_buffer(mini(BLOCK, c.remaining))
			c.remaining -= c.pending.size()
			if c.pending.is_empty(): # the file got shorter: stop, the client sees a short body
				c.remaining = 0
				c.keep_alive = false
		if not c.pending.is_empty():
			var sent := _put(c, c.pending)
			c.pending = c.pending.slice(sent)
			moved = moved or sent > 0
			if not c.pending.is_empty():
				if sent > 0:
					c.born_ms = Time.get_ticks_msec()
				return moved
			c.born_ms = Time.get_ticks_msec()
		if c.pending.is_empty() and c.remaining <= 0:
			if c.keep_alive:
				_reset(c)
			else:
				_drop(c)
			return true
	return moved


## The answer is out: wait for the next request on the same connection.
func _reset(c: Conn) -> void:
	c.responded = false
	c.response = null
	c.head_sent = false
	c.head = PackedByteArray()
	c.pending = PackedByteArray()
	c.file = null
	c.remaining = 0
	c.born_ms = Time.get_ticks_msec()


## Sends what the socket takes; returns the number of bytes sent (a broken socket drops the connection).
func _put(c: Conn, data: PackedByteArray) -> int:
	if data.is_empty():
		return 0
	var r := c.stream.put_partial_data(data)
	if r[0] != OK:
		c.pending = PackedByteArray()
		c.remaining = 0
		c.head_sent = true
		c.head = PackedByteArray()
		c.keep_alive = false
		_drop(c)
		return data.size()
	return int(r[1])


func _drop(c: Conn) -> void:
	_close(c)
	_conns.erase(c)


func _close(c: Conn) -> void:
	c.file = null
	if c.stream != null:
		c.stream.disconnect_from_host()


static func _head_end(buf: PackedByteArray) -> int:
	for i in range(0, buf.size() - 3):
		if buf[i] == 13 and buf[i + 1] == 10 and buf[i + 2] == 13 and buf[i + 3] == 10:
			return i
	return -1


## The Content-Length of a request head, 0 when absent.
static func _body_length(head_text: String) -> int:
	for line in head_text.split("\r\n"):
		if line.to_lower().begins_with("content-length:"):
			return maxi(0, int(line.get_slice(":", 1).strip_edges()))
	return 0
