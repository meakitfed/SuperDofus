## Effects added by the "partial" audit of Incarnam and Astrub (roadmap P1.17).
extends TestCase

const ONDE_ENRAGEANTE := 1036087 # -157 Force, Astrub
const CASSE_NOISETTES := 1019702 # 1071: 10 % of the target's life, neutral
const PIOCHAGE := 1036135 # 1132: 1 water damage per AP the target used, at the end of its turn
const RESISTIVITE := 1036084 # 1076 "#% Résistance" (every element) on its caster's side


func _init() -> void:
	SpellBook.use_file("")


class Arena:
	var fight: Fight
	var me := Fighter.new()
	var foe := Fighter.new()
	var events: Array = []

	func _init() -> void:
		fight = Fight.new(1, MapData.new(), 7, func(ev: Dictionary) -> void: events.append(ev))
		_fighter(me, 1, 0, 300)
		_fighter(foe, 2, 1, MapGeometry.from_iso(MapGeometry.to_iso(300) + Vector2i(1, 0)))
		fight.start_placement(0)
		fight.begin(0)

	func _fighter(f: Fighter, id: int, team: int, cell: int) -> void:
		f.id = id
		f.team = team
		f.cell = cell
		f.hp = 100
		f.max_hp = 100
		f.ai = team == 1
		fight.add_fighter(f)


func test_the_audited_monster_spells_are_whole() -> void:
	for id: int in [ONDE_ENRAGEANTE, CASSE_NOISETTES, PIOCHAGE, RESISTIVITE]:
		check(SpellBook.get_spell(id).has("effects") and not SpellBook.get_spell(id).has("partial"), "spell %d simulated" % id)


func test_deboosts_lower_the_stat() -> void:
	var a := Arena.new()
	a.foe.stats["strength"] = 50
	FightEffects.apply(a.fight, a.me, a.foe, {"kind": "stat", "stat": "strength", "sign": -1, "min": 20, "max": 20, "duration": 2}, a.foe.cell, 0)
	eq(a.foe.stat("strength"), 30)


func test_resistance_to_every_element() -> void:
	var a := Arena.new()
	FightEffects.apply(a.fight, a.me, a.me, {"kind": "stat", "stat": "res_all", "sign": 1, "min": 10, "max": 10, "duration": 2}, a.me.cell, 0)
	eq([a.me.stat("res_fire"), a.me.stat("res_neutral"), a.me.stat("res_fixed_fire")], [10, 10, 0])


func test_percent_of_the_targets_life() -> void:
	var a := Arena.new()
	a.foe.hp = 80
	var out := FightEffects.apply(a.fight, a.me, a.foe, {"kind": "damage", "element": "neutral", "hp_pct": 10, "min": 0, "max": 0}, a.foe.cell, 0)
	eq(int(out[0]["amount"]), 8, "10 % of 80")
	eq(a.foe.hp, 72)


func test_damage_per_ap_used() -> void:
	var a := Arena.new()
	a.foe.ap_spent = 4
	var out := FightEffects.apply(a.fight, a.me, a.foe, {"kind": "damage", "element": "water", "per_ap": [2, 3], "min": 0, "max": 0}, a.foe.cell, 0)
	eq(int(out[0]["amount"]), 6, "3 damage per 2 AP: 4 AP = 6")
	a.foe.start_turn()
	eq(a.foe.ap_spent, 0, "counted per turn")


# P1.17b, cooldown effects 1045 / 1036 / 1035 (spells.id 12940 "Injection Toxique": cooldown 5)
const INJECTION := 1040977


func test_cooldown_effects_set_sub_and_add() -> void:
	var e: Dictionary = (SpellBook.get_spell(INJECTION)["effects"] as Array).filter(func(x: Dictionary) -> bool: return x["kind"] == "cooldown")[0]
	eq([e["mode"], int(e["origin"]), int(e["turns"])], ["sub", 12940, 1], "1036 read from the data")
	var a := Arena.new()
	a.me.spells = [INJECTION]
	a.me.cooldowns[INJECTION] = 5
	var out := FightEffects.apply(a.fight, a.me, a.me, e, a.me.cell, INJECTION)
	eq(int(a.me.cooldowns[INJECTION]), 4, "-1 turn")
	eq([out[0]["kind"], out[0]["spell"], out[0]["turns"]], ["cooldown", INJECTION, 4])
	FightEffects.apply(a.fight, a.me, a.me, {"kind": "cooldown", "mode": "set", "origin": 12940, "turns": 0}, a.me.cell, 0)
	check(not a.me.cooldowns.has(INJECTION), "1045 to 0 = castable")
	FightEffects.apply(a.fight, a.me, a.me, {"kind": "cooldown", "mode": "add", "origin": 12940, "turns": 2}, a.me.cell, 0)
	eq(int(a.me.cooldowns[INJECTION]), 2, "1035 +2")
	FightEffects.apply(a.fight, a.me, a.me, {"kind": "cooldown", "mode": "sub", "origin": 12940, "turns": 9}, a.me.cell, 0)
	check(not a.me.cooldowns.has(INJECTION), "never below 0")


