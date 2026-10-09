## Erosion (roadmap P1.14): HP lost also lowers max HP. APPROX(P1.14b): 10 % base, see FightEffects.hurt.
extends TestCase


func _fighter(hp: int) -> Fighter:
	var f := Fighter.new()
	f.id = 1
	f.hp = hp
	f.max_hp = hp
	return f


func test_ten_percent_of_hp_damage_erodes_the_maximum() -> void:
	var f := _fighter(200)
	var e := FightEffects.hurt(f, 80, "fire")
	eq(f.hp, 120)
	eq(f.max_hp, 192, "10 % of 80 = 8")
	eq(f.eroded, 8)
	eq(int(e["eroded"]), 8)
	eq(int(e["max_hp"]), 192)


func test_shield_is_not_eroded() -> void:
	var f := _fighter(200)
	var b := Buff.new()
	b.kind = "shield"
	b.value = 50
	f.buffs.append(b)
	FightEffects.hurt(f, 80, "fire") # 50 absorbed, 30 on HP
	eq(f.max_hp, 197)


func test_erosion_stat_adds_and_is_capped() -> void:
	var f := _fighter(1000)
	f.stats = {"erosion": 100}
	FightEffects.hurt(f, 100, "fire")
	eq(f.eroded, 50, "capped at 50 %")


func test_heal_stops_at_eroded_maximum() -> void:
	var f := _fighter(100)
	FightEffects.hurt(f, 50, "fire")
	var h := FightEffects.heal_raw(f, 999)
	eq(f.hp, f.max_hp)
	eq(f.max_hp, 95)
	eq(int(h["amount"]), 45)
