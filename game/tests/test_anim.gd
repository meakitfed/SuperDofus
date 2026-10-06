extends TestCase


func _anims(names: Array) -> Dictionary:
	var d := {}
	for n: String in names:
		d[n] = "bone"
	return d


func test_resolve_direct_and_mirror() -> void:
	var anims := _anims(["AnimMarche_1", "AnimMarche_2", "AnimStatique_1"])
	eq(DofusAnimNames.resolve(anims, 1, 5, "AnimMarche"), ["AnimMarche_1", false])
	eq(DofusAnimNames.resolve(anims, 3, 5, "AnimMarche"), ["AnimMarche_1", true], "3 mirrors 1")
	check(DofusAnimNames.resolve(anims, 6, 5, "AnimMarche")[0] != "", "up falls back to the nearest direction")
	eq(DofusAnimNames.resolve(anims, 3, 5, "AnimCourse"), ["", false], "unknown base")


func test_monster_diagonals_only() -> void:
	# typical monster: only 1 and 5 exist, and an artwork clip that must never be picked
	var anims := _anims(["AnimArtwork_1", "AnimStatique_5", "AnimStatique_1"])
	eq(DofusAnimNames.resolve(anims, 0, 42, "AnimStatique"), ["AnimStatique_1", false], "east -> south-east")
	eq(DofusAnimNames.resolve(anims, 4, 42, "AnimStatique")[0], "AnimStatique_1", "west -> mirrored south-east")
	check(DofusAnimNames.resolve(anims, 4, 42, "AnimStatique")[1], "west is mirrored")
	eq(DofusAnimNames.resolve(anims, 6, 42, "AnimStatique")[0], "AnimStatique_5", "north -> north-west/east")
	eq(DofusAnimNames.resolve(anims, 0, 42, "AnimMarche")[0], "", "missing base stays missing")
	check(not DofusAnimNames.resolve(anims, 0, 42)[0].begins_with("AnimArtwork"), "artwork never used as idle")


func test_default_base_per_bone() -> void:
	var anims := _anims(["AnimStatiqueExplo0_1", "AnimStatique_1"])
	eq(DofusAnimNames.resolve(anims, 1, 1)[0], "AnimStatiqueExplo0_1")
	eq(DofusAnimNames.resolve(anims, 1, 42)[0], "AnimStatique_1")


func test_related_child_anim() -> void:
	var pet := _anims(["AnimMarche_1", "AnimStatique_1", "AnimStatique_5"])
	eq(DofusAnimNames.related_child_anim(pet, "AnimMarche_1"), ["AnimMarche_1", false])
	eq(DofusAnimNames.related_child_anim(pet, "AnimStatiqueExplo0_1"), ["AnimStatique_1", false], "Explo stripped")
	eq(DofusAnimNames.related_child_anim(pet, "AnimMarche_3"), ["AnimMarche_1", true], "falls back to the mirror")
	eq(DofusAnimNames.related_child_anim(pet, "AnimAttaque0_5"), ["AnimStatique_5", false])


func test_directions_by_anim() -> void:
	var d := DofusAnimNames.directions_by_anim(["AnimMarche_1", "AnimMarche_2", "FX"])
	eq(d["AnimMarche"], [1, 2, 3])
	check(not d.has("FX"))


func test_iso_facing_matches_dofus_directions() -> void:
	eq(IsoGrid.facing_for_cell_delta(Vector2i(1, -1)), DofusAnimNames.Direction.RIGHT)
	eq(IsoGrid.facing_for_cell_delta(Vector2i(1, 0)), DofusAnimNames.Direction.DOWN_RIGHT)
	eq(IsoGrid.facing_for_cell_delta(Vector2i(1, 1)), DofusAnimNames.Direction.DOWN)
	eq(IsoGrid.facing_for_cell_delta(Vector2i(0, 1)), DofusAnimNames.Direction.DOWN_LEFT)
	eq(IsoGrid.facing_for_cell_delta(Vector2i(-1, -1)), DofusAnimNames.Direction.UP)


func test_iso_roundtrip() -> void:
	for c in [Vector2i(0, 0), Vector2i(3, 7), Vector2i(12, 2)]:
		eq(IsoGrid.world_to_cell(IsoGrid.cell_to_world(Vector2(c))), c)


func test_entity_walks_path() -> void:
	var e := GameEntity.new(1, "{1|10||100}", Vector2i(0, 0))
	var states: Array = []
	e.state_changed.connect(func(s: GameEntity.State, _f: GameEntity.Facing) -> void: states.append(s))
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	e.follow_path(path)
	eq(e.state, GameEntity.State.MOVE)
	eq(e.facing, GameEntity.Facing.SOUTH_EAST)
	for i in 100:
		e.tick(0.05)
	eq(e.cell, Vector2i(2, 0))
	eq(e.state, GameEntity.State.IDLE)
	eq(states.front(), GameEntity.State.MOVE)
