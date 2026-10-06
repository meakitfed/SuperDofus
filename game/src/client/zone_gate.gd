## Zones on demand wired to the game (roadmap C.02d). A big world is downloaded zone by zone
## (ZoneStreamer, C.02c): this node sits between the server events and the map display.
##
##   - `admit(ev)` is asked for every `map_enter` (SessionLink): true = the zone of the map is in the
##     cache, show it; false = the zone is being downloaded (blocking indicator), the event is asked
##     again when `zone_ready` fires. A map is never shown without its files (no black screen).
##   - once a map is admitted, the zones of the maps one exit away are fetched in the background,
##     one at a time, after the zone the player waits for.
##   - a failed download keeps the indicator with the error and tries again after `retry_s`; the maps
##     whose zone is installed stay playable (the event queue only waits for the missing one).
## Downloads run in one worker thread (ContentClient polls its own sockets); `threaded = false`
## runs them inline from `run_all` (tests, where the server lives in the same process).
## C.02e: a class zone holds the skeletons and creation skins of one playable class. The characters
## list (`characters`) and a `map_enter` are held until the zones of the classes they show are in the
## cache too; a player of another class who arrives later (`observe`) is fetched behind, and
## `class_installed` tells the session to draw its views again.
## C.02g: the skins of the items are in the zone `equipment`, fetched behind when a worn skin is seen
## (`observe`: actor_add, actor_look, map_enter) or when the inventory opens (`want_equipment`); the
## monsters of a heavy sub-area are in a zone its blocks require (`ZoneStreamer.requires_of`).
## Nothing here knows what a zone is made of.
class_name ZoneGate
extends Node

## a zone the player waits for is installed: re-ask the held `map_enter`
signal zone_ready
## C.02e: the zone of a class is installed (the creation preview and the views of that class redraw)
signal class_installed(breed: int)
## C.02g: the equipment zone (skins of the items) is installed: the players wearing them are drawn again
signal equipment_installed

var streamer: ZoneStreamer
var threaded := true
var retry_s := 5.0
## "indexing" (zones.json being fetched), "idle", "loading" (the player waits), "failed"
var state := "indexing"
## the zone being downloaded (blocking or background), "" when none
var zone := ""
var error := ""
## bytes of the current zone downloaded / expected (for the bar)
var done_bytes := 0
var total_bytes := 0
var indicator: ZoneIndicator

var _jobs: Array[String] = []
var _thread: Thread
var _job := ""
var _holding := false # an event is held until `_need` is installed
var _need := PackedStringArray()
var _index_ok := false
var _retry_at := 0


func _init(p_streamer: ZoneStreamer = null) -> void:
	streamer = p_streamer
	indicator = ZoneIndicator.new()


func _ready() -> void:
	add_child(indicator)
	start()


## Fetches the zones index first (a job like the others, so that a map_enter during it waits).
func start() -> void:
	if streamer == null:
		return
	streamer.client.progress = func(n: int, total: int, _file: String) -> void:
		done_bytes = n
		total_bytes = total
	_enqueue("@index", true)
	_next()


## True when `ev` can be applied now. Only `map_enter` and `characters` are held.
func admit(ev: Dictionary) -> bool:
	var t := str(ev.get("t", ""))
	if streamer == null or not (t == Protocol.MAP_ENTER or t == Protocol.CHARACTERS):
		return true
	var map_id := -1
	var breeds: Array = []
	if t == Protocol.MAP_ENTER:
		map_id = int(ev["map"]["id"])
		for a: Variant in ev.get("actors", []):
			if a is Dictionary and str(a.get("kind", "")) == "player":
				breeds.append(int(a.get("breed", 0)))
	else:
		for c: Variant in ev.get("list", []):
			breeds.append(int((c as Dictionary).get("breed", 0)))
	if _job == "@index" or _jobs.has("@index"):
		_holding = true
		state = "indexing"
		return false
	if not _index_ok:
		_enqueue("@index", false) # the index failed: one more try at each map, the map is shown as is
		_next()
		return true
	var need := streamer.missing_zones(map_id, breeds)
	if need.is_empty():
		if map_id >= 0:
			_prefetch(MapData.from_dict(ev["map"]))
		return true
	_hold(need)
	return false


## A player of `breed` appeared: its class zone is fetched behind (no wait), `class_installed` follows.
func observe(ev: Dictionary) -> void:
	if streamer == null or not _index_ok:
		return
	var looks: Array = []
	match str(ev.get("t", "")):
		Protocol.ACTOR_ADD:
			var a: Variant = ev.get("actor")
			if a is Dictionary:
				looks = (a as Dictionary).get("looks", [])
				if str(a.get("kind", "")) == "player":
					want_class(int(a.get("breed", 0)))
		Protocol.ACTOR_LOOK:
			looks = ev.get("looks", [])
		Protocol.MAP_ENTER:
			for a: Variant in ev.get("actors", []):
				if a is Dictionary:
					looks.append_array((a as Dictionary).get("looks", []))
	if streamer.needs_equipment(looks):
		want_equipment()


