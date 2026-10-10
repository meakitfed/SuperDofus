## Downloads byte ranges of content bundles over a few persistent HTTP connections (roadmap C.07), the way
## a game launcher patches: each request is one span of one bundle (ContentRelease.plan_ranges) that holds
## several files side by side; the stream is cut into files as it arrives, each file is checked against its
## SHA-256 and written by a worker thread (the download loop never waits for the disk), and reported done
## once on disk. A cut request is asked again from its first unfinished file: nothing is fetched twice.
##
## No thread, no scene: `fetch_all` is a loop the caller runs (the loading screen in a thread, the tests
## with `pump`).
class_name RangeDownloader
extends RefCounted

## requests in flight
const PARALLEL := 8
## failures (cut connection, short answer) tolerated per range before giving up
const RETRIES := 3
## checked files waiting for their write (each is held in memory: this bounds it)
const MAX_WRITES := 64
## idle polls in a row before the loop sleeps (a sleep costs a millisecond or more)
const SPINS_BEFORE_SLEEP := 60

var host := ""
var port := 0
var headers := {}
## Callable(), called while waiting for the network (default: a short sleep)
var pump := Callable()
## Callable() -> bool, true to stop (the error is then "cancelled")
var cancelled := Callable()
var parallel := PARALLEL
## chunks read per poll and a pause per loop: ways to slow a download down (screen captures, tests)
var max_chunks := 64
var loop_delay_ms := 0
var _links: Array[HTTPClient] = []


## A checked file on its way to the disk (worker thread)
class Write:
	var entry: Dictionary
	var buf: PackedByteArray
	var task := -1
	var error := ""


## One request in flight
class Slot:
	var range: Dictionary
	var fetch := HttpFetch.new()
	var link: HTTPClient
	var reused := false
	var pos := 0 # bundle offset of the next byte the stream brings
	var idx := 0 # the file of `range.files` being filled
	var buf := PackedByteArray()
	var refused := false # the server ignored the Range header
	var ready: Array = [] # files completed by the last chunks, not yet handed to a writer


func _init(p_host := "", p_port := 0, p_headers := {}) -> void:
	host = p_host
	port = p_port
	headers = p_headers


## Fetches every range {bundle, start, end, files: [{offset, size, hash, dests: [absolute paths]}]}; `url_of`
## gives the URL of a bundle hash. `on_bytes(n)` is called with the bytes received since the last call (negative
## when a failed try is taken back), `on_done(entry)` once a file is written. Returns "" or the first error
## that stopped it (what was written stays and was reported).
func fetch_all(ranges: Array, url_of: Callable, on_bytes: Callable, on_done: Callable) -> String:
	var queue: Array = ranges.duplicate()
	var active: Array[Slot] = []
	var writes: Array[Write] = []
	var failure := ""
	var spins := 0
	while failure == "" and (not queue.is_empty() or not active.is_empty() or not writes.is_empty()):
		if cancelled.is_valid() and cancelled.call():
			failure = "cancelled"
			break
		var moved := false
		for w: Write in writes.duplicate(): # files that reached the disk
			if not WorkerThreadPool.is_task_completed(w.task):
				continue
			WorkerThreadPool.wait_for_task_completion(w.task)
			writes.erase(w)
			moved = true
			if w.error != "":
				failure = w.error
				break
			on_done.call(w.entry)
		if failure != "":
			break
		while active.size() < parallel and writes.size() < MAX_WRITES and not queue.is_empty():
			active.append(_start(queue.pop_front(), url_of))
		for slot: Slot in active.duplicate():
			var f := slot.fetch
			var before := f.received
			var finished := f.poll()
			if f.received != before:
				moved = true
				on_bytes.call(f.received - before)
			for e: Dictionary in slot.ready:
				writes.append(_write(e, e["_buf"]))
			slot.ready.clear()
			if not finished:
				continue
			moved = true
			active.erase(slot)
			var verdict := _finish(slot)
			if verdict == "ok":
				continue
			if verdict.begins_with("retry"):
				var rest: Array = (slot.range["files"] as Array).slice(slot.idx)
				on_bytes.call(-maxi(0, slot.pos - int(slot.range["start"]) - _done_bytes(slot)))
				var again := {"bundle": slot.range["bundle"], "start": int(rest[0]["offset"]), "end": int(slot.range["end"]),
						"files": rest, "tries": int(slot.range.get("tries", 0)) + (0 if verdict == "retry-stale" else 1)}
				queue.push_front(again)
			else:
				failure = verdict
		if loop_delay_ms > 0:
			OS.delay_msec(loop_delay_ms)
		if moved:
			spins = 0
		else:
			spins += 1
			if pump.is_valid():
				pump.call()
			elif spins > SPINS_BEFORE_SLEEP:
				OS.delay_msec(1)
	for slot in active: # an error or a cancel: nothing half read goes back to the pool
		slot.fetch.abort()
	for w in writes:
		WorkerThreadPool.wait_for_task_completion(w.task)
		if w.error == "" and failure == "cancelled":
			on_done.call(w.entry) # written: the next run does not ask for it again
	return failure