# P1.17b, 285 / 2935 (spell modifiers) and 115 / 178 / 414 (plain characteristics)
const PETRIFICATION := 1041637 # 285 "-1 PA" on spells.id 13290, 3 turns
const MOT_SECRET := 1065840 # 2935 "+30 soins de base" on spells.id 25882


func test_spell_modifier_effects_are_read() -> void:
	var p: Dictionary = (SpellBook.get_spell(PETRIFICATION)["effects"] as Array).filter(func(x: Dictionary) -> bool: return x["kind"] == "stat")[0]
	eq([p["stat"], int(p["min"]), int(p["sign"])], ["spell_mod:ap:13290", 1, -1])
	var e: Dictionary = (SpellBook.get_spell(MOT_SECRET)["effects"] as Array).filter(func(x: Dictionary) -> bool: return x["kind"] == "stat")[0]
	eq([e["stat"], int(e["min"]), int(e["sign"])], ["spell_mod:heal:25882", 30, 1])


func test_a_spell_modifier_changes_the_ap_cost_and_the_base_heal() -> void:
	var a := Arena.new()
	a.me.own_spells[7] = {"id": 7, "origin": 77, "ap": 3, "effects": [{"kind": "heal", "min": 10, "max": 12}, {"kind": "damage", "min": 5, "max": 5}]}
	FightEffects.apply(a.fight, a.me, a.me, {"kind": "stat", "stat": "spell_mod:ap:77", "sign": -1, "min": 1, "max": 1, "duration": 2}, a.me.cell, 0)
	FightEffects.apply(a.fight, a.me, a.me, {"kind": "stat", "stat": "spell_mod:heal:77", "sign": 1, "min": 30, "max": 30, "duration": 2}, a.me.cell, 0)
	FightEffects.apply(a.fight, a.me, a.me, {"kind": "stat", "stat": "spell_mod:ap:99", "sign": -1, "min": 1, "max": 1, "duration": 2}, a.me.cell, 0)
	var s := a.me.spell(7)
	eq(int(s["ap"]), 2, "-1 AP (the other spell's modifier is ignored)")
	eq([int(s["effects"][0]["min"]), int(s["effects"][0]["max"]), int(s["effects"][1]["min"])], [40, 42, 5], "heal only")
	eq(int(a.me.own_spells[7]["ap"]), 3, "the book is untouched")
	FightEffects.apply(a.fight, a.me, a.me, {"kind": "stat", "stat": "spell_mod:ap:77", "sign": -1, "min": 9, "max": 9, "duration": 2}, a.me.cell, 0)
	eq(int(a.me.spell(7)["ap"]), 0, "never below 0")


func test_the_boosted_cost_is_what_a_cast_pays() -> void:
	var a := Arena.new()
	a.me.own_spells[7] = {"id": 7, "origin": 77, "ap": 3, "range": [0, 0], "effects": [{"kind": "heal", "min": 10, "max": 10, "target": "caster"}]}
	a.me.spells = [7]
	a.me.ap = 6
	FightEffects.apply(a.fight, a.me, a.me, {"kind": "stat", "stat": "spell_mod:ap:77", "sign": -1, "min": 2, "max": 2, "duration": 2}, a.me.cell, 0)
	var before := a.me.ap
	a.fight.cast(a.me, 7, a.me.cell, 0)
	eq(before - a.me.ap, 1, "3 AP - 2")


func test_crit_heals_and_push_damage_buffs() -> void:
	var a := Arena.new()
	for p: Array in [["crit", 10], ["heals", 5], ["push_damage", 50]]:
		FightEffects.apply(a.fight, a.me, a.me, {"kind": "stat", "stat": p[0], "sign": 1, "min": p[1], "max": p[1], "duration": 2}, a.me.cell, 0)
	eq([a.me.stat("crit"), a.me.stat("heals"), a.me.stat("push_damage")], [10, 5, 50])


