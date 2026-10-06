## Summons (roadmap P1.11): the real class spells (spells.json) and their monsters
## (spells.json `summons`): who plays, the summon limit, stats from the summoner's
## level, chain deaths, replace, double, no rewards.
extends TestCase

const TOFU := 1082231 # Osamodas "Tofu" grade 1: summons monster 8070 grade 1
const TREE := 1042093 # Sadida "Arbre" grade 1: summons 5894, which does not play
const MAD := 1042223 # Sadida "La Folle" grade 1: replaces its Arbre with 5896
const DOUBLE := 1040922 # Sram "Double" grade 1


func _init() -> void:
	SpellBook.use_file("")


## A bare fight on an empty map: `me` (team 0, plays first, level 10) and `foe`.
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
		foe.cell = MapGeometry.from_iso(MapGeometry.to_iso(300) + Vector2i(6, 0))
		foe.hp = 100
		foe.max_hp = 100
		fight.add_fighter(me)
		fight.add_fighter(foe)
		fight.start_placement(0)
		fight.begin(0)

	## a free cell `dx` cells from me
	func near(dx := 1) -> int:
		return MapGeometry.from_iso(MapGeometry.to_iso(me.cell) + Vector2i(0, dx))

	func summons() -> Array:
		return fight.fighters.values().filter(func(f: Fighter) -> bool: return f.summoner == me.id and f.alive)

	func last_effects() -> Array:
		for i in range(events.size() - 1, -1, -1):
			if events[i]["t"] == Protocol.SPELL_CAST:
				return events[i]["effects"]
		return []


func test_the_extracted_spells_summon_real_monsters() -> void:
	var tofu := SpellBook.get_spell(TOFU)
	eq(str(tofu["effects"][0]["kind"]), "summon")
	eq(int(tofu["effects"][0]["monster"]), 8070)
	check(not tofu.has("partial"), "Tofu fully simulated")
	var m := SpellBook.summon(8070)
	check(bool(m["slot"]) and bool(m["plays"]), "the Tofu uses a slot and plays (monsters.m_flags bits 0, 6)")
	check(not bool(SpellBook.summon(5894)["plays"]), "the Arbre does not play")
	check(not bool(SpellBook.summon(5894)["slot"]), "nor uses a slot")


func test_a_summon_plays_right_after_its_summoner() -> void:
	var a := Arena.new([TOFU])
	eq(a.fight.cast(a.me, TOFU, a.near(), 0), "")
	var s: Array = a.summons()
	eq(s.size(), 1)
	var t: Fighter = s[0]
	eq(t.team, a.me.team)
	eq(t.cell, a.near())
	check(t.id < 0, "summon ids are negative")
	eq(t.max_hp, 50 * (10 + 10) / 20, "HP: bonus 50 x (summoner level 10 + 10) / 20")
	eq(t.stat("agility"), 500, "50 % of its summoner's agility (P1.11b)")
	eq(a.fight.order, [a.me.id, t.id, a.foe.id])
	var eff: Dictionary = a.last_effects()[0]
	eq(str(eff["kind"]), "summon")
	eq(int(eff["summoner"]), a.me.id)
	eq(int(eff["fighter"]["summoner"]), a.me.id)
	eq(Array(eff["order"]), a.fight.order)
	a.fight.end_turn(0)
	eq(a.fight.current(), t, "the summon plays next")
	check(t.ai, "played by the AI")


func test_the_summon_limit() -> void:
	var a := Arena.new([TOFU])
	eq(a.fight.cast(a.me, TOFU, a.near(), 0), "")
	a.me.cooldowns.clear()
	eq(a.fight.cast(a.me, TOFU, a.near(-1), 0), Protocol.E_SUMMON_LIMIT, "1 summon at level 1 (StatFormulas.BASE_SUMMONS)")
	a.me.stats["summons"] = 1
	eq(a.fight.cast(a.me, TOFU, a.near(-1), 0), "", "+1 summon (characteristic 26)")
	eq(a.summons().size(), 2)
	eq(a.fight.order, [a.me.id, -101, -102, a.foe.id], "the newer summon plays after the older one")


func test_a_static_summon_has_no_turn_and_no_slot() -> void:
	var a := Arena.new([TREE, TOFU])
	eq(a.fight.cast(a.me, TREE, a.near(), 0), "")
	eq(a.fight.cast(a.me, TOFU, a.near(-1), 0), "", "the Arbre uses no slot")
	var tree: Fighter = a.fight.fighter_at(a.near())
	eq(tree.monster, 5894)
	check(not a.fight.order.has(tree.id), "the Arbre never plays")
	check(not tree.has_state(256), "the spell's next effect has a delay of 1 turn")
	a.fight.end_turn(0)
	while a.fight.current() != a.me:
		a.fight.end_turn(0)
	check(tree.has_state(256), "it lands on the new Arbre at the start of the caster's next turn")


