## Hide the interface (lot U.14) and the fight on a real client: a fight started by a ClientSession on a
## LocalBackend lays its HUD out without error (the format of the layout signature crashed every frame
## with a bool under %d), keeps the fighters clear of the bands, and survives hiding / showing the
## interface. HudToggles itself: remembered choices, "all hidden" never remembered.
extends TestCase


func _init() -> void:
	HudToggles.reset_for_tests()


func _tree() -> SceneTree:
	return Engine.get_meta("test_tree") as SceneTree


func test_toggles_state() -> void:
	HudToggles.reset_for_tests()
	check(not HudToggles.is_hidden("chat"))
	HudToggles.toggle("chat")
	check(HudToggles.is_hidden("chat") and not HudToggles.is_hidden("minimap"), "one block at a time")
	HudToggles.toggle("chat")
	HudToggles.toggle_all()
	for p: String in HudToggles.PARTS:
		check(HudToggles.is_hidden(p), "all hidden hides " + p)
	HudToggles.toggle_all()
	check(not HudToggles.is_hidden("tracker"))
	for a: String in ["toggle_ui", "toggle_chat", "toggle_minimap", "toggle_tracker"]:
		check(Shortcuts.key(a) != KEY_NONE, "a key for " + a)
	HudToggles.reset_for_tests()


func _session(world: String) -> ClientSession:
	var s := ClientSession.new()
	s.world_id = world
	s.player_name = "Tester"
	s.persistent = false
	_tree().root.add_child(s)
	return s


func _frames(s: ClientSession, n: int, until := Callable()) -> bool:
	for i in n:
		s._process(0.05)
		if until.is_valid() and until.call():
			return true
	return not until.is_valid()


func test_a_fight_starts_and_the_hud_follows() -> void:
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()
	HudToggles.reset_for_tests()
	var s := _session("incarnam")
	_frames(s, 30)
	var group := -1
	for id: int in s.views:
		if s.views[id] is GroupView:
			group = id
			break
	check(group >= 0, "a group of monsters on the first map")
	s.backend.send(Protocol.fight_attack(group))
	check(_frames(s, 400, func() -> bool: return s.fight != null and s.fight.hud != null), "the fight HUD is up")
	_frames(s, 20)
	eq((s._hud_sig as String).split("|")[3], "1", "the layout signature was built in a fight")
	var top0: float = s._area.top
	var bottom0: float = s._area.bottom
	check(top0 > 0.0 and bottom0 > 0.0, "the timeline and the bar are reserved")
	var vp := s.get_viewport_rect().size
	for id: int in s.fight.views:
		var p := (s.fight.views[id] as Node2D).position
		var scr: Vector2 = (p - s._camera.position) * s._camera.zoom.x + vp * 0.5
		check(scr.y > top0 - 1.0 and scr.y < vp.y - bottom0 + 1.0, "fighter %d inside the free strip" % id)
	# the interface goes away: only the buttons stay, the bands shrink
	HudToggles.toggle_all()
	_frames(s, 20)
	check(s.fight.hud.compact, "the fight HUD is compact")
	check(s._area.top == 0.0 and s._area.bottom < bottom0, "the bands shrink to the buttons")
	check(not s.chat.visible, "no chat")
	check(s._area.bottom > 0.0, "the end-turn button is still reserved")
	HudToggles.toggle_all()
	_frames(s, 20)
	check(not s.fight.hud.compact and s._area.top > 0.0, "back to the full interface")
	HudToggles.toggle("chat")
	_frames(s, 5)
	check(not s.chat.visible, "the chat folded on its own")
	s.chat.open()
	check(s.chat.visible, "Enter brings it back to type")
	HudToggles.reset_for_tests()
	s.backend = null
	_tree().root.remove_child(s)
	s.free()


func test_exploration_hides_the_dock() -> void:
	HudToggles.reset_for_tests()
	var s := _session("incarnam")
	_frames(s, 30)
	var band: float = s.player_hud.reserved_bottom()
	check(band > 0.0, "a dock band at first")
	HudToggles.toggle_all()
	_frames(s, 5)
	eq(s.player_hud.reserved_bottom(), 0.0, "no band once hidden")
	check(not s._info.visible, "the place names go too")
	HudToggles.toggle_all()
	_frames(s, 5)
	check(s.player_hud.reserved_bottom() > 0.0, "and back")
	HudToggles.reset_for_tests()
	s.backend = null
	_tree().root.remove_child(s)
	s.free()