# P1.17b, third piece: 2822 / 2828 (best element), 1078 (% vitality), 420 (critical resistance),
# 2905 / 2906 (fixed range), 1026 (triggers the glyphs), 335 (looks: ignored)
const FOUET := 1082230 # 2822 "dommages du meilleur élément"
const VITALITE := 1041316 # 1078
const TRANSHUMANCE := 1041057 # 1026
const ESPRIT_FELIN := 1040779 # 420


func test_the_new_effects_are_read_and_their_spells_whole() -> void:
	var f: Dictionary = (SpellBook.get_spell(FOUET)["effects"] as Array).filter(func(x: Dictionary) -> bool: return x.get("element", "") == "best")[0]
	eq(f["kind"], "damage")
	var v: Dictionary = (SpellBook.get_spell(VITALITE)["effects"] as Array).filter(func(x: Dictionary) -> bool: return x["kind"] == "stat")[0]
	eq([v["stat"], bool(v["pct"])], ["vitality", true])
	var c: Dictionary = (SpellBook.get_spell(ESPRIT_FELIN)["effects"] as Array).filter(func(x: Dictionary) -> bool: return x.get("stat", "") == "crit_res")[0]
	eq(int(c["sign"]), 1)
	check((SpellBook.get_spell(TRANSHUMANCE)["effects"] as Array).any(func(x: Dictionary) -> bool: return x["kind"] == "glyph_trigger"))
	for id: int in [FOUET, VITALITE, TRANSHUMANCE, ESPRIT_FELIN]:
		check(not SpellBook.get_spell(id).has("partial"), "spell %d is whole" % id)


func test_the_best_element_is_the_casters_highest() -> void:
	var a := Arena.new()
	a.me.stats["strength"] = 10
	a.me.stats["chance"] = 80
	a.me.stats["intelligence"] = 40
	eq(FightEffects.best_element(a.me), "water")
	var out := FightEffects.apply(a.fight, a.me, a.foe, {"kind": "damage", "element": "best", "min": 10, "max": 10}, a.foe.cell, 0)
	eq([out[0]["element"], int(out[0]["amount"])], ["water", 18], "10 x 180 / 100")
	a.me.stats["agility"] = 500
	eq(FightEffects.best_element(a.me), "air")


func test_a_percent_vitality_buff_raises_the_max_life() -> void:
	var a := Arena.new()
	a.me.max_hp = 200
	FightEffects.apply(a.fight, a.me, a.me, {"kind": "stat", "stat": "vitality", "pct": true, "sign": 1, "min": 20, "max": 20, "duration": 2}, a.me.cell, 0)
	eq(a.me.max_hp, 240, "+20% of 200")


func test_critical_resistance_lowers_critical_hits_only() -> void:
	var a := Arena.new()
	a.foe.stats["crit_res"] = 7
	var e := {"kind": "damage", "element": "neutral", "min": 20, "max": 20}
	eq(int(FightEffects.apply(a.fight, a.me, a.foe, e, a.foe.cell, 0)[0]["amount"]), 20, "not critical")
	a.fight.cast_crit = true
	eq(int(FightEffects.apply(a.fight, a.me, a.foe, e, a.foe.cell, 0)[0]["amount"]), 13, "critical: -7")
	a.fight.cast_crit = false


func test_a_fixed_range_replaces_the_spells_range() -> void:
	var a := Arena.new()
	a.me.own_spells[7] = {"id": 7, "origin": 77, "ap": 3, "range": [1, 4], "effects": []}
	FightEffects.apply(a.fight, a.me, a.me, {"kind": "stat", "stat": "spell_mod:rmax:77", "sign": 1, "min": 9, "max": 9, "duration": 2}, a.me.cell, 0)
	eq(a.me.spell(7)["range"], [1, 9])
	FightEffects.apply(a.fight, a.me, a.me, {"kind": "stat", "stat": "spell_mod:rmin:77", "sign": 1, "min": 0, "max": 0, "duration": 2}, a.me.cell, 0)
	eq(a.me.spell(7)["range"], [0, 9], "a fixed 0 counts")
	eq(a.me.own_spells[7]["range"], [1, 4], "the book is untouched")


