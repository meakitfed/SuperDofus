## Trigger codes read in the client's fight preview (roadmap P1.13i, FightTriggers): made-up
## spells and a made-up listener ("+1 power each time <code> happens") on the fighters.
extends TestCase

const HIT := 970 # made up: 100 neutral
const PUSH := 971 # made up: push 3 cells
const HEAL := 972 # made up: heals 10, gives a shield
const CRIT := 973 # made up: 1 neutral, always critical
const SAP := 974 # made up: -1 AP, -1 range, +10 vitality
const HOOK := 975 # made up: attracts 2 cells
const SWAP := 976 # made up: swaps with the target (P1.13m)
const THIEF := 977 # made up: steals 2 MP and 1 AP, not dodgeable (P1.13m)
const DISPEL := 978 # made up: dispels (P1.13m)


func _init() -> void:
	SpellBook.use_file("")


class Arena:
	var fight: Fight
	var me := Fighter.new()
	var foe := Fighter.new()
	var friend := Fighter.new()
	var events: Array = []

	func _init() -> void:
		fight = Fight.new(1, MapData.new(), 7, func(ev: Dictionary) -> void: events.append(ev))
		_fighter(me, 1, 0, 300, 1000)
		me.ap = 12
		me.max_ap = 12
		me.stats = {"agility": 1000} # plays first
		me.spells = [HIT, PUSH, HEAL, CRIT, SAP, HOOK, SWAP, THIEF, DISPEL, Equipment.WEAPON_SPELL]
		me.own_spells[Equipment.WEAPON_SPELL] = {"id": Equipment.WEAPON_SPELL, "ap": 0, "range": [0, 9], "los": false,
				"per_turn": 9, "per_target": 9, "effects": [{"kind": "damage", "element": "earth", "min": 60, "max": 60, "target": "all"}]}
		_fighter(foe, 2, 1, at(6, 0), 500)
		_fighter(friend, 3, 0, at(0, -3), 100)
		fight.start_placement(0)
		fight.begin(0)

	func _fighter(f: Fighter, id: int, team: int, cell: int, hp: int) -> void:
		f.id = id
		f.team = team
		f.cell = cell
		f.level = 10
		f.hp = hp
		f.max_hp = hp
		fight.add_fighter(f)

	func at(dx: int, dy: int) -> int:
		return MapGeometry.from_iso(MapGeometry.to_iso(300) + Vector2i(dx, dy))

	## `f` gets "+1 power each time one of `codes` happens to it" (cast by `me`)
	func listen(f: Fighter, codes: Array) -> void:
		for c: String in codes:
			FightTriggers.add(fight, me, f, {"kind": "stat", "stat": "power", "min": 1, "max": 1, "on": [c], "turns": 5,
					"target": "all", "code": c}, 0, 0)

	## `caster` casts `id` on `cell` (the cast limits and AP set back first)
	func cast(caster: Fighter, id: int, cell: int) -> void:
		fight._casts.clear()
		fight._casts_on.clear()
		caster.ap = 12
		fight.cast(caster, id, cell, 0)


func _made_up() -> void:
	SpellBook.get_spell(1040972) # loads spells.json first (it loads when its table is empty)
	var base := {"ap": 0, "range": [0, 9], "los": false, "per_turn": 9, "per_target": 9}
	SpellBook._spells[HIT] = base.merged({"id": HIT, "effects": [{"kind": "damage", "element": "neutral", "min": 100, "max": 100, "target": "all"}]})
	SpellBook._spells[PUSH] = base.merged({"id": PUSH, "effects": [{"kind": "push", "min": 3, "max": 3, "target": "all"}]})
	SpellBook._spells[HEAL] = base.merged({"id": HEAL, "effects": [{"kind": "heal", "element": "fire", "min": 10, "max": 10, "target": "all"},
			{"kind": "shield", "of": "flat", "min": 5, "max": 5, "duration": 1, "target": "all"}]})
	SpellBook._spells[CRIT] = base.merged({"id": CRIT, "crit": 100, "effects": [{"kind": "damage", "element": "neutral", "min": 1, "max": 1, "target": "all"}]})
	SpellBook._spells[SAP] = base.merged({"id": SAP, "effects": [{"kind": "ap", "sign": -1, "min": 1, "max": 1, "target": "all"},
			{"kind": "stat", "stat": "range", "sign": -1, "min": 1, "max": 1, "duration": 1, "target": "all"},
			{"kind": "stat", "stat": "vitality", "min": 10, "max": 10, "duration": 1, "target": "all"}]})
	SpellBook._spells[HOOK] = base.merged({"id": HOOK, "effects": [{"kind": "pull", "min": 2, "max": 2, "target": "all"}]})
	SpellBook._spells[SWAP] = base.merged({"id": SWAP, "effects": [{"kind": "swap", "min": 0, "max": 0, "target": "all"}]})
	SpellBook._spells[THIEF] = base.merged({"id": THIEF, "effects": [
			{"kind": "mp", "sign": -1, "steal": true, "min": 2, "max": 2, "duration": 1, "target": "all"},
			{"kind": "ap", "sign": -1, "steal": true, "min": 1, "max": 1, "duration": 1, "target": "all"}]})
	SpellBook._spells[DISPEL] = base.merged({"id": DISPEL, "effects": [{"kind": "dispel", "min": 0, "max": 0, "target": "all"}]})


