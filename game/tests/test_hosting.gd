## Standalone / server boundary (docs/ARCHITECTURE.md "Standalone vs serveur"):
## the sim gets Persistence + Clock injected, hosts several sessions, and the
## same code runs whether one backend or many share the LocalServer.
extends TestCase

const LOOK := "{1|120,2195||56}"


static func _world() -> WorldSource:
	return WorldSource.from_dicts(
		{"id": "host", "name": "Host", "start_map": 1, "start_cell": 300},
		[{"id": 1, "coords": [0, 0], "neighbors": {}}])


class Conn:
	var backend := LocalBackend.new()
	var events: Array = []
	var you := -1

	func _init(server: LocalServer, name: String, account := "local") -> void:
		backend.server = server
		backend.account = account
		backend.event.connect(func(ev: Dictionary) -> void:
			events.append(ev)
			if ev["t"] == Protocol.WELCOME:
				you = int(ev["you"]))
		backend.send(Protocol.hello("host", name, LOOK))
		backend.poll(0.0)

	func take(type: String) -> Array:
		var out := events.filter(func(e: Dictionary) -> bool: return e["t"] == type)
		events = events.filter(func(e: Dictionary) -> bool: return e["t"] != type)
		return out


static func _server(persistence: Persistence = null) -> LocalServer:
	var s := LocalServer.new()
	s.sources["host"] = _world()
	if persistence != null:
		s.persistence = persistence
	return s


func test_two_sessions_share_one_world() -> void:
	var server := _server()
	var a := Conn.new(server, "Alice")
	var b := Conn.new(server, "Bob")
	a.backend.poll(0.0)
	eq(server.worlds.size(), 1, "one WorldSim for both")
	eq(server.worlds["host"].players.size(), 2)
	var added := a.take(Protocol.ACTOR_ADD)
	check(added.any(func(e: Dictionary) -> bool: return e["actor"]["name"] == "Bob"), "Alice sees Bob arrive")
	b.backend.send(Protocol.move(310, false))
	b.backend.poll(0.0)
	a.backend.poll(0.0)
	check(not a.take(Protocol.ACTOR_MOVE).is_empty(), "Alice sees Bob move")


func test_logging_in_again_ends_the_previous_session() -> void:
	var server := _server()
	var first := Conn.new(server, "Alice")
	var second := Conn.new(server, "Alice")
	first.backend.poll(0.0)
	var errors := first.take(Protocol.ERROR)
	eq(errors.size(), 1)
	eq(str(errors[0]["code"]), Protocol.E_CONNECTED_ELSEWHERE)
	eq(first.backend.player_id, -1, "first connection dropped")
	eq(server.worlds["host"].players.size(), 1)
	check(second.you >= 0 and server.worlds["host"].players.has(second.you), "second session plays")


func test_characters_survive_across_servers_through_persistence() -> void:
	var store := Persistence.new()
	var server := _server(store)
	server.clock = Clock.new(1_700_000_000_000)
	var a := Conn.new(server, "Alice", "acc1")
	server.tick(5000)
	a.backend.close()
	var saved := store.load_character("host", "Alice")
	eq(str(saved.get("account")), "acc1", "owner account stored")
	eq(int(saved.get("saved_at")), 1_700_000_005_000, "date from the injected clock")
	# a brand new server (e.g. after a restart) finds the character again
	var again := Conn.new(_server(store), "Alice", "acc1")
	var st := again.take(Protocol.PLAYER_STATS)
	eq(st.size(), 1)
	eq(str(st[0]["stats"]["name"]), "Alice")


func test_persistence_documents() -> void:
	var p := Persistence.new()
	p.save_character("w", "Bob", {"account": "a2"})
	p.save_character("w", "Alice", {"account": "a1"})
	p.save_character("w", "Carl", {"account": "a1"})
	p.save_character("other", "Dan", {"account": "a1"})
	eq(p.list_characters("w"), PackedStringArray(["Alice", "Bob", "Carl"]), "sorted")
	eq(p.list_characters("w", "a1"), PackedStringArray(["Alice", "Carl"]), "per account")
	var doc := p.load_character("w", "Bob")
	doc["account"] = "changed"
	eq(str(p.load_character("w", "Bob")["account"]), "a2", "loads are copies")
	p.commit([{"collection": Persistence.ACCOUNTS, "key": "a1", "data": {"bank": {"311": 3}}},
			{"collection": Persistence.CHARACTERS, "key": "w/Bob", "data": null}])
	eq(p.list_characters("w"), PackedStringArray(["Alice", "Carl"]), "commit deletes")
	eq(int(p.load_account("a1")["bank"]["311"]), 3)
	eq(p.load_account("nobody"), {})


func test_file_persistence_round_trip() -> void:
	var dir := "user://test_saves_%d" % Time.get_ticks_usec()
	var p := FilePersistence.new(dir)
	p.save_character("incarnam", "Alice", {"account": "a1", "level": 3})
	p.save_account("a1", {"bank": {}})
	eq(int(FilePersistence.new(dir).load_character("incarnam", "Alice")["level"]), 3)
	eq(p.list_characters("incarnam", "a1"), PackedStringArray(["Alice"]))
	check(FileAccess.file_exists(dir + "/characters/incarnam/Alice.json"))
	# saves written before P0.02 (<dir>/<world>/<name>.json) are still read
	DirAccess.make_dir_recursive_absolute(dir + "/incarnam")
	FileAccess.open(dir + "/incarnam/Old.json", FileAccess.WRITE).store_string('{"level": 7}')
	eq(int(p.load_character("incarnam", "Old").get("level", 0)), 7, "legacy path")
	p.delete_character("incarnam", "Alice")
	eq(p.load_character("incarnam", "Alice"), {})
	_rm(ProjectSettings.globalize_path(dir))


func _rm(path: String) -> void:
	for d in DirAccess.get_directories_at(path):
		_rm(path.path_join(d))
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)
