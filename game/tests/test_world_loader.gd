## The loading screen's model and screen (roadmap C.03): worlds offered by a server, comparison
## with the local cache, download with progress, cut and resume, update, full disk, launch from
## the cache. A real content server runs in this process (127.0.0.1) and is pumped while the
## client waits; fixture folder under user://test_loader/.
extends TestCase

const Api := preload("res://tests/test_content_api.gd")
const BASE := "user://test_loader"
const SIZE := 1200000 # a few 64 KB chunks

var _root := ""
var _store := ""
var _cache := ""


func _fixture(extra := "") -> WorldPackage.Built:
	var base := ProjectSettings.globalize_path(BASE)
	_rm(base)
	_root = base + "/game"
	_store = base + "/packages"
	_cache = base + "/cache"
	_write("worlds/fx/world.json", JSON.stringify({"id": "fx", "name": "Monde fixture", "module": "demo",
			"content": ["content/*"]}).to_utf8_buffer())
	_write("data/t.json", "[1,2,3]".to_utf8_buffer())
	_write("content/a.bin", _blob(1))
	_write("content/b.bin", _blob(2))
	_write("content/c.txt", ("c" + extra).to_utf8_buffer())
	return WorldPackage.build("fx", _root, _store, true)


func _blob(seed_value: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(SIZE)
	for i in SIZE:
		b[i] = (i * (31 + seed_value) + (i >> 8) + seed_value) & 255
	return b


func _write(rel: String, data: PackedByteArray) -> void:
	var path := _root.path_join(rel)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(data)
	f.close()


func _rm(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_rm(dir.path_join(d))
	DirAccess.remove_absolute(dir)


func _loader(rig: Api.Rig) -> WorldLoader:
	var wl := WorldLoader.new(rig.client())
	wl.cache_base = _cache
	wl.free_space = func(_p: String) -> int: return -1
	return wl


func test_first_launch_downloads_everything_then_nothing() -> void:
	var rig := Api.Rig.new(_fixture())
	var wl := _loader(rig)
	check(wl.refresh(), wl.error)
	eq(wl.worlds.size(), 1)
	var e := wl.entry("fx")
	eq(e["name"], "Monde fixture")
	eq(e["status"], "new")
	eq(int(e["todo_files"]), 5, "world.json, t.json, a.bin, b.bin, c.txt")
	check(not wl.launch("fx"), "a world that is not downloaded cannot be launched")
	check(wl.install("fx"), wl.error)
	eq(wl.state, "done")
	eq(wl.entry("fx")["status"], "current")
	eq(wl.done_bytes, wl.total_bytes)
	# the next start: nothing to download, the cache is reused
	var again := _loader(rig)
	check(again.refresh(), again.error)
	eq(again.entry("fx")["status"], "current")
	eq(int(again.entry("fx")["todo_files"]), 0)
	eq(int(again.entry("fx")["todo_bytes"]), 0)
	check(again.launch("fx"), "launched from the cache")
	check(ContentSource.using_cache(), "the cache answers")
	eq(ContentSource.world(), "fx")
	ContentSource.use_dev()
	rig.host.shutdown()


func test_a_changed_file_downloads_only_that_file() -> void:
	var rig := Api.Rig.new(_fixture())
	var wl := _loader(rig)
	wl.refresh()
	check(wl.install("fx"), wl.error)
	_write("content/c.txt", "changed on the server".to_utf8_buffer())
	rig.host.content.set_package(WorldPackage.build("fx", _root, _store, true))
	var next := _loader(rig)
	next.refresh()
	var e := next.entry("fx")
	eq(e["status"], "update", "the server has another version")
	eq(int(e["todo_files"]), 1)
	eq(int(e["todo_bytes"]), "changed on the server".length())
	check(not next.launch("fx"), "an outdated world is updated first")
	check(next.install("fx"), next.error)
	eq(next.entry("fx")["status"], "current")
	eq(FileAccess.get_file_as_string(_cache + "/fx/content/c.txt"), "changed on the server")
	rig.host.shutdown()


func test_cancel_then_resume_where_it_stopped() -> void:
	var rig := Api.Rig.new(_fixture())
	var wl := _loader(rig)
	wl.refresh()
	wl.client.chunks_per_poll = 1
	var total := int(wl.entry("fx")["todo_bytes"])
	wl.on_progress = func() -> void:
		if wl.done_files >= 1 and wl.done_bytes > SIZE + 200000: # inside the second big file
			wl.cancel()
	check(not wl.install("fx"), "cancelled")
	eq(wl.state, "cancelled")
	check(wl.error != "")
	var cut := _loader(rig)
	cut.refresh()
	var e := cut.entry("fx")
	eq(e["status"], "partial", "an interrupted download is resumed")
	check(int(e["todo_bytes"]) < total, "what arrived is not fetched again")
	check(not cut.launch("fx"), "not launchable while incomplete")
	check(cut.install("fx"), cut.error)
	eq(cut.entry("fx")["status"], "current")
	eq(FileAccess.get_file_as_bytes(_cache + "/fx/content/b.bin"), _blob(2), "complete and identical")
	rig.host.shutdown()


func test_full_disk_is_reported_before_downloading() -> void:
	var rig := Api.Rig.new(_fixture())
	var wl := _loader(rig)
	wl.refresh()
	wl.free_space = func(_p: String) -> int: return 1000
	check(not wl.install("fx"))
	eq(wl.state, "failed")
	check(wl.error.contains("Espace disque insuffisant"), wl.error)
	check(not FileAccess.file_exists(_cache + "/fx/content/a.bin"), "nothing written")
	check(not DirAccess.dir_exists_absolute(_cache + "/fx/content") or DirAccess.get_files_at(_cache + "/fx/content").is_empty())
	rig.host.shutdown()


func test_a_damaged_file_is_found_after_a_cut() -> void:
	var rig := Api.Rig.new(_fixture())
	var wl := _loader(rig)
	wl.refresh()
	wl.client.chunks_per_poll = 1
	wl.on_progress = func() -> void:
		if wl.done_files >= 2:
			wl.cancel()
	wl.install("fx")
	# the first installed file is damaged without changing its size (a bad sector, a crash)
	var damaged := ""
	for p in ["content/a.bin", "content/b.bin"]:
		if FileAccess.file_exists(_cache + "/fx/" + p):
			damaged = _cache + "/fx/" + p
			break
	check(damaged != "", "a file was installed before the cut")
	var f := FileAccess.open(damaged, FileAccess.READ_WRITE)
	f.seek(1000)
	var old := f.get_8()
	f.seek(1000)
	f.store_8(old ^ 0xFF)
	f.close()
	var next := _loader(rig)
	check(next.refresh(), next.error)
	eq(next.entry("fx")["status"], "partial")
	check(not FileAccess.file_exists(damaged), "the full hash check removed the damaged file")
	check(next.install("fx"), next.error)
	for p in ["a.bin", "b.bin"]:
		check(FileHash.sha256(_cache + "/fx/content/" + p) != "")
	eq(FileAccess.get_file_as_bytes(_cache + "/fx/content/a.bin"), _blob(1), "a.bin is intact")
	eq(FileAccess.get_file_as_bytes(_cache + "/fx/content/b.bin"), _blob(2), "b.bin is intact")
	rig.host.shutdown()


func test_the_session_token_of_a_websocket_login_drives_the_loader() -> void:
	var rig := Api.Rig.new(_fixture())
	rig.host.listen(0, "127.0.0.1")
	var backend := NetBackend.new()
	backend.connect_to("127.0.0.1:%d" % rig.host.local_port())
	backend.send(Protocol.register("eve", "secret3"))
	var waited := 0
	while backend.token == "" and waited < 400:
		rig.pump()
		backend.poll(0.005)
		waited += 1
	check(backend.token != "", "login_ok gave a token")
	var client := ContentClient.new("127.0.0.1", rig.host.http_port(), backend.token)
	client.pump = rig.pump
	var wl := WorldLoader.new(client)
	wl.cache_base = _cache
	wl.free_space = func(_p: String) -> int: return -1
	check(wl.refresh(), wl.error)
	check(wl.install("fx"), wl.error)
	check(wl.launch("fx"))
	ContentSource.use_dev()
	backend.close()
	rig.host.shutdown()


func test_errors_are_plain_words() -> void:
	var rig := Api.Rig.new(_fixture())
	var stranger := WorldLoader.new(ContentClient.new("127.0.0.1", rig.host.http_port(), "nope"))
	stranger.client.pump = rig.pump
	check(not stranger.refresh())
	check(stranger.error.contains("reconnectez-vous"), stranger.error)
	eq(stranger.state, "failed")
	rig.host.shutdown()
	var dead := WorldLoader.new(ContentClient.new("127.0.0.1", 1, "x"))
	check(not dead.refresh())
	check(dead.error.contains("Connexion perdue") or dead.error.contains("cannot"), dead.error)


func test_the_loading_screen_lists_downloads_and_starts_the_world() -> void:
	var rig := Api.Rig.new(_fixture())
	var wl := _loader(rig)
	wl.client.pump = Callable() # the screen's thread only waits: the test thread alone pumps the server
	var screen := WorldLoadScreen.new()
	screen.setup(wl)
	var ready_ids: Array = []
	screen.world_ready.connect(func(id: String) -> void: ready_ids.append(id))
	screen._ready() # not in a tree here (the runner is a SceneTree in _init): builds the UI, starts the list thread
	_wait(rig, screen, func() -> bool: return screen._thread == null)
	eq(screen._rows.get_child_count(), 1, "one row per world")
	eq(WorldLoadScreen.action_text(wl.entry("fx")).begins_with("Télécharger"), true)
	screen.pick("fx")
	_wait(rig, screen, func() -> bool: return not ready_ids.is_empty())
	eq(ready_ids, ["fx"], "the world starts once its cache is complete")
	check(ContentSource.using_cache())
	ContentSource.use_dev()
	screen.free()
	rig.host.shutdown()


func _wait(rig: Api.Rig, screen: WorldLoadScreen, done: Callable) -> void:
	var guard := 0
	while not done.call() and guard < 4000:
		rig.pump()
		screen._process(0.0)
		guard += 1
	check(guard < 4000, "the screen finished")


func test_texts_and_helpers() -> void:
	eq(WorldLoader.format_bytes(830), "830 o")
	eq(WorldLoader.format_bytes(2048), "2 Ko")
	eq(WorldLoader.format_bytes(13 * 1048576 + 400000), "13,4 Mo")
	eq(WorldLoader.split_address("10.0.0.2:7777", 1), {"host": "10.0.0.2", "port": 7777})
	eq(WorldLoader.split_address("ws://10.0.0.2", 7777), {"host": "10.0.0.2", "port": 7777})
	eq(DiskSpace.parse_dir_output("  2 Rép(s)  78056042496 octets libres\r\n"), 78056042496)
	eq(DiskSpace.parse_dir_output("nothing"), -1)
	eq(DiskSpace.parse_df_output("Filesystem 1024-blocks Used Available Capacity Mounted\n/dev/sda1 100 40 60 40% /"), 60 * 1024)
	eq(WorldLoadScreen.action_text({"status": "current", "todo_bytes": 0}), "Jouer")
	eq(WorldLoadScreen.action_text({"status": "update", "todo_bytes": 2048}), "Mettre à jour (2 Ko)")
	eq(WorldLoadScreen.action_text({"status": "partial", "todo_bytes": 2048}), "Reprendre (2 Ko)")
	var free := DiskSpace.free_bytes(BASE)
	check(free == -1 or free > 0, "the real disk answers a number or -1")