func _cleanup() -> void:
	for id in [HIT, PUSH, HEAL, CRIT, SAP, HOOK, SWAP, THIEF, DISPEL]:
		SpellBook._spells.erase(id)


## Which of `codes` fire on `f` while `act` runs (one listener per code, +1 power each).
func _which(a: Arena, f: Fighter, codes: Array, act: Callable) -> Array:
	var out: Array = []
	for c: String in codes:
		var power := f.stat("power")
		a.listen(f, [c])
		var b: Buff = f.buffs[-1]
		for g: Fighter in [a.me, a.foe, a.friend]:
			g.hp = g.max_hp
		act.call()
		if f.stat("power") > power:
			out.append(c)
		f.buffs.erase(b)
	return out


func test_the_holder_is_hit() -> void:
	_made_up()
	var a := Arena.new()
	var codes := ["D", "DN", "DA", "DBE", "DBA", "DM", "DR", "DS", "DT", "DG", "PD"]
	eq(_which(a, a.foe, codes, func() -> void: a.cast(a.me, HIT, a.foe.cell)),
			["D", "DN", "DBE", "DR", "DS"], "an enemy's spell from afar (gzp.bmzx)")
	eq(_which(a, a.me, ["D", "DBA", "DM", "DS"], func() -> void: a.cast(a.me, HIT, a.me.cell)),
			["D", "DBA", "DM", "DS"], "its own spell: an ally, at melee range")
	_cleanup()


func test_a_poison_or_a_triggered_hit_is_not_ds() -> void:
	_made_up()
	var a := Arena.new()
	var b := FightEffects._buff(a.fight, a.me, HIT, "poison", 2)
	b.effect = {"kind": "damage", "element": "air", "min": 3, "max": 3}
	eq(_which(a, a.foe, ["D", "DA", "DS"], func() -> void:
		FightEffects.poison(a.fight, a.foe, b)
		FightTriggers.flush(a.fight)), ["D", "DA"])
	_cleanup()


func test_what_the_holder_does() -> void:
	_made_up()
	var a := Arena.new()
	eq(_which(a, a.me, ["CD", "CDN", "CDBE", "CDBA", "CDR", "CDM", "CDS", "H", "D"],
			func() -> void: a.cast(a.me, HIT, a.foe.cell)), ["CD", "CDN", "CDBE", "CDR", "CDS"],
			"the author of the hit (gzp.bnaa / bmzz)")
	var heal := func() -> void:
		a.friend.hp = 50
		a.cast(a.me, HEAL, a.friend.cell)
	eq(_which(a, a.me, ["CH", "CS", "H"], heal), ["CH", "CS"], "it heals, it gives a shield")
	eq(_which(a, a.friend, ["H", "CH"], heal), ["H"])
	eq(_which(a, a.me, ["CC"], func() -> void: a.cast(a.me, CRIT, a.foe.cell)), ["CC"], "a critical hit")
	eq(_which(a, a.me, ["CC"], func() -> void: a.cast(a.me, HIT, a.foe.cell)), [])
	_cleanup()


