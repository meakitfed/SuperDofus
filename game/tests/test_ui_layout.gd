## Interface scale and windows that stay on screen (lot U.02, docs/ui/ADAPTATIF.md 2.1-2.6): the virtual
## screen for several window shapes and interface scales, every window of the real client inside the safe
## area at each of them, the saved layout (v2 shares, v1 pixels migrated), a content taller than the
## screen that scrolls, the open / close animation.
extends TestCase

const SHAPES := [Vector2(1280, 720), Vector2(1920, 1080), Vector2(2560, 1440), Vector2(1280, 1024), Vector2(3440, 1440)]
const CHOICES := [0.0, 0.75, 1.0, 1.25, 1.5]


func _init() -> void:
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()


func _tree() -> SceneTree:
	return Engine.get_meta("test_tree") as SceneTree


func _stage(size: Vector2) -> SubViewport:
	var sv := SubViewport.new()
	sv.size = Vector2i(size)
	_tree().root.add_child(sv)
	return sv


func _inside(w: UiWindow, safe: Rect2) -> bool:
	var r := Rect2(w.position, w.size)
	return r.position.x >= safe.position.x - 0.5 and r.position.y >= safe.position.y - 0.5 \
			and r.end.x <= safe.end.x + 0.5 and r.end.y <= safe.end.y + 0.5


func test_the_virtual_screen_follows_the_window_shape() -> void:
	for px: Vector2 in SHAPES:
		var v := UiScale.virtual_for(px, 0.0)
		check(v.x >= 1279.0 and v.y >= 719.0, "never smaller than the design screen at %s (got %s)" % [px, v])
		near(v.x / v.y, px.x / px.y, 0.01, "same shape at %s" % px)
	eq(UiScale.virtual_for(Vector2(1920, 1080), 0.0), Vector2(1280, 720))
	eq(UiScale.virtual_for(Vector2(2560, 1440), 1.0), Vector2(1280, 720))
	eq(UiScale.virtual_for(Vector2(1280, 1024), 0.0), Vector2(1280, 1024))
	for px: Vector2 in SHAPES + [Vector2(1024, 576)]:
		for c: float in CHOICES:
			var total := UiScale.stretch(px) * UiScale.factor_for(px, c)
			check(total >= UiScale.MIN_TOTAL - 0.001 and total <= UiScale.MAX_TOTAL + 0.001, "readable at %s x %s (%s)" % [px, c, total])


func test_a_4k_window_at_100_percent_is_not_blown_up() -> void:
	var px := Vector2(7680, 4320)
	var total := UiScale.stretch(px) * UiScale.factor_for(px, 0.0)
	near(total, UiScale.MAX_TOTAL, 0.001)
	eq(UiScale.virtual_for(Vector2(3840, 2160), 0.0), Vector2(1280, 720)) # 3x, still allowed


func test_every_window_of_the_client_stays_on_screen() -> void:
	UiWindow.reset_layout()
	var sv := _stage(Vector2(1280, 720))
	var b := LocalBackend.new()
	b.server = LocalServer.new()
	b.server.sources["walk"] = WorldSource.from_dicts(
		{"id": "walk", "name": "Walk", "start_map": 1, "start_cell": 300, "wander_ms": [600000, 600000]},
		[{"id": 1, "coords": [0, 0]}])
	var s := ClientSession.new()
	s.world_id = "walk"
	s.player_name = "Marcheur"
	s.persistent = false
	s.backend = b
	sv.add_child(s)
	for i in 10:
		b.server.tick(50)
		b.poll(0.05)
	var wins: Array = s.find_children("*", "UiWindow", true, false)
	check(wins.size() >= 8, "found the windows (%d)" % wins.size())
	for w: UiWindow in wins:
		w.open()
	for px: Vector2 in SHAPES + [Vector2(1024, 576)]:
		for c: float in [0.0, 1.5]:
			var v := UiScale.virtual_for(px, c)
			sv.size = Vector2i(v)
			UiWindow.relayout_all()
			var safe := UiScale.safe_rect(s)
			for w: UiWindow in wins:
				check(w.size.x > 100.0 and w.size.y > 40.0 and _inside(w, safe), "%s (%s) inside %s at %s x %s" % [w.window_id, Rect2(w.position, w.size), safe, px, c])
	for w: UiWindow in wins:
		w.close_window()
		check(not w.visible, "%s closed" % w.window_id)
	s.backend = null
	sv.remove_child(s)
	s.free()
	_tree().root.remove_child(sv)
	sv.free()


