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
##   {errors, family, casts, can_hurt, start, mortal, heals_others, dummy_lost, hp, alive, fighters, summons, ap_spent, cells, turns, ticks, ally_healed}
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
	var hurt_castable := false # one of its attack spells could be cast at the start of one of its turns
	var heal_castable := false # ... and one that heals someone else
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
				hurt_castable = hurt_castable or can_hurt_now(fight, mon)
				heal_castable = heal_castable or can_heal_now(fight, mon)
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
	var casts := 0
	for ev: Dictionary in st["events"]:
		if str(ev.get("t", "")) == Protocol.SPELL_CAST and int(ev.get("caster", 0)) == mon.id:
			casts += 1
	return {"errors": errors, "family": family, "casts": casts, "can_hurt": hurt_castable and can_hurt(mon), "start": mon.start_spell > 0, "mortal": mortal(mon.start_spell), "heals_others": heal_castable and heals_others(mon), "dummy_lost": DUMMY_HP - dummy.hp, "hp": mon.hp, "alive": mon.alive,
			"fighters": fight.fighters.size(), "summons": summons, "ap_spent": mon.ap_spent, "turns": mon_turns,
			"ticks": ticks, "moved": mon.cell != cell_at(GAP, 0), "gap": FightRules.distance(mon.cell, dummy.cell),
			"ally_healed": ally != null and ally.hp > ally.max_hp / 2, "result": fight.result}


## Whether a spell of `f` can hurt an enemy at all: an effect that damages, steals life or kills something other
## than its caster (H.04d: a monster of buffs and debuffs only has nothing to hurt the dummy with).
static func can_hurt(f: Fighter) -> bool:
	return f.spells.any(func(sid: int) -> bool: return spell_hurts(f.spell(sid)))


## Whether an attack spell of `f` passes the checks of a cast at this moment (criterion on its states, cooldown...).
static func can_hurt_now(fight: Fight, f: Fighter) -> bool:
	for sid: int in f.spells:
		if fight.spell_block(f, sid) == "" and spell_hurts(f.spell(sid)):
			return true
	return false


static func can_heal_now(fight: Fight, f: Fighter) -> bool:
	for sid: int in f.spells:
		if fight.spell_block(f, sid) == "" and spell_heals_others(f.spell(sid)):
			return true
	return false


static func spell_heals_others(spell: Dictionary) -> bool:
	for e: Dictionary in spell.get("effects", []):
		if str(e.get("kind", "")) == "heal" and not ["caster", "enemies"].has(str(e.get("target", "all"))):
			return true
	return false


static func spell_hurts(spell: Dictionary) -> bool:
	for e: Dictionary in (spell.get("effects", []) as Array) + (spell.get("crit_effects", []) as Array):
		# `caster_missing_pct`: the damage is a share of the life the CASTER is missing: nothing at full life
		if ["damage", "steal", "kill"].has(str(e.get("kind", ""))) and str(e.get("target", "all")) != "caster" and not bool(e.get("caster_missing_pct", false)):
			return true
	return false


## Whether the spell `spell_id` (a start spell, with the spells it casts) kills its own caster: a monster that
## lives a few turns (a totem, a mine) dies in the game and that is what its data says.
static func mortal(spell_id: int, seen := {}) -> bool:
	if spell_id <= 0 or seen.has(spell_id):
		return false
	seen[spell_id] = true
	var spell := SpellBook.get_spell(spell_id)
	for e: Dictionary in (spell.get("effects", []) as Array) + (spell.get("crit_effects", []) as Array):
		if str(e.get("kind", "")) == "kill" and str(e.get("target", "all")) == "caster":
			return true
		if e.has("spell") and mortal(int(e["spell"]), seen):
			return true
	return false


## Whether a spell of `f` heals someone else than its caster.
static func heals_others(f: Fighter) -> bool:
	return f.spells.any(func(sid: int) -> bool: return spell_heals_others(f.spell(sid)))


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
