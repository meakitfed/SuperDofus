## Target masks (roadmap P1.13h): TargetMask decides who an effect touches as the client's
## native code does (class gtz: sides blqf, conditions blqe, alternatives blqd).
extends TestCase

const CRI_DU_CORBAC := 1082226 # Osamodas: steal "A", heal "g", +1 MP "g,C"
const FRAPPE_DE_XELOR := 1041556 # Xélor, grade 1: sym_caster "a,A", casts Téléfrag "a,A,T" (all the map)
const TELEFRAG := 251


func _init() -> void:
	SpellBook.use_file("")


## me (team 0, a Sram), an allied character, my summon, a static allied summon, a foe monster.
class Arena:
	var fight: Fight
	var me := Fighter.new()
	var ally := Fighter.new()
	var pet := Fighter.new()
	var bomb := Fighter.new()
	var foe := Fighter.new()
	var events: Array = []

	func _init() -> void:
		fight = Fight.new(1, MapData.new(), 7, func(ev: Dictionary) -> void: events.append(ev))
		_fighter(me, 1, 0, 300)
		me.breed = 4
		me.ap = 12
		me.max_ap = 12
		me.stats = {"agility": 1000}
		me.spells = [CRI_DU_CORBAC]
		_fighter(ally, 2, 0, at(0, -1))
		ally.breed = 8
		_fighter(foe, 3, 1, at(1, 0))
		foe.monster = 31
		foe.ai = true
		_fighter(pet, -101, 0, at(-1, 0))
		pet.monster = 8070
		pet.summoner = 1
		pet.ai = true
		_fighter(bomb, -102, 0, at(0, 1))
		bomb.monster = 3112
		bomb.summoner = 1
		bomb.ai = true
		bomb.plays = false
		fight.start_placement(0)
		fight.begin(0)

	func _fighter(f: Fighter, id: int, team: int, cell: int) -> void:
		f.id = id
		f.team = team
		f.cell = cell
		f.hp = 100
		f.max_hp = 200
		fight.add_fighter(f)

	func at(dx: int, dy: int) -> int:
		return MapGeometry.from_iso(MapGeometry.to_iso(300) + Vector2i(dx, dy))

	## the fighters of this arena `mask` touches when `me` casts
	func touched(mask: String, caster: Fighter = null) -> Array:
		var c := caster if caster != null else me
		return [me, ally, pet, bomb, foe].filter(func(t: Fighter) -> bool:
			return TargetMask.affects(fight, c, t, {"mask": mask})).map(func(t: Fighter) -> int: return t.id)


func test_the_caster_only_with_c_or_a() -> void:
	var a := Arena.new()
	eq(a.touched("C"), [1])
	eq(a.touched("a"), [1, 2, -101, -102], "a: the allies, the caster too (gtz.blqf)")
	eq(a.touched("g"), [2, -101, -102], "g: the allies but not the caster")
	eq(a.touched("A"), [3])
	eq(a.touched("E12"), [], "no side letter: no one")
	eq(a.touched(""), [1, 2, -101, -102, 3], "an empty mask: everyone (gtz.blqi)")


func test_kinds_of_fighters() -> void:
	var a := Arena.new()
	eq(a.touched("h"), [2], "h: allied characters, not summoned (not the caster: C / c / a only)")
	eq(a.touched("j"), [-101, -102], "j: allied summons")
	eq(a.touched("i"), [-101], "i: summons that are not static")
	eq(a.touched("s"), [-102], "s: static summons")
	eq(a.touched("M"), [3], "M: enemy monsters")
	eq(a.touched("m"), [], "m: allied monsters (not summoned)")
	eq(a.touched("d,D"), [], "companions: none here")


func test_conditions_on_the_target_or_the_caster() -> void:
	var a := Arena.new()
	FightEffects.add_state(a.fight, a.me, a.ally, {"state": 55}, -1, 0)
	eq(a.touched("a,A,E55"), [2])
	eq(a.touched("a,A,e55"), [1, -101, -102, 3])
	eq(a.touched("a,A,*E55"), [], "*: on the caster")
	eq(a.touched("a,A,F31"), [3])
	eq(a.touched("a,A,F31,F8070"), [-101, 3], "several F: alternatives (gtz.blqd)")
	eq(a.touched("a,A,f31,f8070"), [1, 2, -102], "several f: all must hold")
	eq(a.touched("a,B4,B8"), [1, 2], "B<n>: characters of breed n, alternatives")
	eq(a.touched("a,b4"), [2, -101, -102])


func test_life_ap_mp_shield_conditions() -> void:
	var a := Arena.new()
	a.ally.hp = 50 # 25 %
	eq(a.touched("h,V30"), [], "V30: above 30 % of its life")
	eq(a.touched("h,v30"), [2], "v30: at most 30 %")
	a.ally.ap = 2
	eq(a.touched("h,ap3"), [2], "ap<n> / AP<n>: never checked (gtz.blqc lets no A / a / M / m through)")
	eq(a.touched("h,PB"), [], "PB: has a shield")
	eq(a.touched("h,pb"), [2])


