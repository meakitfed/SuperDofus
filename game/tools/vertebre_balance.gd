## Balance probe for a generated world (the Vertebre): every class, played by the fight AI, against what
## each floor offers (a group of its creatures at the floor's middle level, and its boss one level
## below), the player carrying the stats a character of that level would typically have.
##   godot --headless --path game -s res://tools/vertebre_balance.gd -- [--world=vertebre] [--runs=6] [--floors=1,2,3,4,5]
## Prints win rate, rounds and the player's hp left for each class and floor. Numbers to read, not asserts:
## the AI plays both sides (it does not heal at the right time or drink potions), so a class that wins 50 %
## here is fine in human hands.
extends SceneTree

const STEP_MS := 150
const GUARD := 30000
const CENTER := 300


func _init() -> void:
	var opts := {"world": "vertebre", "runs": "6", "floors": "1,2,3,4,5"}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		if kv.size() == 2:
			opts[kv[0]] = kv[1]
	ContentSource.use_dev_world(opts["world"])
	SpellBook.use_file("")
	var monsters: Dictionary = ContentSource.read_json("worlds/%s/monsters.json" % opts["world"])
	var runs := int(opts["runs"])
	var floors: Array = str(opts["floors"]).split(",")
	var breeds: Array = (ContentSource.read_json("worlds/%s/world.json" % opts["world"]) as Dictionary)["breeds"]
	print("%-18s %s" % ["class", "  ".join(floors.map(func(f: String) -> String: return "floor %s (group | boss)" % f))])
	for b: Variant in breeds:
		var breed := int(b)
		var cols := PackedStringArray()
		for f: String in floors:
			var group := _floor_result(monsters, breed, int(f), runs, false)
			var boss := _floor_result(monsters, breed, int(f), runs, true)
			cols.append("%s | %s" % [group, boss])
		print("%-18s %s" % [DofusI18n.text(int(str(GameData.row("breeds", breed)["shortNameId"])), str(breed)), "   ".join(cols)])
	quit()


## "win% r<rounds> hp<left%>" over `runs` fights of a floor (a group, or the boss).
func _floor_result(monsters: Dictionary, breed: int, floor: int, runs: int, boss: bool) -> String:
	var wins := 0
	var rounds := 0
	var hp_left := 0.0
	var level := _level(monsters, floor, boss)
	for run in runs:
		var r := _fight(monsters, breed, floor, level, boss, run + 1)
		if r["win"]:
			wins += 1
			hp_left += float(r["hp"])
		rounds += int(r["rounds"])
	return "%3d%% r%-2d hp%3d%%" % [100 * wins / runs, rounds / runs, int(hp_left / maxf(1.0, wins) * 100.0)]


func _level(monsters: Dictionary, floor: int, boss: bool) -> int:
	if boss:
		return floor * 10 - 1
	return floor * 10 - 5 # the middle of the floor's ten levels


func _fight(monsters: Dictionary, breed: int, floor: int, level: int, boss: bool, seed: int) -> Dictionary:
	var events: Array = []
	var fight := Fight.new(1, MapData.new(), seed, func(ev: Dictionary) -> void: events.append(ev))
	var me := _player(breed, level)
	me.cell = _at(-4, 0)
	fight.add_fighter(me)
	var foes: Array[Fighter] = []
	var area: String = str(9100 + floor)
	if boss:
		var id: String = str(monsters["bosses"].keys()[floor - 1])
		foes.append(_monster((monsters["bosses"][id]["grades"] as Array)[0]))
	else:
		var pool: Array = (monsters["subareas"][area]["monsters"] as Array).slice(0, 8) # the regular ones, not the elite
		var rng := RandomNumberGenerator.new()
		rng.seed = seed * 31 + floor
		for i in 3:
			var mid: String = str(int(pool[rng.randi_range(0, pool.size() - 1)]))
			var grades: Array = monsters["monsters"][mid]["grades"]
			foes.append(_monster(grades[rng.randi_range(0, grades.size() - 1)]))
	for i in foes.size():
		foes[i].cell = _at(2 + (i % 2), -1 + i)
		fight.add_fighter(foes[i])
	fight.start_placement(0)
	fight.begin(0)
	var now := 0
	var turns := 0
	var ticks := 0
	var seen := 0
	while fight.result == "" and ticks < GUARD:
		ticks += 1
		now += STEP_MS
		fight.tick(now)
		while seen < events.size():
			if str(events[seen].get("t", "")) == Protocol.FIGHT_TURN:
				turns += 1
			seen += 1
	var alive := me.hp > 0 and me.alive
	return {"win": fight.result == "win" and alive, "rounds": turns / maxi(1, foes.size() + 1), "hp": float(me.hp) / maxf(1.0, me.max_hp)}


## A player of `level` with the stats a character of that level typically has (capital, gear, set bonus).
func _player(breed: int, level: int) -> Fighter:
	var f := Fighter.new()
	f.id = 1
	f.player_id = 1
	f.breed = breed
	f.team = 0
	f.name = "Player"
	f.level = level
	var vit := 6 * level
	f.max_hp = 50 + 5 * level + vit
	f.hp = f.max_hp
	f.max_ap = 6 if level < 100 else 7
	f.max_mp = 3
	f.ap = f.max_ap
	f.mp = f.max_mp
	var main := int(3.5 * level)
	f.stats = {"strength": main, "intelligence": main, "chance": main, "agility": main, "power": level / 2, "damage": level / 4,
			"vitality": vit, "res_neutral": level / 4, "res_earth": level / 4, "res_fire": level / 4, "res_water": level / 4, "res_air": level / 4}
	var spells: Array[int] = []
	for pair: Array in SpellBook.pairs(breed):
		var g := SpellBook.grade_for(int(pair[0]), level)
		if g != 0:
			spells.append(g)
	f.spells = spells
	f.ai = true
	return f


func _monster(m: Dictionary) -> Fighter:
	var f := Fighter.new()
	f.id = 100 + randi() % 1000000
	f.team = 1
	f.ai = true
	f.name = str(m.get("name", "Monstre"))
	f.monster = int(m.get("monster", 0))
	f.grade = int(m.get("grade", 1))
	f.level = int(m.get("level", 1))
	f.max_hp = int(m.get("hp", 40))
	f.hp = f.max_hp
	f.max_ap = int(m.get("ap", 5))
	f.max_mp = int(m.get("mp", 3))
	f.ap = f.max_ap
	f.mp = f.max_mp
	for k: String in m.get("stats", {}):
		f.stats[k] = int(m["stats"][k])
	for k: String in m.get("res", {}):
		f.stats["res_" + k] = int(m["res"][k])
	f.spells = (m.get("spells", []) as Array).map(func(s: Variant) -> int: return int(s)).filter(func(s: int) -> bool: return not SpellBook.get_spell(s).is_empty())
	f.loot = {"xp": int(m.get("xp", 0)), "kamas": [0, 0], "drops": []}
	return f


static func _at(dx: int, dy: int) -> int:
	return MapGeometry.from_iso(MapGeometry.to_iso(CENTER) + Vector2i(dx, dy))
