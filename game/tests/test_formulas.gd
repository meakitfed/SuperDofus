## Exactitude des formules de combat (roadmap P1.14): un tableau de cas calcules a la main, un par
## regle, qui fige l'arithmetique exacte (ordre des operations, arrondis, plafonds) de
## FightLife.damage / heal / hurt, FightDisplace.push et StatFormulas.
## Sources : voir docs/RULES_SOURCES.md (formules de dommages = communautaires, APPROX(P1.14) : aucune
## formule de combat dans luaformulas, ni dans les tables du client ; l'ordre est celui de FightLife).
## Chaque ligne : [libelle, stats du lanceur, stats de la cible, base, element, zone %, critique, attendu].
extends TestCase

const HP := 100000


class Arena:
	var fight: Fight
	var me := Fighter.new()
	var foe := Fighter.new()

	func _init(my_stats: Dictionary, foe_stats: Dictionary) -> void:
		fight = Fight.new(1, MapData.new(), 7, func(_ev: Dictionary) -> void: pass)
		_add(me, 1, 0, 300, my_stats)
		_add(foe, 2, 1, MapGeometry.from_iso(MapGeometry.to_iso(300) + Vector2i(1, 0)), foe_stats)

	func _add(f: Fighter, id: int, team: int, cell: int, stats: Dictionary) -> void:
		f.id = id
		f.team = team
		f.cell = cell
		f.level = 10
		f.hp = HP
		f.max_hp = HP
		f.stats = stats.duplicate()
		fight.add_fighter(f)


# Dommages : base x (100 + stat + puissance) / 100 + fixes ; zone ; - resistance fixe ; - critique ;
# x (100 - resistance %) / 100 ; x (100 + finaux) / 100 ; tout en entiers (division entiere = arrondi bas).
const DAMAGE_CASES := [
	["neutre sans stat", {}, {}, 100, "neutral", 0, false, 100],
	["feu : 100 x (100 + 50 + 20) / 100 + 5 + 3 = 178", {"intelligence": 50, "power": 20, "damage": 5, "damage_fire": 3}, {}, 100, "fire", 0, false, 178],
	["puissance negative plafonnee a 0 %", {"intelligence": -300}, {}, 100, "fire", 0, false, 0],
	["resistance fixe : 178 - 8 = 170", {"intelligence": 50, "power": 20, "damage": 5, "damage_fire": 3}, {"res_fixed_fire": 8}, 100, "fire", 0, false, 170],
	["resistance fixe puis %: (178 - 8) x 70 / 100 = 119", {"intelligence": 50, "power": 20, "damage": 5, "damage_fire": 3}, {"res_fixed_fire": 8, "res_fire": 30}, 100, "fire", 0, false, 119],
	["arrondi bas : 33 x 50 / 100 = 16", {}, {"res_neutral": 50}, 33, "neutral", 0, false, 16],
	["resistance 130 % plafonnee a 100 %", {}, {"res_fire": 130}, 100, "fire", 0, false, 0],
	["resistance -150 % plafonnee a -100 % : double", {}, {"res_fire": -150}, 100, "fire", 0, false, 200],
	["dommages finaux : 16 x 110 / 100 = 17", {"final_damage": 10}, {"res_neutral": 50}, 33, "neutral", 0, false, 17],
	["combo ajoute aux finaux : 100 x 130 / 100", {"final_damage": 10, "combo": 20}, {}, 100, "neutral", 0, false, 130],
	["zone 25 % : floor(100 x 0,75) = 75", {}, {}, 100, "neutral", 25, false, 75],
	["zone 25 % arrondie bas : floor(24,75) = 24", {}, {}, 33, "neutral", 25, false, 24],
	["critique : 100 + 20 - 5 = 115", {"crit_damage": 20}, {"crit_res": 5}, 100, "neutral", 0, true, 115],
	["critique ignore hors coup critique", {"crit_damage": 20}, {"crit_res": 5}, 100, "neutral", 0, false, 100],
	["resistance critique plancher a 0", {}, {"crit_res": 500}, 100, "neutral", 0, true, 0],
	["dommages recus negatifs (265) : 100 - 30", {}, {"dmg_taken": -30}, 100, "neutral", 0, false, 70],
	["resistance melee 20 % (adjacents) : 100 x 80 / 100", {}, {"melee_res": 20}, 100, "neutral", 0, false, 80],
	["dommages de melee 25 % (sorts) : 100 x 125 / 100", {"melee_damage": 25}, {}, 100, "neutral", 0, false, 125],
	["invulnerable : 0", {}, {"_flag": "invulnerable"}, 100, "neutral", 0, false, 0],
]


