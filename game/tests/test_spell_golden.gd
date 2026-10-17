## Golden of the class spells (H.02, tests/spells/spell_golden.gd): each spell (spells.id) of each class
## cast in the standard duel, compared with tests/golden/spells/classe_<NN>.json. One sub-test per
## spell; TEST_CASE=<name or spells.id> runs only those. To accept an intended change:
##   GOLDEN_UPDATE=1 (or `-- --update-golden`), then read the diff of the files before committing.
extends TestCase


func _init() -> void:
	SpellBook.use_file("")


func test_golden_class_spells() -> void:
	var update := SpellGolden.updating()
	var filtered := _case_filter != ""
	for breed: int in SpellGolden.breeds():
		var golden := SpellGolden.read(breed)
		var spells := SpellGolden.spells_of(breed)
		var changed := false
		for sid: int in spells:
			var first: Dictionary = SpellBook.get_spell(spells[sid][0])
			if not sub("%s (%d)" % [first.get("name", "?"), sid]):
				continue
			var actual := SpellGolden.spell(sid, spells[sid])
			if update:
				golden[str(sid)] = actual
				changed = true
			elif not golden.has(str(sid)):
				fail("no golden for this spell: GOLDEN_UPDATE=1 to write it")
			else:
				for msg: String in SpellGolden.diff(golden[str(sid)], actual):
					fail(msg)
		if not filtered:
			for key: String in golden.keys(): # a spell the data no longer has
				if not spells.has(int(key)):
					if update:
						golden.erase(key)
						changed = true
					else:
						sub("breed %d" % breed)
						fail("golden of spell %s, which is not a class spell any more" % key)
		if update and changed:
			SpellGolden.write(breed, golden)
	sub("")
