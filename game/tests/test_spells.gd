## Spell book of every class (roadmap P1.03): grades unlocked by level
## (spelllevels.minPlayerLevel), Dofus 3 variant pairs (spellvariants), the
## customisable spell bar. Real data (data/spells.json), driven through LocalBackend.
extends TestCase

const PAUME := 12781 # Pandawa, pair with Picole... (spellvariants 201: 12781 / 12815)
const PAUME_VARIANT := 12815


func _init() -> void:
	SpellBook.use_file("") # the real game data (other suites switch to test fixtures)
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()


static func _world() -> WorldSource:
	return WorldSource.from_dicts(
		{"id": "book", "name": "Book", "start_map": 1, "start_cell": 300},
		[{"id": 1, "coords": [0, 0], "neighbors": {}}])


static func _server() -> LocalServer:
	var s := LocalServer.new()
	s.sources["book"] = _world()
	return s


## Plays `name` (created with `breed` if needed) at `level`: the save is edited
## between two connections, like an admin would.
static func _play(server: LocalServer, name: String, level := 1, breed := 12) -> Array:
	var b := LocalBackend.new()
	b.server = server
	var events: Array = []
	b.event.connect(func(ev: Dictionary) -> void: events.append(ev))
	b.send(Protocol.hello("book"))
	b.send(Protocol.create_character(name, breed))
	b.poll(0.0)
	var saved := server.persistence.load_character("book", name)
	saved["level"] = level
	server.persistence.save_character("book", name, saved)
	events.clear()
	b.send(Protocol.select_character(name))
	b.poll(0.0)
	return [b, events]


static func _last_stats(events: Array) -> Dictionary:
	var st := events.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.PLAYER_STATS)
	return st[-1]["stats"] if not st.is_empty() else {}


static func _ints(a: Array) -> Array:
	return a.map(func(v: Variant) -> int: return int(v))


func test_grades_follow_the_player_level() -> void:
	var g := SpellBook.grade_ids(PAUME)
	eq(g, [1040644, 1061177, 1061178], "LEVEL_SPELL + spelllevels.id, grade order")
	eq(SpellBook.grade_for(PAUME, 1), g[0])
	eq(SpellBook.grade_for(PAUME, 66), g[0])
	eq(SpellBook.grade_for(PAUME, 67), g[1], "spelllevels.minPlayerLevel 67")
	eq(SpellBook.grade_for(PAUME, 200), g[2])
	eq(SpellBook.grade_for(PAUME_VARIANT, 99), 0, "the variant is learnt at 100")
	eq(SpellBook.unlock_level(PAUME_VARIANT), 100)
	eq(int(SpellBook.get_spell(g[1])["spell"]), PAUME)
	eq(int(SpellBook.get_spell(g[1])["grade"]), 2)


func test_spells_unlock_at_their_level_for_three_classes() -> void:
	# Iop, Cra, Pandawa: 22 pairs each; 4 spells at level 1, 14 at 50, all 22 at 200
	for breed: int in [8, 9, 12]:
		eq(SpellBook.pairs(breed).size(), 22, "breed %d pairs" % breed)
		eq(SpellBook.known_ids(breed, 1).size(), 4, "breed %d level 1" % breed)
		eq(SpellBook.known_ids(breed, 50).size(), 14, "breed %d level 50" % breed)
		eq(SpellBook.known_ids(breed, 200).size(), 22, "breed %d level 200" % breed)
		for id: int in SpellBook.known_ids(breed, 50):
			var s := SpellBook.get_spell(id)
			eq(int(s["breed"]), breed)
			check(int(s["level"]) <= 50, "grade learnt at %d" % int(s["level"]))
	var first := SpellBook.chosen_spells(12, 1, [])
	eq(first, [12803, PAUME, 12782, 12791], "the spell book order (breeds.breedSpellsId)")


func test_every_class_can_be_created_and_plays_its_spells() -> void:
	var server := _server()
	var r := _play(server, "Goultard", 1, 8)
	var st := _last_stats(r[1])
	eq(int(st["breed"]), 8)
	var spells := _ints(st["spells"])
	eq(spells.size(), 4)
	for id: int in spells:
		eq(int(SpellBook.get_spell(id)["breed"]), 8, "Iop spells")
	var b: LocalBackend = r[0]
	b.send(Protocol.hello("book"))
	b.poll(0.0)
	var ev := (r[1] as Array).filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.CHARACTERS)
	var breeds := _ints(ev[-1]["breeds"])
	eq(breeds.size(), 19, "every class of the breeds table")
	check(not breeds.has(19), "spellvariants breed 19 has no class")


