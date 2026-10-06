## Runes, bombs and their walls (roadmap P1.13d): effects 2022 / 2023 (Steamer), 1009 and
## spellbombs / spellbombwalls (Roublard), monster filters of the target masks, final damage.
extends TestCase

const BOMB := 1041922 # Roublard "Explobombe" grade 1: summons an Explobombe (monster 3112)
const DETONATOR := 1041886 # Roublard "Détonateur" grade 1: 1009 on its own bomb
const FLAME := 1042410 # Steamer "Lance-flamme" grade 1: a fire rune under the target
const RUNIFY := 1042414 # Steamer "Runification" grade 1: 2023 on the target
const EXPLOBOMB := 3112


func _init() -> void:
	SpellBook.use_file("")


class Arena:
	var fight: Fight
	var me := Fighter.new()
	var foe := Fighter.new()
	var events: Array = []

	func _init(spells: Array, foe_at: Vector2i) -> void:
		fight = Fight.new(1, MapData.new(), 7, func(ev: Dictionary) -> void: events.append(ev))
		me.id = 1
		me.cell = 300
		me.level = 10
		me.hp = 200
		me.max_hp = 200
		me.ap = 12
		me.max_ap = 12
		me.mp = 6
		me.max_mp = 6
		me.spells = spells
		me.stats = {"agility": 1000} # plays first
		foe.id = 2
		foe.team = 1
		foe.ai = true
		foe.cell = at(foe_at.x, foe_at.y)
		foe.hp = 500
		foe.max_hp = 500
		foe.ap = 0
		foe.max_ap = 0
		foe.mp = 0
		foe.max_mp = 0
		fight.add_fighter(me)
		fight.add_fighter(foe)
		fight.start_placement(0)
		fight.begin(0)

	func at(dx: int, dy: int) -> int:
		return MapGeometry.from_iso(MapGeometry.to_iso(300) + Vector2i(dx, dy))

	func bombs() -> Array:
		return fight.fighters.values().filter(func(f: Fighter) -> bool: return f.monster == EXPLOBOMB)

	func effects(kind: String) -> Array:
		var out: Array = []
		for ev: Dictionary in events:
			for key: String in ["effects", "triggered"]:
				for e: Dictionary in ev.get(key, []):
					if e["kind"] == kind:
						out.append(e)
		return out

	func marks(kind: String) -> Array:
		return fight.marks.filter(func(m: Dictionary) -> bool: return m["kind"] == kind)


func test_the_extracted_bombs_and_runes() -> void:
	var data := SpellBook.summon(EXPLOBOMB)
	eq((data["explode"] as Array).size(), 7, "spellbombs.explodSpellId at each grade")
	eq(SpellBook.get_spell(int(data["explode"][0]))["name"], "Explosion Roublarde")
	var wall: Dictionary = data["wall"]
	eq([wall["color"], wall["linear"], int(wall["min"]), int(wall["max"])], ["#ff0000", true, 1, 7], "spellbombwalls 2")
	eq(SpellBook.get_spell(int(wall["spells"][0]))["name"], "Mur de Feu")
	check(not SpellBook.get_spell(DETONATOR).has("partial"))
	var rune: Dictionary = SpellBook.get_spell(FLAME)["effects"][0]
	eq([rune["kind"], int(rune["duration"])], ["rune", 2])
	check(SpellBook.get_spell(RUNIFY)["effects"].any(func(e: Dictionary) -> bool: return e["kind"] == "runes"))


func test_a_rune_goes_off_under_its_target() -> void:
	var a := Arena.new([FLAME, RUNIFY], Vector2i(2, 0))
	eq(a.fight.cast(a.me, FLAME, a.foe.cell, 0), "")
	eq(a.marks("rune").size(), 1, "a rune under the target (placed twice: the second replaces the first)")
	eq(int(a.marks("rune")[0]["cell"]), a.foe.cell)
	var hp := a.foe.hp
	eq(a.fight.cast(a.me, RUNIFY, a.foe.cell, 0), "")
	eq(a.marks("rune").size(), 0, "set off, gone")
	check(a.foe.hp < hp, "its spell steals fire life (Runification's states on the caster)")
	eq(a.effects("mark_remove").size(), 2, "the replaced one and the one set off")


func test_a_rune_only_goes_off_with_2023() -> void:
	var a := Arena.new([FLAME], Vector2i(2, 0))
	a.fight.cast(a.me, FLAME, a.foe.cell, 0)
	a.fight.end_turn(0)
	eq(a.marks("rune").size(), 1, "the target standing on it does nothing")
	a.fight.end_turn(0)
	a.fight.end_turn(0)
	a.fight.end_turn(0) # two of my turns: its duration
	eq(a.marks("rune").size(), 0)


