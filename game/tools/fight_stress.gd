## Stress test of the fights: the player's fighter is played by the monster AI too (AI vs AI), for
## every class, several levels and seeds, against the monster groups of a world. Reports the
## fights that never end, the turns that last too long, and the enemies that stop playing
## (several own turns in a row with no action while they could still walk or cast).
##   godot --headless --path game -s res://tools/fight_stress.gd -- --world=incarnam --breeds=1-19 \
##         --levels=5,30,80 --seeds=1,2 [--seconds=240]
extends SceneTree

var _issues: PackedStringArray = []
var _trace := false


func _init() -> void:
	var opts := {"world": "incarnam", "breeds": "1-19", "levels": "5,30,80", "seeds": "1,2", "seconds": "240", "trace": "0"}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		if kv.size() == 2:
			opts[kv[0]] = kv[1]
	_trace = opts["trace"] == "1"
	var breeds: Array = _ints(opts["breeds"])
	var fights := 0
	for breed: int in breeds:
		for level: int in _ints(opts["levels"]):
			for seed_v: int in _ints(opts["seeds"]):
				fights += _one(str(opts["world"]), breed, level, seed_v, float(opts["seconds"]))
	print("fights: %d, issues: %d" % [fights, _issues.size()])
	for s in _issues:
		print("  ISSUE ", s)
	quit()


static func _ints(text: String) -> Array:
	var out: Array = []
	for part in text.split(","):
		if part.contains("-"):
			for i in range(int(part.get_slice("-", 0)), int(part.get_slice("-", 1)) + 1):
				out.append(i)
		elif part != "":
			out.append(int(part))
	return out


func _one(world: String, breed: int, level: int, seed_v: int, seconds: float) -> int:
	var backend := LocalBackend.new()
	backend.seed = seed_v
	var ch := {"name": "Stress", "breed": breed, "level": level, "map": -1}
	backend.persistence.save_character(world, "Stress", ch)
	var tag := "breed %d lvl %d seed %d" % [breed, level, seed_v]
	var events: Array = []
	backend.event.connect(func(ev: Dictionary) -> void: events.append(ev))
	backend.send(Protocol.hello(world, "Stress", "{1|120,2195||56}"))
	backend.poll(0.0)
	var groups: Array = []
	for ev: Dictionary in events:
		if ev["t"] == Protocol.MAP_ENTER:
			for a: Dictionary in ev["actors"]:
				if a["kind"] == "monster_group":
					groups.append(int(a["id"]))
	if groups.is_empty():
		return 0
	var count := 0
	for gid: int in groups.slice(0, 2):
		events.clear()
		backend.send(Protocol.fight_attack(gid))
		backend.poll(0.05)
		if backend.sim.fights.is_empty():
			continue
		var fight: Fight = backend.sim.fights.values()[0]
		for f: Fighter in fight.fighters.values():
			f.ai = true
		var enemies := fight.fighters.values().filter(func(f: Fighter) -> bool: return f.team == 1).size()
		count += 1
		_play(backend, fight, "%s group %d (%d monsters)" % [tag, gid, enemies], seconds)
		backend.sim.fights.clear()
		break
	backend.close()
	return count


