## Every spell grade of the game, classes then monsters, against the contracts of its effects
## (tests/spells: SpellCheck, one effect at a time in the SpellArena). One failure per problem,
## prefixed with the grade; TEST_CASE=<grade id or spell name> runs only that grade.
extends TestCase


func _init() -> void:
	SpellBook.use_file("")


func test_class_spells() -> void:
	_check(SpellIndex.class_grades())


func test_monster_spells() -> void:
	_check(SpellIndex.monster_grades())


## Every grade cast whole, normal then critical (SpellSmoke): the fight stays sane.
func test_whole_spells() -> void:
	for id: int in SpellBook.all_ids():
		if sub(SpellIndex.label(id)):
			for msg: String in SpellSmoke.grade(id):
				fail(msg)
	sub("")


func test_known_gaps_still_fail() -> void:
	for id: int in SpellGaps.GAPS:
		if sub(SpellIndex.label(id)):
			check(not SpellCheck.grade(id).is_empty(), "passes now: take it out of SpellGaps")


func _check(ids: Array) -> void:
	for id: int in ids:
		if SpellGaps.GAPS.has(id) or not sub(SpellIndex.label(id)):
			continue
		for msg: String in SpellCheck.grade(id):
			fail(msg)
	sub("")