func test_a_bomb_explodes() -> void:
	var a := Arena.new([BOMB, DETONATOR], Vector2i(4, 0))
	eq(a.fight.cast(a.me, BOMB, a.at(3, 0), 0), "")
	eq(a.bombs().size(), 1)
	var bomb: Fighter = a.bombs()[0]
	check(not bomb.plays, "a bomb has no turns (monsters.m_flags)")
	var hp := a.foe.hp
	eq(a.fight.cast(a.me, DETONATOR, bomb.cell, 0), "")
	eq(a.effects("explode").size(), 1)
	check(not bomb.alive, "its explosion kills it (141 on the caster)")
	check(a.foe.hp < hp, "and hurts the enemy next to it (circle 2)")
	eq(a.me.hp, a.me.max_hp, "not its caster, 3 cells away")


func test_bombs_explode_in_a_chain_once() -> void:
	var a := Arena.new([BOMB, DETONATOR], Vector2i(0, -5))
	a.fight.cast(a.me, BOMB, a.at(2, 0), 0)
	a.fight.cast(a.me, BOMB, a.at(2, 2), 0)
	eq(a.bombs().size(), 2)
	var first: Fighter = a.bombs()[0]
	var second: Fighter = a.bombs()[1]
	var hp := second.hp
	eq(a.fight.cast(a.me, DETONATOR, first.cell, 0), "")
	eq(a.effects("explode").size(), 2, "the second one is in the first one's circle 2")
	check(not first.alive and not second.alive)
	eq(second.hp, 0)
	check(hp > 0)


func test_the_explosion_spares_the_allied_bombs() -> void:
	# the second damage effect: "a,f3112,f3113,f3114,f5161,e92" (not a bomb)
	var e: Dictionary = SpellBook.get_spell(int(SpellBook.summon(EXPLOBOMB)["explode"][0]))["effects"][1]
	var a := Arena.new([BOMB], Vector2i(0, -5))
	a.fight.cast(a.me, BOMB, a.at(2, 0), 0)
	var bomb: Fighter = a.bombs()[0]
	check(not FightEffects.cond_ok(e, bomb, bomb), "a bomb")
	check(FightEffects.cond_ok(e, bomb, a.me), "its Roublard")


func test_a_wall_links_two_aligned_bombs() -> void:
	var a := Arena.new([BOMB], Vector2i(0, -5))
	eq(a.fight.cast(a.me, BOMB, a.at(-1, 2), 0), "")
	eq(a.marks("wall").size(), 0)
	eq(a.fight.cast(a.me, BOMB, a.at(2, 2), 0), "")
	eq(a.marks("wall").size(), 1)
	var wall: Dictionary = a.marks("wall")[0]
	eq(wall["cells"], [a.at(0, 2), a.at(1, 2)], "the cells between them")
	eq(wall["color"], "#ff0000")
	eq(a.effects("mark_add").filter(func(e: Dictionary) -> bool: return e["mark"]["kind"] == "wall").size(), 1)
	# an enemy starting its turn in it
	a.foe.cell = a.at(1, 2)
	var hp := a.foe.hp
	a.fight.end_turn(0)
	check(a.foe.hp < hp, "Mur de Feu")


func test_a_wall_goes_with_its_bomb() -> void:
	var a := Arena.new([BOMB, DETONATOR], Vector2i(0, -5))
	a.fight.cast(a.me, BOMB, a.at(-1, 2), 0)
	a.fight.cast(a.me, BOMB, a.at(3, 2), 0)
	eq(a.marks("wall").size(), 1)
	eq(a.fight.cast(a.me, DETONATOR, a.at(3, 2), 0), "")
	eq(a.marks("wall").size(), 0)


func test_no_wall_for_neighbours_or_out_of_line() -> void:
	var a := Arena.new([BOMB], Vector2i(0, -5))
	a.fight.cast(a.me, BOMB, a.at(1, 0), 0)
	a.fight.cast(a.me, BOMB, a.at(2, 1), 0)
	eq(a.marks("wall").size(), 0)


func test_final_damage() -> void:
	var a := Arena.new([], Vector2i(3, 0))
	var base := int(FightEffects.damage(a.fight, a.me, a.foe, "neutral", 100)[0]["amount"])
	var b := Buff.new()
	b.kind = "stat"
	b.stat = "final_damage"
	b.value = 50
	b.turns = 1
	a.me.buffs.append(b)
	eq(int(FightEffects.damage(a.fight, a.me, a.foe, "neutral", 100)[0]["amount"]), base * 150 / 100)
