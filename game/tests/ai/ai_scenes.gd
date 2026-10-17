## The AI profile scenes (H.05), the situations of tests/test_ai_profiles.gd written as data: a monster
## of team 1 that plays first, a player 100-life foe `gap` cells away on the same line, hand-made spells.
## Each scene is played for the first turn of the monster (AiTrace) and written to
## tests/golden/monsters/ai_profiles.json.
class_name AiScenes
extends RefCounted

const HIT := 9001
const SHOT := 9002
const CURE := 9003
const CALL := 9004
const BOOM := 9005
const CENTER := 300
const SEED := 7


static func _area() -> Dictionary:
	return {"shape": "point", "size": 0}


static func spell(effects: Array, range := [1, 1], los := false) -> Dictionary:
	return {"ap": 3, "range": range, "range_boost": false, "los": los, "in_line": false,
			"need_free_cell": false, "need_taken_cell": false, "per_turn": 9, "per_target": 9,
			"cooldown": 0, "initial_cooldown": 0, "crit": 0, "area": _area(),
			"effects": effects, "crit_effects": []}


static func dmg() -> Dictionary:
	return eff("damage", "enemies", "neutral")


static func eff(kind: String, who: String, element := "") -> Dictionary:
	var e := {"target": who, "min": 20, "max": 20, "duration": 0, "delay": 0, "mask": "", "kind": kind, "area": _area()}
	if element != "":
		e["element"] = element
	return e


static func summon() -> Dictionary:
	return {"kind": "summon", "target": "all", "monster": 5894, "grade": 1}


static func at(dx: int, dy: int) -> int:
	return MapGeometry.from_iso(MapGeometry.to_iso(CENTER) + Vector2i(dx, dy))


## name -> {profile, spells, gap, and optional hp, ap, wall, blind, corner, ally (a cell)}
static func scenes() -> Dictionary:
	var melee := {HIT: spell([dmg()])}
	var shooter := {SHOT: spell([dmg()], [2, 5])}
	var healer := {HIT: spell([dmg()]), CURE: spell([eff("heal", "allies")], [1, 4])}
	var caller := {HIT: spell([dmg()]), CALL: spell([summon()], [1, 4])}
	var bomb := {BOOM: spell([dmg(), eff("kill", "caster")])}
	return {
		"aggressive_far": {"profile": FightAI.AGGRESSIVE, "spells": melee, "gap": 6},
		"aggressive_adjacent": {"profile": FightAI.AGGRESSIVE, "spells": melee, "gap": 1},
		"aggressive_wall": {"profile": FightAI.AGGRESSIVE, "spells": melee, "gap": 8, "wall": true},
		"cautious_far": {"profile": FightAI.CAUTIOUS, "spells": shooter, "gap": 9},
		"cautious_close": {"profile": FightAI.CAUTIOUS, "spells": shooter, "gap": 3},
		"cautious_hurt_flees": {"profile": FightAI.CAUTIOUS, "spells": shooter, "gap": 3, "hp": 20, "ap": 0},
		"cautious_hurt_in_range": {"profile": FightAI.CAUTIOUS, "spells": shooter, "gap": 4, "hp": 20},
		"cautious_cornered": {"profile": FightAI.CAUTIOUS, "spells": shooter, "gap": 9, "hp": 10, "corner": true},
		"cautious_no_sight": {"profile": FightAI.CAUTIOUS, "spells": {SHOT: spell([dmg()], [2, 5], true)}, "gap": 5, "blind": true},
		"healer_hurt_ally_near": {"profile": FightAI.HEALER, "spells": healer, "gap": 1, "ally": at(0, 2)},
		"healer_hurt_ally_far": {"profile": FightAI.HEALER, "spells": {CURE: spell([eff("heal", "allies")], [1, 1])}, "gap": 8, "ap": 0, "ally": at(0, 6)},
		"healer_no_ally": {"profile": FightAI.HEALER, "spells": healer, "gap": 3},
		"summoner": {"profile": FightAI.SUMMONER, "spells": caller, "gap": 1, "ap": 3},
		"summoner_far": {"profile": FightAI.SUMMONER, "spells": caller, "gap": 7},
		"kamikaze_far": {"profile": FightAI.KAMIKAZE, "spells": bomb, "gap": 6, "hp": 10},
		"kamikaze_adjacent": {"profile": FightAI.KAMIKAZE, "spells": bomb, "gap": 1},
	}


## Plays the scene `s`: {trace, profile} (the profile FightAI finds in the spells).
static func play(s: Dictionary) -> Dictionary:
	var events: Array = []
	var fight := Fight.new(1, MapData.new(), SEED, func(ev: Dictionary) -> void: events.append(ev))
	var mon := _fighter(1, 1, CENTER)
	mon.ai = true
	mon.max_ap = 6
	mon.max_mp = 4
	mon.mp = 4
	mon.stats = {"agility": 1000}
	mon.own_spells = s["spells"]
	mon.spells = (s["spells"] as Dictionary).keys()
	mon.hp = int(s.get("hp", 100))
	var foe := _fighter(2, 0, at(int(s["gap"]), 0))
	if s.get("corner", false):
		mon.cell = 0
		foe.cell = at(5, 5)
	fight.add_fighter(mon)
	fight.add_fighter(foe)
	var passive := [foe]
	if s.has("ally"):
		var ally := _fighter(3, 1, int(s["ally"]))
		ally.hp = 40
		fight.add_fighter(ally)
		passive.append(ally)
	if s.get("wall", false):
		for dy in range(-2, 3):
			fight.map.fight_blocked[at(1, dy)] = true
	if s.get("blind", false):
		for dy in range(-7, 8):
			fight.map.los_blocked[at(1, dy)] = true
	fight.start_placement(0)
	fight.begin(0)
	if s.has("ap"):
		mon.ap = int(s["ap"]) # begin() gave the turn's AP: this is what is left
	return {"profile": FightAI.profile(mon), "trace": AiTrace.first_turn(fight, events, mon, passive)}


static func _fighter(id: int, team: int, cell: int) -> Fighter:
	var f := Fighter.new()
	f.id = id
	f.team = team
	f.cell = cell
	f.level = 10
	f.hp = 100
	f.max_hp = 100
	return f
