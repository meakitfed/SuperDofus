## P2.05: jobs, harvesting (interactive_use), shared element state, job XP.
## Skills used: 6 (Couper : Frêne, Bûcheron, level 1) and 10 (Couper : Chêne, level 60).
extends TestCase

const ELEMENT := 77
const ASH_CELL := 300
const OAK := 78
const OAK_CELL := 330
const ASH_SKILL := 6
const OAK_SKILL := 10


class Conn:
	var backend := LocalBackend.new()
	var events: Array = []
	var you := -1
	var server: LocalServer

	func _init(p_server: LocalServer, name: String) -> void:
		server = p_server
		backend.server = server
		backend.event.connect(func(ev: Dictionary) -> void:
			events.append(ev)
			if ev["t"] == Protocol.WELCOME:
				you = int(ev["you"]))
		backend.send(Protocol.hello("jobs", name, "{1}"))
		backend.poll(0.0)

	func send(cmd: Dictionary) -> Array:
		events = []
		backend.send(cmd)
		backend.poll(0.0)
		return events

	func wait(seconds: float) -> Array:
		events = []
		var left := int(seconds * 1000.0)
		while left > 0:
			var step := mini(left, 500)
			server.tick(step)
			left -= step
		backend.poll(0.0)
		return events

	func of(type: String) -> Array:
		return events.filter(func(e: Dictionary) -> bool: return e["t"] == type)


static func _server() -> LocalServer:
	var s := LocalServer.new()
	var src := WorldSource.from_dicts({"id": "jobs", "name": "Jobs", "start_map": 1, "start_cell": 301},
		[{"id": 1, "coords": [0, 0], "neighbors": {}}, {"id": 2, "coords": [1, 0], "neighbors": {}}])
	src.set_interactives({1: [{"e": ELEMENT, "cell": ASH_CELL, "gfx": 3715, "skill": ASH_SKILL},
			{"e": OAK, "cell": OAK_CELL, "gfx": 1, "skill": OAK_SKILL}]})
	s.sources["jobs"] = src
	return s


static func _beside(c: Conn, cell: int) -> void:
	c.send(Protocol.move(MapGeometry.neighbors(cell)[0], false))
	c.wait(3.0)


func test_the_map_lists_its_harvestable_elements() -> void:
	var c := Conn.new(_server(), "Eli")
	var enter: Dictionary = c.events.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.MAP_ENTER)[0]
	var els: Array = enter["map"]["interactives"]
	eq(els.size(), 2)
	eq(int(els[0]["skill"]), ASH_SKILL)
	var map := MapData.from_dict(enter["map"])
	eq(int(map.interactive_near(ASH_CELL)["e"]), ELEMENT)
	eq(int(map.interactive(OAK)["cell"]), OAK_CELL)


func test_a_harvest_takes_time_then_gives_the_resource_and_xp() -> void:
	var c := Conn.new(_server(), "Eli")
	_beside(c, ASH_CELL)
	var started := c.send(Protocol.interactive_use(ELEMENT, ASH_SKILL))
	var start: Dictionary = c.of(Protocol.INTERACTIVE_START)[0]
	eq(int(start["element"]), ELEMENT)
	eq(int(start["player"]), c.you)
	check(c.of(Protocol.ITEM_ADDED).is_empty(), "nothing yet")
	check(started.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.ERROR).is_empty())
	var done := c.wait(Jobs.HARVEST_MS / 1000.0 + 0.5)
	var added := done.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.ITEM_ADDED)
	eq(added.size(), 1)
	eq(int(added[0]["item"]["id"]), 303, "Frêne")
	var qty := int(added[0]["item"]["qty"])
	check(qty >= 1 and qty <= 2, "1-2 at the required level")
	var xp: Dictionary = c.of(Protocol.JOB_XP)[0]
	eq(int(xp["gained"]), Jobs.xp_gain(ASH_SKILL))
	eq(int(xp["view"]["job"]), 2, "Bûcheron")
	eq(int(xp["view"]["xp"]), Jobs.xp_gain(ASH_SKILL))
	var state: Dictionary = c.of(Protocol.INTERACTIVE_STATE)[0]
	check(not bool(state["ready"]))
	check(not c.of(Protocol.INTERACTIVE_END).is_empty())
	var stats: Dictionary = c.of(Protocol.PLAYER_STATS)[0]["stats"]
	eq((stats["jobs"] as Array).size(), 1, "player_stats lists the jobs practised")


