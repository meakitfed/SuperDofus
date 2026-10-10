## Fixtures shared by the zone tests (C.02c to C.02g): a fixture world "zx" under user://test_zones/, a content server
## in this process (Rig) and the gate / streamer helpers. Not a test file itself (no test_ prefix).
class_name ZonesRig
extends TestCase

const BASE := "user://test_zones"
const CONTENT := "content/Content"

var _root := ""
var _store := ""
var _open: Array = []


class Rig:
	var host := ServerHost.new()
	var token := ""

	func _init(built: Array) -> void:
		var store := AccountStore.new(Persistence.new())
		store.iterations = 1000
		var auth := AuthService.new(store)
		host.auth = auth
		token = auth.register("bob", "secret1").token
		host.listen_http(0, "127.0.0.1")
		for b: WorldPackage.Built in built:
			publish(b)

	## C.07: the build is published into its store, which the content API serves as static files.
	func publish(b: WorldPackage.Built) -> ContentPublisher.Result:
		var r := ContentPublisher.publish_built(b, b.store)
		host.content.store = b.store
		return r

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


func _png(rel: String, shade: int) -> void:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color8(shade, 0, 0))
	DirAccess.make_dir_recursive_absolute(_root.path_join(rel).get_base_dir())
	img.save_png(_root.path_join(rel))


func _map(id: int, gfx: Array) -> void:
	var layer: Array = []
	for g in gfx:
		layer.append({"g": g, "c": 0, "t": [1, 0, 0, 1, 0, 0]})
	_write_json(CONTENT + "/Maps/%d.json" % id, {"id": id, "layers": {"background": layer}})
	_write_json("worlds/zx/maps/%d.json" % id, {"id": id, "subarea": {1: 10, 2: 10, 3: 20, 4: 30}[id], "area": 0})
	for g in gfx:
		var rel := CONTENT + "/Maps/Gfx/%d.png" % g
		if not FileAccess.file_exists(_root.path_join(rel)):
			_png(rel, g % 250)


func _table(rows: Array) -> Dictionary:
	var by_id := {}
	for r: Dictionary in rows:
		by_id[str(int(r["id"]))] = r
	return {"objectsById": by_id}


## World "zx": maps 1-2 in sub-area 10 (the start zone), map 3 in 20 (a monster lives there), map 4 in
## 30. Texture 101 is used by maps 2 and 3, 102 by maps 3 and 4. World "plain": no zone_key.
func _fixture() -> void:
	var d := ProjectSettings.globalize_path(BASE)
	ContentFolder.remove_dir(d)
	_root = d + "/game"
	_store = d + "/packages"
	_write_json("worlds/zx/world.json", {"id": "zx", "name": "Zoned", "module": "demo", "start_map": 1, "zone_key": "subarea",
			"server_only": ["worlds/zx/maps/*"], "maps": [1, 2, 3, 4]})
	_write_json("worlds/zx/monsters.json", {"subareas": {"20": {"level": 5, "area": 0, "monsters": [9]}},
			"monsters": {"9": {"grades": [{"look": "{20|30}", "drops": [{"item": 7, "pct": 10.0}]}]}}})
	_write_json("worlds/zx/npcs.json", {"maps": {"4": [{"npc": 3, "cell": 10, "dir": 1}]}})
	_write_json("worlds/plain/world.json", {"id": "plain", "name": "Plain", "maps": [1]})
	_write_json("data/spells.json", {"summons": {}})
	_write_json("data/items.json", {"items": [{"id": 7, "skin": 70}, {"id": 8, "skin": 80}]})
	_write_json("worlds/zx/shops.json", {"shops": {"1": {"items": [8]}}}) # sold by a shop: its skin is in the equipment zone (C.02g)
	_write_json("data/tables/npcs.json", _table([{"id": 3, "look": "{40|50}"}]))
	_write_json("data/tables/breeds.json", _table([{"id": 1, "maleLook": "{1|10||53}", "femaleLook": "{1|11||52}"}]))
	_write_json("data/tables/bodies.json", _table([]))
	_write_json("data/tables/heads.json", _table([]))
	_write_json("data/tables/recipes.json", _table([]))
	_map(1, [100])
	_map(2, [100, 101])
	_map(3, [101, 102])
	_map(4, [102, 103])
	_write_json(CONTENT + "/Characters/Bones/families.json", {})
	for bone in ["1", "20", "40", "666"]:
		_write_json(CONTENT + "/Characters/Bones/%s/bone.json" % bone, {"name": bone})
	for skin in [10, 11, 30, 50, 70, 80]:
		_write_json(CONTENT + "/Characters/Skins/%d/skin.json" % skin, {"textures": []})
	for t in ["bodies", "breeds", "skinslotsrules"]:
		_write_json(CONTENT + "/Data/%sdataroot.json" % t, {"objectsById": {}})
	_write(CONTENT + "/Fonts/f.ttf", PackedByteArray([1, 2, 3]))
	_write(CONTENT + "/UI/a.txt", PackedByteArray([1]))


