## Selection of the assets a world uses (roadmap C.02b): WorldAssets computes the globs of a tiny
## fixture world from its maps, monsters, NPCs, summons, bodies and items, WorldPackage ships exactly
## those files, and a client that downloaded the package from a server (login over a WebSocket on
## 127.0.0.1, content over HTTP) reads everything the renderer asks for from its cache alone.
extends TestCase

const BASE := "user://test_world_assets"
const CONTENT := "content/Content"

var _root := ""


class Rig:
	var host := ServerHost.new()
	var token := ""

	func _init(built: WorldPackage.Built) -> void:
		var store := AccountStore.new(Persistence.new())
		store.iterations = 1000
		var auth := AuthService.new(store)
		host.auth = auth
		token = auth.register("bob", "secret1").token
		host.listen_http(0, "127.0.0.1")
		host.content.set_package(built)

	func pump() -> void:
		host.poll(0.005)
		OS.delay_msec(1)

	func client() -> ContentClient:
		var c := ContentClient.new("127.0.0.1", host.http_port(), token)
		c.pump = pump
		return c


func _write_json(rel: String, data: Variant) -> void:
	_write(rel, JSON.stringify(data).to_utf8_buffer())


func _write(rel: String, data: PackedByteArray) -> void:
	var path := _root.path_join(rel)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(data)
	f.close()


func _png(rel: String) -> void:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	DirAccess.make_dir_recursive_absolute(_root.path_join(rel).get_base_dir())
	img.save_png(_root.path_join(rel))


