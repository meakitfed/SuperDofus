## P2.05c: the client side of the jobs: the XP of a harvest (native formula), the state of a harvested
## resource on the map (ResourceView), the jobs window model (JobsModel), the harvest cursor, and the
## whole thing over the network (NetBackend, 127.0.0.1).
extends TestCase

const ELEMENT := 77
const ASH_CELL := 300
const ASH_SKILL := 6
const OAK_SKILL := 10


static func _source(id: String) -> WorldSource:
	var src := WorldSource.from_dicts({"id": id, "name": id, "start_map": 1, "start_cell": 301},
		[{"id": 1, "coords": [0, 0], "neighbors": {}}])
	src.set_interactives({1: [{"e": ELEMENT, "cell": ASH_CELL, "gfx": 3715, "skill": ASH_SKILL}]})
	return src


func test_xp_of_a_harvest_follows_the_native_formula() -> void:
	eq(Jobs.required_level(ASH_SKILL), 1)
	eq(Jobs.xp_gain(ASH_SKILL), 10, "(1 / 10) * 2 + 10")
	eq(Jobs.required_level(OAK_SKILL), 60)
	eq(Jobs.xp_gain(OAK_SKILL), 22, "(60 / 10) * 2 + 10")


func test_gathering_skills_of_a_job_are_sorted_by_level() -> void:
	var skills := Jobs.gathering_skills(2) # Bûcheron
	check(skills.has(ASH_SKILL) and skills.has(OAK_SKILL))
	for i in range(1, skills.size()):
		check(Jobs.required_level(skills[i - 1]) <= Jobs.required_level(skills[i]), "sorted by level")
	for sk in skills:
		check(Jobs.is_gathering(sk) and Jobs.job_of(sk) == 2)
	check(Jobs.cursor_of(ASH_SKILL) > 0, "a gathering skill has its cursor")


func test_a_depleted_resource_is_greyed_until_it_grows_back() -> void:
	var near := Sprite2D.new()
	var far := Sprite2D.new()
	var by_cell := {ASH_CELL: [near]}
	var sprites := func(cell: int, _gfx: int) -> Array: return by_cell.get(cell, [])
	var el := {"e": ELEMENT, "cell": ASH_CELL, "gfx": 3715, "skill": ASH_SKILL}
	ResourceView.apply(sprites, el, true)
	eq(near.self_modulate, ResourceView.DEPLETED, "greyed")
	eq(near.modulate, Color.WHITE, "the hover light (modulate) is left alone")
	eq(far.self_modulate, Color.WHITE, "the other sprites are not touched")
	ResourceView.apply(sprites, el, false)
	eq(near.self_modulate, Color.WHITE, "back to normal")
	ResourceView.apply_all(sprites, [el], {ELEMENT: 9999})
	eq(near.self_modulate, ResourceView.DEPLETED, "apply_all reads the depleted table")
	near.free()
	far.free()


func test_the_cursor_over_a_resource() -> void:
	var t := {"kind": "element", "cell": ASH_CELL, "e": ELEMENT, "skill": ASH_SKILL}
	eq(MapHover.cursor_kind(t, false, {}), MapCursor.HARVEST + str(ASH_SKILL), "the harvest cursor")
	eq(MapHover.cursor_kind(t, false, {ELEMENT: 1}), "use", "a hand while it grows back")
	eq(MapHover.cursor_kind({"kind": "exit", "dir": "left"}, false, {}), "left")
	eq(MapHover.cursor_kind({}, true, {}), "use", "an NPC")
	eq(MapHover.cursor_kind({}, false, {}), "")


func test_the_jobs_model_follows_stats_and_xp() -> void:
	var m := JobsModel.new()
	eq(m.rows().size(), 0)
	var log := JobLog.new()
	log.gain(2, 25)
	m.apply_stats({"jobs": log.to_views()})
	var rows := m.rows()
	eq(rows.size(), 1)
	eq(int(rows[0]["job"]), 2)
	eq(int(rows[0]["xp"]), 25)
	var skills: Array = rows[0]["skills"]
	check(not skills.is_empty())
	var oak: Dictionary = skills.filter(func(s: Dictionary) -> bool: return int(s["skill"]) == OAK_SKILL)[0]
	check(bool(oak["locked"]), "oak needs level 60")
	var ash: Dictionary = skills.filter(func(s: Dictionary) -> bool: return int(s["skill"]) == ASH_SKILL)[0]
	check(not bool(ash["locked"]))
	log.gain(2, GameData.xp_floor(60))
	m.apply_xp(Protocol.job_xp(10, 59, log.view(2)))
	rows = m.rows()
	eq(int(rows[0]["level"]), 60)
	oak = (rows[0]["skills"] as Array).filter(func(s: Dictionary) -> bool: return int(s["skill"]) == OAK_SKILL)[0]
	check(not bool(oak["locked"]), "unlocked at 60")


func test_harvest_over_the_network() -> void:
	var rig = preload("res://tests/test_net.gd").Rig.new()
	rig.host.server.sources["jobs"] = _source("jobs")
	var c = rig.client("jobs", "Eli")
	check(rig.run(5.0, func() -> bool: return c.has(Protocol.MAP_ENTER)), "entered")
	var map: Dictionary = c.take(Protocol.MAP_ENTER)[0]["map"]
	check((map["interactives"] as Array).size() == 1, "the map lists its element")
	c.backend.send(Protocol.move(MapGeometry.neighbors(ASH_CELL)[0], false))
	rig.run(3.0)
	c.backend.send(Protocol.interactive_use(ELEMENT, ASH_SKILL))
	check(rig.run(2.0, func() -> bool: return c.has(Protocol.INTERACTIVE_START)), "the harvest starts")
	var model := JobsModel.new()
	var depleted := {}
	rig.run(Jobs.HARVEST_MS / 1000.0 + 1.0)
	for ev: Dictionary in c.take(Protocol.JOB_XP):
		model.apply_xp(ev)
		eq(int(ev["gained"]), Jobs.xp_gain(ASH_SKILL))
	for ev: Dictionary in c.take(Protocol.INTERACTIVE_STATE):
		if not bool(ev["ready"]):
			depleted[int(ev["element"])] = int(ev["until"])
	check(depleted.has(ELEMENT), "the element is depleted")
	eq(model.rows().size(), 1, "the jobs window has its job")
	eq(int(model.rows()[0]["xp"]), Jobs.xp_gain(ASH_SKILL))
	var stats := c.take(Protocol.PLAYER_STATS)
	check(not stats.is_empty(), "player_stats carries the jobs")
	model.apply_stats(stats.back()["stats"])
	eq(model.rows().size(), 1)
	eq(c.take(Protocol.ERROR).size(), 0, "no error")
	eq(c.backend.schema_errors.size(), 0, "events match the schema: %s" % [c.backend.schema_errors])
	rig.host.shutdown()