func _zoned() -> Dictionary:
	_fixture()
	var wa := WorldAssets.new(_root, "zx")
	var z := wa.compute_zoned()
	check(wa.save(PackedStringArray(z["base"]), z) == "", "_content.json written")
	return z


func _build(force := true) -> WorldPackage.Built:
	return WorldPackage.build("zx", _root, _store, force)


func _paths(m: Dictionary) -> Array:
	return m["files"].map(func(f: Dictionary) -> String: return f["path"])


func _zone_files(z: Dictionary, id: String) -> Array:
	var out := []
	for dir: String in z["zones"][id]["files"]:
		for n: String in z["zones"][id]["files"][dir]:
			out.append(dir + "/" + n)
	return out


func _login(rig: Rig) -> String:
	rig.host.listen(0, "127.0.0.1")
	var backend := NetBackend.new()
	backend.connect_to("127.0.0.1:%d" % rig.host.local_port())
	backend.send(Protocol.register("amy", "secret2"))
	var waited := 0
	while backend.token == "" and waited < 400:
		rig.pump()
		backend.poll(0.005)
		waited += 1
	_open.append(backend) # stays connected: the token dies with the session
	return backend.token


func _end(rig: Rig) -> void:
	for b: NetBackend in _open:
		b.close()
	_open.clear()
	rig.host.shutdown()


func _enter(map_id: int, near: Dictionary = {}) -> Dictionary:
	return {"t": Protocol.MAP_ENTER, "map": {"id": map_id, "neighbors": near}, "actors": []}


func _gate(rig: Rig, dir: String, token: String) -> ZoneGate:
	var cc := rig.client()
	cc.token = token
	var g := ZoneGate.new(ZoneStreamer.new(cc, "zx", dir))
	g.threaded = false # the server lives in this process: the downloads run from run_all
	return g


## The fixture with a split player bone (families: `1-<breed>-*` bundles belong to a class, `1-combat` to all),
## two classes and their creation faces, and four maps in a big sub-area 40 (1000 bytes of texture each).
func _class_fixture(start_map := 1) -> void:
	_fixture()
	_write_json("worlds/zx/world.json", {"id": "zx", "name": "Zoned", "module": "demo", "start_map": start_map, "zone_key": "subarea",
			"server_only": ["worlds/zx/maps/*"], "maps": [1, 2, 3, 4, 5, 6, 7, 8]})
	_write_json("data/tables/breeds.json", _table([{"id": 1, "maleLook": "{1|10||53}", "femaleLook": "{1|11||52}"},
			{"id": 2, "maleLook": "{1|20||50}", "femaleLook": "{1|21||48}"}]))
	_write_json("data/tables/heads.json", _table([
			{"id": 1, "skins": "2012", "breed": 1, "gender": 0, "payable": 0, "availableAtCreation": 1},
			{"id": 2, "skins": "2022", "breed": 2, "gender": 0, "payable": 0, "availableAtCreation": 1}]))
	_write_json(CONTENT + "/Characters/Bones/families.json", {"1": {"1-1-combat": [], "1-1-static": [], "1-2-combat": [], "1-combat": [], "1-static": []}})
	for bundle in ["1-1-combat", "1-1-static", "1-2-combat", "1-combat", "1-static"]:
		_write_json(CONTENT + "/Characters/Bones/%s/bone.json" % bundle, {"name": bundle})
	for skin in [2012, 2022, 20, 21]:
		_write_json(CONTENT + "/Characters/Skins/%d/skin.json" % skin, {"textures": []})
	for i in 4: # sub-area 40: maps 5..8 side by side (x = 3..0), a texture of 1000 bytes of their own
		var id := 5 + i
		_write_json(CONTENT + "/Maps/%d.json" % id, {"id": id, "layers": {"background": [{"g": 200 + i, "c": 0, "t": [1, 0, 0, 1, 0, 0]}]}})
		_write_json("worlds/zx/maps/%d.json" % id, {"id": id, "subarea": 40, "area": 0, "world_map": 1, "coords": [3 - i, 0]})
		var b := PackedByteArray()
		b.resize(1000)
		_write(CONTENT + "/Maps/Gfx/%d.png" % (200 + i), b)


