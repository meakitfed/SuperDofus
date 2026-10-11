## Playing on the map (out of the roadmap, "jouabilité"): a double click runs, what the mouse
## points at (resource, door, zaap, exit) and its tooltip, where a door leads (also over
## WebSockets), the mask of the cells that MapFrame blurs around, and the map visuals laid on
## the cell grid (DofusMapNode.GRID_SHIFT_Y).
extends TestCase

const LOOK := "{1|120,2195,4072,4941,3963,5716|1=13418918,2=4077879,3=16022817,4=14386944,5=4275500,6=9904435|56|1@0={1420|||90}}"
const ASTRUB := 192416776 # Astrub, Cité (6,-19): the portal on cell 455 leads back up to Incarnam
const FIELDS := 154010372 # Incarnam, Champs (-1,-4): wheat (gfx 660) on cell 187
const Net := preload("res://tests/test_net.gd")


func _init() -> void:
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()


func _tree() -> SceneTree:
	return Engine.get_meta("test_tree") as SceneTree


static func _world() -> LocalServer:
	var s := LocalServer.new()
	s.sources["walk"] = WorldSource.from_dicts(
		{"id": "walk", "name": "Walk", "start_map": 1, "start_cell": 300, "wander_ms": [600000, 600000]},
		[{"id": 1, "coords": [0, 0]}])
	return s


func _session(server: LocalServer) -> ClientSession:
	var b := LocalBackend.new()
	b.server = server
	var s := ClientSession.new()
	s.world_id = "walk"
	s.player_name = "Marcheur"
	s.persistent = false
	s.backend = b
	_tree().root.add_child(s)
	for i in 10:
		server.tick(50)
		b.poll(0.05)
	return s


func _drop(s: ClientSession) -> void:
	s.backend = null
	_tree().root.remove_child(s)
	s.free()


## One click walks; a second click on (about) the same cell right after runs, like Dofus.
func test_a_double_click_runs() -> void:
	var server := _world()
	var s := _session(server)
	var b := s.backend as LocalBackend
	check(s.map != null, "on the map")
	s.clicks.press(MapGeometry.to_screen(328), false)
	b.poll(0.05)
	var me: SimActor = b.sim.players[b.player_id]
	check(not me.run, "one click: a walk")
	s.clicks.press(MapGeometry.to_screen(328), false)
	b.poll(0.05)
	check(me.run, "double click: a run")
	s.clicks.press(MapGeometry.to_screen(356), false) # a third click starts over
	b.poll(0.05)
	check(not me.run, "the next click walks again")
	_drop(s)


## Further than 3 steps the player runs anyway, from one click.
func test_far_away_runs_from_one_click() -> void:
	var server := _world()
	var s := _session(server)
	var b := s.backend as LocalBackend
	var me: SimActor = b.sim.players[b.player_id]
	eq(s.clicks.steps_to(300 + 28 * 6), 6)
	s.clicks.press(MapGeometry.to_screen(300 + 28 * 6), false)
	b.poll(0.05)
	check(me.run, "6 steps: a run")
	_drop(s)


func test_what_the_mouse_points_at() -> void:
	var m := MapData.new()
	m.neighbors["top"] = 2
	m.interactives = [{"e": 9, "cell": 200, "gfx": 660, "skill": 45}]
	m.triggers = {250: {"to_map": 2, "to_cell": 100, "to_name_id": 0, "to_area_name_id": 0}}
	var view := MapView.new()
	view.set_map(m)
	eq(MapHover.target(m, view, 200, MapGeometry.to_screen(200))["kind"], "element")
	eq(MapHover.target(m, view, 200, MapGeometry.to_screen(200))["e"], 9)
	eq(MapHover.target(m, view, 250, MapGeometry.to_screen(250))["kind"], "door")
	eq(MapHover.target(m, view, 300, MapGeometry.to_screen(300)), {}, "a plain cell")
	var edge := MapHover.target(m, view, 1, MapGeometry.to_screen(1))
	eq(edge.get("kind"), "exit", "a top edge cell, a map above")
	eq(edge.get("dir"), "top")
	var tip := MapHover.tip_lines(m, MapHover.target(m, view, 200, MapGeometry.to_screen(200)))
	eq(tip.size(), 2)
	check(tip[0] != "" and tip[1].contains("niveau 1"), "the resource, its verb and level: %s" % [tip])
	eq(MapHover.tip_lines(m, MapHover.target(m, view, 200, Vector2.ZERO), true)[1], "Repousse bientôt")
	eq(MapHover.tip_lines(m, MapHover.target(m, view, 250, Vector2.ZERO))[0], "Entrée", "a door of no known place")
	view.free()


## Past the edge of the map, the arrow of that side if it leads out, at its exit cell closest to
## the mouse, however far along the side; a click there walks to that cell and changes map.
func test_past_the_edge_the_closest_exit_of_that_side() -> void:
	var m := MapData.new()
	m.neighbors["left"] = 2
	var view := MapView.new()
	view.set_map(m)
	var b := MapGeometry.screen_bounds()
	var far_left := Vector2(b.position.x - 300.0, b.position.y + 40.0) # far left, by the top corner
	eq(MapGeometry.screen_to_cell(far_left), -1, "off the cells")
	var t := MapHover.target(m, view, -1, far_left)
	eq(t.get("kind"), "exit")
	eq(t.get("dir"), "left")
	var best := -1
	for c in m.exit_cells("left"):
		if best < 0 or MapGeometry.to_screen(c).distance_to(far_left) < MapGeometry.to_screen(best).distance_to(far_left):
			best = c
	eq(int(t["cell"]), best, "the closest left exit cell")
	check(MapGeometry.to_screen(best).y < b.get_center().y, "up the side, by the mouse")
	eq(MapHover.target(m, view, -1, Vector2(b.get_center().x, b.position.y - 50.0)), {}, "above: no map up there")
	eq(MapHover.target(m, view, -1, Vector2(b.end.x + 20.0, b.get_center().y)), {}, "right: none either")
	view.free()


