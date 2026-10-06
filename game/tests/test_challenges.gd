## Fight challenges, options, flee and turn timer (roadmap P1.15).
extends TestCase

const LOOK := "{1|120,2195||56}"


func _init() -> void:
	SpellBook.use_file("res://tests/fixtures/spells.json")
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()


## A bare fight: allies (team 0, ids 1..) and foes (team 1, ids 11..), nobody plays by itself.
class Arena:
	var fight: Fight
	var events: Array = []

	func _init(allies := 1, foes := 2, ally_level := 10, foe_levels: Array = []) -> void:
		fight = Fight.new(1, MapData.new(), 7, func(ev: Dictionary) -> void: events.append(ev))
		for i in allies:
			add(1 + i, 0, ally_level, 300 + 2 * i)
		for i in foes:
			add(11 + i, 1, int(foe_levels[i]) if i < foe_levels.size() else 5, 400 + 2 * i)
		fight.start_placement(0)
		fight.begin(0)

	func add(id: int, team: int, level: int, cell: int) -> Fighter:
		var f := Fighter.new()
		f.id = id
		f.team = team
		f.level = level
		f.cell = cell
		f.hp = 100
		f.max_hp = 100
		f.player_id = id if team == 0 else -1
		fight.add_fighter(f)
		return f

	func f(id: int) -> Fighter:
		return fight.fighters[id]

	func chal(id: int) -> Dictionary:
		for c: Dictionary in fight.challenges:
			if int(c["id"]) == id:
				return c
		return {}

	## The fight starts over with exactly these challenges.
	func with(ids: Array, target := -1) -> Arena:
		fight.challenges = ids.map(func(i: int) -> Dictionary:
			return {"id": i, "name_id": 0, "desc_id": 0, "icon": 0, "state": "running", "target": target, "bonus": FightChallenges.BONUS})
		FightChallenges.begin(fight)
		return self

	func kill(id: int, by := 1, weapon := true) -> void:
		var v := f(id)
		v.hp = 0
		v.alive = false
		v.last_hit_by = by
		v.last_hit_weapon = weapon
		FightChallenges.observe(fight)

	func updates() -> Array:
		return events.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.CHALLENGE_UPDATE)


# ── drawing ──────────────────────────────────────────────────────────────────

func test_pick_respects_activation_and_incompatibilities() -> void:
	var a := Arena.new(1, 3)
	a.fight.draw_challenges()
	eq(a.fight.challenges.size(), 2, "3 foes: two challenges")
	var ids: Array = a.fight.challenges.map(func(c: Dictionary) -> int: return int(c["id"]))
	var row := GameData.row("challenges", ids[0])
	check(not (row["incompatibleChallenges"] as Array).has(ids[1]), "never two incompatible challenges")
	for id: int in ids:
		check(FightChallenges.RULES.has(id), "only simulated rules")
		eq(int(GameData.row("challenges", id)["targetMonsterId"]), 0, "generic challenges only")
	var low := Arena.new(1, 2, 3) # GL>4,0: the party must be above level 4
	low.fight.draw_challenges()
	eq(low.fight.challenges.size(), 0, "no challenge for a level 3 party")
	var solo := Arena.new(1, 1)
	solo.fight.draw_challenges()
	eq(solo.fight.challenges.size(), 1, "one challenge against a lone monster")
	var ally_only: Array = []
	for i in 40: # a lone player never gets a challenge that needs another ally (GN>1,0)
		var s := Arena.new(1, 1)
		s.fight._seed = i
		s.fight.draw_challenges()
		ally_only.append_array(s.fight.challenges.map(func(c: Dictionary) -> int: return int(c["id"])))
	check(not ally_only.has(37) and not ally_only.has(39) and not ally_only.has(5), "needs allies / level 90: never drawn alone")


func test_drawing_does_not_move_the_fight_dice() -> void:
	var a := Arena.new(1, 3)
	var b := Arena.new(1, 3)
	a.fight.draw_challenges()
	eq(a.fight.rng.randi(), b.fight.rng.randi(), "own generator")
	var c := Arena.new(1, 3)
	c.fight.draw_challenges()
	eq(JSON.stringify(a.fight.challenges), JSON.stringify(c.fight.challenges), "same seed, same challenges")


# ── rules ────────────────────────────────────────────────────────────────────

