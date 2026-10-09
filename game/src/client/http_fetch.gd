## One non-blocking HTTP GET (roadmap C.02), polled by its owner: `poll()` until it returns true,
## then read `status`, `headers` (lower-case names), `body` (unless a `sink` took the bytes) and
## `error` ("" = the whole body arrived). No screen, no scene: ContentClient, the loading screen
## (C.03) and the tests drive it. A body shorter than Content-Length is an error (cut connection).
class_name HttpFetch
extends RefCounted

const IDLE_TIMEOUT_MS := 15000

var status := 0
var headers := {}
var body := PackedByteArray()
var error := ""
var done := false
var received := 0
## chunks (of the HTTPClient read size, 64 KB) read per poll: a screen test slows a download down
var max_chunks := 64

var _http := HTTPClient.new()
## false when the connection belongs to a pool (`use_link`): it stays open after a complete answer
var _owned := true
## true once the answer is complete and the connection can serve another request
var reusable := false
var _host := ""
var _port := 0
var _path := ""
var _request_headers: PackedStringArray = []
var _sink := Callable()
var _sent := false
var _method := HTTPClient.METHOD_GET
var _body := ""
var _last_ms := 0


## Runs on a connection that outlives this request (keep-alive pool): call before `start`. A connection
## that is still open skips the connect; `reusable` tells afterwards whether it can serve another request.
func use_link(link: HTTPClient) -> void:
	_http = link
	_owned = false


## `sink` (optional): Callable(chunk: PackedByteArray), called for each piece of a 2xx body; the
## body is then not kept in memory. A non-2xx body is always kept (it is the error text).
func start(host: String, port: int, path: String, request_headers := {}, sink := Callable()) -> void:
	_host = host
	_port = port
	_path = path
	_sink = sink
	for k: String in request_headers:
		_request_headers.append("%s: %s" % [k, request_headers[k]])
	_last_ms = Time.get_ticks_msec()
	if not _owned and _http.get_status() == HTTPClient.STATUS_CONNECTED:
		return # a pooled connection still open: the request goes out on the next poll
	_http.read_chunk_size = 256 * 1024
	var err := _http.connect_to_host(host, port)
	if err != OK:
		_finish("cannot connect to %s:%d (%s)" % [host, port, error_string(err)])


## A POST with a text body (the admin web, A1.02), instead of `start`'s GET.
func start_post(host: String, port: int, path: String, text: String, request_headers := {}) -> void:
	_method = HTTPClient.METHOD_POST
	_body = text
	start(host, port, path, request_headers)


func poll() -> bool:
	if done:
		return true
	if Time.get_ticks_msec() - _last_ms > IDLE_TIMEOUT_MS:
		_finish("timeout")
		return true
	var err := _http.poll()
	if err != OK:
		# the server closes the connection after the body (Connection: close): once the head was
		# read, a cut is told by the Content-Length check, not by this error
		if status != 0:
			_complete()
		else:
			_finish("network error (%s)" % error_string(err))
		return true
	if status == 0 and _http.has_response():
		_read_head()
	match _http.get_status():
		HTTPClient.STATUS_CONNECTED:
			if not _sent:
				_sent = true
				var e := _http.request(_method, _path, _request_headers, _body)
				if e != OK:
					_finish("request failed (%s)" % error_string(e))
			elif status != 0: # response fully read
				_complete()
		HTTPClient.STATUS_BODY:
			_read_body()
		HTTPClient.STATUS_DISCONNECTED:
			if _sent and status != 0:
				_complete()
			else:
				_finish("connection closed")
		HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_CONNECTION_ERROR, \
		HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
			_finish("cannot reach %s:%d" % [_host, _port])
	return done


## Ends the request now (the owner gave up): `error` = "cancelled".
func abort() -> void:
	if not done:
		_finish("cancelled")


func content_length() -> int:
	return int(headers.get("content-length", -1))


func _read_head() -> void:
	status = _http.get_response_code()
	var raw := _http.get_response_headers_as_dictionary()
	for k: String in raw:
		headers[k.to_lower()] = raw[k]


func _read_body() -> void:
	if status == 0:
		_read_head()
	for _i in max_chunks:
		if _http.get_status() != HTTPClient.STATUS_BODY: # the last chunk ended the body
			break
		var chunk := _http.read_response_body_chunk()
		if chunk.is_empty():
			break
		_last_ms = Time.get_ticks_msec()
		received += chunk.size()
		if _sink.is_valid() and status >= 200 and status < 300:
			_sink.call(chunk)
		else:
			body.append_array(chunk)


func _complete() -> void:
	var expected := content_length()
	if expected >= 0 and received != expected:
		_finish("body cut: %d of %d bytes" % [received, expected])
	else:
		_finish("")


func _finish(message: String) -> void:
	error = message
	done = true
	var keeps_open := str(headers.get("connection", "")).to_lower() != "close"
	reusable = not _owned and message == "" and keeps_open and _http.get_status() == HTTPClient.STATUS_CONNECTED
	if not reusable:
		_http.close()