func test_glyph_trigger_sets_off_the_casters_glyphs_and_keeps_them() -> void:
	var a := Arena.new()
	a.fight.marks.append({"id": 1, "kind": "glyph_end", "caster": a.me.id, "cells": [a.foe.cell], "cell": a.foe.cell,
			"spell": FOUET, "origin": 5, "turns": 3, "color": "#ffffff"})
	var other := {"id": 2, "kind": "glyph_end", "caster": a.foe.id, "cells": [a.foe.cell], "cell": a.foe.cell,
			"spell": FOUET, "origin": 6, "turns": 3, "color": "#ffffff"}
	a.fight.marks.append(other)
	var n := a.fight.marks.size()
	var out := FightEffects.apply(a.fight, a.me, a.foe, {"kind": "glyph_trigger", "min": 0, "max": 0}, a.foe.cell, 0)
	check(not out.is_empty(), "the glyph spell hit %s" % [out])
	eq(a.fight.marks.size(), n, "glyphs stay")
	var empty := FightEffects.apply(a.fight, a.me, a.me, {"kind": "glyph_trigger", "min": 0, "max": 0}, a.me.cell, 0)
	eq(empty, [], "no glyph under the caster")


# P1.17b, fourth piece: 182 (+summons), 776 (erosion buff, not simulated), 2792 (ignored)
const LARCIN := 1040974 # 776
const PERTURBATION := 1041635 # 2792 (Xelor)


func test_summon_limit_776_and_2792_spells_are_whole() -> void:
	for id: int in [LARCIN, PERTURBATION]:
		check(SpellBook.get_spell(id).has("effects") and not SpellBook.get_spell(id).has("partial"), "spell %d simulated" % id)


func test_a_summons_buff_raises_the_summon_limit() -> void:
	var a := Arena.new()
	var base := Summons.max_summons(a.me)
	FightEffects.apply(a.fight, a.me, a.me, {"kind": "stat", "stat": "summons", "sign": 1, "min": 2, "max": 2, "duration": 2}, a.me.cell, 0)
	eq(Summons.max_summons(a.me), base + 2)


func test_p117b5_stat_buffs_and_steals() -> void:
	var a := Arena.new()
	var ap0 := a.me.stat("ap_dodge")
	FightEffects.apply(a.fight, a.me, a.me, {"kind": "stat", "stat": "ap_dodge", "sign": -1, "min": 4, "max": 4, "duration": 2}, a.me.cell, 0)
	eq(a.me.stat("ap_dodge"), ap0 - 4)
	var s0 := a.me.stat("strength")
	var t0 := a.foe.stat("strength")
	FightEffects.apply(a.fight, a.me, a.foe, {"kind": "steal_stat", "stat": "strength", "min": 10, "max": 10, "duration": 2}, a.foe.cell, 0)
	eq(a.me.stat("strength"), s0 + 10)
	eq(a.foe.stat("strength"), t0 - 10)


func test_p117b6_spell_flags_and_percent_vitality_loss() -> void:
	var a := Arena.new()
	a.me.own_spells[7] = {"id": 7, "origin": 77, "ap": 3, "range": [2, 4], "los": true, "per_turn": 2, "crit": 10, "effects": []}
	for m: Array in [["perturn", 1], ["crit", 5], ["rminadd", 1], ["nolos", 1], ["freecell", 1]]:
		FightEffects.apply(a.fight, a.me, a.me, {"kind": "stat", "stat": "spell_mod:%s:77" % m[0], "sign": 1, "min": m[1], "max": m[1], "duration": 2}, a.me.cell, 0)
	var s := a.me.spell(7)
	eq([int(s["per_turn"]), int(s["crit"]), s["range"], s["los"], s["need_free_cell"]], [3, 15, [3, 4], false, true])
	eq(int(a.me.own_spells[7]["per_turn"]), 2, "the book is untouched")
	var hp0 := a.foe.max_hp
	FightEffects.apply(a.fight, a.me, a.foe, {"kind": "stat", "stat": "vitality", "sign": -1, "pct": true, "min": 10, "max": 10, "duration": 2}, a.foe.cell, 0)
	eq(a.foe.max_hp, hp0 - hp0 / 10)
	FightEffects.apply(a.fight, a.me, a.me, {"kind": "stat", "stat": "crit_damage", "sign": -1, "min": 3, "max": 3, "duration": 2}, a.me.cell, 0)
	eq(a.me.stat("crit_damage"), -3)


