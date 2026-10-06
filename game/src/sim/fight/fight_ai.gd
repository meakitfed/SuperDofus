## Monster turns. One action at a time, like a player (only Fight.move / cast),
## so the AI runs unchanged in standalone and on a server:
##   1. for every spell it can cast and every cell it can walk to, estimate the
##      value of casting on the cells around the fighters (damage on enemies,
##      heals on hurt allies, AP/MP removal...; hitting allies counts against);
##      best > 0: walk there (next action casts), or cast;
##   2. otherwise walk towards the nearest enemy; 3. otherwise end the turn.
## Summons (P1.11) are played by this AI too, on their summoner's side.
## It only knows what its team knows (FightVisibility, P1.13c): invisible enemies are
## neither aimed at nor walked to (APPROX(P1.13c): it does not guess where they are).
## Deterministic (no randomness): same fight, same choices.
## Profiles (P1.16): the monsters data has no behaviour field (`monsters` : only aggression
## radius), so APPROX(P1.16) the profile is read from the spells the fighter owns:
##   kamikaze   a spell that kills its caster (bombs, explosions): rushes the enemies;
##   summoner   a summon spell: casts it first, then keeps its distance;
##   healer     a heal on allies: heals first, walks to its hurt allies, else keeps its distance;
##   cautious   only ranged damage spells: keeps its casting range, flees below FLEE_PCT of its HP;
##   aggressive everything else: closes in, hits the best target.
## Summoners and healers flee too when hurt; kamikazes never do.
class_name FightAI
extends RefCounted

const CAST_WAIT_MS := 1500
const MOVE_EXTRA_MS := 300
const FLEE_PCT := 30
const FLEE_MAX_TURNS := 3 # APPROX(P1.16): then it fights back (Dofus monsters do not flee at all): a runner nobody can catch stalls the fight
const AGGRESSIVE := "aggressive"
const CAUTIOUS := "cautious"
const HEALER := "healer"
const SUMMONER := "summoner"
const KAMIKAZE := "kamikaze"


## The profile of `f` (see the header), from its spells. Cached on the fighter.
static func profile(f: Fighter) -> String:
	if f.ai_profile != "":
		return f.ai_profile
	var kills := false
	var summons := false
	var heals := false
	var melee := false
	var ranged := false
	for sid: int in f.spells:
		var spell := f.spell(sid)
		var hits := false
		for e: Dictionary in spell.get("effects", []):
			var kind := str(e.get("kind", ""))
			if kind == "kill" and str(e.get("target", "")) == "caster":
				kills = true
			elif kind == "summon" or kind == "double":
				summons = true
			elif kind == "heal" and str(e.get("target", "all")) != "enemies":
				heals = true
			elif kind == "damage" or kind == "steal":
				hits = true
		if hits:
			if int(spell.get("range", [1, 1])[1]) <= 1:
				melee = true
			else:
				ranged = true
	f.ai_profile = KAMIKAZE if kills else SUMMONER if summons else HEALER if heals 			else CAUTIOUS if ranged and not melee else AGGRESSIVE
	return f.ai_profile


## Hurt below FLEE_PCT and not a kamikaze: it runs instead of closing in.
static func fleeing(f: Fighter) -> bool:
	return profile(f) != KAMIKAZE and profile(f) != AGGRESSIVE and f.hp * 100 < f.max_hp * FLEE_PCT


## Plays one action. Returns how long to wait before the next one, -1 = end the turn.
static func act(fight: Fight, f: Fighter, now: int) -> int:
	var flee := fleeing(f)
	if flee and fight._ai_actions == 1: # first action of the turn
		f.flee_turns += 1
	if flee and f.flee_turns > FLEE_MAX_TURNS:
		flee = false
	var wait := _act(fight, f, now, flee)
	if wait < 0 and flee and fight._ai_actions <= 1: # cornered, nothing to do at all this turn: it fights back
		wait = _act(fight, f, now, false)
	return wait


