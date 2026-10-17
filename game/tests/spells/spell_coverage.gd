## Coverage of the spell tests (H.03): what each grade of the game is checked by. A grade is covered when
##   - its data can be played by the contracts (SpellCheck.data_errors empty: every effect has a contract,
##     nothing partial), which test_spell_contracts then runs, and
##   - a class grade also has its golden record (tests/golden/spells/classe_<NN>.json, SpellGolden),
## or when SpellGaps declares it. test_spell_coverage fails on any other grade, and on a declared gap the data
## no longer has. `class_report` is the per-class audit written to docs/SPELL_AUDIT.md (tools/spell_audit.gd).
class_name SpellCoverage
extends RefCounted

static var _golden := {} # breed -> SpellGolden.read(breed)


## Why grade `id` is covered by nothing (empty: it is covered or declared in SpellGaps).
static func missing(id: int) -> PackedStringArray:
	var out: PackedStringArray = []
	if SpellGaps.GAPS.has(id):
		return out
	var spell := SpellBook.get_spell(id)
	for msg: String in SpellCheck.data_errors(spell):
		out.append("no contract: " + msg + " (play it or declare it in SpellGaps)")
	if spell.has("breed") and not has_golden(spell):
		out.append("no golden record (GOLDEN_UPDATE=1) nor declared gap")
	return out


static func has_golden(spell: Dictionary) -> bool:
	var breed := int(spell.get("breed", 0))
	if not _golden.has(breed):
		_golden[breed] = SpellGolden.read(breed)
	var rec: Variant = (_golden[breed] as Dictionary).get(str(int(spell.get("spell", spell.get("id", 0)))), null)
	return rec is Dictionary and (rec.get("grades", {}) as Dictionary).has(str(int(spell.get("rank", 1))))


static func forget() -> void:
	_golden.clear()


## SpellCases per class: breed -> [cases].
static func cases_by_breed() -> Dictionary:
	var out := {}
	for c: Dictionary in SpellCases.CASES:
		var b := int(c.get("breed", 0))
		if not out.has(b):
			out[b] = []
		out[b].append(c)
	return out


## The grades a case casts.
static func case_grades(c: Dictionary) -> Array:
	var out: Array = []
	for step: Array in c["steps"]:
		if str(step[0]) in ["cast", "fight_cast"] and not out.has(int(step[1])):
			out.append(int(step[1]))
	for slot: Dictionary in (c.get("setup", {}) as Dictionary).values():
		for g: int in slot.get("spells", []):
			out.append(g)
	return out


## The effect kinds a grade holds (its own lists; sub-spells are other grades).
static func kinds_of(id: int) -> Array:
	var seen := {}
	var spell := SpellBook.get_spell(id)
	for e: Dictionary in spell.get("effects", []) + spell.get("crit_effects", []):
		seen[str(e.get("kind", "?"))] = true
	return seen.keys()


## Audit of one class: {spells, grades, gaps, untested: [..], kinds: {kind: [grades]}, cases: [..], uncased: [kinds]}.
static func class_report(breed: int) -> Dictionary:
	var grades: Array = SpellIndex.class_grades().filter(func(id: int) -> bool: return int(SpellBook.get_spell(id)["breed"]) == breed)
	var spells := {}
	var kinds := {}
	var untested: PackedStringArray = []
	var gaps := 0
	for id: int in grades:
		spells[int(SpellBook.get_spell(id).get("spell", id))] = true
		for k: String in kinds_of(id):
			if not kinds.has(k):
				kinds[k] = []
			kinds[k].append(id)
		if SpellGaps.GAPS.has(id):
			gaps += 1
		else:
			SpellCheck.grade(id, untested)
	var cases: Array = cases_by_breed().get(breed, [])
	var cased := {}
	for c: Dictionary in cases:
		for g: int in case_grades(c):
			for k: String in kinds_of(g):
				cased[k] = true
	var uncased: Array = kinds.keys().filter(func(k: String) -> bool: return not cased.has(k))
	uncased.sort()
	return {"spells": spells.size(), "grades": grades.size(), "gaps": gaps, "untested": untested,
			"kinds": kinds, "cases": cases, "uncased": uncased}