func test_damage_table() -> void:
	for c: Array in DAMAGE_CASES:
		if not sub(str(c[0])):
			continue
		var foe_stats: Dictionary = (c[2] as Dictionary).duplicate()
		var flag := str(foe_stats.get("_flag", ""))
		foe_stats.erase("_flag")
		var a := Arena.new(c[1], foe_stats)
		if flag == "invulnerable":
			var b := Buff.new()
			b.kind = "state"
			b.flags = ["invulnerable"]
			a.foe.buffs.append(b)
		a.fight.cast_crit = bool(c[6])
		var out := FightLife.damage(a.fight, a.me, a.foe, str(c[4]), int(c[3]), int(c[5]))
		eq(out.size(), 1)
		eq(HP - a.foe.hp, int(c[7]), "points de vie perdus")


# Soins : base x (100 + stat) / 100 + soins ; zone ; x (100 + soins finaux) / 100.
const HEAL_CASES := [
	["soin brut", {}, 20, "fire", 0, 20],
	["20 x (100 + 100) / 100 + 4 = 44", {"intelligence": 100, "heals": 4}, 20, "fire", 0, 44],
	["soins finaux : 44 x 125 / 100 = 55", {"intelligence": 100, "heals": 4, "final_heals": 25}, 20, "fire", 0, 55],
	["zone 50 % : floor(44 x 0,5) = 22 puis 22 x 125 / 100 = 27", {"intelligence": 100, "heals": 4, "final_heals": 25}, 20, "fire", 50, 27],
	["soins finaux negatifs : 20 x 70 / 100 = 14", {"final_heals": -30}, 20, "fire", 0, 14],
	["stat negative plafonnee a 0 %", {"intelligence": -500}, 20, "fire", 0, 0],
]


func test_heal_table() -> void:
	for c: Array in HEAL_CASES:
		if not sub(str(c[0])):
			continue
		var a := Arena.new(c[1], {})
		a.foe.hp = 1000
		a.foe.max_hp = 100000
		FightLife.heal(a.fight, a.me, a.foe, str(c[3]), int(c[2]), int(c[4]))
		eq(a.foe.hp - 1000, int(c[5]), "PV rendus")


func test_incurable_target_receives_nothing() -> void:
	var a := Arena.new({}, {})
	a.foe.hp = 1000
	var b := Buff.new()
	b.kind = "state"
	b.flags = ["incurable"]
	a.foe.buffs.append(b)
	FightLife.heal(a.fight, a.me, a.foe, "fire", 50)
	eq(a.foe.hp, 1000)


func test_heal_is_capped_by_the_eroded_maximum() -> void:
	var a := Arena.new({}, {})
	FightLife.hurt(a.foe, 1000, "fire") # 10 % = 100 erodes
	eq(a.foe.max_hp, HP - 100)
	FightLife.heal(a.fight, a.me, a.foe, "fire", HP)
	eq(a.foe.hp, HP - 100, "never above the eroded maximum")


# Erosion : min(PV perdus x (10 + erosion) / 100 arrondi bas, plafonnee a 50 %), jamais sur un bouclier,
# jamais sur le coup qui tue ; le maximum ne descend pas sous 1. [libelle, stat erosion, PV, degats, erosion attendue]
const EROSION_CASES := [
	["10 % de 80", 0, 1000, 80, 8],
	["9 degats : floor(0,9) = 0", 0, 1000, 9, 0],
	["19 degats : floor(1,9) = 1", 0, 1000, 19, 1],
	["erosion 15 : 25 % de 40", 15, 1000, 40, 10],
	["plafond 50 % : erosion 100", 100, 1000, 100, 50],
	["erosion negative plancher a 0 %", -40, 1000, 100, 0],
	["le coup qui tue n'erode pas", 0, 50, 80, 0],
	["PV perdus = PV restants si moins que les degats", 0, 100, 90, 9],
]


