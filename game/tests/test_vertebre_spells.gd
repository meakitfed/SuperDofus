## The Vertebre world's own spells (worlds/vertebre/data/spells.json, WorldOverlay): every class and monster grade
## against the same contracts as the Dofus ones (SpellCheck, SpellSmoke), plus the shape of the class book.
extends TestCase

const WORLD := "vertebre"


func _enter() -> bool:
	if not ContentSource.dir_exists("worlds/%s/data" % WORLD):
		skip("world %s not generated" % WORLD)
		return false
	ContentSource.use_world(WORLD)
	return true


func _own_ids() -> Array:
	var own: Variant = ContentSource.read_json("worlds/%s/data/spells.json" % WORLD)
	var ids: Array = []
	for s: Dictionary in (own as Dictionary).get("spells", []):
		ids.append(int(s["id"]))
	ids.sort()
	return ids


func test_data_and_contracts() -> void:
	if not _enter():
		return
	for id: int in _own_ids():
		if not sub(SpellIndex.label(id)):
			continue
		var spell := SpellBook.get_spell(id)
		check(not spell.is_empty(), "not loaded by SpellBook")
		for msg: String in SpellCheck.data_errors(spell):
			fail(msg)
		for msg: String in SpellCheck.grade(id):
			fail(msg)
	sub("")
	ContentSource.use_dev()


func test_whole_spells() -> void:
	if not _enter():
		return
	for id: int in _own_ids():
		if sub(SpellIndex.label(id)):
			for msg: String in SpellSmoke.grade(id):
				fail(msg)
	sub("")
	ContentSource.use_dev()


func test_class_books() -> void:
	if not _enter():
		return
	for breed: int in [901, 902, 903, 904, 905]:
		var pairs := SpellBook.pairs(breed)
		eq(pairs.size(), 8, "spells of class %d" % breed)
		for p: Array in pairs:
			check(SpellBook.unlock_level(int(p[0])) <= 40, "class %d spell %d unlocks too late" % [breed, int(p[0])])
			check(not SpellBook.get_spell(SpellBook.grade_for(int(p[0]), 60)).is_empty(), "class %d spell %d has no grade at level 60" % [breed, int(p[0])])
		check(SpellBook.unlock_level(int(pairs[0][0])) == 1, "class %d starts with a spell at level 1" % breed)
	check(CharacterRoster.playable_breeds().has(901), "class 901 is playable")
	ContentSource.use_dev()
