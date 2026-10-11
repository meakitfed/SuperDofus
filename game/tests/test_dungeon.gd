## Dungeon rules (roadmap P4.01): rooms, entry, keys, composition (Bouftou Royal).
extends TestCase

const DEF := {
	"id": 1, "name": "Bouftou Royal", "level": 30, "min_level": 20, "difficulty": 1,
	"maps": [121373185, 121374209, 121375233, 121373187, 121374211],
	"entrance_map": 120063489, "exit_map": 120063489,
	"keys": [{"item": 1568, "qty": 1}], "bosses": [147],
}


func _pool() -> Array:
	var out := []
	for id in [101, 102, 103]:
		var gr := []
		for g in 5:
			gr.append({"look": "{%d}" % id, "name": "m%d" % id, "level": 5 + g * 10, "hp": 10})
		out.append({"id": id, "grades": gr})
	out.append({"id": 147, "grades": [{"level": 10}, {"level": 30}, {"level": 50}]})
	return out


func test_rooms() -> void:
	eq(Dungeon.room_count(DEF), 5)
	eq(Dungeon.room_map(DEF, 0), 121373185)
	eq(Dungeon.room_map(DEF, 4), 121374211)
	eq(Dungeon.room_map(DEF, 5), -1)
	eq(Dungeon.room_map(DEF, -1), -1)
	eq(Dungeon.room_index(DEF, 121375233), 2)
	eq(Dungeon.room_index(DEF, 1), -1)
	check(Dungeon.is_last(DEF, 4) and not Dungeon.is_last(DEF, 3))
	eq(Dungeon.next_room(DEF, 0), 1)
	eq(Dungeon.next_room(DEF, 4), -1)
	eq(Dungeon.boss_room(DEF), 4)
	check(Dungeon.has_boss(DEF, 4) and not Dungeon.has_boss(DEF, 2))
	check(Dungeon.room_cleared(0) and not Dungeon.room_cleared(2))


func test_entry() -> void:
	eq(Dungeon.check_entry(DEF, 19, {1568: 1}), "level")
	eq(Dungeon.check_entry(DEF, 20, {}), "key")
	eq(Dungeon.check_entry(DEF, 20, {1568: 0}), "key")
	eq(Dungeon.check_entry(DEF, 20, {"1568": 1}), "")
	eq(Dungeon.check_entry(DEF, 50, {1568: 3}), "")
	eq(Dungeon.keys_to_consume(DEF), [{"item": 1568, "qty": 1}])


func test_compose() -> void:
	var pool := _pool()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var a := Dungeon.compose_room(DEF, 0, rng, pool)
	check(a.size() >= 2 and a.size() <= 3, "groups")
	for g: Dictionary in a:
		check(not (g["members"] as Array).is_empty())
		for m: Dictionary in g["members"]:
			check(m.has("monster") and m.has("grade") and m.has("level"))
	rng.seed = 7
	eq(Dungeon.compose_room(DEF, 0, rng, pool), a, "deterministic")
	var boss := Dungeon.compose_room(DEF, 4, rng, pool)
	eq(boss.size(), 1)
	var first: Dictionary = boss[0]["members"][0]
	eq(int(first["monster"]), 147)
	eq(int(first["grade"]), 2, "grade closest to level 30")
	check((boss[0]["members"] as Array).size() >= 2, "escort")
	eq(Dungeon.compose_room(DEF, 9, rng, pool), [])
	eq(Dungeon.compose_room(DEF, 0, rng, []), [])