func test_a_window_keeps_its_share_of_the_screen_and_a_big_content_scrolls() -> void:
	UiWindow.reset_layout()
	var sv := _stage(Vector2(1280, 720))
	var w := UiWindow.new()
	w.setup("t_big", "Test")
	sv.add_child(w)
	var tall := Control.new()
	tall.custom_minimum_size = Vector2(300, 3000)
	w.body.add_child(tall)
	w.default_anchor = Vector2(1.0, 1.0)
	w.open()
	var safe := UiScale.safe_rect(w)
	check(_inside(w, safe), "taller than the screen: still inside")
	check(w.size.y <= safe.size.y + 0.5, "capped to the screen height")
	check(absf(w.position.x + w.size.x - safe.end.x) < 1.5, "stuck to the right edge")
	sv.size = Vector2i(1280, 1024)
	UiWindow.relayout_all()
	safe = UiScale.safe_rect(w)
	check(_inside(w, safe), "inside after the screen got taller")
	check(absf(w.position.x + w.size.x - safe.end.x) < 1.5, "still on the right edge")
	sv.size = Vector2i(640, 360)
	UiWindow.relayout_all()
	check(_inside(w, UiScale.safe_rect(w)), "inside a tiny screen")
	w.close_window()
	sv.remove_child(w)
	w.free()
	_tree().root.remove_child(sv)
	sv.free()


func test_the_safe_margin_keeps_windows_away_from_the_edges() -> void:
	UiWindow.reset_layout()
	var sv := _stage(Vector2(1280, 720))
	var w := UiWindow.new()
	w.setup("t_safe", "Test")
	sv.add_child(w)
	w.default_anchor = Vector2(1.0, 0.0)
	w.open()
	var before := w.position
	UiScale.set_safe_share(_tree().root, 0.05)
	check(w.position.x < before.x - 30.0 and w.position.y > before.y + 30.0, "moved in by the margin (%s -> %s)" % [before, w.position])
	check(_inside(w, UiScale.safe_rect(w)), "inside the safe rect")
	UiScale.set_safe_share(_tree().root, 0.0)
	UiScale.reset_for_tests()
	w.close_window()
	sv.remove_child(w)
	w.free()
	_tree().root.remove_child(sv)
	sv.free()


func test_layout_v1_pixels_become_a_share_and_a_saved_share_is_followed() -> void:
	UiWindow.reset_layout()
	UiWindow._layout["windows"]["t_old"] = {"x": 900.0, "y": 100.0} # v1 file: pixels
	UiWindow._layout["windows"]["t_new"] = {"fx": 0.0, "fy": 1.0, "sw": 500.0, "sh": 200.0}
	var sv := _stage(Vector2(1280, 720))
	var a := UiWindow.new()
	a.setup("t_old", "Old")
	var b := UiWindow.new()
	b.setup("t_new", "New")
	sv.add_child(a)
	sv.add_child(b)
	a.open()
	b.open()
	check(a.position.x > 500.0 and _inside(a, UiScale.safe_rect(a)), "v1 position kept on the same screen (%s)" % a.position)
	check(b.position.x < 1.5 and absf(b.position.y + b.size.y - 720.0) < 1.5, "saved share: bottom left (%s)" % b.position)
	check(b.size.x >= 500.0 and b.size.y >= 200.0, "saved size applied (%s)" % b.size)
	var fx := a._frac.x
	sv.size = Vector2i(1280, 1024)
	UiWindow.relayout_all()
	near(a._frac.x, fx, 0.001, "the share survives a change of shape")
	check(absf(b.position.y + b.size.y - 1024.0) < 1.5, "bottom left follows the taller screen")
	a.close_window()
	b.close_window()
	sv.free()
	UiWindow.reset_layout()


func test_open_and_close_animate_but_the_state_is_immediate() -> void:
	var was := UiWindow.animate
	UiWindow.animate = true
	var sv := _stage(Vector2(1280, 720))
	var w := UiWindow.new()
	w.setup("t_anim", "Anim")
	sv.add_child(w)
	w.open()
	check(w.is_open() and w.visible, "open at once")
	check(w.modulate.a < 1.0, "starts transparent")
	w.close_window()
	check(not w.is_open(), "closed at once for the logic")
	check(w.visible, "still drawn while it fades")
	w._finish_close()
	check(not w.visible and w.modulate.a == 1.0, "hidden and reset at the end")
	w.toggle()
	check(w.is_open(), "reopens")
	UiWindow.animate = was
	w.close_window()
	sv.free()
