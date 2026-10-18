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


## Zoom of the player (lot U.12): never below the fitting zoom, bounded above, kept through a resize.
func _screen(cam: Dictionary, vp: Vector2, w: Vector2) -> Vector2:
	return (w - (cam["position"] as Vector2)) * float(cam["zoom"]) + vp * 0.5


func test_zoom_out_is_impossible_and_zoom_in_is_bounded() -> void:
	for vp: Vector2 in SIZES + [Vector2(1000, 1000)]:
		var a := _area(vp)
		var fit_zoom: float = a.camera_for(vp)["zoom"]
		for i in 40:
			a.zoom_step(-1)
		eq(a.ratio, 1.0)
		near(float(a.camera_for(vp)["zoom"]), fit_zoom, 0.0001, "no zoom out at %s" % vp)
		for i in 60:
			a.zoom_step(1)
		near(a.ratio, GameArea.MAX_RATIO, 0.0001, "bounded at %s" % vp)
		near(float(a.camera_for(vp)["zoom"]), fit_zoom * GameArea.MAX_RATIO, 0.0001)


func test_a_zoomed_map_still_covers_the_free_strip() -> void:
	var b := MapGeometry.screen_bounds()
	for vp: Vector2 in SIZES:
		var a := _area(vp)
		a.ratio = 2.0
		for f: Vector2 in [Vector2.INF, b.position, b.end, b.get_center()]:
			a.focus = f
			var c := a.camera_for(vp)
			var free := a.rect(vp)
			var tl := _screen(c, vp, b.position)
			var br := _screen(c, vp, b.end)
			for ax in [0, 1]: # on each axis where the map is larger than the strip (the other one is the letterbox of the fit)
				if (br - tl)[ax] >= free.size[ax]:
					check(tl[ax] <= free.position[ax] + 0.5 and br[ax] >= free.end[ax] - 0.5, "no void on axis %d at %s focus %s" % [ax, vp, f])


func test_the_ratio_survives_a_resize_and_a_new_layout() -> void:
	var a := _area(Vector2(1280, 720))
	a.zoom_step(1)
	a.zoom_step(1)
	var r := a.ratio
	for vp: Vector2 in SIZES:
		a.set_layout(60.0, 150.0, {})
		var c := a.camera_for(vp)
		var base := a.place(vp, MapGeometry.screen_bounds())
		near(float(c["zoom"]), float(base["zoom"]) * r, 0.0001, "ratio kept at %s" % vp)
		eq(a.ratio, r)
	a.reset_zoom()
	eq(a.ratio, 1.0)


func test_a_fight_never_zooms_a_fighter_out_of_the_strip() -> void:
	for vp: Vector2 in SIZES + [Vector2(1000, 1000)]:
		var a := _area(vp)
		var pts: Array[Vector2] = []
		for cell: int in [10, 25, 350, 545, 559]: # spread over the map
			pts.append(MapGeometry.to_screen(cell))
		a.must_show = pts
		a.ratio = GameArea.MAX_RATIO
		var c := a.camera_for(vp)
		var free := a.rect(vp)
		for p: Vector2 in pts:
			var s := _screen(c, vp, p)
			check(free.has_point(s), "fighter %s inside the strip at %s" % [p, vp])
			for k: String in a.blocks:
				check(not (a.blocks[k] as Rect2).has_point(s), "fighter not under %s at %s" % [k, vp])
		# a tight group may zoom in
		a.must_show = [MapGeometry.to_screen(280), MapGeometry.to_screen(281)]
		var gain: float = float(a.camera_for(vp)["zoom"]) / float(a.place(vp, MapGeometry.screen_bounds())["zoom"])
		check(gain >= (1.2 if vp.x >= 1280.0 else 1.0), "a close group zooms in at %s (x%.2f)" % [vp, gain])


func test_map_zoom_wheel_and_recentre() -> void:
	var a := _area(Vector2(1280, 720))
	var z := MapZoom.new()
	check(not z.wheel(a, -1), "wheel out at the fit: nothing to refit")
	check(z.wheel(a, 1), "wheel in refits")
	check(z.recentre(a), "recentre had something to undo")
	check(not z.recentre(a), "a second recentre does nothing")
	eq(a.ratio, 1.0)
	eq(Shortcuts.key("recentre"), KEY_END)
	check(not z.track(a, null, {}, 1), "exploration without a view: no refit")
