## Downloads many small contents at once over a few persistent HTTP connections (keep-alive), the way a
## launcher/patcher does: one connection per file costs a TCP handshake and a full round trip each, which on a
## 50 ms link caps a download at ~20 files/s however fast the line is. Here PARALLEL requests are in flight, each
## connection serves one request after the other, and the SHA-256 is computed while the bytes arrive (the file is
## written once, already verified, never read back: reading it back costs an antivirus scan on Windows).
##
## No thread, no scene: `fetch_all` is a loop that the caller runs (the loading screen runs it in a thread, the
## tests with `pump`). Big contents (streamed to a `.part` and resumed) stay in ContentClient._fetch_blob.
class_name BlobDownloader
extends RefCounted

## requests in flight
const PARALLEL := 8
## a content above this is not buffered in memory (1 MiB: past it a cut is worth resuming from a .part): ContentClient streams it
const SMALL_MAX := 1024 * 1024
## network failures (cut connection, hash mismatch) tolerated per content before giving up
const RETRIES := 2
## verified contents waiting for their file to be written (each is held in memory: this bounds it)
const MAX_WRITES := 48
## idle polls in a row before the loop sleeps (a sleep costs a millisecond or more; an answer on a fast link takes less)
const SPINS_BEFORE_SLEEP := 60

var host := ""
var port := 0
var headers := {}
## Callable(), called while waiting for the network (default: a 1 ms sleep)
var pump := Callable()
## Callable() -> bool, true to stop (the error is then "cancelled")
var cancelled := Callable()
## requests in flight (tests set 1 to cut a download at a known place)
var parallel := PARALLEL
## chunks read per poll and a pause per loop: ways to slow a download down (screen captures, tests)
var max_chunks := 64
var loop_delay_ms := 0
var _links: Array[HTTPClient] = []


## A verified content on its way to the disk, written by a worker thread
class Write:
	var job: Dictionary
	var buf: PackedByteArray
	var task := -1
	var error := ""


## One request in flight (a class, not a Dictionary: the buffer must be appended to in place)
class Slot:
	var job: Dictionary
	var fetch := HttpFetch.new()
	var link: HTTPClient
	var buf := PackedByteArray()
	var reused := false


func _init(p_host := "", p_port := 0, p_headers := {}) -> void:
	host = p_host
	port = p_port
	headers = p_headers


## Fetches every job {url, hash, size, dest} and writes `dest` (the folder is created) once the SHA-256 and the
## size match. `on_bytes(n)` is called with the bytes received since the last call, `on_done(job)` once a job is
## installed. Returns "" or "<dest>: <error>" for the first job that failed for good (the others in flight are
## dropped, what was installed stays).
func fetch_all(jobs: Array, on_bytes: Callable, on_done: Callable) -> String:
	var next := 0
	var retry: Array = []
	var active: Array = []
	var made := {}
	var writes: Array[Write] = []
	var failure := ""
	var spins := 0
	while failure == "" and (next < jobs.size() or not retry.is_empty() or not active.is_empty() or not writes.is_empty()):
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
			on_done.call(w.job)
		if failure != "":
			break
		while active.size() < parallel and writes.size() < MAX_WRITES and (next < jobs.size() or not retry.is_empty()):
			var job: Dictionary
			if not retry.is_empty():
				job = retry.pop_front()
			else:
				job = jobs[next]
				next += 1
			active.append(_start(job))
		for slot: Slot in active.duplicate():
			var f: HttpFetch = slot.fetch
			var before := f.received
			var finished := f.poll()
			if f.received != before:
				moved = true
				on_bytes.call(f.received - before)
			if not finished:
				continue
			moved = true
			active.erase(slot)
			var verdict := _finish(slot, made)
			if verdict == "ok":
				var dest := str(slot.job["dest"])
				var dir := dest.get_base_dir()
				if not made.has(dir):
					DirAccess.make_dir_recursive_absolute(dir)
					made[dir] = true
				var w := Write.new()
				w.job = slot.job
				w.buf = slot.buf
				w.task = WorkerThreadPool.add_task(_write_file.bind(w), false, "write a downloaded file")
				writes.append(w)
			elif verdict.begins_with("retry"):
				on_bytes.call(-f.received) # the bytes of a failed try do not count twice
				var job: Dictionary = slot.job
				job["tries"] = int(job.get("tries", 0)) + (0 if verdict == "retry-stale" else 1)
				retry.append(job)
			else:
				failure = "%s: %s" % [slot.job["dest"], verdict]
		if loop_delay_ms > 0:
			OS.delay_msec(loop_delay_ms)
		if moved:
			spins = 0
		else:
			spins += 1
			if pump.is_valid():
				pump.call()
			elif spins > SPINS_BEFORE_SLEEP:
				OS.delay_msec(1) # Windows sleeps at least 1 ms, often more: only once the answer is clearly not imminent
	for slot: Slot in active: # an error or a cancel: nothing half read goes back to the pool
		slot.fetch.abort()
	for w in writes:
		WorkerThreadPool.wait_for_task_completion(w.task)
	return failure


func close() -> void:
	for l in _links:
		l.close()
	_links.clear()


func _start(job: Dictionary) -> Slot:
	var slot := Slot.new()
	slot.job = job
	slot.link = _links.pop_back() if not _links.is_empty() else HTTPClient.new()
	slot.reused = slot.link.get_status() == HTTPClient.STATUS_CONNECTED
	slot.fetch.max_chunks = max_chunks
	slot.fetch.use_link(slot.link)
	slot.fetch.start(host, port, str(job["url"]), headers, func(chunk: PackedByteArray) -> void:
		slot.buf.append_array(chunk))
	return slot


## "ok" (complete, to be verified and written), "retry" (counts as a try), "retry-stale" (a pooled connection the server had closed: free) or the error.
func _finish(slot: Slot, made: Dictionary) -> String:
	var f := slot.fetch
	var job := slot.job
	if f.error != "":
		if f.status == 0 and slot.reused:
			return "retry-stale" # the idle connection was closed under us: same request on a fresh one
		return "retry" if int(job.get("tries", 0)) < RETRIES else f.error
	if f.status != 200:
		return "http %d %s" % [f.status, f.body.get_string_from_utf8()]
	if slot.buf.size() != int(job["size"]):
		return "retry" if int(job.get("tries", 0)) < RETRIES else "short body"
	if f.reusable:
		_links.append(slot.link)
	return "ok"


## Worker thread: checks the SHA-256 of the bytes (hashing them while they arrive cost the download loop a third
## of its time) and writes the file; a file that does not match is never written. Touches nothing but `w`.
static func _write_file(w: Write) -> void:
	if ContentManifest.hash_bytes(w.buf) != str(w.job["hash"]):
		w.error = "%s: hash mismatch" % w.job["dest"]
		return
	var out := FileAccess.open(str(w.job["dest"]), FileAccess.WRITE)
	if out == null:
		w.error = "%s: cannot write" % w.job["dest"]
		return
	out.store_buffer(w.buf)
	out.close()
	w.buf = PackedByteArray()