func test_summons_die_with_their_summoner_and_do_not_hold_the_fight() -> void:
	var a := Arena.new([TOFU])
	a.fight.cast(a.me, TOFU, a.near(), 0)
	var t: Fighter = a.summons()[0]
	a.me.hp = 1
	var kill := {"id": 950, "ap": 0, "range": [0, 9], "los": false, "per_turn": 9,
			"effects": [{"kind": "damage", "min": 50, "max": 50, "target": "all"}]}
	SpellBook._spells[950] = kill
	a.foe.spells = [950]
	a.fight.end_turn(0) # the Tofu
	a.fight.end_turn(0) # the foe
	eq(a.fight.cast(a.foe, 950, a.me.cell, 0), "")
	check(not t.alive, "the Tofu died with its summoner")
	var died := a.last_effects().filter(func(e: Dictionary) -> bool: return int(e["target"]) == t.id and bool(e.get("died", false)))
	eq(died.size(), 1, "its death is in the cast's effects")
	eq(a.fight.result, "lose", "a summon does not keep its team in the fight")
	SpellBook._spells.erase(950)


func test_replace_turns_the_arbre_into_la_folle() -> void:
	var a := Arena.new([TREE, MAD])
	a.fight.cast(a.me, TREE, a.near(), 0)
	var tree: Fighter = a.fight.fighter_at(a.near())
	tree.buffs.clear() # grown: no more state 256 (the first variant, grade 1)
	eq(a.fight.cast(a.me, MAD, a.near(), 0), "")
	check(not tree.alive, "the Arbre is killed")
	var mad: Fighter = a.fight.fighter_at(a.near())
	eq(mad.monster, 5896)
	eq(mad.summoner, a.me.id)
	eq(a.summons().size(), 1, "one summon, not two")


func test_double_copies_the_caster() -> void:
	var a := Arena.new([DOUBLE])
	a.me.stats["strength"] = 77
	eq(a.fight.cast(a.me, DOUBLE, a.near(), 0), "")
	var d: Fighter = a.summons()[0]
	eq(d.stat("strength"), 77)
	eq(d.max_hp, a.me.max_hp)
	eq(d.looks, a.me.looks)


func test_summons_give_no_rewards() -> void:
	var a := Arena.new([])
	var s := Summons.create(a.fight, a.foe, 8070, 1)
	s.cell = a.near(3)
	a.fight.add_summon(s, a.foe)
	a.foe.loot = {"xp": 100}
	a.foe.alive = false
	a.fight.result = "win"
	a.me.player_id = a.me.id
	var r := FightRewards.compute(a.fight)
	check(int(r[a.me.id]["xp"]) > 0, "XP for the monster")
	var solo := Arena.new([])
	solo.foe.loot = {"xp": 100}
	solo.foe.alive = false
	solo.fight.result = "win"
	solo.me.player_id = solo.me.id
	eq(int(FightRewards.compute(solo.fight)[solo.me.id]["xp"]), int(r[a.me.id]["xp"]), "the monster's summon changes nothing")


## P1.11b: a summon gets bonusCharacteristics % of its summoner's characteristics (Tofu: 50 %
## agility and air damage), its HP grow with the summoner's level (JondoEmu measure).
func test_a_summon_gets_a_share_of_its_summoner() -> void:
	for level: int in [10, 200]:
		var a := Arena.new([TOFU])
		a.me.level = level
		a.me.stats = {"agility": 1000, "damage_air": 40, "strength": 300}
		eq(a.fight.cast(a.me, TOFU, a.near(), 0), "")
		var tofu: Fighter = a.summons()[0]
		eq(tofu.stat("agility"), int(SpellBook.summon(8070)["grades"][0]["stats"].get("agility", 0)) + 500)
		eq(tofu.stat("damage_air"), 20)
		eq(tofu.stat("strength"), 0, "not its element")
		eq(tofu.max_hp, Summons.scaled(50, level) + int(SpellBook.summon(8070)["grades"][0]["hp"]))


func test_a_bomb_gets_all_of_its_summoner() -> void:
	var bomb := Summons.create(Arena.new([]).fight, _roublard(0), 3112, 1)
	eq(bomb.stat("damage_fire"), 0, "a level 10 Roublard without gear: its bomb neither")
	bomb = Summons.create(Arena.new([]).fight, _roublard(60), 3112, 1)
	eq([bomb.stat("damage_fire"), bomb.stat("intelligence")], [60, 60], "100 %")


func _roublard(v: int) -> Fighter:
	var f := Fighter.new()
	f.level = 10
	f.stats = {"damage_fire": v, "intelligence": v}
	return f
