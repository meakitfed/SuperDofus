## Exploration HUD (lot U.04): the parts sit in the corners of HudLayout at every window shape
## without covering one another, the chat keeps its share of the window, remembers its opacity and
## counts what it has not shown, the quest tracker folds, the dock buttons ask for their window.
extends TestCase

const SIZES := [Vector2(1280, 720), Vector2(1920, 1080), Vector2(2560, 1440), Vector2(1280, 1024), Vector2(1024, 576)]


func _tree() -> SceneTree:
	return Engine.get_meta("test_tree") as SceneTree


func add_child_free(n: Node) -> void:
	_tree().root.add_child(n)


func _init() -> void:
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()


func _sizes(vp: Vector2) -> Dictionary:
	return {"mapinfo": Vector2(300, 70), "party": Vector2(250, 120), "minimap": Vector2(HudLayout.side_width(vp), 130),
			"tracker": Vector2(244, 90), "dungeon": Vector2(220, 80), "chat": HudLayout.chat_size(vp)}


func test_parts_stay_on_screen_and_apart() -> void:
	for vp: Vector2 in SIZES:
		var sizes := _sizes(vp)
		var spots := HudLayout.place(vp, sizes, 130.0)
		var rects := {}
		for k: String in sizes:
			var r := Rect2(spots[k], sizes[k])
			check(Rect2(Vector2.ZERO, vp).encloses(r), "%s on screen at %s" % [k, vp])
			rects[k] = r
		var keys := rects.keys()
		for i in keys.size():
			for j in range(i + 1, keys.size()):
				if keys[i] == "dungeon" or keys[j] == "dungeon":
					continue # the dungeon widget sits at the top centre, over the map only when shown
				check(not (rects[keys[i]] as Rect2).intersects(rects[keys[j]]), "%s / %s apart at %s" % [keys[i], keys[j], vp])
		check((rects["chat"] as Rect2).end.y <= vp.y - 130.0 + 0.5, "chat above the band at %s" % vp)


func test_missing_parts_close_the_gap() -> void:
	var vp := Vector2(1280, 720)
	var spots := HudLayout.place(vp, {"minimap": Vector2(240, 130), "tracker": Vector2(244, 90)}, 100.0)
	eq((spots["tracker"] as Vector2).y, HudLayout.MARGIN + 130.0 + HudLayout.GAP)
	var alone := HudLayout.place(vp, {"tracker": Vector2(244, 90)}, 100.0)
	eq((alone["tracker"] as Vector2).y, HudLayout.MARGIN, "no minimap: the tracker takes the corner")


func test_chat_size_bounds() -> void:
	for vp: Vector2 in SIZES:
		var s := HudLayout.chat_size(vp)
		check(s.x >= HudLayout.CHAT_MIN.x and s.x <= HudLayout.CHAT_MAX.x and s.y >= HudLayout.CHAT_MIN.y and s.y <= HudLayout.CHAT_MAX.y, "bounds at %s" % vp)


func test_chat_opacity_and_unread() -> void:
	var chat := ChatPanel.new()
	chat.backend = LocalBackend.new()
	add_child_free(chat)
	var first := chat.opacity()
	chat.cycle_opacity()
	check(chat.opacity() != first, "the opacity changed")
	for i in ChatPanel.OPACITIES.size() - 1:
		chat.cycle_opacity()
	eq(chat.opacity(), first, "it cycles back")
	chat.on_message({"channel": Chat.COMMERCE, "from": "Bob", "to": "", "text": "vends", "links": [], "smileys": []})
	eq(chat.unread(Chat.COMMERCE), 1, "a line in another tab is counted")
	eq(chat.unread(Chat.GENERAL), 0)
	chat._tabs.select(Chat.TABS.find(Chat.COMMERCE))
	eq(chat.unread(Chat.COMMERCE), 0, "reading the tab clears it")
	chat.queue_free()


func test_tracker_folds() -> void:
	var t := QuestTracker.new()
	add_child_free(t)
	var journal := QuestWindow.new()
	add_child_free(journal)
	journal.setup_window(LocalBackend.new())
	t.setup(journal)
	QuestTracker.folded = false
	t.toggle_fold()
	check(QuestTracker.folded)
	check(not t._rows.visible, "the list is hidden")
	t.toggle_fold()
	check(t._rows.visible)


func test_menu_buttons_ask_for_their_window() -> void:
	var m := HudMenu.new()
	add_child_free(m)
	var got: Array = []
	m.pressed.connect(func(a: String) -> void: got.append(a))
	for a: String in m.buttons:
		(m.buttons[a] as Button).pressed.emit()
	eq(got.size(), HudMenu.ENTRIES.size())
	for e: Array in HudMenu.ENTRIES:
		check(ClientSession.WINDOW_ACTIONS.has(e[0]), "%s is a window action" % e[0])