func test_pushed_and_attracted() -> void:
	_made_up()
	var a := Arena.new()
	# a wall of fighters behind the foe: the push is blocked, the foe takes push damage
	var codes := ["M", "P", "MA", "D", "PD", "DS"]
	eq(_which(a, a.foe, codes, func() -> void:
		a.foe.cell = a.at(1, 0)
		a.friend.cell = a.at(3, 0)
		a.cast(a.me, PUSH, a.foe.cell)), ["M", "P", "PD"], "a push into a fighter is PD, not D (gzp.bmzw)")
	eq(_which(a, a.foe, codes, func() -> void:
		a.foe.cell = a.at(5, 0)
		a.cast(a.me, HOOK, a.foe.cell)), ["M", "MA"])
	_cleanup()


func test_characteristics_change() -> void:
	_made_up()
	var a := Arena.new()
	eq(_which(a, a.foe, ["APA", "MPA", "R", "LPU"], func() -> void: a.cast(a.me, SAP, a.foe.cell)),
			["APA", "R", "LPU"], "gzp.bmzy: characteristics 1, 19 (down), 11 (up)")
	_cleanup()


func test_states_on_and_off() -> void:
	_made_up()
	var a := Arena.new()
	eq(_which(a, a.foe, ["EON55", "EOFF55", "EON56"], func() -> void:
		FightEffects.add_state(a.fight, a.me, a.foe, {"state": 55}, -1, 0)
		FightTriggers.flush(a.fight)), ["EON55"])
	eq(_which(a, a.foe, ["EOFF55", "EOFF56"], func() -> void:
		FightEffects.add_state(a.fight, a.me, a.foe, {"state": 55}, -1, 0)
		FightEffects.remove_state(a.foe, 55, a.fight)
		FightTriggers.flush(a.fight)), ["EOFF55"])
	eq(_which(a, a.foe, ["ION", "IOFF", "EON250"], func() -> void:
		FightEffects.add_state(a.fight, a.me, a.foe, {"state": 250, "flags": ["invisible"]}, -1, 0)
		FightTriggers.flush(a.fight)), ["ION", "EON250"], "the invisible state (250)")
	_cleanup()


func test_kills() -> void:
	_made_up()
	var a := Arena.new()
	a.foe.hp = 50
	var power := a.me.stat("power")
	a.listen(a.me, ["K"])
	a.listen(a.me, ["EK:A"]) # an enemy dies
	a.listen(a.me, ["EK:a"]) # an ally dies: not here
	a.listen(a.friend, ["EK:A"]) # the friend's mask: an enemy of the friend
	a.listen(a.friend, ["K"]) # the friend killed no one
	a.cast(a.me, HIT, a.foe.cell)
	eq(a.foe.alive, false)
	eq(a.me.stat("power") - power, 2, "K on the killer, EK:A (an enemy died)")
	eq(a.friend.stat("power"), 1, "EK:A for the friend too, not K")
	_cleanup()


func test_the_extracted_codes() -> void:
	# spells.py keeps the codes the sim fires, with their state or mask
	SpellBook.get_spell(1040972)
	var found := {}
	for id: int in SpellBook._spells:
		for e: Dictionary in SpellBook._spells[id].get("effects", []):
			for c: String in e.get("on", []):
				for k in ["EON", "EOFF", "CC", "K", "PD", "MPA"]:
					if c.begins_with(k):
						found[k] = true
	eq(found.keys().size(), 6, str(found.keys()))


func test_swapped_and_moving_others() -> void:
	# P1.13m: MS on both fighters of a swap (swappedEntityId), PO on the author of any move (gzp.bnaa)
	_made_up()
	var a := Arena.new()
	var codes := ["M", "MS", "PO", "P"]
	eq(_which(a, a.foe, codes, func() -> void: a.cast(a.me, SWAP, a.foe.cell)), ["M", "MS"], "the swapped target")
	eq(_which(a, a.me, codes, func() -> void: a.cast(a.me, SWAP, a.foe.cell)), ["M", "MS", "PO"], "the caster swaps too")
	eq(_which(a, a.me, codes, func() -> void:
		a.foe.cell = a.at(2, 0)
		a.cast(a.me, PUSH, a.foe.cell)), ["PO"], "it pushed someone")
	eq(_which(a, a.foe, ["MS", "PO"], func() -> void:
		a.foe.cell = a.at(2, 0)
		a.cast(a.me, PUSH, a.foe.cell)), [], "a push is not a swap")
	_cleanup()