func test_intouchable_fails_on_damage_and_stays_failed() -> void:
	var a := Arena.new().with([17])
	FightChallenges.observe(a.fight)
	eq(a.chal(17)["state"], "running")
	a.f(11).hp = 90 # a foe being hurt is fine
	a.f(1).hp = 80
	FightChallenges.observe(a.fight)
	eq(a.chal(17)["state"], "failed")
	eq(a.updates().size(), 1, "challenge_update sent once")
	eq(a.updates()[0]["state"], "failed")
	a.kill(11)
	a.kill(12)
	a.fight._finish("win")
	eq(a.chal(17)["state"], "failed", "a won fight does not save it")
	near(FightChallenges.coefficient(a.fight), 1.0)


func test_success_pays_the_bonus() -> void:
	var a := Arena.new().with([33])
	a.f(11).loot = {"xp": 1000, "kamas": [0, 0], "drops": [{"item": 5, "pct": 100}]}
	a.f(12).loot = {"xp": 1000, "kamas": [0, 0], "drops": []}
	a.kill(11)
	a.kill(12)
	a.fight._finish("win")
	eq(a.chal(33)["state"], "success")
	eq(a.updates().back()["state"], "success")
	near(FightChallenges.coefficient(a.fight), 1.25)
	var with_bonus: Dictionary = FightRewards.compute(a.fight)
	a.chal(33)["state"] = "failed"
	var without: Dictionary = FightRewards.compute(a.fight)
	var xp_with := int(with_bonus[1]["xp"])
	var xp_without := int(without[1]["xp"])
	check(xp_without > 0, "the fight gives XP")
	check(absf(float(xp_with) / xp_without - 1.25) < 0.01, "XP x1.25 (luaformulas 100 challengeCoefficient)")


func test_a_lost_fight_wins_nothing() -> void:
	var a := Arena.new().with([33])
	a.f(1).alive = false
	a.fight._finish("lose")
	eq(a.chal(33)["state"], "failed")
	near(FightChallenges.coefficient(a.fight), 1.0)


func test_survivant_fails_when_an_ally_dies() -> void:
	var a := Arena.new(2, 1).with([33])
	a.f(2).alive = false
	a.f(2).hp = 0
	FightChallenges.observe(a.fight)
	eq(a.chal(33)["state"], "failed")


func test_level_order_challenges() -> void:
	var up := Arena.new(1, 3, 10, [5, 9, 7]).with([10])
	up.kill(11) # level 5 first
	eq(up.chal(10)["state"], "running")
	up.kill(13) # level 7 before 9
	eq(up.chal(10)["state"], "running")
	up.kill(12)
	up.fight._finish("win")
	eq(up.chal(10)["state"], "success", "Cruel: ascending levels")
	var bad := Arena.new(1, 3, 10, [5, 9, 7]).with([10])
	bad.kill(12) # level 9 while a 5 stands
	eq(bad.chal(10)["state"], "failed")
	var down := Arena.new(1, 3, 10, [5, 9, 7]).with([25])
	down.kill(12)
	down.kill(13)
	eq(down.chal(25)["state"], "running", "Ordonne: descending levels")
	down.kill(11)
	down.fight._finish("win")
	eq(down.chal(25)["state"], "success")


func test_target_challenges() -> void:
	var first := Arena.new(1, 3).with([3], 12)
	first.kill(11)
	eq(first.chal(3)["state"], "failed", "Premier: another one died before the target")
	var ok := Arena.new(1, 3).with([3], 12)
	ok.kill(12)
	ok.kill(11)
	ok.kill(13)
	ok.fight._finish("win")
	eq(ok.chal(3)["state"], "success")
	var last := Arena.new(1, 3).with([4], 12)
	last.kill(11)
	eq(last.chal(4)["state"], "running")
	last.kill(12)
	eq(last.chal(4)["state"], "failed", "Dernier: the target fell while another stood")
	var last_ok := Arena.new(1, 2).with([4], 12)
	last_ok.kill(11)
	last_ok.kill(12)
	last_ok.fight._finish("win")
	eq(last_ok.chal(4)["state"], "success")


func test_barbare_weapon_kills() -> void:
	var a := Arena.new().with([9])
	a.kill(11, 1, true)
	eq(a.chal(9)["state"], "running")
	a.kill(12, 1, false)
	eq(a.chal(9)["state"], "failed", "a spell kill breaks Barbare")


