## Damage reflection (roadmap P1.13o, effects 107 / 220): a trigger buff on D that sends a flat
## damage back to the attacker. APPROX(P1.13o): no formula found, see FightEffects "reflect".
extends TestCase

const HIT := 970 # made up: 100 neutral
const SPIKES := 971 # made up: reflect 15 on D, 2 turns (107, boosted)
const MIRROR := 972 # made up: reflect 15 on D, 2 turns (220, unboosted)


func _init() -> void:
	SpellBook.use_file("")


func _made_up() -> void:
	SpellBook.get_spell(1040972) # loads spells.json first
	var base := {"ap": 0, "range": [0, 9], "los": false, "per_turn": 9, "per_target": 9}
	SpellBook._spells[HIT] = base.merged({"id": HIT, "effects": [
			{"kind": "damage", "element": "neutral", "min": 100, "max": 100, "target": "all"}]})
	SpellBook._spells[SPIKES] = base.merged({"id": SPIKES, "effects": [
			{"kind": "reflect", "boosted": true, "min": 15, "max": 15, "target": "all", "on": ["D"], "turns": 2}]})
	SpellBook._spells[MIRROR] = base.merged({"id": MIRROR, "effects": [
			{"kind": "reflect", "boosted": false, "min": 15, "max": 15, "target": "all", "on": ["D"], "turns": 2}]})


func _cleanup() -> void:
	for id in [HIT, SPIKES, MIRROR]:
		SpellBook._spells.erase(id)


func _arena(spells: Array) -> Fighter:
	var fight := Fight.new(1, MapData.new(), 7, func(_ev: Dictionary) -> void: pass)
	var me := Fighter.new()
	me.id = 1
	me.cell = 300
	me.level = 10
	me.hp = 100
	me.max_hp = 100
	me.ap = 12
	me.max_ap = 12
	me.spells = spells
	me.stats = {"agility": 1000}
	var foe := Fighter.new()
	foe.id = 2
	foe.team = 1
	foe.cell = MapGeometry.from_iso(MapGeometry.to_iso(300) + Vector2i(6, 0))
	foe.hp = 500
	foe.max_hp = 500
	foe.mp = 6
	foe.max_mp = 6
	fight.add_fighter(me)
	fight.add_fighter(foe)
	fight.start_placement(0)
	fight.begin(0)
	me.set_meta("fight", fight)
	me.set_meta("foe", foe)
	return me


func test_a_hit_on_the_holder_sends_damage_back() -> void:
	_made_up()
	var me := _arena([HIT, SPIKES, MIRROR])
	var fight: Fight = me.get_meta("fight")
	var foe: Fighter = me.get_meta("foe")
	eq(fight.cast(me, SPIKES, me.cell, 0), "")
	var hp := me.hp
	FightEffects.damage(fight, foe, me, "neutral", 40)
	FightTriggers.flush(fight)
	eq(hp - me.hp, 40, "the hit lands in full")
	eq(500 - foe.hp, 15, "15 sent back, once")
	_cleanup()


func test_boosted_reflect_reads_the_reflect_stat_unboosted_does_not() -> void:
	_made_up()
	var me := _arena([HIT, SPIKES, MIRROR])
	var fight: Fight = me.get_meta("fight")
	var foe: Fighter = me.get_meta("foe")
	me.stats["reflect"] = 10
	fight.cast(me, SPIKES, me.cell, 0)
	FightEffects.damage(fight, foe, me, "neutral", 40)
	FightTriggers.flush(fight)
	eq(500 - foe.hp, 25, "107: 15 + 10")
	me.buffs.clear()
	foe.hp = 500
	fight.cast(me, MIRROR, me.cell, 0)
	FightEffects.damage(fight, foe, me, "neutral", 40)
	FightTriggers.flush(fight)
	eq(500 - foe.hp, 15, "220: not boosted")
	_cleanup()


func test_hitting_itself_reflects_nothing() -> void:
	_made_up()
	var me := _arena([HIT, SPIKES])
	var fight: Fight = me.get_meta("fight")
	fight.cast(me, SPIKES, me.cell, 0)
	var hp := me.hp
	FightEffects.damage(fight, me, me, "neutral", 10)
	FightTriggers.flush(fight)
	eq(hp - me.hp, 10, "no reflected damage on top of its own hit")
	_cleanup()