func _play(backend: LocalBackend, fight: Fight, tag: String, seconds: float) -> void:
	var start := backend.time_ms()
	var idle := {} # fighter id -> own turns in a row with no action
	var acted := false
	var last_cur := -1
	var turn_start := backend.time_ms()
	var deaths := 0
	var dead_seen := {}
	var step := 0.05
	var counter := {"n": 0}
	backend.event.connect(func(ev: Dictionary) -> void:
			var t := str(ev["t"])
			if t == Protocol.FIGHTER_MOVE or t == Protocol.SPELL_CAST:
				counter["n"] += 1
			if not _trace:
				return
			if t == Protocol.FIGHT_TURN:
				var c: Fighter = fight.fighters[int(ev["id"])]
				print("[%d] turn #%d %s team %d cell %d hp %d/%d ap %d mp %d profile %s" % [backend.time_ms(), c.id, c.name, c.team, c.cell, c.hp, c.max_hp, c.ap, c.mp, FightAI.profile(c)])
			elif t == Protocol.FIGHTER_MOVE:
				print("   move #%d %s" % [int(ev["id"]), str(ev["path"])])
			elif t == Protocol.SPELL_CAST:
				print("   cast #%d spell %d on %d" % [int(ev["caster"]), int(ev["spell"]), int(ev["cell"])]))
	var guard := int(seconds / step)
	for i in guard:
		backend.poll(step)
		if fight.result != "":
			break
		var cur := fight.current()
		if cur == null:
			continue
		if cur.id != last_cur:
			if last_cur != -1 and fight.fighters.has(last_cur):
				var prev: Fighter = fight.fighters[last_cur]
				if prev.alive and prev.ai and prev.team == 1:
					idle[prev.id] = 0 if acted else int(idle.get(prev.id, 0)) + 1
					if int(idle[prev.id]) == 3 and _could_play(fight, prev):
						_issues.append("%s: enemy %s (#%d) idle 3 turns in a row after %d deaths, cell %d ap %d mp %d hp %d/%d profile %s" % [
								tag, prev.name, prev.id, deaths, prev.cell, prev.max_ap, prev.max_mp, prev.hp, prev.max_hp, FightAI.profile(prev)])
			last_cur = cur.id
			counter["n"] = 0
			acted = false
			turn_start = backend.time_ms()
		acted = counter["n"] > 0
		if _trace and backend.time_ms() > 73200 and backend.time_ms() < 73260 and cur.team == 1:
			var reach := FightRules.reachable(fight.map, fight.occupied(cur.id), cur.cell, cur.mp)
			print("DEBUG #%d cell %d mp %d reach %d best_cast %s spells %s flee_turns %d fleeing %s" % [cur.id, cur.cell, cur.mp, reach.size(), str(FightAI._best_cast(fight, cur)), str(cur.spells), cur.flee_turns, str(FightAI.fleeing(cur))])
			var sp := cur.spell(1001001)
			print("   spell range %s ap %s los %s effects %s maxr %d" % [str(sp.get("range")), str(sp.get("ap")), str(sp.get("los")), str(sp.get("effects")).substr(0, 300), FightRules.max_range(sp, cur.stat("range"))])
			print("   want %d profile %s" % [FightAI._distance_wanted(cur, false), FightAI.profile(cur)])
			for g: Fighter in fight.fighters.values():
				print("   fighter #%d team %d cell %d alive %s dist %d" % [g.id, g.team, g.cell, str(g.alive), FightRules.distance(cur.cell, g.cell)])
		if not cur.alive:
			_issues.append("%s: a dead fighter (%s) holds the turn" % [tag, cur.name])
		if backend.time_ms() - turn_start > 90000:
			_issues.append("%s: turn of %s (#%d, ai %s) lasts more than 90 s" % [tag, cur.name, cur.id, str(cur.ai)])
			return
		for f: Fighter in fight.fighters.values():
			if not f.alive and not dead_seen.has(f.id) and f.team == 1 and f.summoner == -1:
				dead_seen[f.id] = true
				deaths += 1
	if fight.result == "":
		_issues.append("%s: not finished after %d s (turn %d, round %d)" % [tag, int((backend.time_ms() - start) / 1000), fight.turn, fight.fight_round])


## Whether an idle enemy had something to do: an enemy it can walk to, with MP.
func _could_play(fight: Fight, f: Fighter) -> bool:
	if f.max_mp <= 0 and f.max_ap <= 0:
		return false
	for g: Fighter in fight.fighters.values():
		if g.alive and g.team != f.team and FightRules.distance(f.cell, g.cell) > 1:
			return true
	return false
