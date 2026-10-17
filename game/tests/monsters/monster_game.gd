## The standard fight every monster plays in (H.04): an open board, a training dummy (a level-100
## player with a huge life that never acts) and one monster built the way a fight builds it
## (WorldFights.monster_fighter), seed fixed. The fight advances with Fight.tick like the server does,
## so the AI's pacing (AI_MAX_ACTIONS, think times) is part of what is tested.
##
## Iso offsets from the board centre (MapGeometry.to_iso):
##   dummy (0,0)   monster (GAP,0)   ally (GAP+1,1) (a hurt monster of the same kind, for the healers)
class_name MonsterGame
extends RefCounted

const CENTER := 300
const SEED := 7
const GAP := 4
const TURNS := 6 # monster turns played
const STEP_MS := 150
const DUMMY_HP := 1000000
const DUMMY_LEVEL := 100
## ticks allowed for the whole game before it is a hang: a dummy turn lasts TURN_MS / STEP_MS ticks
const TICK_GUARD := 20000

static var _sim: WorldSim


## A WorldSim over an empty world: only there to build monsters with the real WorldFights code.
static func sim() -> WorldSim:
	if _sim == null:
		_sim = WorldSim.new(WorldSource.from_dicts({"id": "matrix", "name": "Matrix", "start_map": 1, "start_cell": CENTER},
				[{"id": 1, "coords": [0, 0], "groups": []}]))
	return _sim


static func monster(grade: Dictionary) -> Fighter:
	return sim().combat.monster_fighter(grade)


static func cell_at(dx: int, dy: int) -> int:
	return MapGeometry.from_iso(MapGeometry.to_iso(CENTER) + Vector2i(dx, dy))


static func make_dummy(level := DUMMY_LEVEL) -> Fighter:
	var d := Fighter.new()
	d.id = 1
	d.name = "mannequin"
	d.team = 0
	d.player_id = 0
	d.cell = CENTER
	d.level = level
	d.hp = DUMMY_HP
	d.max_hp = DUMMY_HP
	d.plays = true
	return d


## The standard fight, ready to run: {fight, events, dummy, mon, ally, family} (ally: healers only).
static func setup(grade: Dictionary) -> Dictionary:
	var events: Array = []
	var fight := Fight.new(1, MapData.new(), SEED, func(ev: Dictionary) -> void: events.append(ev))
	var dummy := make_dummy()
	fight.add_fighter(dummy)
	var mon := monster(grade)
	mon.id = 2
	mon.cell = cell_at(GAP, 0)
	fight.add_fighter(mon)
	var family := MonsterFamily.of(mon)
	var ally: Fighter = null
	if family == MonsterFamily.HEALER:
		ally = monster(grade)
		ally.id = 3
		ally.cell = cell_at(GAP + 1, 1)
		ally.hp = maxi(1, ally.max_hp / 2)
		ally.spells = []
		ally.ai = false
		fight.add_fighter(ally)
	fight.prepare()
	fight.start_placement(0)
	fight.begin(0)
	return {"fight": fight, "events": events, "dummy": dummy, "mon": mon, "ally": ally, "family": family}


## Plays `grade` against the dummy for TURNS monster turns. Returns the report:
##   {errors, family, dummy_lost, hp, alive, fighters, summons, ap_spent, cells, turns, ticks, ally_healed}
static func play(grade: Dictionary) -> Dictionary:
	var st := setup(grade)
	var fight: Fight = st["fight"]
	var dummy: Fighter = st["dummy"]
	var mon: Fighter = st["mon"]
	var ally: Fighter = st["ally"]
	var family: String = st["family"]
	var errors: PackedStringArray = []
	var now := 0
	var ticks := 0
	var mon_turns := 0
	var last_key := ""
	while fight.result == "" and mon_turns < TURNS and ticks < TICK_GUARD:
		ticks += 1
		now += STEP_MS
		var cur := fight.current()
		if cur == null:
			errors.append("no fighter has the turn")
			break
		var key := "%d/%d" % [fight.fight_round, cur.id]
		if key != last_key:
			last_key = key
			if cur == mon:
				mon_turns += 1
		if cur == dummy or cur == ally:
			fight.end_turn(now)
		else:
			fight.tick(now)
	if fight.result == "" and mon_turns < TURNS:
		errors.append("the fight stopped moving after %d ticks (monster turn %d)" % [ticks, mon_turns])
	errors.append_array(sanity(fight))
	var summons := 0
	for f: Fighter in fight.fighters.values():
		if f.summoner == mon.id:
			summons += 1
	return {"errors": errors, "family": family, "dummy_lost": DUMMY_HP - dummy.hp, "hp": mon.hp, "alive": mon.alive,
			"fighters": fight.fighters.size(), "summons": summons, "ap_spent": mon.ap_spent, "turns": mon_turns,
			"ticks": ticks, "moved": mon.cell != cell_at(GAP, 0), "gap": FightRules.distance(mon.cell, dummy.cell),
			"ally_healed": ally != null and ally.hp > ally.max_hp / 2, "result": fight.result}


## What can never be true of a fight in progress, whatever the monster.
static func sanity(fight: Fight) -> PackedStringArray:
	var out: PackedStringArray = []
	var seen := {}
	for f: Fighter in fight.fighters.values():
		if f.hp > f.max_hp or f.hp < 0:
			out.append("%s: hp %d outside 0..%d" % [f.name, f.hp, f.max_hp])
		if f.ap < 0 or f.mp < 0:
			out.append("%s: negative AP / MP (%d / %d)" % [f.name, f.ap, f.mp])
		if f.alive:
			if f.hp <= 0:
				out.append("%s: alive with %d hp" % [f.name, f.hp])
			if seen.has(f.cell):
				out.append("%s: shares cell %d" % [f.name, f.cell])
			seen[f.cell] = true
		elif f.hp > 0:
			out.append("%s: dead with %d hp" % [f.name, f.hp])
	return out


## The rewards of killing `grade`'s monster: a fight the dummy (of the monster's level) won, with a reward
## rate high enough for every drop. {xp, kamas, items} of the dummy, and the expected values.
static func rewards(grade: Dictionary) -> Dictionary:
	var fight := Fight.new(1, MapData.new(), SEED, func(_ev: Dictionary) -> void: pass)
	var mon := monster(grade)
	mon.id = 2
	var dummy := make_dummy(maxi(1, mon.level))
	fight.add_fighter(dummy)
	fight.add_fighter(mon)
	mon.hp = 0
	mon.alive = false
	fight.result = "win"
	var out: Dictionary = FightRewards.compute(fight)[dummy.id]
	var expected_xp := FightXp.player_xp(FightXp.group_xp(float(mon.loot.get("xp", 0)), mon.level, dummy.level, 1, true),
			dummy.level, mon.level, dummy.level, dummy.stat("wisdom"))
	# every drop at once: the chance (pct x prospecting x rate) tops 100 for any drop above 0 %
	fight.reward_rate = 100000.0
	var all_drops: Dictionary = FightRewards.compute(fight)[dummy.id]["items"]
	return {"xp": int(out["xp"]), "kamas": int(out["kamas"]), "expected_xp": expected_xp, "all_drops": all_drops}
