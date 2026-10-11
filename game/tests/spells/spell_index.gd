## The spell grades the tests go through, from SpellBook (the real data/spells.json).
class_name SpellIndex
extends RefCounted

static var _by_origin := {} # spells.id -> castable ids, grade order


## Class grades (they have a breed), then monster grades, by id.
static func class_grades() -> Array:
	return SpellBook.all_ids().filter(func(id: int) -> bool: return SpellBook.get_spell(id).has("breed"))


static func monster_grades() -> Array:
	return SpellBook.all_ids().filter(func(id: int) -> bool: return not SpellBook.get_spell(id).has("breed"))


## A castable grade of spell `origin` (spells.id): the one of rank `grade` (spelllevels.grade; 0 = its
## first one); 0 when the data has none.
static func grade_of(origin: int, grade := 0) -> int:
	if _by_origin.is_empty():
		for id: int in SpellBook.all_ids():
			var o := int(SpellBook.get_spell(id).get("origin", -1))
			if not _by_origin.has(o):
				_by_origin[o] = []
			_by_origin[o].append(id)
		for o: int in _by_origin:
			_by_origin[o].sort_custom(func(a: int, b: int) -> bool:
				return int(SpellBook.get_spell(a).get("rank", 1)) < int(SpellBook.get_spell(b).get("rank", 1)))
	var ids: Array = _by_origin.get(origin, [])
	if ids.is_empty():
		return 0
	if grade == 0:
		return ids[0]
	for id: int in ids:
		if int(SpellBook.get_spell(id).get("rank", 1)) == grade:
			return id
	return 0


## "Pression (1041127) grade 2".
static func label(id: int) -> String:
	var s := SpellBook.get_spell(id)
	return "%s (%d)%s" % [s.get("name", "?"), id, " grade %d" % int(s["grade"]) if s.has("grade") else ""]