func test_stealing_ap_and_mp() -> void:
	# P1.13m: 84 / 77, the caster wins what the target lost; CAPA / CMPA on it (a stat output with isSteal)
	_made_up()
	var a := Arena.new()
	a.foe.mp = 3
	a.foe.ap = 6
	a.me.mp = 3
	a.fight._casts.clear()
	a.me.ap = 12
	a.fight.cast(a.me, THIEF, a.foe.cell, 0)
	eq([a.foe.mp, a.foe.ap, a.me.mp, a.me.ap], [1, 5, 5, 13], "2 MP and 1 AP change hands")
	eq(_which(a, a.me, ["CAPA", "CMPA", "APA", "MPA"], func() -> void: a.cast(a.me, THIEF, a.foe.cell)),
			["CAPA", "CMPA", "APA", "MPA"])
	eq(_which(a, a.foe, ["CAPA", "CMPA", "APA", "MPA"], func() -> void: a.cast(a.me, THIEF, a.foe.cell)), ["APA", "MPA"])
	_cleanup()


func test_dispel() -> void:
	# P1.13m: 132 removes the buffs with dispellable 1 (2 only at death, 3 never); DIS on the target
	_made_up()
	var a := Arena.new()
	for d in [1, 2, 3]:
		FightEffects.apply(a.fight, a.me, a.foe, {"kind": "stat", "stat": "wisdom", "min": d, "max": d, "duration": 3, "dispellable": d},
				a.foe.cell, 0)
	FightEffects.apply(a.fight, a.me, a.foe, {"kind": "stat", "stat": "chance", "min": 5, "max": 5, "duration": 3},
			a.foe.cell, 0)
	eq(a.foe.stat("wisdom"), 6)
	a.cast(a.me, DISPEL, a.foe.cell)
	eq([a.foe.stat("wisdom"), a.foe.stat("chance")], [5, 0], "only the dispellable ones go")
	eq(_which(a, a.foe, ["DIS"], func() -> void: a.cast(a.me, DISPEL, a.foe.cell)), ["DIS"])
	_cleanup()


func test_weapon_and_critical_hits() -> void:
	# P1.13m, gzp.bmzx / bnaa / bmzz: DCAC / CDCAC for a weapon (DS / CDS for spells), DCCB* for a critical
	_made_up()
	var a := Arena.new()
	var weapon := func() -> void: a.cast(a.me, Equipment.WEAPON_SPELL, a.foe.cell)
	eq(_which(a, a.foe, ["D", "DE", "DCAC", "DS"], weapon), ["D", "DE", "DCAC"], "a weapon's hit")
	eq(_which(a, a.me, ["CD", "CDCAC", "CDS"], weapon), ["CD", "CDCAC"])
	eq(_which(a, a.foe, ["DCAC", "DS"], func() -> void: a.cast(a.me, HIT, a.foe.cell)), ["DS"])
	eq(_which(a, a.foe, ["DCCBE", "DCCBA"], func() -> void: a.cast(a.me, CRIT, a.foe.cell)), ["DCCBE"], "a critical hit")
	eq(_which(a, a.friend, ["DCCBE", "DCCBA"], func() -> void: a.cast(a.me, CRIT, a.friend.cell)), ["DCCBA"])
	eq(_which(a, a.me, ["CDCCBE", "CDCCBA"], func() -> void: a.cast(a.me, CRIT, a.foe.cell)), ["CDCCBE"])
	eq(_which(a, a.foe, ["DCCBE"], func() -> void: a.cast(a.me, HIT, a.foe.cell)), [])
	# a weapon's kill: KWW
	a.foe.hp = 10
	a.listen(a.me, ["KWW"])
	a.listen(a.me, ["KWS"])
	var power := a.me.stat("power")
	a.fight._casts.clear()
	a.me.ap = 12
	a.fight.cast(a.me, Equipment.WEAPON_SPELL, a.foe.cell, 0)
	eq([a.foe.alive, a.me.stat("power") - power], [false, 1], "KWW, not KWS")
	_cleanup()


func test_life_changes() -> void:
	# P1.13m, gzp.bmzy: V / VA for any life output (hit, push damage, heal, shield), PPD with PD
	_made_up()
	var a := Arena.new()
	var codes := ["V", "VA", "VM", "VE"]
	eq(_which(a, a.foe, codes, func() -> void: a.cast(a.me, HIT, a.foe.cell)), ["V", "VA"], "a hit (no erosion: no VM / VE)")
	eq(_which(a, a.friend, codes, func() -> void:
		a.friend.hp = 50
		a.cast(a.me, HEAL, a.friend.cell)), ["V", "VA"], "a heal and a shield")
	eq(_which(a, a.foe, ["PD", "PPD", "V", "D"], func() -> void:
		a.foe.cell = a.at(1, 0)
		a.friend.cell = a.at(3, 0)
		a.cast(a.me, PUSH, a.foe.cell)), ["PD", "PPD", "V"], "push damage")
	_cleanup()


