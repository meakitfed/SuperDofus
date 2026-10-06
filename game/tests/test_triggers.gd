## Triggered effects, delays, chained spells and glyph-auras (roadmap P1.13b): the
## real spells (spells.json) where the data says it all, small made-up spells for the
## trigger codes themselves.
extends TestCase

const CUT := 1040972 # Sram "Coupe-gorge" grade 1: fire 30-33, then x110 % damage suffered (D, 1 turn), maxStack 1
const TOX := 1040970 # Sram "Toxines" grade 1: air 5-7 at the end of the target's turn (TE, 2 turns)
const MIST := 1040967 # Sram "Brume" grade 1: glyph-aura (circle 3, 2 turns): -3 range to enemies, allies invisible
const TOFU := 1082231 # Osamodas "Tofu" grade 1: its start spell puts it in states 95 / 96
const DOUBLE := 1040922 # Sram "Double" grade 1: swap, +2 MP and kill after 2 turns (delay 2)
const HIT := 960 # made up: 100 neutral
const THORNS := 961 # made up: "when hit by an enemy, take 7 more" (DBE, 2 turns)
const LOOP := 962 # made up: casts itself


func _init() -> void:
	SpellBook.use_file("")


class Arena:
	var fight: Fight
	var me := Fighter.new()
	var foe := Fighter.new()
	var events: Array = []

	func _init(spells: Array) -> void:
		fight = Fight.new(1, MapData.new(), 7, func(ev: Dictionary) -> void: events.append(ev))
		me.id = 1
		me.cell = 300
		me.level = 10
		me.hp = 100
		me.max_hp = 100
		me.ap = 12
		me.max_ap = 12
		me.spells = spells
		me.stats = {"agility": 1000} # plays first
		foe.id = 2
		foe.team = 1
		foe.cell = at(6, 0)
		foe.hp = 500
		foe.max_hp = 500
		foe.mp = 6
		foe.max_mp = 6
		fight.add_fighter(me)
		fight.add_fighter(foe)
		fight.start_placement(0)
		fight.begin(0)

	func at(dx: int, dy: int) -> int:
		return MapGeometry.from_iso(MapGeometry.to_iso(300) + Vector2i(dx, dy))

	## ends turns until it is `f`'s
	func turn_of(f: Fighter) -> void:
		fight.end_turn(0)
		while fight.current() != f:
			fight.end_turn(0)

	func triggers(f: Fighter) -> Array:
		return f.buffs.filter(func(b: Buff) -> bool: return b.kind == "trigger")


func _made_up() -> void:
	SpellBook.get_spell(CUT) # loads spells.json first (it loads when its table is empty)
	SpellBook._spells[HIT] = {"id": HIT, "ap": 0, "range": [0, 9], "los": false, "per_turn": 9, "per_target": 9,
			"effects": [{"kind": "damage", "element": "neutral", "min": 100, "max": 100, "target": "all"}]}
	SpellBook._spells[THORNS] = {"id": THORNS, "ap": 0, "range": [0, 9], "los": false, "per_turn": 9, "per_target": 9,
			"effects": [{"kind": "damage", "element": "neutral", "min": 7, "max": 7, "target": "all", "on": ["DBE"], "turns": 2}]}
	SpellBook._spells[LOOP] = {"id": LOOP, "ap": 0, "range": [0, 9], "los": false, "per_turn": 9, "per_target": 9,
			"effects": [{"kind": "damage", "element": "neutral", "min": 1, "max": 1, "target": "enemies"},
				{"kind": "cast", "spell": LOOP, "target": "enemies"}]}


func _cleanup() -> void:
	for id in [HIT, THORNS, LOOP]:
		SpellBook._spells.erase(id)


func test_the_extracted_triggers() -> void:
	var e: Dictionary = SpellBook.get_spell(CUT)["effects"][1]
	eq([str(e["kind"]), int(e["pct"]), e["on"], int(e["turns"])], ["taken", 110, ["D"], 1],
			"1163 x110 %, triggers D, effectTriggerDuration 1")
	var t: Dictionary = SpellBook.get_spell(TOX)["effects"][0]
	eq([str(t["kind"]), t["on"], int(t["turns"])], ["damage", ["TE"], 2])
	eq(str(SpellBook.get_spell(MIST)["effects"][0]["kind"]), "aura")
	check(int(SpellBook.summon(8070)["grades"][0]["start"]) > 0, "the Tofu's startingSpellId")


