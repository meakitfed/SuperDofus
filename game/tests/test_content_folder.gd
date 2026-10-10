## The configurable folder of the downloaded worlds (roadmap C.04): resolution (command line,
## remembered, default), validation, migration of the old cache, and a client that logs in by
## WebSocket (127.0.0.1), downloads a world into a folder of its choice and reads it from there.
## Fixtures under user://test_folder/ (the world fixture is the one of test_world_loader.gd).
extends TestCase

const Api := preload("res://tests/test_content_api.gd")
const Loader := preload("res://tests/test_world_loader.gd")
const BASE := "user://test_folder"

var _dir := ""


func _fresh() -> String:
	_dir = ProjectSettings.globalize_path(BASE)
	ContentFolder.remove_dir(_dir)
	DirAccess.make_dir_recursive_absolute(_dir)
	return _dir


func _no_space(_p: String) -> int:
	return -1


func test_normalize() -> void:
	eq(ContentFolder.normalize("  D:\\Jeux\\SuperDofus\\ "), "D:/Jeux/SuperDofus")
	eq(ContentFolder.normalize("D:\\"), "D:/")
	eq(ContentFolder.normalize(""), "")


func test_resolution_order_command_line_then_remembered_then_default() -> void:
	var d := _fresh()
	var cfg := d + "/launch.cfg"
	var r := ContentFolder.resolve({}, cfg)
	eq(r["source"], "default")
	check(not r["configured"], "first launch: the player is asked")
	eq(r["path"], ContentFolder.legacy_dir(), "the default is the old cache")
	# the file also holds the other memories of the launch screen: they survive
	var other := ConfigFile.new()
	other.set_value("server", "address", "25.1.2.3:7777")
	other.save(cfg)
	check(ContentFolder.remember("D:\\Jeux\\Mondes\\", cfg))
	eq(ContentFolder.remembered(cfg), "D:/Jeux/Mondes")
	var back := ConfigFile.new()
	back.load(cfg)
	eq(back.get_value("server", "address"), "25.1.2.3:7777", "the address is kept")
	r = ContentFolder.resolve({}, cfg)
	eq(r["source"], "config")
	check(r["configured"])
	eq(r["path"], "D:/Jeux/Mondes")
	r = ContentFolder.resolve({"content-dir": "E:\\Autre"}, cfg)
	eq(r["source"], "cli")
	eq(r["path"], "E:/Autre", "the command line wins")


func test_validate_refuses_the_unusable_and_reports_the_free_space() -> void:
	var d := _fresh()
	eq(ContentFolder.validate("")["ok"], false)
	eq(ContentFolder.validate("mondes/relatif")["ok"], false, "a relative path is refused")
	var f := FileAccess.open(d + "/un fichier", FileAccess.WRITE)
	f.store_string("x")
	f.close()
	var under_file := ContentFolder.validate(d + "/un fichier/sous", func(_p: String) -> int: return 5)
	eq(under_file["ok"], false, "cannot create a folder under a file")
	check(str(under_file["error"]) != "")
	var good := ContentFolder.validate(d + "/Mes mondes/avec espaces", func(_p: String) -> int: return 12345)
	eq(good["ok"], true, str(good["error"]))
	eq(good["free"], 12345)
	check(DirAccess.dir_exists_absolute(d + "/Mes mondes/avec espaces"), "the folder was created")
	check(not FileAccess.file_exists(d + "/Mes mondes/avec espaces/.write_test"), "probe removed")
	eq(ContentFolder.free_text(-1), "espace libre inconnu")
	check(ContentFolder.free_text(3 << 30).begins_with("3,0 Go"))
	# the real free-space probe works on a folder with spaces
	check(int(ContentFolder.validate(d + "/Mes mondes")["free"]) > 0, "DiskSpace answers for a path with spaces")


func test_apply_points_content_source_at_the_folder() -> void:
	var d := _fresh()
	ContentFolder.apply(d + "/A B/")
	eq(ContentSource.cache_base(), d + "/A B")
	eq(ContentSource.cache_dir_for("fx"), d + "/A B/fx")
	eq(ContentSource.cache_dir_for("fx", "z:/y"), "z:/y/fx", "an explicit base still wins")
	eq(WorldLoader.new().cache_base, d + "/A B", "the loader follows the folder")
	ContentSource.set_cache_base("")
	eq(ContentSource.cache_base(), ContentSource.CACHE_BASE)


func _fake_world(base: String, id: String, bytes: int) -> void:
	var dir := base + "/" + id + "/content"
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(base + "/" + id + "/manifest.json", FileAccess.WRITE)
	f.store_string("{}")
	f.close()
	f = FileAccess.open(dir + "/a.bin", FileAccess.WRITE)
	f.store_buffer(PackedByteArray([1]).duplicate() if bytes == 1 else _bytes(bytes))
	f.close()