func test_making_invisible() -> void:
	# P1.13m, gzp.bnaa: CION / CIOFF on who makes someone invisible / visible
	_made_up()
	var a := Arena.new()
	eq(_which(a, a.me, ["CION", "ION"], func() -> void:
		FightEffects.add_state(a.fight, a.me, a.foe, {"state": 250, "flags": ["invisible"]}, -1, 0)
		FightTriggers.flush(a.fight)), ["CION"])
	eq(_which(a, a.me, ["CIOFF"], func() -> void:
		FightEffects.add_state(a.fight, a.me, a.foe, {"state": 250, "flags": ["invisible"]}, -1, 0)
		FightEffects.apply(a.fight, a.me, a.foe, {"kind": "reveal"}, a.foe.cell, 0)
		FightTriggers.flush(a.fight)), ["CIOFF"])
	_cleanup()


func test_server_codes_read_from_descriptions() -> void:
	# P1.13p: XD / XPD / XDM = D / PD / DM, TP = moved, CPD = moves a fighter, CMPAS / CAPAS = steals,
	# DTB = poison damage (APPROX(P1.13p): meanings deduced from the spells' i18n descriptions)
	_made_up()
	var a := Arena.new()
	a.foe.cell = a.at(1, 0) # melee
	eq(_which(a, a.foe, ["XD", "XDM", "XPD", "D"], func() -> void: a.cast(a.me, HIT, a.foe.cell)),
			["XD", "XDM", "D"], "XD / XDM: a hit, in melee")
	a.foe.cell = a.at(5, 0)
	eq(_which(a, a.foe, ["XD", "XDM"], func() -> void: a.cast(a.me, HIT, a.foe.cell)), ["XD"], "not XDM at range")
	_cleanup()


func test_server_push_and_moves() -> void:
	_made_up()
	var a := Arena.new()
	var wall := func() -> void:
		a.foe.cell = a.at(1, 0)
		a.friend.cell = a.at(3, 0)
		a.cast(a.me, PUSH, a.foe.cell)
	eq(_which(a, a.foe, ["XPD", "XD", "TP"], wall), ["XPD", "TP"], "push damage is XPD, not XD; TP: moved")
	eq(_which(a, a.foe, ["TP"], func() -> void:
		a.foe.cell = a.at(5, 0)
		a.cast(a.me, HOOK, a.foe.cell)), ["TP"], "attracted")
	eq(_which(a, a.foe, ["TP"], func() -> void: a.cast(a.me, HIT, a.foe.cell)), [], "a plain hit does not move")
	eq(_which(a, a.me, ["CPD", "TP"], func() -> void:
		a.foe.cell = a.at(5, 0)
		a.cast(a.me, HOOK, a.foe.cell)), ["CPD"], "the author of a move, not the one moved")
	_cleanup()


func test_server_steals_and_poison() -> void:
	_made_up()
	var a := Arena.new()
	a.foe.mp = 3
	a.foe.ap = 6
	eq(_which(a, a.me, ["CAPAS", "CMPAS"], func() -> void: a.cast(a.me, THIEF, a.foe.cell)), ["CAPAS", "CMPAS"])
	var b := FightEffects._buff(a.fight, a.me, HIT, "poison", 2)
	b.effect = {"kind": "damage", "element": "water", "min": 3, "max": 3}
	eq(_which(a, a.foe, ["DTB", "XDTB", "DTE", "DS"], func() -> void:
		FightEffects.poison(a.fight, a.foe, b)
		FightTriggers.flush(a.fight)), ["DTB", "XDTB"], "a poison ticks at the start of the turn")
	_cleanup()


func test_server_codes_are_known() -> void:
	for c: String in ["XD", "XPD", "XDM", "XDTB", "TP", "CPD", "CMPAS", "CAPAS", "DTB", "DTE"]:
		check(FightTriggers.ALIASES.has(c) or c in ["DTB", "DTE"], c)
