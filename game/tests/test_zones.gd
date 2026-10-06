## Zone shapes (roadmap P1.13e, P1.13g): the letters are named by the client enum
## Metadata.Enums.SpellZoneShape (docs/client_enums.md), FightRules.zone draws them as the
## client's native classes SpellZoneShape*Behavior do (P1.13g). Offsets are our iso coords.
extends TestCase

const O := 300 # a cell in the middle of the map


func _init() -> void:
	SpellBook.use_file("")


func at(dx: int, dy: int) -> int:
	return MapGeometry.from_iso(MapGeometry.to_iso(O) + Vector2i(dx, dy))


## cells of `shape` / `size` cast from (fx, fy) on (cx, cy), sorted
func cells(shape: String, size: int, cx: int, cy: int, fx := 0, fy := 0, extra := {}) -> Array:
	var a := {"shape": shape, "size": size}
	a.merge(extra)
	var out: Array = Array(FightRules.zone(a, at(cx, cy), at(fx, fy)))
	out.sort()
	return out


func sorted(list: Array) -> Array:
	var out := list.duplicate()
	out.sort()
	return out


func test_the_extracted_letters() -> void:
	var fracture: Dictionary = SpellBook.get_spell(1041349) # Xélor "Fracture": l, param1 1, param2 63
	var area: Dictionary = fracture["area"]
	eq([str(area["shape"]), int(area["size"]), int(area["max"]), area.get("stop")], ["from_caster", 1, 63, true])
	var toison: Dictionary = SpellBook.get_spell(1082254)["effects"][1]["area"]
	eq([str(toison["shape"]), int(toison["size"]), int(toison["min"])], ["circle", 2, 1], "Toison d'Or: C param2 = minimum")
	var epieu: Dictionary = SpellBook.get_spell(1060543)["area"]
	eq([str(epieu["shape"]), int(epieu["size"]), int(epieu["length"])], ["rectangle", 1, 3], "Épieu Sismique: R")
	eq(str(SpellBook.get_spell(1041904)["area"]["shape"]), "half_circle", "Dagues Boomerang: U = HalfCircle")
	eq(str(SpellBook.get_spell(1042785)["area"]["shape"]), "fork", "Foène: F = Fork")
	eq(str(SpellBook.get_spell(1044428)["area"]["shape"]), "cone", "Faisceau: V = Cone")
	eq(str(SpellBook.get_spell(1041910)["area"]["shape"]), "diagonal_tline", "Espingole: - = DiagonalPerpendicularLine")


func test_a_perpendicular_line_is_not_a_cross() -> void:
	eq(cells("tline", 1, 2, 0), sorted([at(2, 0), at(2, -1), at(2, 1)]), "T = PerpendicularLine (a cross before P1.13e)")
	eq(cells("cross", 1, 2, 0).size(), 5)


func test_diagonal_crosses() -> void:
	var diag := [at(3, 1), at(3, -1), at(1, 1), at(1, -1)]
	eq(cells("diagonal_cross", 1, 2, 0), sorted(diag + [at(2, 0)]), "+ = DiagonalCross (the star before P1.13e)")
	eq(cells("diagonal_cross_ring", 1, 2, 0), sorted(diag), "# = DiagonalCrossWithoutCenter (a square before P1.13e)")


func test_a_line_from_the_caster() -> void:
	eq(cells("from_caster", 1, 4, 0, 0, 0, {"max": 63, "stop": true}), sorted([at(1, 0), at(2, 0), at(3, 0), at(4, 0)]),
			"isStopAtTarget: up to the target")
	eq(cells("from_caster", 1, 4, 0, 0, 0, {"max": 2, "stop": true}), sorted([at(1, 0), at(2, 0)]), "at most param2 cells")
	eq(cells("from_caster", 2, 1, 0, 0, 0, {"max": 2}), sorted([at(2, 0), at(3, 0)]), "without isStopAtTarget: past the target")


func test_cone_half_circle_and_fork_face_away_from_the_caster() -> void:
	eq(cells("cone", 1, 2, 0), sorted([at(2, 0), at(3, 0), at(3, 1), at(3, -1)]))
	eq(cells("half_circle", 1, 2, 0), sorted([at(2, 0), at(1, 1), at(1, -1)]), "its arms come back towards the caster")
	eq(cells("fork", 1, 2, 0), sorted([at(2, 0), at(3, 0), at(3, 1), at(3, -1), at(4, 0), at(4, 2), at(4, -2)]),
			"Fork: three prongs of param1 + 1 cells")
	eq(cells("fork", 1, 0, 2), sorted([at(0, 2), at(0, 3), at(1, 3), at(-1, 3), at(0, 4), at(2, 4), at(-2, 4)]),
			"along the other axis too")


