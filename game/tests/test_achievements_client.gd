## P2.12b: the client side of the achievements: the model (categories, rows, objectives ticked), the window
## (opening asks the sim, a list and an unlock redraw it), the toast text, and the whole thing over a LocalBackend
## and over WebSockets (NetBackend on 127.0.0.1).
extends TestCase

const NetTests := preload("res://tests/test_net.gd")
const MONSTER := 55


func _defs() -> Dictionary:
	var a := func(id: int, cat: int, order: int, points: int, crit: Array) -> Dictionary:
		var objs := []
		for i in crit.size():
			objs.append({"id": id * 10 + i, "name_id": 0, "criterion": crit[i]})
		return {"id": id, "name_id": 0, "desc_id": 0, "category": cat, "icon": 0, "points": points, "level": 20,
				"order": order, "objectives": objs, "rewards": []}
	return {
		"9002": a.call(9002, 11, 2, 5, ["(EM>%d,0,d)" % MONSTER]),
		"9003": a.call(9003, 12, 3, 7, ["(EM>%d,1)" % MONSTER, "PL>200"]),
		"9004": a.call(9004, 20, 4, 3, ["EI>683,0"])}


func _cats() -> Dictionary:
	return {"10": {"id": 10, "name_id": 0, "parent": 0, "order": 1, "icon": ""},
		"11": {"id": 11, "name_id": 0, "parent": 10, "order": 1, "icon": ""},
		"12": {"id": 12, "name_id": 0, "parent": 11, "order": 2, "icon": ""},
		"20": {"id": 20, "name_id": 0, "parent": 0, "order": 2, "icon": ""}}


func _model() -> AchievementsModel:
	AchievementsModel.set_defs(_defs(), _cats())
	return AchievementsModel.new()


func test_categories_group_their_sub_categories() -> void:
	var m := _model()
	var cats := m.categories()
	eq(cats.size(), 2, "two top categories")
	eq(int(cats[0]["id"]), 10)
	eq(int(cats[0]["count"]), 2, "10 holds 9002 (in 11) and 9003 (in 12, under 11)")
	eq(int(cats[1]["id"]), 20)
	m.apply_list({"points": 5, "total": 15, "done": [{"id": 9002, "day": 20000}], "progress": [{"id": 9003, "objectives": [90030.0]}]})
	cats = m.categories()
	eq(int(cats[0]["done"]), 1)
	eq(int(cats[0]["points"]), 5)
	AchievementsModel.reset()


func test_rows_put_the_obtained_first_and_tick_objectives() -> void:
	var m := _model()
	m.apply_list({"points": 0, "total": 15, "done": [], "progress": [{"id": 9003, "objectives": [90030.0]}]})
	var rows := m.rows(10)
	eq(rows.size(), 2)
	eq(int(rows[0]["id"]), 9002, "by order")
	var r3: Dictionary = rows[1]
	eq(int(r3["id"]), 9003)
	check(bool(r3["objectives"][0]["done"]) and not bool(r3["objectives"][1]["done"]), "the first objective is ticked, not the level")
	m.apply_unlocked({"achievement": 9003, "points": 7, "total_points": 7, "name_id": 0})
	rows = m.rows(10)
	eq(int(rows[0]["id"]), 9003, "obtained first")
	check(bool(rows[0]["objectives"][1]["done"]), "all ticked once obtained")
	eq(m.points, 7)
	AchievementsModel.reset()


func test_unlocked_text_names_the_achievement_and_its_points() -> void:
	var t := AchievementsModel.unlocked_text({"achievement": 9002, "name_id": 0, "points": 5, "total_points": 5})
	check(t.contains("Succès 9002") and t.contains("5"), t)


func test_the_window_asks_the_sim_and_redraws() -> void:
	var m := _model()
	var b := LocalBackend.new()
	var w := AchievementsWindow.new()
	w.setup_window(b)
	w.on_event(ProtocolAchievement.LIST, {"points": 5, "total": 15, "done": [{"id": 9002, "day": 3}], "progress": []})
	eq(w.model.points, 5)
	eq(w._points.text, "5 points sur 15")
	w.select(20)
	eq(w._selected, 20)
	w.on_event(ProtocolAchievement.UNLOCKED, {"achievement": 9004, "name_id": 0, "points": 3, "total_points": 8})
	eq(w._points.text, "8 points sur 15")
	w.free()
	AchievementsModel.reset()


func test_real_file_loads_with_categories() -> void:
	AchievementsModel.reset()
	var m := AchievementsModel.new()
	var cats := m.categories()
	check(cats.size() >= 5, "the real categories are there: %d" % cats.size())
	var n := 0
	for c: Dictionary in cats:
		n += int(c["count"])
	check(n >= 700, "725 achievements are listed: %d" % n)
	check(not m.rows(int(cats[0]["id"])).is_empty())
	AchievementsModel.reset()


func test_over_websocket_the_client_model_follows() -> void:
	var m := _model()
	var rig := NetTests.Rig.new()
	var a := rig.client("tiny", "Alice")
	rig.run(2.0, func() -> bool: return a.has(Protocol.MAP_ENTER))
	var sim := rig.sim()
	sim.info["achievements"] = true
	Achievements.set_defs(_defs())
	sim._quest_event(sim.players[a.you], {"kind": "fight", "win": true, "monsters": [MONSTER], "map": 1})
	check(rig.run(2.0, func() -> bool: return a.has(ProtocolAchievement.UNLOCKED)), "unlock received")
	for ev: Dictionary in a.take(ProtocolAchievement.UNLOCKED):
		m.apply_unlocked(ev)
	a.backend.send(ProtocolAchievement.open())
	check(rig.run(2.0, func() -> bool: return a.has(ProtocolAchievement.LIST)), "list received")
	for ev: Dictionary in a.take(ProtocolAchievement.LIST):
		m.apply_list(ev)
	check(m.done.has(9002), "the model has the obtained achievement")
	eq(m.points, 5)
	eq(int(m.categories()[0]["done"]), 1)
	eq(a.backend.schema_errors.size(), 0, "schema: %s" % [a.backend.schema_errors])
	rig.host.shutdown()
	Achievements.reset()
	AchievementsModel.reset()
