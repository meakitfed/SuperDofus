## P4.01a: dungeon data (worlds/<id>/dungeons.json) and bosses (monsters.json `bosses`) read through WorldSource.
extends TestCase


func test_royal_bouftou_dungeon() -> void:
	var src := JsonWorldSource.for_world("dofus")
	check(src.get_dungeons().size() > 100, "dungeons loaded")
	var d := src.get_dungeon(1)
	eq(str(d["name"]), "Cour du Bouftou Royal")
	eq(int(d["entrance_map"]), 120063489)
	eq(int(d["exit_map"]), 120063489)
	eq((d["maps"] as Array).map(func(m: Variant) -> int: return int(m)), [121373185, 121374209, 121375233, 121373187, 121374211])
	eq(d["keys"].size(), 1)
	eq(int(d["keys"][0]["item"]), 1568)
	eq(int(d["keys"][0]["qty"]), 1)
	eq((d["bosses"] as Array).map(func(m: Variant) -> int: return int(m)), [147])
	var boss := src.get_boss(147)
	check(not boss.is_empty() and not (boss["grades"] as Array).is_empty(), "boss 147 resolvable")
	check(int(boss["grades"][0]["hp"]) > 0, "boss has hp")


func test_boss_not_in_spawn_pools() -> void:
	var src := JsonWorldSource.for_world("dofus")
	for sid: Variant in src.get_monsters()["subareas"]:
		check(not (src.get_monsters()["subareas"][sid]["monsters"] as Array).has(147), "147 not in pool " + str(sid))


func test_other_worlds_empty() -> void:
	eq(JsonWorldSource.for_world("incarnam").get_dungeons().size(), 0)
	eq(JsonWorldSource.for_world("test").get_dungeon(1), {})