func test_diagonal_lines() -> void:
	eq(cells("diagonal_tline", 1, 2, 2), sorted([at(2, 2), at(3, 1), at(1, 3)]), "across the diagonal it was cast on")
	eq(cells("diagonal_line", 2, 2, 2), sorted([at(2, 2), at(3, 3), at(4, 4)]))


func test_square_without_diagonals_and_outside() -> void:
	eq(cells("square_ring", 1, 2, 0), sorted([at(3, 0), at(1, 0), at(2, 1), at(2, -1)]), "W: without its diagonals, so without its centre")
	eq(cells("square", 0, 0, 0).size(), 9, "G: side 2 * max(param1, 1) + 1")
	var far := cells("outside", 3, 0, 0)
	check(not far.has(at(2, 0)) and far.has(at(3, 0)) and far.has(at(5, 5)), "I = OutsideCircle: 3 steps and farther")
	eq(cells("all", 1, 0, 0).size(), MapGeometry.CELL_COUNT, "A = WholeMapWithTheDead")


func test_circles_and_crosses_have_a_minimum() -> void:
	var ring := cells("circle", 2, 0, 0, 0, 0, {"min": 1})
	eq(ring.size(), 12, "C2 param2 1: the diamond without its centre")
	check(not ring.has(O))
	eq(cells("cross", 3, 0, 0, 0, 0, {"min": 2}).size(), 8, "X: steps 2 and 3 of each arm")
	eq(cells("cross_ring", 2, 0, 0, 0, 0, {"min": 2}).size(), 4)


func test_diagonal_arms_count_steps() -> void:
	var plus := cells("diagonal_cross", 2, 0, 0)
	eq(plus.size(), 9, "+2: centre and two diagonal steps each way")
	check(plus.has(at(2, 2)) and plus.has(at(-2, 2)), "a diagonal step moves both coordinates")
	eq(cells("star", 2, 0, 0).size(), 17)


func test_the_direction_is_exact_or_none() -> void:
	eq(cells("line", 2, 2, 2), sorted([at(2, 2), at(3, 3), at(4, 4)]), "L cast in diagonal follows the diagonal")
	eq(cells("line", 2, 2, 1), [at(2, 1)], "not aligned: no direction, only the target cell")
	eq(cells("cone", 2, 2, 1), [at(2, 1)])
	eq(cells("tline", 1, 2, 1), sorted([at(2, 1), at(3, 1), at(1, 1)]), "no direction turns into direction 1")
	eq(cells("line", 3, 2, 0, 0, 0, {"min": 2}), sorted([at(4, 0), at(5, 0)]), "L param2: first step")


func test_boomerang() -> void:
	eq(cells("boomerang", 2, 3, 0), sorted([at(3, 0), at(3, 1), at(3, -1), at(2, 2), at(2, -2)]),
			"B: arms of param1 - 1 cells, tips curling back towards the caster")


func test_checkerboard() -> void:
	eq(cells("checkerboard", 2, 0, 0).size(), 9, "D2: distances 0 and 2")
	var odd := cells("checkerboard", 3, 0, 0)
	eq(odd.size(), 16, "D3: distances 1 and 3")
	check(not odd.has(O))


func test_rectangle_goes_away_from_the_caster() -> void:
	var r := cells("rectangle", 1, 2, 0, 0, 0, {"length": 3})
	eq(r.size(), 12, "3 wide, 4 long")
	check(r.has(at(2, 1)) and r.has(at(5, -1)) and not r.has(at(1, 0)))
	var back := cells("rectangle", 1, -2, 0, 0, 0, {"length": 3})
	check(back.has(at(-5, 0)) and not back.has(at(-1, 0)))
	var up := cells("rectangle", 1, 0, 2, 0, 0, {"length": 3})
	check(up.has(at(1, 5)) and up.has(at(-1, 2)) and not up.has(at(0, 1)))


func test_outside_complex_circle() -> void:
	var z := cells("outside_complex", 3, 0, 0)
	check(z.has(at(3, 0)) and not z.has(at(2, 2)) and not z.has(O), "Z: Euclidean distance >= param1")