func test_the_element_grows_back() -> void:
	var c := Conn.new(_server(), "Eli")
	_beside(c, ASH_CELL)
	c.send(Protocol.interactive_use(ELEMENT, ASH_SKILL))
	c.wait(4.0)
	var again := c.send(Protocol.interactive_use(ELEMENT, ASH_SKILL))
	eq(again.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.ERROR)[0]["code"], Protocol.E_ELEMENT_BUSY, "harvested")
	var back := c.wait(Jobs.RESPAWN_MS / 1000.0)
	var states := back.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.INTERACTIVE_STATE)
	check(not states.is_empty() and bool(states[0]["ready"]), "grown back")
	c.send(Protocol.interactive_use(ELEMENT, ASH_SKILL))
	check(not c.of(Protocol.INTERACTIVE_START).is_empty(), "harvestable again")


func test_the_job_level_gates_the_skill_and_xp_raises_it() -> void:
	var c := Conn.new(_server(), "Eli")
	_beside(c, OAK_CELL)
	var err := c.send(Protocol.interactive_use(OAK, OAK_SKILL)).filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.ERROR)
	eq(err[0]["code"], Protocol.E_JOB_LEVEL, "Chêne needs level 60")
	eq(Jobs.required_level(OAK_SKILL), 60)
	var log := JobLog.new()
	eq(log.level(2), 1)
	var levels := log.gain(2, GameData.xp_floor(60))
	eq(levels, 59)
	eq(log.level(2), 60)
	eq(JobLog.from_dict(log.to_dict()).xp_of(2), GameData.xp_floor(60), "saved")


func test_quantity_grows_with_the_level() -> void:
	eq(Jobs.quantity_range(ASH_SKILL, 1), Vector2i(1, 2))
	eq(Jobs.quantity_range(ASH_SKILL, 101), Vector2i(3, 7))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 20:
		var q := Jobs.roll_quantity(ASH_SKILL, 101, rng)
		check(q >= 3 and q <= 7, "within the range")


func test_not_beside_or_unknown_element_is_refused() -> void:
	var c := Conn.new(_server(), "Eli")
	c.send(Protocol.move(10, false))
	c.wait(5.0)
	var far := c.send(Protocol.interactive_use(ELEMENT, ASH_SKILL)).filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.ERROR)
	eq(far[0]["code"], Protocol.E_NOT_AT_ELEMENT)
	_beside(c, ASH_CELL)
	var wrong := c.send(Protocol.interactive_use(ELEMENT, OAK_SKILL)).filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.ERROR)
	eq(wrong[0]["code"], Protocol.E_NO_ELEMENT, "not the skill of the element")
	var none := c.send(Protocol.interactive_use(5, ASH_SKILL)).filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.ERROR)
	eq(none[0]["code"], Protocol.E_NO_ELEMENT)


func test_moving_away_cancels_the_harvest() -> void:
	var c := Conn.new(_server(), "Eli")
	_beside(c, ASH_CELL)
	c.send(Protocol.interactive_use(ELEMENT, ASH_SKILL))
	c.wait(1.0)
	var evs := c.send(Protocol.move(10, false))
	var end: Dictionary = evs.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.INTERACTIVE_END)[0]
	check(not bool(end["done"]))
	c.wait(10.0)
	check(c.of(Protocol.ITEM_ADDED).is_empty(), "nothing harvested")
	_beside(c, ASH_CELL)
	c.send(Protocol.interactive_use(ELEMENT, ASH_SKILL))
	check(not c.of(Protocol.INTERACTIVE_START).is_empty(), "the element was released")


