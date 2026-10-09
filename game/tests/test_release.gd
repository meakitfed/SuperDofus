## Export (X.01): the presets of the light client and of the headless server, the `--check` of the
## server, and the movable dev root which lets an exported server read worlds/ and data/ beside its exe.
extends TestCase

const BASE := "user://test_release"


func _wipe(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for d in DirAccess.get_directories_at(path):
		_wipe(path.path_join(d))
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)


func _write(rel: String, text: String) -> void:
	var path := ProjectSettings.globalize_path(BASE).path_join(rel)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _root() -> String:
	return ProjectSettings.globalize_path(BASE).path_join("root")


func _fixture() -> void:
	_wipe(BASE)
	_write("root/worlds/w1/world.json", '{"id": "w1", "name": "W1", "maps": []}')
	_write("root/data/experience.json", "{}")


func test_presets_split_client_and_server() -> void:
	var cfg := ConfigFile.new()
	eq(cfg.load("res://export_presets.cfg"), OK, "export_presets.cfg readable")
	var names := {}
	for section in cfg.get_sections():
		if section.count(".") == 1: # preset.N
			names[str(cfg.get_value(section, "name"))] = section
	check(names.has("Client") and names.has("Serveur"), "presets Client and Serveur")
	var client: String = names.get("Client", "preset.none")
	for folder in ["content/*", "data/*", "worlds/*", "mods/*"]:
		check(str(cfg.get_value(client, "exclude_filter", "")).contains(folder), "client excludes " + folder)
		check(str(cfg.get_value(names.get("Serveur", "preset.none"), "exclude_filter", "")).contains(folder),
				"the server PCK holds no assets either: " + folder)
	eq(cfg.get_value(names.get("Serveur", "preset.none") + ".options", "debug/export_console_wrapper", 0), 2,
			"the server ships a console exe in release")
	check(FileAccess.file_exists("res://scenes/server/server.tscn"), "the server scene an exported exe opens")


func test_check_passes_on_a_good_folder() -> void:
	_fixture()
	var r := ServerCheck.run(PackedStringArray(["w1"]), _root(), BASE + "/packages", BASE + "/saves", 0, 0)
	check(bool(r["ok"]), "all good: " + "\n".join(r["lines"]))
	check("\n".join(r["lines"]).contains("WARN paquet w1 non publie"), "package not published yet is a warning")
	r = ServerCheck.run(PackedStringArray(["w1"]), _root(), BASE + "/packages", BASE + "/saves", 0, 7778)
	check(bool(r["ok"]) and "\n".join(r["lines"]).contains("sera prepare en arriere-plan"), "...and does not block the content API: it is prepared at start")
	var store := ProjectSettings.globalize_path(BASE + "/packages")
	var pub := ContentPublisher.publish("w1", _root(), store)
	check(pub.ok, pub.error)
	r = ServerCheck.run(PackedStringArray(["w1"]), _root(), store, BASE + "/saves", 0, 0)
	check("\n".join(r["lines"]).contains("OK   paquet w1 publie"), "published package")
	_wipe(BASE)


func test_check_fails_on_missing_world_and_data() -> void:
	_fixture()
	var r := ServerCheck.run(PackedStringArray(["w1", "nope"]), _root(), BASE + "/packages", BASE + "/saves", 0, 0)
	check(not bool(r["ok"]), "an unknown world blocks")
	check("\n".join(r["lines"]).contains("FAIL monde nope"))
	_wipe(_root().path_join("data"))
	r = ServerCheck.run(PackedStringArray(["w1"]), _root(), BASE + "/packages", BASE + "/saves", 0, 0)
	check("\n".join(r["lines"]).contains("FAIL dossier data"), "missing data folder")
	_wipe(BASE)


func test_check_fails_on_a_busy_port() -> void:
	_fixture()
	var tcp := TCPServer.new()
	eq(tcp.listen(0, "*"), OK)
	var port := tcp.get_local_port()
	var worlds := PackedStringArray(["w1"])
	var r := ServerCheck.run(worlds, _root(), BASE + "/packages", BASE + "/saves", port, 0)
	check(not bool(r["ok"]), "port in use blocks")
	check("\n".join(r["lines"]).contains("FAIL port %d" % port))
	tcp.stop()
	_wipe(BASE)


func test_dev_root_can_move_beside_the_executable() -> void:
	_fixture()
	var before := ContentSource.dev_root()
	check(not ContentSource.exists("worlds/w1/world.json"), "not in the project")
	ContentSource.set_dev_root(_root())
	check(ContentSource.exists("worlds/w1/world.json"), "found under the new root")
	eq(int(ContentSource.read_json("worlds/w1/world.json")["id"] == "w1"), 1)
	ContentSource.set_dev_root(before)
	check(not ContentSource.exists("worlds/w1/world.json"), "back to the project")
	check(ContentSource.exists("worlds/test/world.json"), "project worlds readable again")
	_wipe(BASE)


func test_solo_is_offered_from_the_project() -> void:
	check(LaunchScreen.solo_available(), "the project holds worlds: solo available")
