## A roaming monster group: one actor on one cell, several looks (leader first).
## Followers placement is purely visual and left to the client, like in Dofus.
class_name MonsterGroup
extends SimActor

## next time the AI may decide something (ms)
var next_think := 0
var home_cell := 0
## fight stats of each member: [{look, name, level, hp, ap, mp}] (same order as looks)
var members: Array = []
## the spawn entry it came from (respawned after being defeated)
var spawn := {}
## Dofus subarea it belongs to, and its stars (SubareaBonus, XP and loot bonus in %)
var subarea := 0
var bonus := 0
## player id -> when they entered the leader's vision (aggression, MapInstance)
var seen := {}


func kind() -> String:
	return "monster_group"


## Public info of each member (what hovering the group shows in Dofus): name,
## level, grade and base XP (the tooltip's XP estimate, FightXp.estimate),
## never the fight stats or the loot; the group's stars (`bonus`, %).
func to_dict(now: int) -> Dictionary:
	var d := super.to_dict(now)
	d["members"] = members.map(func(m: Dictionary) -> Dictionary:
		return {"name": str(m.get("name", "")), "name_id": int(m.get("name_id", 0)), "level": int(m.get("level", 1)),
				"grade": int(m.get("grade", 1)), "xp": int(m.get("xp", FightXp.monster_xp(int(m.get("level", 1)))))})
	d["bonus"] = bonus
	return d
