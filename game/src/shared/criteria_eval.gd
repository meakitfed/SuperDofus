## The one reader of Dofus criteria (items.criterions, later quests, NPC
## replies…), e.g. "cs<25", "PL>10&CW>100", "Ps=1&Pa>20|PG=3".
##   PL level · PG breed (breeds.id) · PS sex (0 male, 1 female)
##   C<x> a characteristic in total, c<x> its additional part (scrolls: the
##   Petit Parchemin de Force description, "cs<25", says "si vos points
##   additionnels de Force sont inférieurs à 25"); x = S strength,
##   I intelligence, C chance, A agility, V vitality, W wisdom, P AP, M MP
##   PO an item owned (=: has one, !: has none) · Ps alignment side · Pa alignment level
##   PJ job level (PJ<op><jobs.id>,<level>: "PJ>2,80" = Bucheron above level 80, "PJ=44,200" = level 200; P2.05b)
##   BI never (items flagged unusable)
##   BT always true (the default condition of a quest: "BT=1")
##   Qf quest finished (Qf=<quest id>, "Qf!" not) · Qa quest under way (P2.03)
##   operators < > = ! · & and | (& first, no brackets)
## An unknown key makes the condition false: nothing passes that the game
## cannot check yet (quest objectives Qo, subscription S*… later lots).
class_name CriteriaEval
extends RefCounted

const STATS := {"s": "strength", "i": "intelligence", "c": "chance", "a": "agility", "v": "vitality",
		"w": "wisdom", "p": "ap", "m": "mp"}


## `values`: level, breed, sex, "<stat>" (total), "<stat>_additional", ap, mp,
## items (Array of owned item ids), alignment, alignment_level, quests_finished /
## quests_active (Array of quest ids), jobs (jobs.id -> job level).
static func ok(criteria: String, values: Dictionary) -> bool:
	var text := criteria.strip_edges()
	if text == "":
		return true
	for any in text.split("|"):
		var all := true
		for one in any.split("&"):
			if not _one(one.strip_edges(), values):
				all = false
				break
		if all:
			return true
	return false


## The keys of `criteria` this evaluator cannot read (for tooltips / tests).
static func unknown_keys(criteria: String) -> PackedStringArray:
	var out := PackedStringArray()
	for part in criteria.replace("|", "&").split("&", false):
		var p := part.strip_edges()
		if p.length() >= 3 and _value(p.substr(0, 2), {"items": []}) == null and not p.substr(0, 2) in ["BI", "BT", "Qf", "Qa", "PJ"]:
			out.append(p.substr(0, 2))
	return out


static func _one(c: String, values: Dictionary) -> bool:
	if c.length() < 3:
		return false
	var key := c.substr(0, 2)
	var op := c[2]
	var target := c.substr(3)
	if key == "BI":
		return false
	if key == "BT":
		return op == "=" and target == "1"
	if key == "Qf" or key == "Qa":
		var list: Array = values.get("quests_finished" if key == "Qf" else "quests_active", [])
		var yes := false
		for q: Variant in list:
			if int(q) == int(target):
				yes = true
		return yes if op == "=" else (not yes if op == "!" else false)
	if key == "PJ":
		# the comparison is on the job level: "PJ>2,80" (job 2 above 80), "PJ=44,200" (job 44 at 200)
		var parts := target.split(",")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			return false
		var level := int((values.get("jobs", {}) as Dictionary).get(int(parts[0]), Jobs.START_LEVEL))
		return _compare(level, op, int(parts[1]))
	if key == "PO":
		var has := (values.get("items", []) as Array).has(int(target))
		return has if op == "=" else (not has if op == "!" else false)
	if not target.is_valid_int():
		return false
	var v: Variant = _value(key, values)
	if v == null:
		return false
	return _compare(int(v), op, int(target))


static func _compare(a: int, op: String, b: int) -> bool:
	match op:
		"<": return a < b
		">": return a > b
		"=": return a == b
		"!": return a != b
	return false


static func _value(key: String, values: Dictionary) -> Variant:
	match key:
		"PL": return values.get("level", 1)
		"PG": return values.get("breed", 0)
		"PS": return values.get("sex", 0)
		"Ps": return values.get("alignment", 0)
		"Pa": return values.get("alignment_level", 0)
		"PO": return 0
	if (key[0] == "C" or key[0] == "c") and STATS.has(key[1].to_lower()):
		var stat: String = STATS[key[1].to_lower()]
		return values.get(stat, 0) if key[0] == "C" else values.get(stat + "_additional", 0)
	return null