func _bytes(n: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(n)
	return b


func test_legacy_worlds_are_listed_and_moved() -> void:
	var d := _fresh()
	var old := d + "/old"
	var fresh := d + "/new"
	_fake_world(old, "alpha", 1000)
	_fake_world(old, "beta", 2000)
	DirAccess.make_dir_recursive_absolute(old + "/notaworld") # no manifest: not a world
	var found := ContentFolder.legacy_worlds(old)
	eq(found.size(), 2)
	eq(found[0]["id"], "alpha")
	eq(found[1]["bytes"], 2002, "the manifest counts too")
	eq(ContentFolder.legacy_worlds(old, old).size(), 0, "nothing to offer when it is the folder in use")
	_fake_world(fresh, "beta", 5) # already there: the new copy is kept
	var r := ContentFolder.migrate(old, fresh, ["alpha", "beta"], _no_space)
	eq(r["ok"], true, str(r["error"]))
	eq(r["moved"], ["alpha"])
	eq(r["skipped"], ["beta"])
	check(FileAccess.file_exists(fresh + "/alpha/manifest.json"), "alpha arrived")
	check(not DirAccess.dir_exists_absolute(old + "/alpha"), "alpha left the old folder")
	check(DirAccess.dir_exists_absolute(old + "/beta"), "the skipped world stays where it was")
	eq(FileAccess.get_file_as_bytes(fresh + "/beta/content/a.bin").size(), 5, "the existing copy is untouched")
	# same folder twice: nothing happens
	eq(ContentFolder.migrate(fresh, fresh, ["alpha"])["moved"], [])
	ContentFolder.remove_dir(d)


func test_a_full_disk_stops_a_copy_but_a_rename_needs_no_room() -> void:
	var d := _fresh()
	_fake_world(d + "/old", "alpha", 3000)
	# a rename on one disk needs no space even when the free-space probe says 0
	var r := ContentFolder.migrate(d + "/old", d + "/new", ["alpha"], func(_p: String) -> int: return 0)
	eq(r["moved"], ["alpha"])
	ContentFolder.remove_dir(d)


## The player's folder holds a space and is not under user://; two clients, one per folder.
func test_a_client_downloads_into_the_chosen_folder_and_reads_it_from_there() -> void:
	var fixture := Loader.new()
	var built := fixture._fixture()
	var d := ProjectSettings.globalize_path(BASE)
	var folder := d + "/Jeux perso/Mondes"
	ContentFolder.remove_dir(folder)
	var rig := Api.Rig.new(built)
	rig.host.listen(0, "127.0.0.1")
	var backend := NetBackend.new()
	backend.connect_to("127.0.0.1:%d" % rig.host.local_port())
	backend.send(Protocol.register("frodo", "secret3"))
	var waited := 0
	while backend.token == "" and waited < 400:
		rig.pump()
		backend.poll(0.005)
		waited += 1
	check(backend.token != "", "login_ok gave a token")
	ContentFolder.apply(folder)
	var client := ContentClient.new("127.0.0.1", rig.host.http_port(), backend.token)
	client.pump = rig.pump
	var wl := WorldLoader.new(client) # no cache_base set: it follows the chosen folder
	wl.free_space = func(_p: String) -> int: return -1
	check(wl.refresh(), wl.error)
	eq(wl.entry("fx")["status"], "new")
	check(wl.install("fx"), wl.error)
	check(FileAccess.file_exists(folder + "/fx/" + ContentSource.MANIFEST), "the world is in the chosen folder")
	check(wl.launch("fx"))
	eq(ContentSource.cache_dir(), folder + "/fx", "the content layer reads from there")
	check(ContentSource.exists("content/c.txt"), "a file of the world is read from the folder")
	ContentSource.use_dev()
	# the old cache moves, a later session sees a complete world and downloads nothing
	var elsewhere := d + "/Autre disque"
	var moved := ContentFolder.migrate(folder, elsewhere, ["fx"], _no_space)
	eq(moved["moved"], ["fx"])
	ContentFolder.apply(elsewhere)
	var again := WorldLoader.new(client)
	again.free_space = wl.free_space
	check(again.refresh(), again.error)
	eq(again.entry("fx")["status"], "current", "moved cache is reused as is")
	eq(int(again.entry("fx")["todo_bytes"]), 0)
	check(again.launch("fx"))
	eq(ContentSource.cache_dir(), elsewhere + "/fx")
	# a folder that cannot be written is explained before anything is downloaded
	var blocked := WorldLoader.new(client)
	blocked.cache_base = d + "/Autre disque/fx/" + ContentSource.MANIFEST + "/sub" # under a file
	blocked.free_space = wl.free_space
	check(blocked.refresh(), blocked.error)
	check(not blocked.install("fx"))
	check(blocked.error.contains("dossier des mondes"), blocked.error)
	ContentSource.use_dev()
	ContentSource.set_cache_base("")
	backend.close()
	rig.host.shutdown()
	ContentFolder.remove_dir(d)