## The inventory opens (ClientSession): the skins of the items are asked for, when there is a gate.
static func ask_equipment(gate: ZoneGate) -> void:
	if gate != null:
		gate.want_equipment()


## C.02g: true when the skins of the items are installed (or the world keeps them in its base); else the
## zone is queued in front and `equipment_installed` follows.
func want_equipment() -> bool:
	if streamer == null or not _index_ok or streamer.equipment_ready():
		return true
	_enqueue(streamer.equipment_zone(), true)
	_next()
	return false


## True when the zone of the class is installed; else it is queued in front (the creation preview waits
## for `class_installed`).
func want_class(breed: int) -> bool:
	if streamer == null or streamer.class_ready(breed):
		return true
	_enqueue(streamer.class_zone(breed), true)
	_next()
	return false


func _hold(need: PackedStringArray) -> void:
	_holding = true
	_need = need
	state = "loading"
	zone = need[0]
	for i in range(need.size() - 1, -1, -1):
		_enqueue(need[i], true)
	_next()


## True while a map_enter is held (the blocking indicator is shown).
func waiting() -> bool:
	return _holding


## Inline mode (`threaded = false`): runs the queue until it is empty.
func run_all() -> void:
	var guard := 0
	while not _jobs.is_empty() and guard < 1000:
		guard += 1
		_job = _jobs.pop_front()
		_done(_work(_job))


func _process(_delta: float) -> void:
	if _thread != null:
		if not _thread.is_alive():
			var r: Dictionary = _thread.wait_to_finish()
			_thread = null
			_done(r)
	elif state == "failed" and _retry_at > 0 and Time.get_ticks_msec() >= _retry_at:
		_retry_at = 0
		state = "loading"
		_enqueue(_first_missing(), true)
	_next()
	indicator.update(self)


func _exit_tree() -> void:
	if _thread != null:
		streamer.client.cancel_requested = true
		_thread.wait_to_finish()
		_thread = null


## The zones of the maps one exit away, behind what is already queued.
func _prefetch(m: MapData) -> void:
	var near: Array = []
	for dir: String in m.neighbors:
		near.append(int(m.neighbors[dir]))
	for cell: int in m.map_change:
		near.append(int(m.map_change[cell]))
	for cell: int in m.triggers:
		near.append(int(m.triggers[cell]["to_map"]))
	for z in streamer.zones_to_fetch(-1, near):
		_enqueue(z, false)
	_next()


func _enqueue(job: String, front: bool) -> void:
	if job == "" or job == _job:
		return
	if _jobs.has(job):
		if front:
			_jobs.erase(job)
			_jobs.push_front(job)
		return
	if front:
		_jobs.push_front(job)
	else:
		_jobs.append(job)


func _next() -> void:
	if not threaded or _thread != null or _jobs.is_empty():
		return
	_job = _jobs.pop_front()
	if _job != "@index":
		zone = _job
		done_bytes = 0
		total_bytes = streamer.size_of(_job)
	_thread = Thread.new()
	_thread.start(_work.bind(_job))


## Worker side: only touches the streamer and its client.
func _work(job: String) -> Dictionary:
	if job == "@index":
		var r := streamer.load_index()
		return {"ok": r.ok, "error": r.error, "index": true}
	var z := streamer.ensure_zone(job)
	z["index"] = false
	return z


func _done(r: Dictionary) -> void:
	var job := _job
	_job = ""
	if bool(r["index"]):
		_index_ok = bool(r["ok"])
		error = "" if _index_ok else str(r["error"])
		if _holding:
			_holding = false # admit() asks again: the zone, or the map as is without an index
			state = "idle"
			zone_ready.emit()
		elif state == "indexing":
			state = "idle"
		return
	if bool(r["ok"]):
		error = ""
		if job.begins_with("class_") and job.substr(6).is_valid_int():
			class_installed.emit(int(job.substr(6)))
		elif job == ZoneStreamer.EQUIPMENT:
			equipment_installed.emit()
		if _holding and _first_missing() == "":
			_holding = false
			state = "idle"
			zone_ready.emit()
		return
	error = str(r["error"])
	if _holding and _need.has(job):
		state = "failed"
		_retry_at = Time.get_ticks_msec() + int(retry_s * 1000.0)


func _first_missing() -> String:
	for z in _need:
		if not streamer.installed.has(z):
			return z
	return ""