static func _act(fight: Fight, f: Fighter, now: int, flee: bool) -> int:
	var best := _best_cast(fight, f, flee)
	if not best.is_empty():
		if int(best["from"]) != f.cell:
			return _move(fight, f, int(best["from"]), now)
		if fight.cast(f, int(best["spell"]), int(best["cell"]), now) == "":
			return CAST_WAIT_MS
		return -1
	var enemies := _enemies(fight, f)
	if f.mp <= 0 or enemies.is_empty():
		return -1
	var reach := FightRules.reachable(fight.map, fight.occupied(f.id), f.cell, f.mp)
	var best_cell := f.cell
	var hurt := _hurt_allies(fight, f) if profile(f) == HEALER and not flee else []
	var goals: Array = hurt if not hurt.is_empty() else enemies
	var want := 1 if not hurt.is_empty() else _distance_wanted(f, flee)
	var best_d := _gap(f.cell, goals, want)
	for c: int in reach:
		var d := _gap(c, goals, want)
		if d < best_d or (d == best_d and int(reach[c]) < int(reach[best_cell])):
			best_d = d
			best_cell = c
	# nothing to cast with all its AP (out of sight, out of reach...) while it holds its range: it closes in
	var stuck := f.ap > 0 and fight._ai_actions <= 1 and _nearest(f.cell, goals) > 1
	if best_cell == f.cell and not flee and want >= 0 and (_nearest(f.cell, goals) > want or stuck):
		best_cell = _detour(fight, f, goals, reach)
	if best_cell == f.cell:
		return -1
	return _move(fight, f, best_cell, now)


## No reachable cell is nearer in a straight line (an obstacle in the way: walking round it starts by
## moving away): the reachable cell with the shortest WALK to the nearest goal, `f.cell` if none is better.
static func _detour(fight: Fight, f: Fighter, goals: Array, reach: Dictionary) -> int:
	var walk := {}
	for g: Fighter in goals:
		var d := FightRules.reachable(fight.map, {}, g.cell, 9999)
		for c: int in d:
			if not walk.has(c) or int(d[c]) < int(walk[c]):
				walk[c] = d[c]
	var best_cell := f.cell
	var best_w := int(walk.get(f.cell, 9999))
	for c: int in reach:
		var w := int(walk.get(c, 9999))
		if w < best_w or (w == best_w and best_cell != f.cell and int(reach[c]) < int(reach[best_cell])):
			best_w = w
			best_cell = c
	return best_cell


## The distance to the nearest enemy this fighter walks to: 0 = closing in, a number = keeps
## that distance, -1 = as far as it can (fleeing). Healers first walk to a hurt ally (_hurt_allies).
static func _distance_wanted(f: Fighter, flee: bool) -> int:
	if flee:
		return -1
	match profile(f):
		AGGRESSIVE, KAMIKAZE:
			return 0
		_:
			var r := 1
			for sid: int in f.spells:
				r = maxi(r, FightRules.max_range(f.spell(sid), f.stat("range")))
			return r


## How far `cell` is from what the fighter wants (smaller = better): the gap to `want`
## cells from the nearest enemy, or minus that distance when fleeing.
static func _gap(cell: int, enemies: Array, want: int) -> int:
	var d := _nearest(cell, enemies)
	return -d if want < 0 else absi(d - want)


static func _move(fight: Fight, f: Fighter, to: int, now: int) -> int:
	var path := FightRules.path_to(fight.map, fight.occupied(f.id), f.cell, to, f.mp)
	if fight.move(f, to, now) != "":
		return -1
	return Movement.duration_ms(path, path.size() > 3) + MOVE_EXTRA_MS


## {spell, from, cell, score} of the best cast (walking first if needed), {} if none is worth it.
## `stay` (fleeing): only casts from where it stands.
static func _best_cast(fight: Fight, f: Fighter, stay := false) -> Dictionary:
	var best := {}
	var best_score := 0.5
	var occ := fight.occupied(f.id)
	var reach := FightRules.reachable(fight.map, occ, f.cell, f.mp)
	if stay:
		reach = {f.cell: 0}
	var candidates := {}
	for g: Fighter in fight.fighters.values():
		if g.alive and not FightVisibility.hidden(fight, g.id, f.team):
			candidates[g.cell] = true
			for n in FightRules.neighbors4(g.cell):
				candidates[n] = true
	for sid: int in f.spells:
		var spell := FightRules.for_caster(f.spell(sid), f.state_ids())
		if spell.is_empty() or int(spell.get("ap", 0)) > f.ap or fight.spell_block(f, sid) != "" \
				or Summons.cast_error(fight, f, spell) != "":
			continue
		var r: Array = spell.get("range", [1, 1])
		var max_r := FightRules.max_range(spell, f.stat("range"))
		for from: int in reach:
			for cell: int in candidates:
				var d := FightRules.distance(from, cell)
				if d < int(r[0]) or d > max_r:
					continue
				if FightRules.cast_error(fight.map, occ, spell, from, cell, f.ap, f.stat("range")) != "":
					continue
				if fight.target_limit_reached(f, sid, fight.fighter_at(cell)):
					continue
				var score := _score(fight, f, spell, from, cell) - int(reach[from]) * 0.5 * _walk_cost(f)
				if score > best_score:
					best_score = score
					best = {"spell": sid, "from": from, "cell": cell, "score": score}
	return best


