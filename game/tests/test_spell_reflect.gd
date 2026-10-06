## Spell reflection (roadmap P1.13r, effect 106 CharacterSpellReflector): a buff sending an enemy's
## harmful spell of a low enough grade back to its caster. APPROX(P1.13r): fields not named by the client.
extends TestCase

const HIT := 980 # made up: 50 neutral, grade 2
const HIGH := 981 # made up: 50 neutral, grade 5
const MIRROR := 982 # made up: reflects grades <= 3, 100 %, 3 turns
const SOMETIMES := 983 # made up: reflects grades <= 3, 0 %


func _init() -> void:
	SpellBook.use_file("")


func _made_up() -> void:
	SpellBook.get_spell(1040972) # loads spells.json first
	var base := {"ap": 0, "range": [0, 9], "los": false, "per_turn": 9, "per_target": 9}
	var hit := {"kind": "damage", "element": "neutral", "min": 50, "max": 50, "target": "all"}
	SpellBook._spells[HIT] = base.merged({"id": HIT, "grade": 2, "effects": [hit]})
	SpellBook._spells[HIGH] = base.merged({"id": HIGH, "grade": 5, "effects": [hit]})
	SpellBook._spells[MIRROR] = base.merged({"id": MIRROR, "effects": [
			{"kind": "spell_reflect", "level": 3, "pct": 100, "min": 0, "max": 0, "target": "all", "turns": 3}]})
	SpellBook._spells[SOMETIMES] = base.merged({"id": SOMETIMES, "effects": [
			{"kind": "spell_reflect", "level": 3, "pct": 0, "min": 0, "max": 0, "target": "all", "turns": 3}]})


func _cleanup() -> void:
	for id in [HIT, HIGH, MIRROR, SOMETIMES]:
		SpellBook._spells.erase(id)


func _arena() -> Fight:
	var fight := Fight.new(1, MapData.new(), 7, func(_ev: Dictionary) -> void: pass)
	var foe := Fighter.new() # the holder
	foe.id = 2
	foe.team = 1
	foe.cell = MapGeometry.from_iso(MapGeometry.to_iso(300) + Vector2i(4, 0))
	foe.hp = 500
	foe.max_hp = 500
	foe.ap = 12
	foe.max_ap = 12
	foe.spells = [MIRROR, SOMETIMES]
	var me := Fighter.new()
	me.id = 1
	me.cell = 300
	me.level = 10
	me.hp = 100
	me.max_hp = 100
	me.ap = 12
	me.max_ap = 12
	me.spells = [HIT, HIGH]
	fight.add_fighter(me)
	fight.add_fighter(foe)
	fight.start_placement(0)
	fight.begin(0)
	return fight


func _arm(fight: Fight, spell: int) -> void:
	var foe: Fighter = fight.fighters[2]
	FightEffects.apply_spell(fight, foe, SpellBook.get_spell(spell), foe.cell, false)


func test_a_low_grade_spell_goes_back_to_its_caster() -> void:
	_made_up()
	var fight := _arena()
	var me: Fighter = fight.fighters[1]
	var foe: Fighter = fight.fighters[2]
	_arm(fight, MIRROR)
	var out := FightEffects.apply_spell(fight, me, SpellBook.get_spell(HIT), foe.cell, false)
	eq(foe.hp, 500, "the holder is untouched")
	eq(me.hp, 50, "the caster takes its own 50")
	eq(out.filter(func(e: Dictionary) -> bool: return str(e["kind"]) == "reflected").size(), 1, "announced once")
	_cleanup()


func test_a_higher_grade_is_not_reflected() -> void:
	_made_up()
	var fight := _arena()
	var me: Fighter = fight.fighters[1]
	var foe: Fighter = fight.fighters[2]
	_arm(fight, MIRROR)
	FightEffects.apply_spell(fight, me, SpellBook.get_spell(HIGH), foe.cell, false)
	eq(foe.hp, 450, "grade 5 > 3 lands")
	eq(me.hp, 100, "nothing comes back")
	_cleanup()


func test_the_chance_decides() -> void:
	_made_up()
	var fight := _arena()
	var me: Fighter = fight.fighters[1]
	var foe: Fighter = fight.fighters[2]
	_arm(fight, SOMETIMES)
	FightEffects.apply_spell(fight, me, SpellBook.get_spell(HIT), foe.cell, false)
	eq(foe.hp, 450, "0 %: the hit lands")
	eq(me.hp, 100, "nothing comes back")
	_cleanup()


func test_a_spell_cast_on_oneself_or_an_ally_is_never_reflected() -> void:
	_made_up()
	var fight := _arena()
	var foe: Fighter = fight.fighters[2]
	_arm(fight, MIRROR)
	FightEffects.apply_spell(fight, foe, SpellBook.get_spell(HIT), foe.cell, false)
	eq(foe.hp, 450, "its own spell hits it as usual")
	_cleanup()