func _rm(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_rm(dir.path_join(d))
	DirAccess.remove_absolute(dir)


func _table(rows: Array) -> Dictionary:
	var by_id := {}
	for r: Dictionary in rows:
		by_id[str(int(r["id"]))] = r
	return {"objectsById": by_id}


## A world "fx" with two maps (one missing from content/), and unrelated assets that must stay out.
func _fixture() -> void:
	_root = ProjectSettings.globalize_path(BASE).path_join("game")
	_rm(ProjectSettings.globalize_path(BASE))
	_write_json("worlds/fx/world.json", {"id": "fx", "name": "Fixture", "maps": [1, 2]})
	_write_json("worlds/fx/monsters.json", {"subareas": {}, "monsters": {"9": {"grades": [
			{"look": "{20|30,31||100|2@0={21|32}}", "drops": [{"item": 7, "pct": 10.0}]}]}}})
	_write_json("worlds/fx/npcs.json", {"maps": {"1": [{"npc": 3, "cell": 10, "dir": 1}, {"npc": 4, "cell": 11, "dir": 1, "look": "{41}"}]}})
	_write_json("worlds/fx/shops.json", {"shops": {"3": {"items": [8]}}})
	_write_json("worlds/fx/quests.json", {"quests": {"1": {"steps": [{"rewards": [{"items": [[10, 1]]}]}]}}})
	_write_json("data/spells.json", {"summons": {"5": {"look": "{60|61}"}}})
	_write_json("data/items.json", {"items": [{"id": 7, "skin": 70}, {"id": 8, "skin": 80}, {"id": 10, "skin": 100},
			{"id": 11, "skin": 110}, {"id": 12, "skin": 0}]})
	_write_json("data/tables/npcs.json", _table([{"id": 3, "look": "{40|50}"}]))
	_write_json("data/tables/breeds.json", _table([{"id": 1, "maleLook": "{1|10||53}", "femaleLook": "{1|11||52}"}]))
	_write_json("data/tables/bodies.json", _table([{"id": 1, "skins": "10", "breed": 1, "gender": 0, "availableAtCreation": 1, "payable": 0},
			{"id": 2, "skins": "900", "breed": 1, "gender": 0, "availableAtCreation": 0, "payable": 0}]))
	_write_json("data/tables/heads.json", _table([{"id": 1, "skins": "12", "breed": 1, "gender": 0, "availableAtCreation": 1, "payable": 0}]))
	_write_json("data/tables/recipes.json", _table([{"id": 1, "resultId": 11}]))
	_write_json(CONTENT + "/Maps/1.json", {"id": 1, "bg": 0, "layers": {
			"background": [{"g": 100, "c": 0, "t": [1, 0, 0, 1, 0, 0]}],
			"sortable": [{"g": 101, "c": 0, "t": [1, 0, 0, 1, 0, 0], "cell": 1, "o": 0}],
			"foreground": [{"g": 102, "c": 0, "t": [1, 0, 0, 1, 0, 0]}]},
			"animated": [{"g": 5, "c": 0, "t": [1, 0, 0, 1, 0, 0], "cell": 2, "o": 0}]})
	_png(CONTENT + "/Maps/Gfx/100.png")
	_png(CONTENT + "/Maps/Gfx/101.webp.png") # not the right name: stays out
	_png(CONTENT + "/Maps/Gfx/101.png")
	_png(CONTENT + "/Maps/Gfx/102.png")
	_png(CONTENT + "/Maps/Gfx/999.png") # an unrelated texture
	_write_json(CONTENT + "/Animations/Props/5/bone.json", {"name": "5"})
	_write_json(CONTENT + "/Animations/Props/6/bone.json", {"name": "6"}) # another map's prop
	_write_json(CONTENT + "/Characters/Bones/families.json", {"1": {"1-static": ["a"], "1-12-combat": ["b"]}})
	for bone in ["1-static", "1-12-combat", "20", "21", "41", "40", "60", "666", "99"]:
		_write_json(CONTENT + "/Characters/Bones/%s/bone.json" % bone, {"name": bone})
	for skin in [10, 12, 30, 31, 32, 50, 61, 70, 80, 100, 110, 900, 999]:
		_write_json(CONTENT + "/Characters/Skins/%d/skin.json" % skin, {"textures": []})
	_write_json(CONTENT + "/Data/bodiesdataroot.json", {"objectsById": {}})
	_write_json(CONTENT + "/Data/breedsdataroot.json", {"objectsById": {}})
	_write_json(CONTENT + "/Data/skinslotsrulesdataroot.json", {"objectsById": {}})
	_write_json(CONTENT + "/Data/quests.json", {}) # a heavy raw table nobody reads
	_png(CONTENT + "/UI/darkStone/texture/a.png")
	_write(CONTENT + "/Fonts/f.ttf", PackedByteArray([1, 2, 3]))
	_write(CONTENT + "/I18n/fr.bin", PackedByteArray([1]))
	_png(CONTENT + "/Picto/Spells/1.png")
	_png(CONTENT + "/Picto/Items/1.png")
	_png(CONTENT + "/Picto/Monsters/1.png")
	_png(CONTENT + "/Worldmaps/1/1/1.png")


func _compute() -> WorldAssets:
	_fixture()
	return WorldAssets.new(_root, "fx")


func test_globs_cover_what_the_world_uses_and_nothing_else() -> void:
	var wa := _compute()
	var globs := wa.compute()
	var has := func(g: String) -> bool: return globs.has(g)
	for g in [CONTENT + "/Maps/1.json", CONTENT + "/Maps/Gfx/100.png", CONTENT + "/Maps/Gfx/101.png", CONTENT + "/Maps/Gfx/102.png",
			CONTENT + "/Animations/Props/5/*", CONTENT + "/Characters/Bones/20/*", CONTENT + "/Characters/Bones/21/*",
			CONTENT + "/Characters/Bones/40/*", CONTENT + "/Characters/Bones/41/*", CONTENT + "/Characters/Bones/60/*",
			CONTENT + "/Characters/Bones/666/*", CONTENT + "/Characters/Bones/families.json",
			CONTENT + "/Data/bodiesdataroot.json", CONTENT + "/Fonts/*", CONTENT + "/UI/*", CONTENT + "/I18n/*", CONTENT + "/Picto/Spells/*"]:
		check(has.call(g), "selected: " + g)
	for s in [10, 12, 30, 31, 32, 50, 61, 70, 80, 100, 110]:
		check(has.call(CONTENT + "/Characters/Skins/%d/*" % s), "skin %d (look, body, face, item)" % s)
	for g in [CONTENT + "/Maps/Gfx/999.png", CONTENT + "/Maps/Gfx/101.webp.png", CONTENT + "/Animations/Props/6/*",
			CONTENT + "/Characters/Bones/99/*", CONTENT + "/Characters/Skins/900/*", CONTENT + "/Characters/Skins/999/*",
			CONTENT + "/Data/quests.json"]:
		check(not has.call(g), "left out: " + g)
	check(has.call(CONTENT + "/Characters/Bones/1-static/*") and has.call(CONTENT + "/Characters/Bones/1-12-combat/*"),
			"a split bone brings every bundle of its family")
	eq(int(wa.stats["maps"]), 1, "one map found")
	check(wa.missing.has(CONTENT + "/Maps/2.json"), "a map absent from content/ is reported, not fatal")
	check(wa.size_of(globs) > 0, "size")


func test_package_holds_exactly_the_selected_files() -> void:
	var wa := _compute()
	var globs := wa.compute()
	wa.save(globs)
	var store := ProjectSettings.globalize_path(BASE).path_join("packages")
	var b := WorldPackage.build("fx", _root, store)
	check(b.ok, b.error)
	var paths: Array = b.manifest["files"].map(func(f: Dictionary) -> String: return f["path"])
	check(paths.has(CONTENT + "/Maps/Gfx/100.png"), "the selected texture ships")
	check(paths.has(CONTENT + "/Characters/Bones/1-12-combat/bone.json"), "folder glob: its files ship")
	check(paths.has(CONTENT + "/Picto/Items/1.png"), "base folder ships")
	check(not paths.has(CONTENT + "/Maps/Gfx/999.png"), "unrelated texture stays out")
	check(not paths.has(CONTENT + "/Characters/Skins/999/skin.json"), "unrelated skin stays out")
	check(not paths.has(CONTENT + "/Data/quests.json"), "unread raw table stays out")
	check(not paths.has("worlds/fx/" + WorldAssets.FILE), "the list itself is a build file, not shipped")
	check(paths.has("worlds/fx/world.json") and paths.has("data/items.json"), "world and data still ship")
	eq(wa.uncovered(globs, PackedStringArray([CONTENT + "/Maps/Gfx/999.png", CONTENT + "/Maps/Gfx/100.png",
			CONTENT + "/Maps/Gfx/none.png", "data/items.json", "worlds/fx/x.json"])),
			PackedStringArray([CONTENT + "/Maps/Gfx/999.png"]), "a trace read outside the package is reported (probes and data are not)")


func test_client_plays_from_the_cache_alone() -> void:
	var wa := _compute()
	wa.save(wa.compute())
	var b := WorldPackage.build("fx", _root, ProjectSettings.globalize_path(BASE).path_join("packages"))
	check(b.ok, b.error)
	var rig := Rig.new(b)
	rig.host.listen(0, "127.0.0.1")
	# the token comes from a real login over the WebSocket (NetBackend, 127.0.0.1)
	var backend := NetBackend.new()
	backend.connect_to("127.0.0.1:%d" % rig.host.local_port())
	backend.send(Protocol.register("amy", "secret2"))
	var waited := 0
	while backend.token == "" and waited < 400:
		rig.pump()
		backend.poll(0.005)
		waited += 1
	check(backend.token != "", "login_ok gave a token")
	var cc := rig.client()
	cc.token = backend.token
	var cache := ProjectSettings.globalize_path(BASE).path_join("cache")
	var r := cc.update("fx", cache.path_join("fx"))
	check(r.ok, r.error)
	ContentSource.use_world("fx", cache)
	check(ContentSource.using_cache(), "the cache answers")
	# what the renderer reads for this world, through its provider, with no res:// fallback
	var provider := ContentSourceProvider.new()
	var look := DofusLook.parse("{20|30,31||100|2@0={21|32}}")
	var needed: Array[String] = ["Maps/1.json", "Animations/Props/5/bone.json", "Characters/Bones/20/bone.json",
			"Characters/Bones/21/bone.json", "Characters/Bones/40/bone.json", "Characters/Bones/1-12-combat/bone.json",
			"Characters/Skins/32/skin.json", "Characters/Skins/70/skin.json", "Data/breedsdataroot.json", "Fonts/f.ttf", "I18n/fr.bin"]
	for rel in needed:
		check(provider.exists("Content/" + rel), "in the cache: " + rel)
	for g in [100, 101, 102]:
		check(provider.load_image("Content/Maps/Gfx/%d" % g) != null, "texture %d decodes from the cache" % g)
	check(provider.load_image("Content/Maps/Gfx/999") == null, "an unrelated texture was not downloaded")
	check(provider.load_image("Content/Picto/Spells/1") != null, "spell picto")
	eq(look.bone, 20)
	ContentSource.use_dev()
	backend.close()
	rig.host.shutdown()
