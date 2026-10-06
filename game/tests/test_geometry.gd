## shared/: map geometry, pathfinding, movement timing.
extends TestCase


func test_cell_roundtrip() -> void:
	for c in MapGeometry.CELL_COUNT:
		if MapGeometry.from_iso(MapGeometry.to_iso(c)) != c:
			check(false, "roundtrip broken at %d" % c)
			return
	eq(MapGeometry.from_iso(Vector2i(-5, 40)), -1, "outside")


func test_screen_layout() -> void:
	var s0 := MapGeometry.to_screen(0)
	near((MapGeometry.to_screen(1) - s0).x, IsoGrid.CELL_W, 0.01, "same row = one cell right")
	near((MapGeometry.to_screen(1) - s0).y, 0.0, 0.01)
	eq(MapGeometry.to_screen(14) - s0, Vector2(IsoGrid.CELL_W, IsoGrid.CELL_H) * 0.5, "odd row shifted half a cell")
	eq(MapGeometry.to_screen(28) - s0, Vector2(0, IsoGrid.CELL_H), "row 2 below row 0")
	eq(MapGeometry.screen_to_cell(MapGeometry.to_screen(321)), 321)
	check(MapGeometry.screen_bounds().has_point(MapGeometry.to_screen(559)))


func test_edges_and_mirror() -> void:
	eq(MapGeometry.edge_dirs(0), PackedStringArray(["left", "top"]))
	check(MapGeometry.is_edge(27, "right") and MapGeometry.is_edge(27, "top"))
	check(not MapGeometry.is_edge(300))
	eq(MapGeometry.mirror_cell(14 * 10, "left"), 14 * 10 + 13)
	eq(MapGeometry.mirror_cell(14 * 10 + 13, "right"), 14 * 10)
	eq(MapGeometry.mirror_cell(5, "top"), 38 * 14 + 5)
	eq(MapGeometry.mirror_cell(39 * 14 + 5, "bottom"), 14 + 5)


func test_pathfinder() -> void:
	var m := MapData.new()
	m.blocked = {301: true, 302: true}
	var pf := MapPathfinder.new(m)
	var p := pf.find_path(299, 304)
	check(p.size() >= 2, "path found")
	eq(p[0], 299)
	eq(p[-1], 304)
	for i in range(1, p.size()):
		check(m.is_walkable(p[i]), "walkable step")
		eq(MapGeometry.distance(p[i - 1], p[i]), 1, "adjacent step")
	eq(pf.find_path(299, 301), [], "blocked target")


func test_movement_timing() -> void:
	eq(Movement.step_ms(0, 1, false), 510, "screen horizontal")
	eq(Movement.step_ms(0, 28, false), 425, "screen vertical")
	eq(Movement.step_ms(0, 14, false), 480, "diagonal")
	eq(Movement.step_ms(0, 1, true), 255)
	var path := [0, 1, 2]
	eq(Movement.duration_ms(path, false), 1020)
	var s := Movement.sample(path, 1000, false, 1255)
	check(s["moving"])
	eq(s["index"], 0)
	near(s["pos"].x, 0.5, 0.01)
	eq(s["dir"], 0, "facing east")
	check(not Movement.sample(path, 1000, false, 5000)["moving"])


func test_replan_continues_current_step() -> void:
	var pf := MapPathfinder.new(MapData.new())
	var path := [300, 301, 302, 303]
	# at t=700 the actor is between 301 and 302 (steps of 510 ms)
	var r := Movement.replan(path, 0, false, 300, 700, 330, pf)
	eq(r["path"][0], 301, "starts from the cell of the current step")
	eq(r["path"][1], 302, "keeps walking to the next cell")
	eq(r["t0"], 510, "same timeline as the old movement")
	eq(r["path"][-1], 330)
