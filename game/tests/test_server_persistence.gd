## Reliable server persistence (roadmap S.03): the Persistence contract replayed on
## ServerPersistence, atomic writes, rotating copies, recovery, periodic save over a
## real WebSocket (NetBackend on 127.0.0.1).
extends TestCase

const NetTest := preload("res://tests/test_net.gd")


static func _dir() -> String:
	return "user://test_srvp_%d" % Time.get_ticks_usec()


static func _rm(path: String) -> void:
	for d in DirAccess.get_directories_at(path):
		_rm(path.path_join(d))
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)


static func _clock(start := 1000000) -> Dictionary:
	var c := {"t": start}
	c["call"] = func() -> int: return c["t"]
	return c


func _write_raw(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


# --- the Persistence contract ----------------------------------------------

func test_contract_on_the_server_store() -> void:
	var dir := _dir()
	var p := ServerPersistence.new(dir)
	p.save_character("w", "Alice", {"account": "a1", "level": 3})
	p.save_character("w", "Carl", {"account": "a2", "level": 1})
	p.save_account("a1", {"bank": {}})
	eq(int(ServerPersistence.new(dir).load_character("w", "Alice")["level"]), 3, "survives a new object")
	eq(p.list_characters("w"), PackedStringArray(["Alice", "Carl"]))
	eq(p.list_characters("w", "a1"), PackedStringArray(["Alice"]))
	eq(p.next_uid("item"), 1)
	eq(p.next_uid("item"), 2)
	p.commit([{"collection": Persistence.ACCOUNTS, "key": "a1", "data": {"bank": {"311": 3}}},
			{"collection": Persistence.CHARACTERS, "key": "w/Carl", "data": null}])
	eq(p.list_characters("w"), PackedStringArray(["Alice"]), "commit deletes")
	eq(int(p.load_account("a1")["bank"]["311"]), 3)
	eq(p.load_account("nobody"), {})
	check(not Array(p.list_keys(Persistence.CHARACTERS)).any(func(k: String) -> bool: return k.contains("_backups")),
			"copies are not documents")
	_rm(ProjectSettings.globalize_path(dir))


# --- atomic writes -----------------------------------------------------------

func test_a_kill_during_a_write_keeps_the_previous_file() -> void:
	var dir := _dir()
	var p := ServerPersistence.new(dir)
	p.save_character("w", "Alice", {"level": 3})
	# the process died after writing half of the tmp file, before the rename
	var path := dir + "/characters/w/Alice.json"
	_write_raw(path + ".tmp", '{"level": 9, "inven')
	eq(int(ServerPersistence.new(dir).load_character("w", "Alice")["level"]), 3, "previous document intact")
	eq(ServerPersistence.new(dir).list_characters("w"), PackedStringArray(["Alice"]), "the tmp is not a document")
	eq(p.sweep_tmp(), 1, "the leftover is swept")
	check(not FileAccess.file_exists(path + ".tmp"))
	p.save_character("w", "Alice", {"level": 4})
	eq(int(p.load_character("w", "Alice")["level"]), 4, "the next write replaces the file")
	check(not FileAccess.file_exists(path + ".tmp"), "no tmp left after a write")
	_rm(ProjectSettings.globalize_path(dir))


func test_a_failed_write_leaves_the_document_and_is_reported() -> void:
	var dir := _dir()
	var p := ServerPersistence.new(dir)
	p.save_character("w", "Alice", {"level": 3})
	# a directory where the tmp file should go: the write cannot happen
	DirAccess.make_dir_recursive_absolute(dir + "/characters/w/Alice.json.tmp")
	p.save_character("w", "Alice", {"level": 8})
	eq(p.failed_writes.size(), 1, "failure recorded")
	eq(int(p.load_character("w", "Alice")["level"]), 3, "old document kept")
	_rm(ProjectSettings.globalize_path(dir))


# --- copies ------------------------------------------------------------------

func test_rotating_copies_keep_the_last_ten() -> void:
	var dir := _dir()
	var clk := _clock()
	var p := ServerPersistence.new(dir)
	p.now_ms = clk["call"]
	for i in 15:
		clk["t"] += p.backup_interval_ms
		p.save_character("w", "Alice", {"level": i})
	var stamps := p.backups("characters", "w/Alice")
	eq(stamps.size(), 10, "ten copies at most")
	eq(int(JSON.parse_string(FileAccess.get_file_as_string(
			dir + "/_backups/characters/w/Alice/%d.json" % stamps[0]))["level"]), 13, "newest copy = previous save")
	eq(int(JSON.parse_string(FileAccess.get_file_as_string(
			dir + "/_backups/characters/w/Alice/%d.json" % stamps[9]))["level"]), 4, "oldest kept")
	_rm(ProjectSettings.globalize_path(dir))


func test_copies_are_spaced_by_the_interval() -> void:
	var dir := _dir()
	var clk := _clock()
	var p := ServerPersistence.new(dir)
	p.now_ms = clk["call"]
	for i in 6:
		clk["t"] += 1000 # many saves within the interval
		p.save_character("w", "Alice", {"level": i})
	eq(p.backups("characters", "w/Alice").size(), 1, "one copy per interval")
	clk["t"] += p.backup_interval_ms
	p.save_character("w", "Alice", {"level": 6})
	eq(p.backups("characters", "w/Alice").size(), 2)
	_rm(ProjectSettings.globalize_path(dir))


func test_a_deleted_document_keeps_a_copy_and_can_be_restored() -> void:
	var dir := _dir()
	var p := ServerPersistence.new(dir)
	p.save_character("w", "Alice", {"level": 12})
	p.delete_character("w", "Alice")
	eq(p.load_character("w", "Alice"), {}, "deleted")
	check(p.restore("characters", "w/Alice"), "restore the newest copy")
	eq(int(p.load_character("w", "Alice")["level"]), 12)
	check(not p.restore("characters", "w/Nobody"), "nothing to restore")
	_rm(ProjectSettings.globalize_path(dir))


func test_restore_a_chosen_copy() -> void:
	var dir := _dir()
	var clk := _clock()
	var p := ServerPersistence.new(dir)
	p.now_ms = clk["call"]
	for i in 4:
		clk["t"] += p.backup_interval_ms
		p.save_character("w", "Alice", {"level": i})
	var stamps := p.backups("characters", "w/Alice") # holds levels 2, 1, 0
	check(p.restore("characters", "w/Alice", stamps[2]))
	eq(int(p.load_character("w", "Alice")["level"]), 0, "level 0 is back")
	check(p.backups("characters", "w/Alice").size() >= 3, "the replaced document was kept too")
	_rm(ProjectSettings.globalize_path(dir))


# --- recovery ------------------------------------------------------------------

func test_a_damaged_document_is_rebuilt_from_a_copy() -> void:
	var dir := _dir()
	var clk := _clock()
	var p := ServerPersistence.new(dir)
	p.now_ms = clk["call"]
	clk["t"] += p.backup_interval_ms
	p.save_character("w", "Alice", {"level": 5})
	clk["t"] += p.backup_interval_ms
	p.save_character("w", "Alice", {"level": 6}) # the copy now holds level 5
	var path := dir + "/characters/w/Alice.json"
	_write_raw(path, '{"level": 6, "inven') # truncated: a crash on a store without atomic rename
	var fresh := ServerPersistence.new(dir)
	eq(int(fresh.load_character("w", "Alice")["level"]), 5, "the last good copy answers")
	eq(fresh.recovered.size(), 1, "recovery recorded")
	eq(int(JSON.parse_string(FileAccess.get_file_as_string(path))["level"]), 5, "the main file is healed")
	# a damaged file never replaces the good copies
	_write_raw(path, "garbage")
	var before := fresh.backups("characters", "w/Alice").size()
	fresh._backup("characters", "w/Alice", true)
	eq(fresh.backups("characters", "w/Alice").size(), before, "no copy of a damaged file")
	_rm(ProjectSettings.globalize_path(dir))


func test_a_damaged_document_without_copy_reads_as_missing() -> void:
	var dir := _dir()
	var p := ServerPersistence.new(dir)
	p.save_account("a1", {"x": 1})
	_write_raw(dir + "/accounts/a1.json", "")
	eq(p.load_account("a1"), {}, "no copy: absent, never a crash")
	_rm(ProjectSettings.globalize_path(dir))


# --- periodic save over the network -----------------------------------------------

func test_periodic_save_and_recovery_over_websocket() -> void:
	var dir := _dir()
	var rig := NetTest.Rig.new()
	var store := ServerPersistence.new(dir)
	rig.host.server.persistence = store
	rig.host.ticks = func() -> int: return rig.virtual_ms
	rig.host.autosave_ms = 10000
	var c := rig.client()
	check(rig.run(5.0, func() -> bool: return c.has(Protocol.MAP_ENTER)), "joined")
	var path := dir + "/characters/tiny/Tester.json"
	check(not FileAccess.file_exists(path) or rig.host.autosaves == 0, "nothing forced yet")
	c.backend.send(Protocol.move(20 * 14 + 13))
	check(rig.run(30.0, func() -> bool: return rig.host.autosaves >= 1), "the periodic save ran")
	eq(rig.host.last_autosave_count, 1, "one connected character saved")
	check(FileAccess.file_exists(path), "written while the player is still connected")
	eq(rig.sim().players.size(), 1, "still connected")
	# the stored document is damaged: a fresh server reads it back through the copy
	rig.run(11.0, func() -> bool: return rig.host.autosaves >= 2)
	store.backup_interval_ms = 0
	rig.run(11.0, func() -> bool: return rig.host.autosaves >= 3)
	check(store.backups("characters", "tiny/Tester").size() >= 1, "a copy exists")
	c.backend.close()
	rig.run(1.0)
	rig.host.shutdown()
	_write_raw(path, "{ broken")
	var rig2 := NetTest.Rig.new()
	var store2 := ServerPersistence.new(dir)
	rig2.host.server.persistence = store2
	var c2 := rig2.client()
	check(rig2.run(5.0, func() -> bool: return c2.has(Protocol.MAP_ENTER)), "joins again with a damaged save")
	eq(store2.recovered.size(), 1, "the character came back from a copy")
	eq(rig2.sim().players.values()[0].name, "Tester")
	c2.backend.close()
	rig2.run(1.0)
	rig2.host.shutdown()
	_rm(ProjectSettings.globalize_path(dir))


func test_autosave_can_be_disabled() -> void:
	var dir := _dir()
	var rig := NetTest.Rig.new()
	rig.host.server.persistence = ServerPersistence.new(dir)
	rig.host.ticks = func() -> int: return rig.virtual_ms
	rig.host.autosave_ms = 0
	var c := rig.client()
	rig.run(40.0)
	eq(rig.host.autosaves, 0)
	c.backend.close()
	rig.run(1.0)
	rig.host.shutdown()
	_rm(ProjectSettings.globalize_path(dir))