func _class_zoned(max_bytes := 2500, start_map := 1) -> Dictionary:
	_class_fixture(start_map)
	var wa := WorldAssets.new(_root, "zx")
	wa.zone_max_bytes = max_bytes
	var z := wa.compute_zoned()
	check(wa.save(PackedStringArray(z["base"]), z) == "", "_content.json written")
	return z


func _monster_zoned() -> Dictionary:
	_class_fixture()
	var ids := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
	_write_json("worlds/zx/world.json", {"id": "zx", "name": "Zoned", "module": "demo", "start_map": 1, "zone_key": "subarea",
			"server_only": ["worlds/zx/maps/*"], "maps": ids})
	_write_json("worlds/zx/monsters.json", {"subareas": {"20": {"level": 5, "area": 0, "monsters": [9]}, "50": {"level": 9, "area": 0, "monsters": [11]}},
			"monsters": {"9": {"grades": [{"look": "{20|30}", "drops": [{"item": 7, "pct": 10.0}]}]},
			"11": {"grades": [{"look": "{60}", "drops": []}]}}})
	for i in 4: # sub-area 50: maps 9..12, a texture of 300 bytes each
		var id := 9 + i
		_write_json(CONTENT + "/Maps/%d.json" % id, {"id": id, "layers": {"background": [{"g": 300 + i, "c": 0, "t": [1, 0, 0, 1, 0, 0]}]}})
		_write_json("worlds/zx/maps/%d.json" % id, {"id": id, "subarea": 50, "area": 0, "world_map": 1, "coords": [10 + i, 0]})
		var t := PackedByteArray()
		t.resize(300)
		_write(CONTENT + "/Maps/Gfx/%d.png" % (300 + i), t)
	var heavy := PackedByteArray() # the monsters of sub-area 50 weigh more than its maps
	heavy.resize(3000)
	_write(CONTENT + "/Characters/Bones/60/bone.json", heavy)
	var wa := WorldAssets.new(_root, "zx")
	wa.zone_max_bytes = 2500
	var z := wa.compute_zoned()
	check(wa.save(PackedStringArray(z["base"]), z) == "", "_content.json written")
	return z


func _common_zoned() -> Dictionary:
	_class_fixture()
	_write_json("worlds/zx/world.json", {"id": "zx", "name": "Zoned", "module": "demo", "start_map": 1, "zone_key": "subarea",
			"server_only": ["worlds/zx/maps/*"], "maps": [1, 2, 3, 4, 5, 6, 7, 8, 13, 14, 15, 16]})
	_write_json("data/tables/npcs.json", _table([{"id": 3, "look": "{40|50}"}, {"id": 4, "look": "{61}"}]))
	var on_maps := {}
	for i in 4: # sub-area 60: four maps with the same heavy NPC (3000 bytes), a texture of 10 bytes each
		var id := 13 + i
		_write_json(CONTENT + "/Maps/%d.json" % id, {"id": id, "layers": {"background": [{"g": 400 + i, "c": 0, "t": [1, 0, 0, 1, 0, 0]}]}})
		_write_json("worlds/zx/maps/%d.json" % id, {"id": id, "subarea": 60, "area": 0, "world_map": 1, "coords": [20 + i, 0]})
		var t := PackedByteArray()
		t.resize(10)
		_write(CONTENT + "/Maps/Gfx/%d.png" % (400 + i), t)
		on_maps[str(id)] = [{"npc": 4, "cell": 10, "dir": 1}]
	_write_json("worlds/zx/npcs.json", {"maps": on_maps})
	var heavy := PackedByteArray()
	heavy.resize(3000)
	_write(CONTENT + "/Characters/Bones/61/bone.json", heavy)
	var wa := WorldAssets.new(_root, "zx")
	wa.zone_max_bytes = 2500
	var z := wa.compute_zoned()
	check(wa.save(PackedStringArray(z["base"]), z) == "", "_content.json written")
	return z