func test_choose_variant() -> void:
	var server := _server()
	var r := _play(server, "Bob", 120)
	var b: LocalBackend = r[0]
	var events: Array = r[1]
	var st := _last_stats(events)
	var slot := _ints(st["bar"]).find(SpellBook.grade_for(PAUME, 120))
	check(slot >= 0, "Paume in the bar")
	b.send(Protocol.choose_variant(PAUME_VARIANT))
	b.poll(0.0)
	st = _last_stats(events)
	var spells := _ints(st["spells"])
	check(spells.has(SpellBook.grade_for(PAUME_VARIANT, 120)), "the variant is used")
	check(not spells.has(SpellBook.grade_for(PAUME, 120)), "instead of its pair")
	eq(_ints(st["bar"])[slot], SpellBook.grade_for(PAUME_VARIANT, 120), "in the same slot")
	eq(spells.size(), 22, "one spell per pair")
	events.clear()
	b.send(Protocol.choose_variant(14309)) # learnt at 190
	b.send(Protocol.choose_variant(13106)) # an Iop spell
	b.poll(0.0)
	eq(events.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.ERROR).map(func(e: Dictionary) -> String: return e["code"]),
			[Protocol.E_SPELL_LOCKED, Protocol.E_UNKNOWN_SPELL])
	b.send(Protocol.choose_variant(PAUME)) # back
	b.poll(0.0)
	check(_ints(_last_stats(events)["spells"]).has(SpellBook.grade_for(PAUME, 120)))
	b.send(Protocol.choose_variant(PAUME_VARIANT))
	b.poll(0.0)
	b.close()
	var again := _play(server, "Bob", 120)
	check(_ints(_last_stats(again[1])["spells"]).has(SpellBook.grade_for(PAUME_VARIANT, 120)), "the choice is saved")


func test_the_spell_bar_persists() -> void:
	var server := _server()
	var r := _play(server, "Bob", 10)
	var b: LocalBackend = r[0]
	var events: Array = r[1]
	var bar := _ints(_last_stats(events)["bar"])
	eq(bar.size(), SpellBook.BAR_SLOTS)
	eq(bar.slice(0, 6), SpellBook.known_ids(12, 10), "learnt spells fill the bar in spell book order")
	b.send(Protocol.move_spell(12782, 12))
	b.poll(0.0)
	bar = _ints(_last_stats(events)["bar"])
	eq(bar[12], SpellBook.grade_for(12782, 10))
	eq(bar[2], 0, "its old slot is now empty")
	b.send(Protocol.move_spell(PAUME, 12)) # swap
	b.poll(0.0)
	bar = _ints(_last_stats(events)["bar"])
	eq([bar[1], bar[12]], [SpellBook.grade_for(12782, 10), SpellBook.grade_for(PAUME, 10)], "the two spells swap")
	events.clear()
	b.send(Protocol.move_spell(PAUME, SpellBook.BAR_SLOTS))
	b.send(Protocol.move_spell(PAUME_VARIANT, 3))
	b.poll(0.0)
	eq(events.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.ERROR).map(func(e: Dictionary) -> String: return e["code"]),
			[Protocol.E_BAD_SLOT, Protocol.E_UNKNOWN_SPELL])
	b.close()
	var again := _play(server, "Bob", 20)
	bar = _ints(_last_stats(again[1])["bar"])
	eq([bar[1], bar[12]], [SpellBook.grade_for(12782, 20), SpellBook.grade_for(PAUME, 20)], "saved")
	var learnt := SpellBook.known_ids(12, 20).filter(func(id: int) -> bool: return not SpellBook.known_ids(12, 10).has(id))
	check(not learnt.is_empty())
	for id: int in learnt:
		check(bar.has(id), "a spell learnt since takes a free slot")


func test_a_spell_without_simulated_effects_cannot_be_cast() -> void:
	var f := Fight.new(1, MapData.new(), 7, func(_ev: Dictionary) -> void: pass)
	var me := Fighter.new()
	me.id = 1
	var none := SpellBook.all_ids().filter(func(id: int) -> bool: return (SpellBook.get_spell(id)["effects"] as Array).is_empty())
	check(not none.is_empty(), "some class spells only have effects not simulated yet")
	me.spells = [none[0]]
	eq(f.spell_block(me, none[0]), Protocol.E_SPELL_NOT_SIMULATED)
