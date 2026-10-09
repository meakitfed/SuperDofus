## Regression (C.02): a world downloaded from a server (cache with a manifest) must not hide the
## world's files in solo play: the cache holds no maps (server_only), so the sim found none
## ("no_start_map", an empty grey screen). A standalone ClientSession reads res://.
extends TestCase

const BASE := "user://test_solo_cache"


func test_a_standalone_session_ignores_the_cache_of_its_world() -> void:
	var dir := ProjectSettings.globalize_path(BASE + "/duo")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir + "/manifest.json", FileAccess.WRITE)
	f.store_string("{}")
	f.close()
	ContentSource.set_cache_base(BASE)
	ContentSource.use_world("duo")
	check(ContentSource.using_cache(), "the cache is ready (the situation of a player who joined a server)")
	var b := LocalBackend.new()
	b.server = LocalServer.new()
	var s := ClientSession.new()
	s.world_id = "duo"
	s.player_name = "Solo"
	s.persistent = false
	s.backend = b
	var tree := Engine.get_meta("test_tree") as SceneTree
	tree.root.add_child(s)
	check(not ContentSource.using_cache(), "solo: res://, not the cache")
	s.backend = null
	tree.root.remove_child(s)
	s.free()
	ContentSource.use_dev()
	ContentSource.set_cache_base("")
	DirAccess.remove_absolute(dir + "/manifest.json")
	DirAccess.remove_absolute(dir)
