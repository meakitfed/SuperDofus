## Coverage guard (H.03, tests/spells/spell_coverage.gd): every grade of the game is either checked by the
## contracts (and, for a class, has its golden record) or declared in SpellGaps. A new spell without its
## golden line, or a gap the data no longer has, fails here.
extends TestCase


func _init() -> void:
	SpellBook.use_file("")
	SpellCoverage.forget()


func test_every_grade_is_covered() -> void:
	for id: int in SpellBook.all_ids():
		var msgs := SpellCoverage.missing(id)
		if msgs.is_empty():
			continue
		if sub(SpellIndex.label(id)):
			for msg: String in msgs:
				fail(msg)
	sub("")


func test_declared_gaps_exist() -> void:
	for id: int in SpellGaps.GAPS:
		check(not SpellBook.get_spell(id).is_empty(), "SpellGaps lists grade %d, which the data does not have" % id)


## A grade without golden record is caught (the guard itself works).
func test_guard_sees_a_missing_golden() -> void:
	var id: int = SpellIndex.class_grades()[0]
	var spell := SpellBook.get_spell(id).duplicate()
	check(SpellCoverage.has_golden(spell), "the first class grade has its golden record")
	spell["rank"] = 999
	check(not SpellCoverage.has_golden(spell), "an unknown rank must have no golden record")
	spell["rank"] = 1
	spell["breed"] = 99
	check(not SpellCoverage.has_golden(spell), "an unknown class must have no golden record")


func test_cases_belong_to_a_class_of_the_data() -> void:
	var breeds := SpellGolden.breeds()
	for c: Dictionary in SpellCases.CASES:
		check(int(c.get("breed", 0)) in breeds, "%s: breed %s has no spells" % [c["name"], c.get("breed")])