func test_erosion_table() -> void:
	for c: Array in EROSION_CASES:
		if not sub(str(c[0])):
			continue
		var f := Fighter.new()
		f.id = 1
		f.hp = int(c[2])
		f.max_hp = int(c[2])
		f.stats = {"erosion": int(c[1])}
		FightLife.hurt(f, int(c[3]), "fire")
		eq(f.eroded, int(c[4]), "erosion")
		eq(f.max_hp, int(c[2]) - int(c[4]), "maximum erode")


func test_erosion_never_drops_the_maximum_below_one() -> void:
	var f := Fighter.new()
	f.id = 1
	f.hp = 2
	f.max_hp = 2
	f.stats = {"erosion": 1000} # plafonne a 50 %
	FightLife.hurt(f, 1, "fire")
	check(f.max_hp >= 1)
	eq(f.hp, 1)


# Poussee contre un obstacle : (niveau / 2 + 32 + dommages de poussee - resistance de poussee) x cases restantes / 4.
# Le lanceur est de niveau 10 (5 + 32 = 37). [libelle, stats lanceur, stats cible, cases poussees, attendu]
const PUSH_CASES := [
	["1 case restante : 37 x 1 / 4 = 9", {}, {}, 2, 9],
	["2 cases restantes : 37 x 2 / 4 = 18", {}, {}, 3, 18],
	["3 cases restantes : 37 x 3 / 4 = 27", {}, {}, 4, 27],
	["dommages de poussee : (37 + 50) x 2 / 4 = 43", {"push_damage": 50}, {}, 3, 43],
	["resistance de poussee : (37 - 20) x 2 / 4 = 8", {}, {"push_res": 20}, 3, 8],
	["resistance superieure : plancher a 0", {}, {"push_res": 500}, 3, 0],
]


func test_push_collision_table() -> void:
	for c: Array in PUSH_CASES:
		if not sub(str(c[0])):
			continue
		var a := Arena.new(c[1], c[2])
		# the target is 1 cell from the caster; the wall stands right behind it: every cell pushed is "left"
		var wall := MapGeometry.from_iso(MapGeometry.to_iso(a.foe.cell) + Vector2i(1, 0))
		a.fight.map.fight_blocked[wall] = true
		var out := FightDisplace.push(a.fight, a.me, a.foe, {"kind": "push", "min": int(c[3]) - 1}, a.me.cell) # min = cells still to walk when the wall stops it
		var dmg := 0
		for e: Dictionary in out:
			if e.get("kind") == "damage":
				dmg = int(e["amount"])
		eq(dmg, int(c[4]), "degats de collision")
		eq(HP - a.foe.hp, int(c[4]), "PV perdus")


# Caracteristiques derivees (StatFormulas), calculees a la main.
func test_derived_characteristics() -> void:
	var s := func(n: String) -> int: return {"agility": 95, "wisdom": 123, "tackle": 3, "escape": -50, "chance": 250, "strength": 40}.get(n, 0)
	eq(StatFormulas.tackle(s), 12, "95 / 10 + 3")
	eq(StatFormulas.escape(s), 0, "9 - 50 plancher a 0")
	eq(StatFormulas.ap_dodge(s), 12, "123 / 10")
	eq(StatFormulas.prospecting(s), 125, "100 + 250 / 10")
	eq(StatFormulas.pods(s), 1200, "1000 + 5 x 40")
	eq(StatFormulas.max_hp(100, 400), 950, "50 + 500 + 400")
	eq(StatFormulas.max_ap(99), 6)
	eq(StatFormulas.max_ap(100), 7)
	eq(StatFormulas.job_pods(200), 2400, "12 pods x 200 niveaux")
	eq(StatFormulas.job_pods(201), 2411, "11 pods des le niveau 201")