func test_partage_and_doume() -> void:
	var share := Arena.new(2, 2).with([44])
	share.kill(11, 1)
	share.kill(12, 1)
	share.fight._finish("win")
	eq(share.chal(44)["state"], "failed", "ally 2 finished nobody")
	var share_ok := Arena.new(2, 2).with([44])
	share_ok.kill(11, 1)
	share_ok.kill(12, 2)
	share_ok.fight._finish("win")
	eq(share_ok.chal(44)["state"], "success")
	var doume := Arena.new(1, 2).with([974])
	doume.kill(11)
	doume.fight.fight_round += 1
	doume.kill(12)
	eq(doume.chal(974)["state"], "failed", "two different global turns")


func test_a_summon_does_not_count_as_a_foe_or_an_ally() -> void:
	var a := Arena.new().with([33, 17])
	var s := a.add(50, 0, 1, 310)
	s.summoner = 1
	FightChallenges.observe(a.fight)
	s.hp = 0
	s.alive = false
	FightChallenges.observe(a.fight)
	eq(a.chal(33)["state"], "running", "a dead summon is not a dead ally")
	eq(a.chal(17)["state"], "failed", "but its lost HP is allied HP lost")


func test_spell_repetition_challenges() -> void:
	var a := Arena.new().with([5, 6])
	FightChallenges.on_cast(a.fight, a.f(1), 100)
	eq(a.chal(6)["state"], "running")
	FightChallenges.on_turn_begin(a.fight, a.f(1))
	FightChallenges.on_cast(a.fight, a.f(1), 101)
	FightChallenges.on_cast(a.fight, a.f(1), 101)
	eq(a.chal(6)["state"], "failed", "Versatile: twice in one turn")
	eq(a.chal(5)["state"], "failed", "Econome: twice in the fight")
	var b := Arena.new().with([6])
	FightChallenges.on_cast(b.fight, b.f(1), 100)
	FightChallenges.on_turn_begin(b.fight, b.f(1))
	FightChallenges.on_cast(b.fight, b.f(1), 100)
	eq(b.chal(6)["state"], "running", "another turn: fine")


func test_turn_end_challenges() -> void:
	# Zombie: exactly 1 MP; Nomade: all MP
	var z := Arena.new().with([1, 8])
	z.f(1).mp = 0
	FightChallenges.on_turn_begin(z.fight, z.f(1))
	FightChallenges.on_walk(z.fight, z.f(1), 1)
	FightChallenges.on_turn_end(z.fight, z.f(1))
	eq(z.chal(1)["state"], "running")
	eq(z.chal(8)["state"], "running", "no MP left")
	FightChallenges.on_turn_begin(z.fight, z.f(1))
	FightChallenges.on_walk(z.fight, z.f(1), 2)
	FightChallenges.on_turn_end(z.fight, z.f(1))
	eq(z.chal(1)["state"], "failed", "2 MP used")
	# Statue: same cell at the end of the turn
	var s := Arena.new().with([2])
	s.f(1).turn_begin_cell = 300
	FightChallenges.on_turn_end(s.fight, s.f(1))
	eq(s.chal(2)["state"], "running")
	s.f(1).turn_begin_cell = 299
	FightChallenges.on_turn_end(s.fight, s.f(1))
	eq(s.chal(2)["state"], "failed")


func test_adjacency_challenges() -> void:
	var next := Arena.new(2, 1).with([36, 37, 39, 40])
	var foe_cell := next.f(11).cell
	next.f(1).cell = MapGeometry.from_iso(MapGeometry.to_iso(foe_cell) + Vector2i(1, 0))
	next.f(2).cell = MapGeometry.from_iso(MapGeometry.to_iso(next.f(1).cell) + Vector2i(1, 0))
	FightChallenges.on_turn_end(next.fight, next.f(1))
	eq(next.chal(36)["state"], "running", "Hardi: next to a foe")
	eq(next.chal(37)["state"], "running", "Collant: next to an ally")
	eq(next.chal(39)["state"], "failed", "Misanthrope: next to an ally")
	eq(next.chal(40)["state"], "failed", "Prudent: next to a foe")
	next.f(1).cell = 100
	next.f(2).cell = 500
	var far := Arena.new(2, 1).with([36, 37])
	far.f(1).cell = 100
	FightChallenges.on_turn_end(far.fight, far.f(1))
	eq(far.chal(36)["state"], "failed")
	eq(far.chal(37)["state"], "failed")


# ── options, flee, timer ─────────────────────────────────────────────────────

