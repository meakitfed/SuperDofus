## Fight XP, the official Dofus 3 formulas of the client data. Shared: the sim
## rewards a fight with it (FightRewards) and the client estimates a monster
## group's XP in its tooltip (the same numbers).
##   luaformulas 99, group XP = floor(Σ xp of the dead monsters × level
##     coefficient × (win ? group bonus[humans] : 1/4) × rewardRate)
##     level coefficient = monsters / players total levels when the players
##     are much stronger (and the reverse when much weaker);
##     rewardRate = the fight's coefficient: the stars (SubareaBonus).
##   luaformulas 100, player XP = group XP × min(level, 2.5 × best monster
##     level) / best player level × (100 + wisdom) / 100.
class_name FightXp
extends RefCounted

const GROUP_BONUS := [1.0, 1.1, 1.5, 2.3, 3.1, 3.6, 4.2, 4.7, 5.15, 5.55, 5.9, 6.2]


## luaformulas 2: a monster's base XP when its data has none (real worlds
## carry monsters.grades.gradeXp).
static func monster_xp(level: int, boss := false) -> int:
	if level < 200:
		if boss:
			return int(floor(((level * 100 + pow(level, 1.75) * 2) * level * 0.1) * 1.2 * 0.5))
		return level * 100 + level * level * 2
	return int(floor((500000.0 if boss else 100000.0) * (1 + (level - 200) / 100.0)))


## luaformulas 99. `dead_xp` = Σ xp of the dead monsters; `humans` = players
## above a third of the best player's level.
static func group_xp(dead_xp: float, monster_levels: int, player_levels: int, humans: int, win: bool,
		reward_rate := 1.0) -> int:
	var total := dead_xp
	if player_levels - 5 > monster_levels:
		total *= float(monster_levels) / player_levels
	elif monster_levels > player_levels + 10:
		total *= float(player_levels + 10) / monster_levels
	if win:
		if humans > 0:
			total *= GROUP_BONUS[mini(humans, GROUP_BONUS.size()) - 1]
	else:
		total /= 4.0
	return int(floor(total * reward_rate))


## luaformulas 100: one player's share.
## `challenge` = challengeCoefficient (P1.15, FightChallenges.coefficient).
static func player_xp(group: int, level: int, max_monster: int, max_player: int, wisdom: int, challenge := 1.0) -> int:
	if group <= 0:
		return 0
	var xp := challenge * float(group) * mini(level, int(max_monster * 2.5)) / maxi(1, max_player)
	if wisdom > 0:
		xp *= (100.0 + wisdom) / 100.0
	return maxi(1, int(xp))


## The XP a player alone would win against the whole group (monster group
## tooltip). `members` = [{level, xp}], `bonus` = the group's stars in %.
static func estimate(members: Array, level: int, wisdom: int, bonus := 0) -> int:
	var xp := 0.0
	var levels := 0
	var best := 1
	for m: Dictionary in members:
		xp += float(m.get("xp", 0))
		levels += int(m.get("level", 1))
		best = maxi(best, int(m.get("level", 1)))
	var g := group_xp(xp, levels, level, 1, true, 1.0 + bonus / 100.0)
	return player_xp(g, level, best, level, wisdom)
