## Zone options (roadmap P1.13l), read in the client's native code: onlyAffectIfInSightLine
## (gtb.blnw: only the cells in sight from the centre), includeCarried (gtz.nhs: a carried
## fighter, state 8, is only touched with it; every point has it) and the Custom shape ;
## (class grx: the cells of zoneDescr.cellIds). forcedDirection has no reader in the client.
extends TestCase

const HARPONNEUSE := 1044693 # Harponneuse II: C7 min 1 in sight, l,m,P,*E134 (+ damage to allies)
const HOLMGANG := 1080099 # effect 2: C2 min 1 with includeCarried, A,E8 (carried enemies only)


func _init() -> void:
	SpellBook.use_file("")


## A bare fight: `me` in the middle, fighters placed with add().
class Arena:
	var fight: Fight
	var me := Fighter.new()

	func _init(map := MapData.new()) -> void:
		fight = Fight.new(1, map, 7, func(_ev: Dictionary) -> void: pass)
		place(me, 1, 0, 300)

	func place(f: Fighter, id: int, team: int, cell: int) -> Fighter:
		f.id = id
		f.team = team
		f.cell = cell
		f.hp = 100
		f.max_hp = 100
		fight.add_fighter(f)
		return f

	func add(id: int, team: int, dx: int, dy: int) -> Fighter:
		return place(Fighter.new(), id, team, at(dx, dy))

	func at(dx: int, dy: int) -> int:
		return MapGeometry.from_iso(MapGeometry.to_iso(300) + Vector2i(dx, dy))

	## `carrier` carries `t` as Carry.apply leaves them (same cell, state 8 "Porté")
	func carry(carrier: Fighter, t: Fighter) -> void:
		t.cell = carrier.cell
		t.carried_by = carrier.id
		carrier.carrying = t.id
		FightEffects.add_state(fight, carrier, t, {"state": FightRules.CARRIED_STATE}, -1, 0)

	func ids(list: Array) -> Array:
		var out := list.map(func(f: Fighter) -> int: return f.id)
		out.sort()
		return out


func test_the_options_are_extracted() -> void:
	var harpon: Dictionary = SpellBook.get_spell(HARPONNEUSE)["effects"][0]["area"]
	eq([str(harpon["shape"]), int(harpon["size"]), harpon.get("sight")], ["circle", 7, true], "onlyAffectIfInSightLine")
	var holm: Dictionary = SpellBook.get_spell(HOLMGANG)["effects"][2]
	eq([str(holm["area"]["shape"]), holm["area"].get("with_carried"), str(holm["mask"])], ["circle", true, "A,E8"],
			"includeCarried, written on the shapes other than points")
	check(FightRules.touches_carried({"shape": "point", "size": 0}), "every point has includeCarried")
	check(not FightRules.touches_carried({"shape": "circle", "size": 2}))


func test_a_zone_in_sight_stops_at_walls_and_fighters() -> void:
	var map := MapData.new()
	var a := Arena.new(map)
	map.los_blocked[a.at(0, 2)] = true
	var zone := {"shape": "circle", "size": 3, "sight": true}
	var cells := FightRules.zone_in(map, {a.at(-2, 0): true}, zone, 300)
	check(cells.has(300), "the centre")
	check(cells.has(a.at(1, 0)) and cells.has(a.at(3, 0)))
	check(not cells.has(a.at(0, 3)), "behind the wall")
	check(cells.has(a.at(-2, 0)) and not cells.has(a.at(-3, 0)), "a fighter is seen, not what is behind it")
	eq(FightRules.zone_in(map, {}, {"shape": "circle", "size": 3}, 300).size(), FightRules.zone({"shape": "circle", "size": 3}, 300).size(),
			"without the flag, every cell")


