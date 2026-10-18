## GameArea (lot U.01): the whole map, cells and monsters included, is placed clear of the HUD bands
## and panels at every window shape, so nothing of the grid ever sits behind the UI.
extends TestCase

const SIZES := [Vector2(1280, 720), Vector2(1920, 1080), Vector2(2560, 1440), Vector2(1280, 1024), Vector2(1024, 576)]


func _area(vp: Vector2) -> GameArea:
	var a := GameArea.new()
	a.set_layout(84.0, 192.0, {
		"chat": Rect2(12, vp.y - 192.0 - 190.0, 553, 190),
		"minimap": Rect2(vp.x - 220.0, 12, 208, 138),
	})
	return a


func test_the_map_clears_every_band_and_panel() -> void:
	for vp: Vector2 in SIZES:
		var a := _area(vp)
		var p := a.place(vp, MapGeometry.screen_bounds())
		var r: Rect2 = p["rect"]
		check(r.position.y >= a.top - 0.5 and r.end.y <= vp.y - a.bottom + 0.5, "inside the bands at %s" % vp)
		check(r.position.x >= -0.5 and r.end.x <= vp.x + 0.5, "inside the width at %s" % vp)
		for k: String in a.blocks:
			check(not r.intersects(a.blocks[k]), "%s clear at %s" % [k, vp])
		check(float(p["zoom"]) > 0.2, "still readable at %s" % vp)


func test_the_camera_shows_the_first_and_last_rows_in_the_area() -> void:
	var cam := Camera2D.new()
	for vp: Vector2 in SIZES:
		var a := _area(vp)
		a.fit(cam, vp)
		var z := cam.zoom.x
		for cell: int in [0, MapGeometry.WIDTH - 1, MapGeometry.WIDTH * MapGeometry.ROWS / 2 - 1, MapGeometry.WIDTH * MapGeometry.ROWS / 2 - MapGeometry.WIDTH]:
			var s := (MapGeometry.to_screen(cell) - cam.position) * z + vp * 0.5
			check(s.y >= a.top and s.y <= vp.y - a.bottom, "cell %d inside the free strip at %s" % [cell, vp])
			for k: String in a.blocks:
				check(not (a.blocks[k] as Rect2).has_point(s), "cell %d not under %s at %s" % [cell, k, vp])
	cam.free()


func test_no_signal_when_nothing_moved() -> void:
	var a := GameArea.new()
	var n := [0]
	a.changed.connect(func() -> void: n[0] += 1)
	a.set_layout(10.0, 20.0, {})
	a.set_layout(10.0, 20.0, {})
	a.set_layout(10.0, 20.4, {})
	eq(n[0], 1)
	a.set_layout(10.0, 60.0, {"chat": Rect2(0, 0, 10, 10)})
	eq(n[0], 2)