func test_damage_suffered_multiplier_does_not_stack_past_max_stack() -> void:
	_made_up()
	var a := Arena.new([CUT, HIT])
	eq(a.fight.cast(a.me, CUT, a.foe.cell, 0), "")
	eq(a.fight.cast(a.me, CUT, a.foe.cell, 0), "", "cast twice (2 per target)")
	eq(a.triggers(a.foe).size(), 1, "maxStack 1: the second replaces the first")
	var hp := a.foe.hp
	a.fight.cast(a.me, HIT, a.foe.cell, 0)
	eq(hp - a.foe.hp, 110, "100 x 110 %, after the formula")
	a.turn_of(a.me)
	eq(a.triggers(a.foe).size(), 0, "1 turn: gone at the caster's next turn")
	_cleanup()


func test_a_poison_ticks_at_the_end_of_its_targets_turns() -> void:
	var a := Arena.new([TOX])
	var hp := a.foe.hp
	eq(a.fight.cast(a.me, TOX, a.foe.cell, 0), "")
	eq(a.foe.hp, hp, "nothing at cast")
	a.turn_of(a.foe)
	eq(a.foe.hp, hp, "nor at the start of its turn")
	a.fight.end_turn(0)
	check(a.foe.hp < hp, "air damage at the end of its turn")
	hp = a.foe.hp
	a.turn_of(a.foe)
	a.fight.end_turn(0)
	check(a.foe.hp < hp, "again the next turn")
	hp = a.foe.hp
	a.turn_of(a.foe)
	a.fight.end_turn(0)
	eq(a.foe.hp, hp, "2 turns: over")


func test_a_hit_fires_the_holders_trigger_once() -> void:
	_made_up()
	var a := Arena.new([THORNS, HIT])
	a.fight.cast(a.me, THORNS, a.foe.cell, 0)
	var hp := a.foe.hp
	a.fight.cast(a.me, HIT, a.foe.cell, 0)
	eq(hp - a.foe.hp, 107, "hit by an enemy (DBE): 7 more, which does not fire it again")
	hp = a.foe.hp
	FightEffects.damage(a.fight, a.foe, a.foe, "neutral", 10)
	FightTriggers.flush(a.fight)
	eq(hp - a.foe.hp, 10, "hitting itself is no enemy hit")
	_cleanup()


func test_chained_spells_stop() -> void:
	_made_up()
	var a := Arena.new([LOOP])
	var hp := a.foe.hp
	eq(a.fight.cast(a.me, LOOP, a.foe.cell, 0), "")
	eq(hp - a.foe.hp, 1 + FightTriggers.MAX_DEPTH, "the cast and 4 chained casts")
	_cleanup()


func test_a_glyph_aura_lasts_while_inside() -> void:
	var a := Arena.new([MIST])
	a.foe.cell = a.at(4, 0)
	eq(a.fight.cast(a.me, MIST, a.at(2, 0), 0), "")
	var aura := a.foe.buffs.filter(func(b: Buff) -> bool: return b.aura != 0)
	eq(aura.size(), 1, "inside the circle 3: -3 range")
	eq([aura[0].stat, aura[0].value, aura[0].turns], ["range", -3, -1])
	check(a.me.has_flag("invisible"), "allies inside: invisible (150, P1.13c)")
	a.turn_of(a.foe)
	eq(a.fight.move(a.foe, a.at(6, 0), 0), "")
	check(not a.foe.buffs.any(func(b: Buff) -> bool: return b.aura != 0), "taken back when it leaves")


func test_a_glyph_aura_takes_back_when_it_goes() -> void:
	var a := Arena.new([MIST])
	a.foe.cell = a.at(4, 0)
	a.fight.cast(a.me, MIST, a.at(2, 0), 0)
	a.turn_of(a.me)
	check(a.foe.buffs.any(func(b: Buff) -> bool: return b.aura != 0), "1 turn left")
	a.turn_of(a.me)
	eq(a.fight.marks.size(), 0, "2 turns of its caster")
	check(not a.foe.buffs.any(func(b: Buff) -> bool: return b.aura != 0), "its effects go with it")


func test_a_summon_casts_its_start_spell() -> void:
	var a := Arena.new([TOFU])
	eq(a.fight.cast(a.me, TOFU, a.at(1, 0), 0), "")
	var tofu := a.fight.fighter_at(a.at(1, 0))
	check(tofu.has_state(95) and tofu.has_state(96), "states 95 / 96 of its startingSpellId")


func test_delayed_effects_land_later() -> void:
	var a := Arena.new([DOUBLE])
	eq(a.fight.cast(a.me, DOUBLE, a.at(1, 0), 0), "")
	var double := a.fight.fighter_at(a.at(1, 0))
	check(double != null and double.alive, "the Double is there")
	check(double.buffs.filter(func(b: Buff) -> bool: return b.kind == "delay").size() >= 3,
			"swap, +2 MP and kill wait 2 turns")
	a.turn_of(a.me)
	a.turn_of(a.me)
	a.turn_of(a.me)
	check(not double.alive, "gone after its turns")
