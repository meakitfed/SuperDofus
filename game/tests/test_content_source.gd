## ContentSource (C.01): one layer reads the data and the assets, from res:// (dev, solo) or
## from a cache downloaded from a server (user://worlds/<id>/), and the renderer reads through it.
extends TestCase

const BASE := "user://test_content_cache"
const WORLD := "unit"


func _cache() -> String:
	return ContentSource.cache_dir_for(WORLD, BASE)


func _put(rel: String, bytes: PackedByteArray) -> void:
	var path := _cache().path_join(rel)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


func _wipe(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for d in DirAccess.get_directories_at(path):
		_wipe(path.path_join(d))
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)


## A cache holding raw copies of real dev files (what C.02 will download).
func _build_cache() -> void:
	ContentSource.use_dev()
	_wipe(BASE)
	_put("manifest.json", "{}".to_utf8_buffer())
	_put("data/experience.json", ContentSource.read_bytes("data/experience.json"))
	_put("data/tables/breeds.json", ContentSource.read_bytes("data/tables/breeds.json"))
	_put("world/world.json", ContentSource.read_bytes("worlds/test/world.json"))
	_put("content/Content/Data/things.json", '{"a": 1}'.to_utf8_buffer())
	_put("mods/mods.json", '{"enabled": ["m"]}'.to_utf8_buffer())
	_put("mods/m/Content/Data/things.json", '{"a": 2}'.to_utf8_buffer())
	_put("mods/m/Content/Data/only_mod.json", '{"b": 3}'.to_utf8_buffer())
	var img := Image.create_empty(4, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	_put("content/Content/Picto/red.png", img.save_png_to_buffer())
	_put("content/Content/Picto/blue.webp", img.save_webp_to_buffer(true))


func _finish() -> void:
	ContentSource.use_dev()
	_wipe(BASE)


func test_dev_root_is_the_default_and_resolves_like_res() -> void:
	ContentSource.use_dev()
	check(not ContentSource.using_cache())
	check(ContentSource.exists("data/experience.json"))
	eq(ContentSource.resolve("res://tests/fixtures/spells.json"), "res://tests/fixtures/spells.json", "a scheme = a physical path")
	eq(ContentSource.dev_path("worlds/test"), "res://worlds/test")
	check(ContentSource.read_json("data/experience.json") is Dictionary)


func test_a_world_without_cache_falls_back_to_the_dev_root() -> void:
	ContentSource.use_world(WORLD, BASE) # nothing downloaded
	check(not ContentSource.using_cache(), "no manifest: dev root")
	check(ContentSource.exists("data/experience.json"))
	eq(ContentSource.world(), WORLD)
	ContentSource.use_dev()


func test_cache_and_dev_read_the_same_bytes() -> void:
	_build_cache()
	var dev := {}
	for p in ["data/experience.json", "data/tables/breeds.json"]:
		dev[p] = ContentSource.read_bytes(p)
		check(dev[p].size() > 0, p)
	dev["world.json"] = ContentSource.read_bytes("worlds/test/world.json")
	ContentSource.use_world(WORLD, BASE)
	check(ContentSource.using_cache())
	for p: String in ["data/experience.json", "data/tables/breeds.json"]:
		eq(ContentSource.read_bytes(p), dev[p], "same bytes from the cache: " + p)
	eq(ContentSource.read_bytes("worlds/%s/world.json" % WORLD), dev["world.json"], "the world definition")
	eq(ContentSource.resolve("worlds/%s/world.json" % WORLD), _cache() + "/world/world.json")
	ContentSource.use_world("test", BASE) # another world, no cache: dev again
	check(not ContentSource.using_cache())
	_finish()


func test_the_cache_answers_alone() -> void:
	_build_cache()
	ContentSource.use_world(WORLD, BASE)
	check(not ContentSource.exists("data/spells.json"), "a file the cache lacks is missing, not read from res://")
	check(not ContentSource.exists("worlds/dofus/world.json"), "another world is not in this package")
	eq(ContentSource.read_json("content/Content/Data/things.json"), {"a": 1.0})
	eq(ContentSource.list_dirs("mods"), PackedStringArray(["m"]))
	_finish()


func test_missing_file_is_a_clear_error() -> void:
	ContentSource.use_dev()
	var r := ContentSource.read_result("data/does_not_exist.json")
	check(not bool(r["ok"]))
	check(str(r["error"]).contains("data/does_not_exist.json") and str(r["error"]).contains("not found"), str(r["error"]))
	eq(ContentSource.read_json("data/does_not_exist.json"), null)
	eq(ContentSource.read_bytes("data/does_not_exist.json").size(), 0)
	check(ContentSource.load_image("content/Nope/none") == null)
	check(ContentSource.read_result("data/experience.json")["ok"])


func test_images_load_raw_from_the_cache() -> void:
	_build_cache()
	ContentSource.use_world(WORLD, BASE)
	var png := ContentSource.load_image("content/Content/Picto/red")
	check(png != null and png.get_size() == Vector2i(4, 2), "png")
	check(ContentSource.load_image("content/Content/Picto/blue") != null, "webp")
	var tex := ContentSource.load_texture("content/Content/Picto/red")
	check(tex != null and tex.get_width() == 4)
	check(ContentSource.load_resource("content/Content/Picto/red.png") is Texture2D)
	_finish()


func test_data_tables_follow_the_active_world() -> void:
	_build_cache()
	GameData.clear_cache()
	var xp_dev := GameData.xp_floor(10)
	ContentSource.use_world(WORLD, BASE)
	eq(GameData.xp_floor(10), xp_dev, "same experience table from the cache")
	eq(GameData.table("breeds").size(), 19, "tables read from the cache")
	ContentSource.use_dev()
	eq(GameData.table("breeds").size(), 19)
	_finish()


func test_the_renderer_provider_reads_the_cache_and_its_mods() -> void:
	_build_cache()
	ContentSource.use_world(WORLD, BASE)
	var p := ContentSourceProvider.new()
	eq(p.read_json("Content/Data/things.json"), {"a": 2.0}, "an enabled mod overlays content/")
	eq(p.read_json("Content/Data/only_mod.json"), {"b": 3.0})
	check(p.exists("Content/Picto/red.png"))
	check(p.load_image("Content/Picto/red") != null)
	check(p.load_image("Content/Picto/missing") == null)
	check(not p.exists("Content/Characters/Bones/1/bone.json"), "nothing from res://content")
	_finish()
	var dev := ContentSourceProvider.new()
	check(not dev.exists("Content/Data/only_mod.json"), "dev root: no such mod file")


func test_the_renderer_asks_the_game_for_its_provider() -> void:
	eq(str(ProjectSettings.get_setting(DofusContent.SETTING_PROVIDER, "")), "res://src/client/content_provider.gd")
	check(DofusContent.get_provider() is ContentSourceProvider)