func test_a_click_past_the_edge_leaves_the_map() -> void:
	var server := LocalServer.new()
	server.sources["walk"] = WorldSource.from_dicts(
		{"id": "walk", "name": "Walk", "start_map": 1, "start_cell": 300, "wander_ms": [600000, 600000]},
		[{"id": 1, "coords": [0, 0], "neighbors": {"right": 2}}, {"id": 2, "coords": [1, 0], "neighbors": {"left": 1}}])
	var s := _session(server)
	var b := s.backend as LocalBackend
	var bounds := MapGeometry.screen_bounds()
	s.clicks.press(Vector2(bounds.end.x + 200.0, bounds.end.y + 100.0), false) # far past the right, low
	eq(s._pending.exit, "right", "the exit waits for the walk")
	b.poll(0.05)
	var me: SimActor = b.sim.players[b.player_id]
	check(not me.path.is_empty(), "walking")
	check(s.map.can_exit(int(me.path[-1]), "right"), "to a cell of the right side")
	check(MapGeometry.to_screen(int(me.path[-1])).y > bounds.get_center().y, "low on the side, by the mouse")
	_drop(s)


## The frame's blur shows only with an exit arrow.
func test_the_edge_blurs_only_with_the_arrow() -> void:
	var f := MapFrame.new()
	_tree().root.add_child(f)
	check(not f.visible, "nothing at rest")
	f.shown = true
	f._process(1.0)
	check(f.visible and f.amount() > 0.9, "the arrow: the blur")
	f.shown = false
	f._process(1.0)
	check(not f.visible, "gone again")
	f.queue_free()


## The portal of Astrub says where it leads (another area: its name).
func test_the_way_up_says_incarnam() -> void:
	var src := JsonWorldSource.for_world("dofus")
	var temple: MapData = src.get_map(ASTRUB)
	var t := temple.trigger_at(455)
	check(int(t["to_area_name_id"]) != 0, "the destination's area travels with the door")
	eq(MapHover.door_name(temple, t), DofusI18n.text(int(t["to_area_name_id"]), "?"))
	eq(MapHover.door_name(temple, t), "Incarnam")
	var back := MapData.from_dict(JSON.parse_string(JSON.stringify(temple.to_dict())))
	eq(back.trigger_at(455), t, "and survives the JSON of map_enter")


## The same over WebSockets: map_enter carries the destination's names.
func test_door_names_over_websocket() -> void:
	var rig := Net.Rig.new()
	rig.host.server.sources["doors"] = WorldSource.from_dicts(
		{"id": "doors", "name": "Doors", "start_map": 1, "start_cell": 300},
		[{"id": 1, "coords": [0, 0], "area_name_id": 5, "triggers": [{"cell": 250, "to_map": 2, "to_cell": 100}]},
		 {"id": 2, "coords": [0, 1], "name_id": 77, "area_name_id": 88}])
	var c := rig.client("doors")
	check(rig.run(5.0, func() -> bool: return c.has(Protocol.MAP_ENTER)), "map_enter arrives")
	var m := MapData.from_dict(c.take(Protocol.MAP_ENTER)[0]["map"])
	eq(int(m.trigger_at(250)["to_name_id"]), 77)
	eq(int(m.trigger_at(250)["to_area_name_id"]), 88)
	rig.host.shutdown()


## MapFrame blurs what lies outside these: one texel per cell, every cell inside the mask.
func test_the_frame_mask_has_every_cell() -> void:
	var img := MapFrame.mask().get_image()
	var lit := 0
	for y in img.get_height():
		for x in img.get_width():
			lit += 1 if img.get_pixel(x, y).r > 0.5 else 0
	eq(lit, MapGeometry.CELL_COUNT)


## The map visuals sit on the cell grid: an animated element (a wheat) is drawn on its cell's centre.
func test_map_visuals_sit_on_the_cells() -> void:
	if not DofusMapNode.has_map(FIELDS):
		return # the Dofus content is not extracted here
	var def := DofusMapNode.load_def(FIELDS)
	var on := 0
	for e: Dictionary in def["animated"]:
		var t: Array = e["t"]
		if is_equal_approx(float(t[5]) + DofusMapNode.GRID_SHIFT_Y, MapGeometry.to_screen(int(e["cell"])).y):
			on += 1
	check(on * 2 > (def["animated"] as Array).size(), "most props on their cell: %d / %d" % [on, (def["animated"] as Array).size()])


## Tactical mode (T): the decor hides, the grid is drawn, and it stays on across maps.
func test_the_tactical_mode_toggles_and_stays_on() -> void:
	var s := _session(_world())
	var press := InputEventKey.new()
	press.keycode = Shortcuts.key("tactical")
	press.pressed = true
	check(not s._map_view.tactical, "off at the start")
	s._input(press)
	check(s._map_view.tactical, "T turns it on")
	check(not s._dofus_map.visible, "the decor is hidden")
	s.set_tactical(true) # a map change re-applies the state
	check(s._map_view.tactical and not s._dofus_map.visible, "kept")
	var press2 := InputEventKey.new()
	press2.keycode = Shortcuts.key("tactical")
	press2.pressed = true
	s._input(press2)
	check(not s._map_view.tactical and s._dofus_map.visible, "T again restores the decor")
	_drop(s)
