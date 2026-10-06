## Carry and throw (roadmap P1.12): the real Pandawa spells (spells.json):
## Karcham carries then throws, the carried fighter follows its carrier, the
## Porteur state blocks the other spells, the throws touch the thrown fighter
## once (targetMask K), rooted fighters cannot be carried, deaths and walking
## off free the pair.
extends TestCase

const KARCHAM := 1040662 # grade 1: range 1 (+3 when carrying), in line
const EAU_DE_VIE := 1040713 # grade 1: throws, heals allies / hurts enemies around (X1), K = the thrown one
const GUEULE := 1040708 # Gueule de Bois grade 1: a plain attack
const SOBER := 3531 # Pandawa start state (Karcham criterion)


func _init() -> void:
	SpellBook.use_file("")


## A bare fight on an empty map: `me` (Pandawa, sober, plays first), an ally next
## to me and a foe next to me on the other side.
class Arena:
	var fight: Fight
	var me := Fighter.new()
	var ally := Fighter.new()
	var foe := Fighter.new()
	var events: Array = []

	func _init() -> void:
		fight = Fight.new(1, MapData.new(), 7, func(ev: Dictionary) -> void: events.append(ev))
		_fighter(me, 1, 0, 300)
		me.level = 10
		me.ap = 12
		me.max_ap = 12
		me.mp = 6
		me.max_mp = 6
		me.spells = [KARCHAM, EAU_DE_VIE, GUEULE]
		me.stats = {"agility": 1000} # plays first
		_fighter(ally, 2, 0, at(0, -1))
		_fighter(foe, 3, 1, at(1, 0))
		fight.start_placement(0)
		fight.begin(0)
		FightEffects.add_state(fight, me, me, {"state": SOBER}, -1, 0)

	func _fighter(f: Fighter, id: int, team: int, cell: int) -> void:
		f.id = id
		f.team = team
		f.cell = cell
		f.hp = 100
		f.max_hp = 200
		fight.add_fighter(f)

	## the cell (dx, dy) diamond steps from 300
	func at(dx: int, dy: int) -> int:
		return MapGeometry.from_iso(MapGeometry.to_iso(300) + Vector2i(dx, dy))

	func last_effects(type := Protocol.SPELL_CAST) -> Array:
		for i in range(events.size() - 1, -1, -1):
			if events[i]["t"] == type:
				return events[i]["effects"]
		return []

	func kinds(type := Protocol.SPELL_CAST) -> Array:
		return last_effects(type).map(func(e: Dictionary) -> String: return str(e["kind"]))


func test_the_extracted_pandawa_spells_carry_and_throw() -> void:
	var k := SpellBook.get_spell(KARCHAM)
	check(not (k.get("partial", []) as Array).has(50.0), "the carry is simulated (its sub-spells may not be)")
	eq(k["effects"].map(func(e: Dictionary) -> String: return str(e["kind"])).slice(0, 2), ["carry", "throw"])
	eq(int(k["carry_range"]), 3, "281 +3 range on itself (grade 1)")
	var e: Array = SpellBook.get_spell(EAU_DE_VIE)["effects"]
	eq(str(e[0]["kind"]), "throw")
	eq(e.filter(func(x: Dictionary) -> bool: return x.get("carried", false)).size(), 2, "K: heal / damage the thrown one")


func test_karcham_carries_the_target_onto_the_caster() -> void:
	var a := Arena.new()
	eq(a.fight.cast(a.me, KARCHAM, a.foe.cell, 0), "")
	eq(a.foe.carried_by, a.me.id)
	eq(a.me.carrying, a.foe.id)
	eq(a.foe.cell, a.me.cell)
	check(a.me.has_state(FightRules.CARRIER_STATE) and a.foe.has_state(FightRules.CARRIED_STATE), "Porteur / Porté")
	eq(a.fight.fighter_at(a.me.cell), a.me, "the carried one is off the board")
	eq(a.kinds(), ["carry", "buff", "buff"])


func test_a_carrier_only_casts_its_throws() -> void:
	var a := Arena.new()
	a.fight.cast(a.me, KARCHAM, a.foe.cell, 0)
	eq(a.fight.cast_check(a.me, GUEULE, a.ally.cell), Protocol.E_SPELL_FORBIDDEN, "Porteur: preventsSpellCast")
	eq(a.fight.cast_check(a.me, EAU_DE_VIE, a.at(0, 3)), "", "the throws need the Porteur state (HS=3)")


