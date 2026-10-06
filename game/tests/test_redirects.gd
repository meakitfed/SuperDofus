## Damage redirections, the immediate glyph and CCMPARR (roadmap P1.13e). Effect names from the
## client enum Metadata.Effect.ActionId (docs/client_enums.md): 786 CharacterHealAttackers,
## 765 CharacterSacrify, 1061 CharacterShareDamages, 1165 FightAddGlyphCastingSpellImmediate.
extends TestCase

const SUPPLICE := 1040541 # Sacrieur "Supplice" grade 1: earth steal, attackers of the target heal 20 % (786, D)
const SACRIFICE := 1040583 # Sacrieur "Sacrifice": allies in circle 2 have their damage intercepted (765, D)
const MUSETTE := 1041760 # Enutrof "Musette Animée": allies around the summon share their damage (1061, D)
const SAC := 1041688 # Enutrof "Sac Animé": intercepts, destroyed 3 turns later
const AGITATION := 1041353 # Enutrof "Agitation": +15 power per MP used (CCMPARR)
const EXCURSION := 1041137 # "Excursion": an aura (1091) and an immediate glyph (1165) of the same spell
const HIT := 970 # made up: 100 neutral
const SHARE := 971 # made up: allies in circle 1 share their damage (1061)
const GLYPH := 972 # made up: an immediate glyph (circle 1) casting HIT


func _init() -> void:
	SpellBook.use_file("")


class Arena:
	var fight: Fight
	var me := Fighter.new()
	var ally := Fighter.new()
	var foe := Fighter.new()

	func _init() -> void:
		fight = Fight.new(1, MapData.new(), 7, func(_ev: Dictionary) -> void: pass)
		for f: Fighter in [me, ally, foe]:
			f.level = 100
			f.hp = 500
			f.max_hp = 500
			f.ap = 12
			f.max_ap = 12
			f.mp = 6
			f.max_mp = 6
		me.id = 1
		me.cell = 300
		me.stats = {"agility": 1000} # plays first
		me.spells = [HIT, SHARE, GLYPH]
		ally.id = 3
		ally.cell = at(1, 0)
		foe.id = 2
		foe.team = 1
		foe.cell = at(6, 0)
		foe.spells = [HIT]
		for f: Fighter in [me, ally, foe]:
			fight.add_fighter(f)
		fight.start_placement(0)
		fight.begin(0)

	func at(dx: int, dy: int) -> int:
		return MapGeometry.from_iso(MapGeometry.to_iso(300) + Vector2i(dx, dy))

	## `by` hits `t` with HIT (100 neutral), its triggers fired
	func strike(by: Fighter, t: Fighter) -> void:
		FightEffects.apply_spell(fight, by, SpellBook.get_spell(HIT), t.cell, false)
		FightTriggers.flush(fight)


func _made_up() -> void:
	SpellBook.get_spell(SUPPLICE) # loads spells.json first
	SpellBook._spells[HIT] = {"id": HIT, "ap": 0, "range": [0, 9], "los": false, "per_turn": 9, "per_target": 9,
			"effects": [{"kind": "damage", "element": "neutral", "min": 100, "max": 100, "target": "all"}]}
	SpellBook._spells[SHARE] = {"id": SHARE, "ap": 0, "range": [0, 9], "los": false, "per_turn": 9, "per_target": 9,
			"effects": [{"kind": "share", "target": "allies", "area": {"shape": "circle", "size": 1}, "on": ["D"], "turns": 1}]}
	SpellBook._spells[GLYPH] = {"id": GLYPH, "ap": 0, "range": [0, 9], "los": false, "per_turn": 9, "per_target": 9,
			"effects": [{"kind": "glyph_now", "spell": HIT, "mark": {"shape": "circle", "size": 1}, "target": "all",
				"duration": 1, "color": "#ffffff", "origin": GLYPH}]}


func _cleanup() -> void:
	for id in [HIT, SHARE, GLYPH]:
		SpellBook._spells.erase(id)


