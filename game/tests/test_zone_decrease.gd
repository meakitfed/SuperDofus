## Damage decrease in areas (roadmap P1.13j): zoneDescr.damageDecreaseStepPercent /
## maxDamageDecreaseApplyCount, read in the client's native code (gru.blgz, grt.blgw, the
## classes grz / gsa / gsb / gsc / gse / gsd; HitContext.bmuv -> gzm.bmyw -> gzm.bmyv).
## Offsets are our iso coords around cell 300.
extends TestCase

const HIT := 980 # made up: 100 neutral in circle 5, -10 % per step, 4 times
const HEAL := 981 # made up: heals 100 in circle 2

const CIRCLE := {"shape": "circle", "size": 5, "step": 10, "steps": 4}


func _init() -> void:
	SpellBook.use_file("")


func at(dx: int, dy: int) -> int:
	return MapGeometry.from_iso(MapGeometry.to_iso(300) + Vector2i(dx, dy))


func pct(a: Dictionary, cx: int, cy: int, dx: int, dy: int, fx := -9, fy := 0) -> int:
	return FightRules.efficiency(a, at(cx, cy), at(fx, fy), at(dx, dy))


func test_the_extracted_areas_carry_the_decrease() -> void:
	var toison: Dictionary = SpellBook.get_spell(1082254)["effects"][1]["area"] # Toison d'Or: C2, min 1
	eq([int(toison.get("step", 0)), int(toison.get("steps", 0))], [10, 4], "10 % per step, 4 times")
	var weapon := Equipment.zone("X1,0,10,1") # hammers: itemtypes.rawZone
	eq([str(weapon["shape"]), int(weapon["step"]), int(weapon["steps"])], ["cross", 10, 1])
	var staff := Equipment.zone("T1,10,1")
	eq([str(staff["shape"]), int(staff["size"]), int(staff["step"]), int(staff["steps"])], ["tline", 1, 10, 1])
	eq(Equipment.zone("P").has("step"), false)


func test_one_step_per_cell_from_the_centre() -> void:
	eq([pct(CIRCLE, 0, 0, 0, 0), pct(CIRCLE, 0, 0, 1, 0), pct(CIRCLE, 0, 0, 1, 1), pct(CIRCLE, 0, 0, 3, 0)], [0, 10, 20, 30])
	eq(pct(CIRCLE, 0, 0, 5, 0), 40, "at most maxDamageDecreaseApplyCount steps")
	var ring := CIRCLE.duplicate()
	ring["min"] = 2 # C with param2: counted from the first ring (offset param2)
	eq([pct(ring, 0, 0, 2, 0), pct(ring, 0, 0, 3, 0)], [0, 10])
	var o := {"shape": "ring", "size": 2, "step": 10, "steps": 4}
	eq(pct(o, 0, 0, 2, 0), 0, "O: offset param1")
	var line := {"shape": "line", "size": 3, "min": 1, "step": 10, "steps": 4}
	eq(pct(line, 0, 0, 2, 0), 20, "L keeps no offset")


func test_distances_of_the_other_classes() -> void:
	var sq := {"shape": "square", "size": 2, "step": 10, "steps": 4}
	eq(pct(sq, 0, 0, 2, 2), 20, "G: the larger coordinate difference (gse)")
	var diag := {"shape": "diagonal_cross", "size": 3, "step": 10, "steps": 4}
	eq(pct(diag, 0, 0, 2, 2), 20, "+: Manhattan / 2 (gsc), two diagonal steps")
	var cone := {"shape": "cone", "size": 3, "step": 10, "steps": 4}
	eq(pct(cone, 2, 0, 4, 1, 0, 0), 20, "V: along the direction only (gsa)")
	eq(pct({"shape": "all", "size": 63, "step": 10, "steps": 4}, 0, 0, 3, 0), 0, "a / A: none")
	eq(pct({"shape": "circle", "size": 51, "step": 10, "steps": 4}, 0, 0, 3, 0), 0, "param1 >= 51: none")
	eq(pct({"shape": "circle", "size": 3}, 0, 0, 3, 0), 0, "no step: none")
	eq(pct({"shape": "circle", "size": 5, "step": 50, "steps": 4}, 0, 0, 3, 0), 100, "at most 100 %")


class Arena:
	var fight: Fight
	var me := Fighter.new()
	var foes: Array[Fighter] = []

	func _init(dists: Array) -> void:
		fight = Fight.new(1, MapData.new(), 7, func(_ev: Dictionary) -> void: pass)
		me.id = 1
		me.cell = at(-4, 0)
		me.stats = {"agility": 1000}
		var all: Array[Fighter] = [me]
		for i in dists.size():
			var f := Fighter.new()
			f.id = 10 + i
			f.team = 1
			f.cell = at(int(dists[i]), 0)
			foes.append(f)
			all.append(f)
		for f: Fighter in all:
			f.level = 100
			f.hp = 500
			f.max_hp = 500
			f.ap = 12
			f.max_ap = 12
			f.mp = 6
			f.max_mp = 6
			fight.add_fighter(f)
		fight.start_placement(0)
		fight.begin(0)

	func at(dx: int, dy: int) -> int:
		return MapGeometry.from_iso(MapGeometry.to_iso(300) + Vector2i(dx, dy))


func _made_up() -> void:
	SpellBook.get_spell(1082254) # loads spells.json first
	SpellBook._spells[HIT] = {"id": HIT, "ap": 0, "range": [0, 9], "los": false, "per_turn": 9, "per_target": 9,
			"effects": [{"kind": "damage", "element": "neutral", "min": 100, "max": 100, "target": "all", "area": CIRCLE}]}
	SpellBook._spells[HEAL] = {"id": HEAL, "ap": 0, "range": [0, 9], "los": false, "per_turn": 9, "per_target": 9,
			"effects": [{"kind": "heal", "element": "fire", "min": 100, "max": 100, "target": "all",
				"area": {"shape": "circle", "size": 2, "step": 10, "steps": 4}}]}


func _cleanup() -> void:
	for id in [HIT, HEAL]:
		SpellBook._spells.erase(id)


func test_a_damage_area_at_1_2_3_cells() -> void:
	_made_up()
	var a := Arena.new([0, 1, 2, 3, 5])
	FightEffects.apply_spell(a.fight, a.me, SpellBook.get_spell(HIT), a.at(0, 0), false)
	eq(a.foes.map(func(f: Fighter) -> int: return 500 - f.hp), [100, 90, 80, 70, 60])
	_cleanup()


func test_before_resistances_after_the_casters_bonuses() -> void:
	_made_up()
	var a := Arena.new([2])
	a.me.stats["damage"] = 20 # fixed damage: 120, then -20 % = 96
	a.foes[0].stats = {"res_neutral": 50} # then 50 % resistance = 48
	FightEffects.apply_spell(a.fight, a.me, SpellBook.get_spell(HIT), a.at(0, 0), false)
	eq(500 - a.foes[0].hp, 48)
	_cleanup()


func test_heals_decrease_too() -> void:
	_made_up()
	var a := Arena.new([1, 2])
	for f: Fighter in a.foes:
		f.hp = 100
	FightEffects.apply_spell(a.fight, a.me, SpellBook.get_spell(HEAL), a.at(0, 0), false)
	eq(a.foes.map(func(f: Fighter) -> int: return f.hp - 100), [90, 80])
	_cleanup()