func test_summoning_family() -> void:
	var a := Arena.new()
	eq(a.touched("a,A,P"), [1, -101, -102], "P: the caster, its summons")
	eq(a.touched("a,A,P", a.pet), [1, -101, -102], "a summon's P: its summoner and its siblings")
	eq(a.touched("a,A,p"), [2, 3])


func test_c_touches_the_caster_outside_the_area() -> void:
	var a := Arena.new()
	# Cri du Corbac on the foe: steal "A", heal "g" (not me), +1 MP "g,C" (me, outside the point area)
	eq(a.fight.cast(a.me, CRI_DU_CORBAC, a.foe.cell, 0), "")
	var mp: Array = a.events.filter(func(ev: Dictionary) -> bool: return ev["t"] == Protocol.SPELL_CAST)[-1]["effects"] \
			.filter(func(e: Dictionary) -> bool: return e["kind"] == "mp")
	eq(mp.map(func(e: Dictionary) -> int: return int(e["target"])), [1])


func test_the_extracted_effects_keep_their_mask() -> void:
	var e: Array = SpellBook.get_spell(CRI_DU_CORBAC)["effects"]
	eq(e.map(func(x: Dictionary) -> String: return str(x.get("mask", ""))), ["A", "g", "g,C"])
	eq(e.map(func(x: Dictionary) -> String: return str(x["target"])), ["enemies", "allies", "allies"])


## P1.13k: W moved in this cast (gvs.bmdi), T telefragged in it (P1.13n), U summoned in it
## (gvs.bmdp), K thrown by the caster in it; the list starts afresh with each cast (Fight.cast_log).
func test_moved_summoned_or_thrown_in_this_cast() -> void:
	var a := Arena.new()
	eq(a.touched("a,A,W"), [], "nobody moved yet")
	a.fight.log_cast(a.foe, "moved")
	eq(a.touched("a,A,W"), [3])
	eq(a.touched("a,A,T"), [], "T: moved is not enough, a Telefrag (P1.13n)")
	a.fight.log_cast(a.foe, "telefrag")
	eq(a.touched("a,A,T"), [3])
	eq(a.touched("a,A,U"), [])
	a.fight.log_cast(a.pet, "summoned")
	eq(a.touched("a,A,U"), [-101])
	eq(a.touched("A,K"), [], "moved, not thrown by me")
	a.fight.log_cast(a.foe, "moved", a.ally.id)
	eq(a.touched("A,K"), [], "thrown by another")
	eq(a.touched("A,K", a.ally), [3])
	var spell := {"id": 0, "effects": [{"kind": "damage", "element": "neutral", "min": 1, "max": 1, "target": "all", "mask": "a,A,W", "area": {"shape": "circle", "size": 3}}]}
	var hits := FightEffects.apply_spell(a.fight, a.me, spell, a.foe.cell, false).filter(
			func(e: Dictionary) -> bool: return e["kind"] == "damage")
	eq(hits, [], "a new cast starts an empty list")
	spell["effects"].push_front({"kind": "push", "min": 1, "max": 1, "target": "all", "mask": "A"})
	hits = FightEffects.apply_spell(a.fight, a.me, spell, a.foe.cell, false).filter(
			func(e: Dictionary) -> bool: return e["kind"] == "damage")
	eq(hits.map(func(e: Dictionary) -> int: return int(e["target"])), [3], "pushed by this cast: W")


## gyn.bmqg: a static creature is one whose monsters.canPlay is false (Fighter.plays).
func test_static_creatures() -> void:
	var a := Arena.new()
	eq(a.touched("s"), [-102], "s: the allied summon that does not play")
	eq(a.touched("i"), [-101])
	eq(a.touched("M"), [3], "a monster that plays")
	a.foe.plays = false
	eq(a.touched("M"), [], "m / M: not static")


## T on a real spell: Frappe de Xélor (grade 1) teleports its target to the other side of the
## caster, then casts Téléfrag (state 251 on an enemy, 244 on an ally) on the fighters it swapped
## (mask a,A,T): a teleport onto a free cell is no Telefrag (P1.13n, see test_telefrag.gd).
func test_frappe_de_xelor_only_telefrags_what_it_swapped() -> void:
	var a := Arena.new()
	a.me.breed = 5
	var frappe := SpellBook.get_spell(FRAPPE_DE_XELOR)
	a.pet.cell = a.at(-3, 3)
	FightEffects.apply_spell(a.fight, a.me, frappe, a.foe.cell, false)
	eq(a.foe.cell, a.at(-1, 0), "the other side is free: teleported")
	check(not a.foe.has_state(TELEFRAG), "moved, not swapped: no T")
	FightEffects.apply_spell(a.fight, a.me, frappe, a.foe.cell, false)
	eq(a.foe.cell, a.at(1, 0), "back again")
	a.pet.cell = a.at(-1, 0)
	FightEffects.apply_spell(a.fight, a.me, frappe, a.foe.cell, false)
	eq([a.foe.cell, a.pet.cell], [a.at(-1, 0), a.at(1, 0)], "the other side is taken (my summon): swapped")
	check(a.foe.has_state(TELEFRAG), "swapped: T")
	check(a.pet.has_state(244), "my summon too (Téléfrag, ally side)")
	check(not a.ally.has_state(TELEFRAG) and not a.ally.has_state(244))
