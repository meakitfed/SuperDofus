## End of fight rewards. XP: the official Dofus 3 formulas (luaformulas 99 and
## 100, shared/FightXp), × the fight's reward rate (the group's stars).
## Winners also get kamas (each dead monster's range, shared by prospecting) and
## APPROX(P1.09): the monsters' kamas ranges and their sharing are not Dofus 3 data;
## drops (each player rolls every drop: pct × prospecting / 100 × reward rate:
## the stars are an "XP and loot" bonus, https://dofus.jeuxonline.info/actualite/56075).
## Prospecting = 100 + chance / 10. Nothing for an abandon.
class_name FightRewards
extends RefCounted

## player fighter id -> {xp, kamas, items: {item id: qty}}
static func compute(fight: Fight) -> Dictionary:
	var players: Array = fight.fighters.values().filter(func(f: Fighter) -> bool: return f.player_id >= 0 and not f.left)
	# summons give nothing and do not count (P1.11)
	var monsters: Array = fight.fighters.values().filter(func(f: Fighter) -> bool: return f.team == 1 and f.summoner == -1)
	var out := {}
	for p: Fighter in players:
		out[p.id] = {"xp": 0, "kamas": 0, "items": {}}
	if fight.result == "abandon" or players.is_empty():
		return out
	var win := fight.result == "win"
	var dead := monsters.filter(func(m: Fighter) -> bool: return not m.alive)
	var dead_xp := 0.0
	for m: Fighter in dead:
		dead_xp += float(m.loot.get("xp", 0))
	var player_levels := 0
	var max_player := 1
	for p: Fighter in players:
		player_levels += p.level
		max_player = maxi(max_player, p.level)
	var monster_levels := 0
	var max_monster := 1
	for m: Fighter in monsters:
		monster_levels += m.level
		max_monster = maxi(max_monster, m.level)
	var humans := players.filter(func(p: Fighter) -> bool: return p.level > max_player / 3.0).size()
	var group := FightXp.group_xp(dead_xp, monster_levels, player_levels, humans, win, fight.reward_rate)
	# the challenges won raise the XP (luaformulas 100 challengeCoefficient) and the drops (P1.15)
	var bonus := FightChallenges.coefficient(fight) if win else 1.0
	for p: Fighter in players:
		out[p.id]["xp"] = FightXp.player_xp(group, p.level, max_monster, max_player, p.stat("wisdom"), bonus)
	if not win:
		return out
	# kamas, shared by prospecting
	var pp := {}
	var pp_total := 0
	for p: Fighter in players:
		pp[p.id] = prospecting(p)
		pp_total += int(pp[p.id])
	var kamas := 0
	for m: Fighter in dead:
		var k: Array = m.loot.get("kamas", [0, 0])
		kamas += fight.rng.randi_range(int(k[0]), maxi(int(k[0]), int(k[1])))
	for p: Fighter in players:
		out[p.id]["kamas"] = kamas * int(pp[p.id]) / maxi(1, pp_total)
	# drops, best prospectors roll first
	players.sort_custom(func(a: Fighter, b: Fighter) -> bool: return int(pp[a.id]) > int(pp[b.id]))
	for p: Fighter in players:
		var items: Dictionary = out[p.id]["items"]
		for m: Fighter in dead:
			for d: Dictionary in m.loot.get("drops", []):
				var chance := float(d.get("pct", 0)) * int(pp[p.id]) / 100.0 * fight.reward_rate * bonus
				if fight.rng.randf() * 100.0 < chance:
					var item := int(d["item"])
					items[item] = int(items.get(item, 0)) + 1
	return out


static func prospecting(f: Fighter) -> int:
	return StatFormulas.prospecting(f.stat)