func test_the_state_is_shared_between_players() -> void:
	var s := _server()
	var a := Conn.new(s, "Eli")
	var b := Conn.new(s, "Bob")
	_beside(a, ASH_CELL)
	_beside(b, ASH_CELL)
	a.send(Protocol.interactive_use(ELEMENT, ASH_SKILL))
	b.wait(0.0)
	check(not b.of(Protocol.INTERACTIVE_START).is_empty(), "Bob sees Eli harvest (animation)")
	var busy := b.send(Protocol.interactive_use(ELEMENT, ASH_SKILL)).filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.ERROR)
	eq(busy[0]["code"], Protocol.E_ELEMENT_BUSY, "taken by Eli")
	a.wait(4.0)
	var late := Conn.new(s, "Cy")
	check(late.events.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.INTERACTIVE_STATE and not bool(e["ready"])).size() == 1, "a newcomer is told what is harvested")


func test_jobs_are_saved_with_the_character() -> void:
	var s := _server()
	var c := Conn.new(s, "Eli")
	_beside(c, ASH_CELL)
	c.send(Protocol.interactive_use(ELEMENT, ASH_SKILL))
	c.wait(4.0)
	c.backend.close()
	var again := Conn.new(s, "Eli")
	var stats: Dictionary = again.events.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.PLAYER_STATS)[0]["stats"]
	eq(int(stats["jobs"][0]["xp"]), Jobs.xp_gain(ASH_SKILL))


# ── P2.05b: criterion PJ, effect 614, jobsReward ───────────────────────────────

func test_criterion_pj_reads_the_job_level() -> void:
	var v := {"jobs": {2: 85, 44: 200}}
	check(CriteriaEval.ok("PJ>2,80", v), "Bucheron 85 > 80")
	check(not CriteriaEval.ok("PJ>2,90", v))
	check(CriteriaEval.ok("PJ=44,200", v), "level 200")
	check(not CriteriaEval.ok("PJ=11,200", v), "an unpractised job is at level 1")
	check(CriteriaEval.ok("PJ>2,80|PJ>24,80", v), "or")
	check(not CriteriaEval.ok("PJ>2,80&PJ>24,80", v), "and")
	check(not CriteriaEval.ok("PJ>2", v), "malformed")
	eq(CriteriaEval.unknown_keys("PJ>2,80").size(), 0)


func test_a_job_scroll_gives_job_xp() -> void:
	var c := Conn.new(_server(), "Eli")
	var sim: WorldSim = c.backend.sim
	var p: PlayerActor = sim.players[c.you]
	sim.give_item(p, 695, 1) # Parchemin de Bucheron: [614, 0, 2, 100]
	var uid: int = p.character.inventory.to_array()[0]["uid"]
	c.send(Protocol.use_item(uid))
	var xp: Dictionary = c.of(Protocol.JOB_XP)[0]
	eq(int(xp["gained"]), 100)
	eq(int(xp["view"]["job"]), 2)
	eq(p.character.jobs.xp_of(2), 100)
	eq(int(p.character.criteria_values()["jobs"][2]), p.character.jobs.level(2))
	check(p.character.inventory.to_array().is_empty(), "the scroll is used up")


func test_quest_rewards_teach_jobs() -> void:
	var r := QuestEngine.rewards({"rows": [{"level_min": -1, "level_max": -1, "xp": 0.0, "kamas": 0.0, "scale": 0, "items": [],
			"emotes": [], "spells": [], "titles": [], "jobs": [27, 47]}], "level": 1}, 5)
	eq(r["jobs"], [27, 47])
	var log := JobLog.new()
	log.learn(27)
	eq(log.to_views().size(), 1, "a taught job is listed")
	eq(log.level(27), Jobs.START_LEVEL)