func test_the_carried_fighter_follows_its_carrier() -> void:
	var a := Arena.new()
	a.fight.cast(a.me, KARCHAM, a.foe.cell, 0)
	eq(a.fight.move(a.me, a.at(-2, 0), 0), "")
	eq(a.me.cell, a.at(-2, 0))
	eq(a.foe.cell, a.me.cell)


func test_karcham_throws_on_a_free_cell_farther_away() -> void:
	var a := Arena.new()
	a.fight.cast(a.me, KARCHAM, a.foe.cell, 0)
	eq(a.fight.cast_check(a.me, KARCHAM, a.ally.cell), Protocol.E_CELL_NOT_FREE, "a throw lands on a free cell")
	eq(a.fight.cast_check(a.me, KARCHAM, a.at(0, 5)), Protocol.E_OUT_OF_RANGE)
	eq(a.fight.cast(a.me, KARCHAM, a.at(0, 4), 0), "", "range 1 + 3 when carrying")
	eq(a.foe.cell, a.at(0, 4))
	eq(a.foe.carried_by, -1)
	eq(a.me.carrying, -1)
	check(not a.me.has_state(FightRules.CARRIER_STATE) and not a.foe.has_state(FightRules.CARRIED_STATE), "states end")
	eq(a.kinds()[0], "throw")
	eq(a.fight.fighter_at(a.at(0, 4)), a.foe)


func test_a_throw_touches_the_thrown_fighter_once() -> void:
	var a := Arena.new()
	a.fight.cast(a.me, KARCHAM, a.ally.cell, 0) # carry the ally
	var land := a.at(3, 0) # the foe (at (1, 0)) is not next to it
	a.foe.cell = a.at(3, 1) # now it is
	eq(a.fight.cast(a.me, EAU_DE_VIE, land, 0), "")
	var heals := a.last_effects().filter(func(e: Dictionary) -> bool: return e["kind"] == "heal")
	eq(heals.size(), 1, "the K heal only (the X1 heal does not count it twice)")
	eq(int(heals[0]["target"]), a.ally.id)
	var hits := a.last_effects().filter(func(e: Dictionary) -> bool: return e["kind"] == "damage")
	eq(hits.size(), 1)
	eq(int(hits[0]["target"]), a.foe.id, "the foe next to the landing cell is hit")


func test_a_rooted_fighter_cannot_be_carried() -> void:
	var a := Arena.new()
	# Enraciné (state 6, Stabilisation): spellstates.cantSwitchPosition
	FightEffects.add_state(a.fight, a.me, a.foe, {"state": 6, "flags": ["cant_be_pushed", "cant_switch"]}, 1, 0)
	eq(a.fight.cast(a.me, KARCHAM, a.foe.cell, 0), "")
	eq(a.foe.carried_by, -1)
	check(not a.me.has_state(FightRules.CARRIER_STATE), "nothing carried")


func test_the_carried_fighter_is_dropped_when_its_carrier_dies() -> void:
	var a := Arena.new()
	a.fight.cast(a.me, KARCHAM, a.ally.cell, 0)
	FightEffects.hurt(a.me, 1000, "neutral")
	var out := a.fight.handle_deaths()
	eq(str(out[0]["kind"]), "drop")
	eq(a.ally.carried_by, -1)
	check(a.ally.alive and not a.ally.has_state(FightRules.CARRIED_STATE), "freed, alive")
	eq(a.fight.fighter_at(a.ally.cell), a.ally, "back on the board, on the carrier's cell")


func test_a_carried_fighter_walks_off_its_carrier() -> void:
	var a := Arena.new()
	a.fight.cast(a.me, KARCHAM, a.foe.cell, 0)
	while a.fight.current() != a.foe:
		a.fight.end_turn(0)
	a.foe.mp = 3
	a.foe.stats = {"agility": 1000} # no tackle from the ally and me
	var to := a.at(0, 2)
	eq(a.fight.move(a.foe, to, 0), "")
	eq(a.foe.cell, to)
	eq(a.me.carrying, -1)
	eq(a.kinds(Protocol.FIGHTER_MOVE)[0], "drop")
	check(not a.me.has_state(FightRules.CARRIER_STATE), "the carrier is free again")
