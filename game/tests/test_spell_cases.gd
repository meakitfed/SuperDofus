## The spells whose effect shows over several steps (tests/spells/spell_cases.gd), one sub-test per
## case; TEST_CASE=<text of its name> runs only those.
extends TestCase


func _init() -> void:
	SpellBook.use_file("")


func test_cases() -> void:
	for c: Dictionary in SpellCases.CASES:
		if sub(str(c["name"])):
			for msg: String in SpellCaseRunner.run(c):
				fail(msg)
	sub("")


func test_cases_say_where_they_come_from() -> void:
	for c: Dictionary in SpellCases.CASES:
		check(str(c.get("source", "")) != "" and not (c["steps"] as Array).is_empty(), "%s: a source and steps" % c["name"])