func test_the_extracted_effects() -> void:
	var heal: Dictionary = SpellBook.get_spell(SUPPLICE)["effects"][1]
	eq([str(heal["kind"]), int(heal["pct"]), heal["on"]], ["heal_attackers", 20, ["D"]], "786 value = the %")
	eq(str(SpellBook.get_spell(SACRIFICE)["effects"][0]["kind"]), "intercept")
	eq(str(SpellBook.get_spell(MUSETTE)["effects"][1]["kind"]), "share")
	var agit: Array = SpellBook.get_spell(AGITATION)["effects"]
	eq(agit[-1]["on"], ["CCMPARR"])
	var kinds: Array = SpellBook.get_spell(EXCURSION)["effects"].map(func(e: Dictionary) -> String: return str(e["kind"]))
	eq(kinds, ["aura", "glyph_now"], "1091 + 1165")
	var kill: Dictionary = SpellBook.get_spell(SAC)["effects"].filter(func(e: Dictionary) -> bool: return e["kind"] == "kill")[0]
	eq([str(kill["target"]), int(kill["delay"])], ["all", 3], "Sac Animé: the summon is destroyed, not its caster")
	for sid in [SUPPLICE, MUSETTE, SAC, AGITATION]:
		check(not SpellBook.get_spell(sid).has("partial"), "%d fully simulated" % sid)


func test_the_attackers_of_the_target_heal() -> void:
	_made_up()
	var a := Arena.new()
	a.foe.cell = a.at(1, 1)
	FightEffects.apply_spell(a.fight, a.me, SpellBook.get_spell(SUPPLICE), a.foe.cell, false)
	FightTriggers.flush(a.fight)
	a.me.hp = 300
	a.ally.hp = 300
	a.strike(a.ally, a.foe)
	eq(a.ally.hp, 320, "20 % of the 100 it dealt")
	eq(a.me.hp, 300, "the caster of Supplice did not strike")
	_cleanup()


func test_the_interceptor_takes_the_hit() -> void:
	_made_up()
	var a := Arena.new()
	FightEffects.apply_spell(a.fight, a.me, SpellBook.get_spell(SACRIFICE), a.me.cell, false)
	a.strike(a.foe, a.ally)
	eq([a.ally.hp, a.me.hp], [500, 400], "the Sacrieur (on the target cell) takes it")
	a.strike(a.foe, a.me)
	eq(a.me.hp, 300, "its own hits stay its own")
	_cleanup()


func test_the_summon_on_the_target_cell_intercepts() -> void:
	_made_up()
	var a := Arena.new()
	eq(FightEffects.apply_spell(a.fight, a.me, SpellBook.get_spell(SAC), a.at(0, 1), false).is_empty(), false)
	var sac := a.fight.fighter_at(a.at(0, 1))
	check(sac != null and sac.summoner == a.me.id, "the Sac Animé is there")
	var hp := sac.hp
	a.strike(a.foe, a.ally)
	eq(a.ally.hp, 500)
	eq(hp - sac.hp, mini(100, hp), "the Sac takes it")
	check(a.me.alive and a.me.hp == 500, "not its caster")
	_cleanup()


func test_shared_damage_is_split() -> void:
	_made_up()
	var a := Arena.new()
	FightEffects.apply_spell(a.fight, a.me, SpellBook.get_spell(SHARE), a.me.cell, false)
	a.strike(a.foe, a.me)
	eq([a.me.hp, a.ally.hp], [450, 450], "100 split between the two holders")
	_cleanup()


func test_an_immediate_glyph_hits_who_stands_in_it() -> void:
	_made_up()
	var a := Arena.new()
	var out := FightEffects.apply_spell(a.fight, a.me, SpellBook.get_spell(GLYPH), a.foe.cell, false)
	eq(a.foe.hp, 400, "hit at once")
	eq(a.fight.marks.size(), 1)
	check(out.any(func(e: Dictionary) -> bool: return e["kind"] == "mark_add"))
	_cleanup()


func test_power_for_each_mp_used() -> void:
	_made_up()
	var a := Arena.new()
	FightEffects.apply_spell(a.fight, a.me, SpellBook.get_spell(AGITATION), a.me.cell, false)
	var power := a.me.stat("power")
	var mp := a.me.mp
	eq(a.fight.move(a.me, a.at(0, 3), 0), "")
	eq(mp - a.me.mp, 3)
	eq(a.me.stat("power") - power, 45, "+15 per MP used (CCMPARR)")
	_cleanup()