## Kamikazes do not mind the walk, the others pay half a point per cell.
static func _walk_cost(f: Fighter) -> float:
	return 0.0 if profile(f) == KAMIKAZE else 1.0


## Expected value of `spell` cast from `from` on `cell` (f standing on `from`).
static func _score(fight: Fight, f: Fighter, spell: Dictionary, from: int, cell: int) -> float:
	var score := 0.0
	for e: Dictionary in spell.get("effects", []):
		if not FightEffects.cond_ok(e, f, null) or bool(e.get("carried", false)):
			continue
		match str(e.get("kind", "")):
			"summon", "double": # APPROX(P1.11): a summon is worth a good hit, on a free cell
				score += (25.0 if profile(f) == SUMMONER else 8.0) if fight.fighter_at(cell) == null and fight.map.is_fight_walkable(cell) else 0.0
				continue
			"replace":
				var old := fight.fighter_at(cell)
				score += 6.0 if old != null and old.summoner == f.id else 0.0
				continue
		var targets: Array = []
		if str(e.get("target", "all")) == "caster":
			targets = [f]
		else:
			for c in FightRules.zone_in(fight.map, fight.occupied(f.id), e.get("area", spell.get("area", {})), cell, from):
				var t: Fighter = f if c == from else (null if c == f.cell else fight.fighter_at(c))
				if t == null or FightVisibility.hidden(fight, t.id, f.team):
					continue
				var who := str(e.get("target", "all"))
				if (who == "enemies" and t.team == f.team) or (who == "allies" and t.team != f.team):
					continue
				targets.append(t)
		for t: Fighter in targets:
			if not FightEffects.cond_ok(e, f, t):
				continue
			var enemy := t.team != f.team
			var avg := (float(e.get("min", 0)) + float(e.get("max", 0))) * 0.5
			match str(e.get("kind", "")):
				"damage", "steal":
					var elem := str(e.get("element", "neutral"))
					var power := f.stat(Fighter.ELEMENT_STAT.get(elem, "strength")) + f.stat("power")
					var dmg := avg * (100 + power) / 100.0 * (100 - clampi(t.stat("res_" + elem), -100, 100)) / 100.0
					if int(e.get("duration", 0)) > 0:
						dmg *= 1.5
					var v := minf(dmg, t.hp) + (30.0 if dmg >= t.hp else 0.0)
					if enemy and profile(f) == HEALER:
						v *= 0.5 # APPROX(P1.16)
					score += v if enemy else -1.5 * v
				"heal":
					if not enemy:
						score += minf(avg, t.max_hp - t.hp) * (1.6 if profile(f) == HEALER else 0.8)
				"ap", "mp":
					var sign := int(e.get("sign", 1))
					score += (6.0 * avg if enemy == (sign < 0) else -3.0 * avg)
				"push", "pull":
					score += 2.0 if enemy else -1.0
				"stat", "shield", "state":
					score += 1.0 if (enemy == (int(e.get("sign", 1)) < 0)) else 0.0
	return score


static func _enemies(fight: Fight, f: Fighter) -> Array:
	return fight.fighters.values().filter(func(g: Fighter) -> bool:
		return g.alive and g.team != f.team and not FightVisibility.hidden(fight, g.id, f.team))


static func _hurt_allies(fight: Fight, f: Fighter) -> Array:
	return fight.fighters.values().filter(func(g: Fighter) -> bool:
		return g.alive and g.id != f.id and g.team == f.team and g.hp < g.max_hp)


static func _nearest(cell: int, enemies: Array) -> int:
	var d := 9999
	for g: Fighter in enemies:
		d = mini(d, FightRules.distance(cell, g.cell))
	return d