func close() -> void:
	for l in _links:
		l.close()
	_links.clear()


func _start(range: Dictionary, url_of: Callable) -> Slot:
	var slot := Slot.new()
	slot.range = range
	slot.pos = int(range["start"])
	slot.link = _links.pop_back() if not _links.is_empty() else HTTPClient.new()
	slot.reused = slot.link.get_status() == HTTPClient.STATUS_CONNECTED
	slot.fetch.max_chunks = max_chunks
	slot.fetch.use_link(slot.link)
	var h := headers.duplicate()
	h["Range"] = "bytes=%d-%d" % [int(range["start"]), int(range["end"]) - 1]
	slot.fetch.start(host, port, str(url_of.call(str(range["bundle"]))), h, func(chunk: PackedByteArray) -> void:
		_take(slot, chunk))
	_flush_empty(slot)
	return slot


## Cuts the stream into the files of the range (the bytes between two files are dropped).
func _take(slot: Slot, chunk: PackedByteArray) -> void:
	if slot.refused:
		return
	if slot.fetch.status == 200 and int(slot.range["start"]) != 0:
		slot.refused = true # a whole bundle when a span was asked: not ours to cut
		return
	var files: Array = slot.range["files"]
	var at := 0
	while at < chunk.size() and slot.idx < files.size():
		var f: Dictionary = files[slot.idx]
		var off := int(f["offset"])
		if slot.pos < off: # a gap between two files
			var skip := mini(off - slot.pos, chunk.size() - at)
			at += skip
			slot.pos += skip
			continue
		var want := off + int(f["size"]) - slot.pos
		var n := mini(want, chunk.size() - at)
		slot.buf.append_array(chunk.slice(at, at + n))
		at += n
		slot.pos += n
		if slot.buf.size() == int(f["size"]):
			_complete(slot, f)
	slot.pos += chunk.size() - at # past the last file (a server that sent more)


func _complete(slot: Slot, f: Dictionary) -> void:
	var e := f.duplicate()
	e["_buf"] = slot.buf
	slot.ready.append(e)
	slot.buf = PackedByteArray()
	slot.idx += 1
	_flush_empty(slot)


## Empty files at the stream position are complete without a byte.
func _flush_empty(slot: Slot) -> void:
	var files: Array = slot.range["files"]
	while slot.idx < files.size() and int(files[slot.idx]["size"]) == 0 and slot.pos >= int(files[slot.idx]["offset"]):
		var e: Dictionary = files[slot.idx].duplicate()
		e["_buf"] = PackedByteArray()
		slot.ready.append(e)
		slot.idx += 1


## Bytes of the range that belong to the files already completed (not to be taken back on a retry).
func _done_bytes(slot: Slot) -> int:
	if slot.idx == 0:
		return 0
	var files: Array = slot.range["files"]
	var last: Dictionary = files[slot.idx - 1]
	return int(last["offset"]) + int(last["size"]) - int(slot.range["start"])


## "ok", "retry" (counts as a try), "retry-stale" (a pooled connection the server had closed: free) or the error.
func _finish(slot: Slot) -> String:
	var f := slot.fetch
	var tries := int(slot.range.get("tries", 0))
	var whole := slot.idx >= (slot.range["files"] as Array).size()
	if f.error != "" and not whole:
		if f.status == 0 and slot.reused:
			return "retry-stale"
		return "retry" if tries < RETRIES else f.error
	if f.status != 206 and f.status != 200:
		return "http %d %s" % [f.status, f.body.get_string_from_utf8()]
	if slot.refused:
		return "the server does not serve byte ranges"
	if not whole:
		return "retry" if tries < RETRIES else "short answer"
	if f.reusable:
		_links.append(slot.link)
	return "ok"


func _write(e: Dictionary, buf: PackedByteArray) -> Write:
	var w := Write.new()
	e.erase("_buf")
	w.entry = e
	w.buf = buf
	w.task = WorkerThreadPool.add_task(_write_file.bind(w), false, "write a downloaded file")
	return w


## Worker thread: checks the SHA-256 and writes the file under each of its paths; a file that does not
## match is never written. Touches nothing but `w` and its files.
static func _write_file(w: Write) -> void:
	if ContentManifest.hash_bytes(w.buf) != str(w.entry["hash"]):
		w.error = "%s: hash mismatch" % w.entry["paths"][0]
		return
	for dest: String in w.entry["dests"]:
		var dir := dest.get_base_dir()
		if not DirAccess.dir_exists_absolute(dir):
			DirAccess.make_dir_recursive_absolute(dir)
		var out := FileAccess.open(dest, FileAccess.WRITE)
		if out == null:
			w.error = "%s: cannot write" % dest
			return
		out.store_buffer(w.buf)
		out.close()
	w.buf = PackedByteArray()