func test_a_turret_only_boosts_the_allies_it_sees() -> void:
	var a := Arena.new()
	var seen := a.add(2, 0, 3, 0)
	var hidden := a.add(3, 0, 0, 4)
	a.add(4, 1, 0, 2) # a foe between the turret and the second ally
	var e: Dictionary = SpellBook.get_spell(HARPONNEUSE)["effects"][0]
	eq(a.ids(FightEffects.targets(a.fight, a.me, SpellBook.get_spell(HARPONNEUSE), e, a.me.cell)), [seen.id],
			"l: allied characters in sight (the one behind the foe is not)")
	check(hidden.alive)


func test_a_carried_fighter_is_only_touched_with_include_carried() -> void:
	var a := Arena.new()
	var carrier := a.add(2, 1, 1, 0)
	var carried := a.add(3, 1, 5, 5)
	a.carry(carrier, carried)
	var spell := {"id": 1, "area": {"shape": "circle", "size": 2}}
	var e := {"kind": "damage", "target": "enemies", "area": {"shape": "circle", "size": 2}}
	eq(a.ids(FightEffects.targets(a.fight, a.me, spell, e, a.me.cell)), [carrier.id], "a circle without the flag: the carrier alone")
	e["area"]["with_carried"] = true
	eq(a.ids(FightEffects.targets(a.fight, a.me, spell, e, a.me.cell)), [carrier.id, carried.id])
	e["area"] = {"shape": "point", "size": 0}
	eq(a.ids(FightEffects.targets(a.fight, a.me, spell, e, carrier.cell)), [carrier.id, carried.id],
			"a point on the carrier touches the carried one too")


func test_holmgang_reaches_the_carried_enemy_only() -> void:
	var a := Arena.new()
	var carrier := a.add(2, 1, 1, 0)
	var carried := a.add(3, 1, 5, 5)
	a.add(4, 1, 0, 1) # a foe next to me, not carried
	a.carry(carrier, carried)
	var spell := SpellBook.get_spell(HOLMGANG)
	var got := FightEffects.targets(a.fight, a.me, spell, spell["effects"][2], a.me.cell)
	got = got.filter(func(t: Fighter) -> bool: return TargetMask.affects(a.fight, a.me, t, spell["effects"][2]))
	eq(a.ids(got), [carried.id], "A,E8: an enemy in state 8 Porté, touched thanks to includeCarried")


func test_a_custom_zone_is_its_listed_cells() -> void:
	var zone := {"shape": "custom", "size": 0, "cells": [330, 287, 287, 900]}
	var cells := Array(FightRules.zone(zone, 10, 20))
	cells.sort()
	eq(cells, [287, 330], "wherever it is cast, map cells only, once")


func test_a_mark_zone_never_touches_a_carried_fighter() -> void:
	# P1.13s, client code MarkedCellsService.bfib: a glyph / aura zone is built by gru.blha with
	# every option flag at 0 (so includeCarried = 0): a fighter in state 8 is left out of it.
	var a := Arena.new()
	var carrier := a.add(2, 1, 1, 0)
	var carried := a.add(3, 1, 5, 5)
	a.carry(carrier, carried)
	a.fight.marks.append({"id": 1, "kind": "glyph_start", "caster": a.me.id, "spell": HOLMGANG, "origin": 0,
			"cell": carried.cell, "cells": [carried.cell], "color": "#ffffff", "turns": 3, "hidden": false,
			"who": "all", "cond": [], "inside": []})
	a.fight.marks.append({"id": 2, "kind": "aura", "caster": a.me.id, "spell": HOLMGANG, "origin": 0,
			"cell": carried.cell, "cells": [carried.cell], "color": "#ffffff", "turns": 3, "hidden": false,
			"who": "all", "cond": [], "inside": []})
	eq(FightMarks.glyphs(a.fight, carried, "glyph_start"), [], "no glyph under a carried fighter")
	eq(FightMarks.entered(a.fight, carried), [], "no trap or wall either")
	FightMarks.auras(a.fight)
	eq(a.fight.marks[1]["inside"], [carrier.id], "the aura takes the carrier in, not the carried one")