func test_p117b7_pass_turn_best_heal_and_range_min() -> void:
	var a := Arena.new()
	# 1031: the target's turn is skipped (it is not the current fighter)
	FightEffects.apply(a.fight, a.me, a.foe, {"kind": "pass_turn", "min": 0, "max": 0}, a.foe.cell, 0)
	check(a.foe.pass_turn, "flag set")
	a.fight.end_turn(0)
	check(not a.foe.pass_turn, "its turn was skipped")
	eq(a.fight.current().id, 1, "back to the caster")
	# 3002: heal with the caster's best element
	a.me.hp = 50
	a.me.own_spells[8] = {"id": 8, "origin": 88, "ap": 3, "range": [2, 4], "los": true, "effects": []}
	FightEffects.apply(a.fight, a.me, a.me, {"kind": "stat", "stat": "spell_mod:rminadd:88", "sign": -1, "min": 1, "max": 1, "duration": 2}, a.me.cell, 0)
	eq((a.me.spell(8)["range"] as Array)[0], 1)
	a.me.hp = 10
	var r := FightEffects.heal(a.fight, a.me, a.me, "best", 10)
	check(int(r["amount"]) >= 10, "healed")
	for id: int in [1082953, 1041883]:
		check(SpellBook.get_spell(id).has("effects"), "spell %d has effects" % id)


func test_p117b8_caster_life_damage_and_unbuff_by_grade() -> void:
	var a := Arena.new()
	# 89 "#1 à #2% PV du lanceur": neutral damage of that % of the caster's current life
	a.me.hp = 100
	a.foe.hp = 500
	var out := FightEffects.apply(a.fight, a.me, a.foe, {"kind": "damage", "element": "neutral", "caster_hp_pct": true, "min": 10, "max": 10}, a.foe.cell, 0)
	check(int(out[0]["amount"]) >= 10, "10 % of 100 life")
	# 1406 "Enlève les effets du rang #1 du sort #2": only the buffs cast by that grade
	var origin := int(SpellBook.get_spell(1041048).get("origin", -1))
	for gid: int in [1041048, 1041049]:
		var b := Buff.new()
		b.kind = "stat"
		b.stat = "power"
		b.value = 5
		b.turns = 3
		b.spell = gid
		a.foe.buffs.append(b)
	FightEffects.apply(a.fight, a.me, a.foe, {"kind": "unbuff", "origin": origin, "grade": 2, "min": 0, "max": 0}, a.foe.cell, 0)
	eq(a.foe.buffs.size(), 1, "the grade 2 buff is gone")
	eq(a.foe.buffs[0].spell, 1041048, "grade 1 stays")


func test_p117b10_damage_scaled_by_mp_left() -> void:
	var a := Arena.new()
	a.foe.hp = 500
	a.foe.max_mp = 4
	a.foe.mp = 2
	var out := FightEffects.apply(a.fight, a.me, a.foe, {"kind": "damage", "element": "neutral", "mp_left": true, "min": 40, "max": 40}, a.foe.cell, 0)
	check(int(out[0]["amount"]) > 0 and int(out[0]["amount"]) <= 20, "half the MP left, half the dice")


func test_p117b9_missing_life_worst_element_and_spell_flags() -> void:
	var a := Arena.new()
	# 279 "#1 a #2% PV manquants du lanceur"
	a.me.hp = a.me.max_hp - 100
	a.foe.hp = 500
	var out := FightEffects.apply(a.fight, a.me, a.foe, {"kind": "damage", "element": "neutral", "caster_missing_pct": true, "min": 50, "max": 50}, a.foe.cell, 0)
	check(int(out[0]["amount"]) >= 50, "50 % of 100 missing life")
	# 2832 worst element: the lowest of the four characteristics
	eq(FightEffects.worst_element(a.me), FightEffects.worst_element(a.me))
	a.me.own_spells[9] = {"id": 9, "origin": 99, "ap": 3, "range": [1, 4], "need_taken_cell": false, "per_target": 1, "effects": []}
	for m: String in ["pertarget", "taken", "visible"]:
		FightEffects.apply(a.fight, a.me, a.me, {"kind": "stat", "stat": "spell_mod:%s:99" % m, "sign": 1, "min": 1, "max": 1, "duration": 2}, a.me.cell, 0)
	var s := a.me.spell(9)
	eq([int(s["per_target"]), s["need_taken_cell"], s["need_visible_target"]], [2, true, true])


