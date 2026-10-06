## A small HTTP/1.1 server on TCPServer (roadmap C.02): `Connection: close`, one
## response per connection, files streamed by blocks of 1 MB. Written by hand because the game
## port speaks WebSocket (docs/ARCHITECTURE.md: two ports) and Godot has no HTTP server.
## It knows nothing about content or accounts: a `handler(request) -> Response` decides.
## Driven by `poll()` from ServerHost, like the game port.
class_name HttpServer
extends RefCounted

const MAX_HEAD_BYTES := 16 * 1024
const MAX_CONNECTIONS := 64
const IDLE_TIMEOUT_MS := 15000
## largest accepted request body (A1.02: the JSON of an admin action); a bigger one gets 413
const MAX_BODY_BYTES := 16 * 1024
const BLOCK := 1024 * 1024
## blocks sent to one connection per poll (the tick stays short)
const BLOCKS_PER_POLL := 4

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


class Conn:
	var stream: StreamPeerTCP
	var address := ""
	var buf := PackedByteArray()
	var born_ms := 0
	var responded := false
	var pending := PackedByteArray() # bytes read from the file, not yet sent
	var head_sent := false
	var head := PackedByteArray()
	var response: Response
	var file: FileAccess
	var remaining := 0


## Set by the owner: Callable(Request) -> Response.
var handler := Callable()
var connections: int:
	get:
		return _conns.size()

var _tcp := TCPServer.new()
var _conns: Array[Conn] = []


func listen(port: int, bind := "*") -> Error:
	return _tcp.listen(port, bind)


func local_port() -> int:
	return _tcp.get_local_port()


func shutdown() -> void:
	_tcp.stop()
	for c in _conns:
		_close(c)
	_conns.clear()


func poll() -> void:
	while _tcp.is_connection_available():
		var stream := _tcp.take_connection()
		if _conns.size() >= MAX_CONNECTIONS:
			stream.disconnect_from_host()
			continue
		var c := Conn.new()
		c.stream = stream
		c.address = stream.get_connected_host()
		c.born_ms = Time.get_ticks_msec()
		_conns.append(c)
	for c in _conns.duplicate():
		_step(c)


func _step(c: Conn) -> void:
	c.stream.poll()
	var status := c.stream.get_status()
	if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
		_drop(c)
		return
	if status != StreamPeerTCP.STATUS_CONNECTED:
		return
	if Time.get_ticks_msec() - c.born_ms > IDLE_TIMEOUT_MS:
		_drop(c)
		return
	if not c.responded:
		var n := c.stream.get_available_bytes()
		if n > 0:
			c.buf.append_array(c.stream.get_data(n)[1])
		var end := _head_end(c.buf)
		if end == -1:
			if c.buf.size() > MAX_HEAD_BYTES:
				_respond(c, Response.text(431, "headers too large"))
			return
		var head_text := c.buf.slice(0, end).get_string_from_utf8()
		var want := _body_length(head_text)
		if want > MAX_BODY_BYTES:
			_respond(c, Response.text(413, "body too large"))
		elif c.buf.size() < end + 4 + want:
			return # the body is still coming
		else:
			_respond(c, _answer(c, head_text, c.buf.slice(end + 4, end + 4 + want)))
	if c.responded:
		_send(c)


func _answer(c: Conn, head_text: String, body := PackedByteArray()) -> Response:
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
	if not handler.is_valid():
		return Response.text(503, "no handler")
	var r: Variant = handler.call(req)
	return r if r is Response else Response.text(500, "no response")


func _respond(c: Conn, r: Response) -> void:
	c.responded = true
	c.response = r
	var length := r.file_length if r.file_path != "" else r.body.size()
	var text := "HTTP/1.1 %d %s\r\n" % [r.status, REASONS.get(r.status, "Status")]
	var headers := r.headers.duplicate()
	headers["Content-Length"] = str(length)
	headers["Connection"] = "close"
	headers["Cache-Control"] = "no-store" if not headers.has("ETag") else "private"
	for k: String in headers:
		text += "%s: %s\r\n" % [k, headers[k]]
	c.head = (text + "\r\n").to_utf8_buffer()
	if r.file_path != "":
		c.file = FileAccess.open(r.file_path, FileAccess.READ)
		if c.file == null:
			c.head = "HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".to_utf8_buffer()
			c.remaining = 0
		else:
			c.file.seek(r.file_offset)
			c.remaining = length
	else:
		c.pending = r.body


func _send(c: Conn) -> void:
	for _i in BLOCKS_PER_POLL:
		if not c.head_sent:
			var sent := _put(c, c.head)
			c.head = c.head.slice(sent)
			if not c.head.is_empty():
				return
			c.head_sent = true
		if c.pending.is_empty() and c.remaining > 0 and c.file != null:
			c.pending = c.file.get_buffer(mini(BLOCK, c.remaining))
			c.remaining -= c.pending.size()
			if c.pending.is_empty(): # the file got shorter: stop, the client sees a short body
				c.remaining = 0
		if not c.pending.is_empty():
			var sent := _put(c, c.pending)
			c.pending = c.pending.slice(sent)
			if not c.pending.is_empty():
				return
		if c.pending.is_empty() and c.remaining <= 0:
			_drop(c)
			return


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
	for line in head_text.split("
"):
		if line.to_lower().begins_with("content-length:"):
			return maxi(0, int(line.get_slice(":", 1).strip_edges()))
	return 0