func test_options_belong_to_the_leader() -> void:
	var a := Arena.new(2, 1)
	eq(a.fight.handle(2, Protocol.fight_option("locked", true), 0), Protocol.E_NOT_LEADER)
	eq(a.fight.handle(1, Protocol.fight_option("nothing", true), 0), Protocol.E_UNKNOWN_OPTION)
	eq(a.fight.handle(1, Protocol.fight_option("locked", true), 0), "")
	eq(a.fight.options["locked"], true)
	var sent: Array = a.events.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.FIGHT_OPTIONS)
	eq(sent.size(), 1)
	eq(sent[0]["options"]["locked"], true)
	a.fight.handle(1, Protocol.fight_option("locked", true), 0)
	eq(a.events.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.FIGHT_OPTIONS).size(), 1, "no change, no message")
	eq(Protocol.validate(sent[0], Protocol.S2C), "")
	eq(Protocol.validate(Protocol.fight_option("help", true), Protocol.C2S), "")


func test_options_decide_who_may_join() -> void:
	var a := Arena.new()
	eq(a.fight.join_error(false), "")
	a.fight.options["party_only"] = true
	eq(a.fight.join_error(false), Protocol.E_FIGHT_PARTY_ONLY)
	eq(a.fight.join_error(true), "")
	a.fight.options["locked"] = true
	eq(a.fight.join_error(true), Protocol.E_FIGHT_LOCKED)
	eq(a.fight.join_error(false, true), "", "spectators are fine until secret")
	a.fight.options["secret"] = true
	eq(a.fight.join_error(false, true), Protocol.E_FIGHT_SECRET)


func test_leaving() -> void:
	var alone := Arena.new()
	alone.fight.handle(1, Protocol.fight_leave(), 0)
	eq(alone.fight.result, "abandon")
	var team := Arena.new(2, 1)
	team.fight.handle(2, Protocol.fight_leave(), 0)
	eq(team.fight.result, "", "the other player goes on")
	check(not team.f(2).alive)
	team.fight.handle(1, Protocol.fight_leave(), 0)
	eq(team.fight.result, "abandon")


func test_turn_times_out() -> void:
	var a := Arena.new()
	var first := a.fight.current()
	check(first != null)
	eq(a.fight.time_left(0), Fight.TURN_MS)
	a.fight.tick(Fight.TURN_MS - 1)
	eq(a.fight.current(), first, "still its turn")
	a.fight.tick(Fight.TURN_MS)
	check(a.fight.current() != first, "the turn ended by itself")
	eq(a.fight.turn_end, Fight.TURN_MS + Fight.TURN_MS)
	var turns: Array = a.events.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.FIGHT_TURN)
	eq(int(turns.back()["end"]), 2 * Fight.TURN_MS)


# ── through the backend ──────────────────────────────────────────────────────

func test_challenges_through_the_backend() -> void:
	var members: Array = []
	for i in 3:
		members.append({"look": "{4907|||130}", "name": "Tofu", "level": 3, "hp": 20, "ap": 4, "mp": 3})
	var source := WorldSource.from_dicts(
		{"id": "arena", "name": "Arena", "start_map": 1, "start_cell": 300, "wander_ms": [600000, 600000], "challenges": true},
		[{"id": 1, "coords": [0, 0], "groups": [{"name": "Tofus", "members": members}]}])
	var backend := LocalBackend.new()
	backend.sources["arena"] = source
	var events: Array = []
	backend.event.connect(func(ev: Dictionary) -> void: events.append(ev))
	backend.send(Protocol.hello("arena", "Tester", LOOK))
	backend.poll(0.1)
	var player := backend.sim.players.values()[0] as PlayerActor
	player.character.level = 12
	var group := -1
	for a: SimActor in backend.sim.maps[1].actors.values():
		if a is MonsterGroup:
			group = a.id
	backend.send(Protocol.fight_attack(group))
	backend.poll(0.05)
	var lists: Array = events.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.CHALLENGE_LIST)
	eq(lists.size(), 1, "challenge_list after fight_start")
	eq(Protocol.validate(lists[0], Protocol.S2C), "")
	eq((lists[0]["challenges"] as Array).size(), 2)
	backend.send(Protocol.fight_option("secret", true))
	backend.poll(0.05)
	check(events.any(func(e: Dictionary) -> bool: return e["t"] == Protocol.FIGHT_OPTIONS and e["options"]["secret"]), "fight_options came back")
	backend.send(Protocol.fight_leave())
	backend.poll(0.05)
	var updates: Array = events.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.CHALLENGE_UPDATE)
	eq(updates.size(), 2, "both challenges lost on abandon")
	var end: Dictionary = events.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.FIGHT_END)[0]
	eq(end["result"], "abandon")