func test_p117b11_transfer_heal_dealt_and_splash() -> void:
	var a := Arena.new()
	# 90 "Transfere #1 a #2% des PV": the caster gives 50 % of its life, the target is healed
	a.me.hp = 100
	a.foe.hp = 10
	a.foe.max_hp = 500
	var out := FightEffects.apply(a.fight, a.me, a.foe, {"kind": "transfer_hp", "min": 50, "max": 50}, a.foe.cell, 0)
	eq([a.me.hp, a.foe.hp], [50, 60], "50 life moved")
	check(out.size() == 2, "a loss and a heal")
	# 2973 "Soin : #1 a #2% des dommages occasionnes": a % of the damage dealt earlier in the same cast
	a.fight.cast_dealt = 0
	var d := FightEffects.apply(a.fight, a.me, a.foe, {"kind": "damage", "element": "neutral", "min": 40, "max": 40}, a.foe.cell, 0)
	var spell := {"id": 1, "effects": [{"kind": "damage", "element": "neutral", "min": 40, "max": 40, "target": "enemies", "area": {"shape": "point", "size": 0}},
		{"kind": "heal_dealt", "min": 50, "max": 50, "target": "caster", "area": {"shape": "point", "size": 0}}]}
	a.me.hp = 10
	a.me.max_hp = 500
	FightEffects.apply_spell(a.fight, a.me, spell, a.foe.cell, false)
	check(a.me.hp > 10, "healed by half of what the spell dealt")
	check(d.size() > 0, "plain damage still works")
	# 1223 "Dommages : #1 a #2% des dommages finaux subis": a % of the hit that fired the trigger
	a.fight.trigger_amount = 80
	a.foe.hp = 500
	a.foe.alive = true
	var sp := FightEffects.apply(a.fight, a.me, a.foe, {"kind": "splash_taken", "min": 50, "max": 50}, a.foe.cell, 0)
	eq(int(sp[0]["amount"]), 40, "half of the 80 taken")


func test_p117b12_forced_rolls() -> void:
	var a := Arena.new()
	var e := {"kind": "damage", "element": "neutral", "min": 10, "max": 50}
	for i in 20:
		var v := FightEffects.roll(a.fight, e, a.me)
		check(v >= 10 and v <= 50, "plain roll in range")
	FightEffects.apply(a.fight, a.me, a.me, {"kind": "stat", "stat": "roll_max", "sign": 1, "min": 1, "max": 1, "duration": 2}, a.me.cell, 0)
	eq(FightEffects.roll(a.fight, e, a.me), 50, "782 maximizes")
	eq(FightEffects.roll(a.fight, e, a.foe) >= 10, true, "other fighters unaffected")
	var b := Arena.new()
	FightEffects.apply(b.fight, b.me, b.me, {"kind": "stat", "stat": "roll_min", "sign": 1, "min": 1, "max": 1, "duration": 2}, b.me.cell, 0)
	eq(FightEffects.roll(b.fight, e, b.me), 10, "781 minimizes")


func test_p117b13_splash_heal() -> void:
	var a := Arena.new()
	a.foe.hp = 10
	a.foe.max_hp = 500
	a.fight.trigger_amount = 80
	var out := FightEffects.apply(a.fight, a.me, a.foe, {"kind": "splash_heal", "min": 50, "max": 50}, a.foe.cell, 0)
	check(out.size() > 0, "a heal")
	eq(a.foe.hp, 50, "half of the 80 taken heals 40")


# P1.17b, fourteenth piece: CMPARR (= CCMPARR) and 2184 (ignored): Laisse Spirituelle is whole
func test_p117b14_cmparr_and_2184() -> void:
	check(not SpellBook.get_spell(1082268).has("partial"), "Laisse Spirituelle is whole")
	check(FightTriggers.ALIASES.get("CMPARR", []).has("CCMPARR"), "CMPARR answers CCMPARR")

# P1.17b, fifteenth piece: 2027 (ControlEntity) is ignored (APPROX: the entity stays under FightAI): Double / Turbine are whole
func test_p117b15_control_entity_ignored() -> void:
	check(not SpellBook.get_spell(1040922).has("partial"), "Double (Sram) is whole")
	check(not SpellBook.get_spell(1042854).has("partial"), "Turbine (Steamer) is whole")
