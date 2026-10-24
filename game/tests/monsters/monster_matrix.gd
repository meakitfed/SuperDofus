## The monster matrix (H.04): one row per monster of the worlds the tests load (incarnam, dofus; the
## `monsters` and the dungeon `bosses` of monsters.json), checked on four things:
##   data       every grade reads (level, life, AP / MP, resistances, drops, kamas) and has all its spells,
##              present in SpellBook and complete (SpellCheck.data_errors, or declared in SpellGaps);
##   appearance the fighter a fight builds from each grade matches the data;
##   game       the last grade plays MonsterGame.TURNS turns against the standard dummy: no error, no hang,
##              and what its family promises (family_errors);
##   rewards    its XP, kamas and drops are what FightRewards / FightXp compute.
## The result of the game is also written as data in tests/golden/monsters/matrix.json (regenerate with
## GOLDEN_UPDATE=1 and read the diff): a change in the behaviour of a monster shows up as a diff, and a
## monster with no row in that file fails the coverage guard.
class_name MonsterMatrix
extends RefCounted

const WORLDS := ["incarnam", "dofus"]
const GOLDEN := "res://tests/golden/monsters/matrix.json"
const ELEMENTS := ["earth", "fire", "water", "air", "neutral"]

static var _entries: Array = []


static func updating() -> bool:
	return OS.get_environment("GOLDEN_UPDATE") == "1" or OS.get_cmdline_user_args().has("--update-golden")


## [{key: "<world>:<id>", world, id, boss, grades: [grade dict]}], sorted by key.
static func entries() -> Array:
	if not _entries.is_empty():
		return _entries
	for world: String in WORLDS:
		var data := JsonWorldSource.new("res://worlds/" + world).get_monsters()
		for section: String in ["monsters", "bosses"]:
			var db: Dictionary = data.get(section, {})
			for id: String in db:
				var grades: Array = (db[id] as Dictionary).get("grades", [])
				_entries.append({"key": "%s:%s" % [world, id], "world": world, "id": int(id), "boss": section == "bosses",
						"grades": grades, "name_id": int((db[id] as Dictionary).get("name_id", 0))})
	_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["key"] < b["key"])
	return _entries


static func label(e: Dictionary) -> String:
	return "%s%s (name %d)" % [e["key"], " boss" if e["boss"] else "", e["name_id"]]


## The grade the game is played with: the strongest.
static func played_grade(e: Dictionary) -> Dictionary:
	return (e["grades"] as Array).back()


# ── data ────────────────────────────────────────────────────────────────────────────────────────────

static func data_errors(e: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	var grades: Array = e["grades"]
	if grades.is_empty():
		out.append("no grade")
	for i in grades.size():
		var g: Dictionary = grades[i]
		var at := "grade %d: " % int(g.get("grade", -1))
		if int(g.get("grade", -1)) != i + 1:
			out.append(at + "grades are not numbered 1..%d" % grades.size())
		if int(g.get("monster", -1)) != e["id"]:
			out.append(at + "monster id %s" % g.get("monster"))
		for k: String in ["level", "hp"]:
			if int(g.get(k, 0)) <= 0:
				out.append(at + "%s %s" % [k, g.get(k, "missing")])
		for k: String in ["ap", "mp", "xp"]:
			if not g.has(k) or int(g[k]) < 0:
				out.append(at + "%s %s" % [k, g.get(k, "missing")])
		for el: String in ELEMENTS:
			if not (g.get("res", {}) as Dictionary).has(el):
				out.append(at + "no resistance " + el)
		for stat: String in ["strength", "intelligence", "chance", "agility", "wisdom"]:
			if not (g.get("stats", {}) as Dictionary).has(stat):
				out.append(at + "no stat " + stat)
		var k: Array = g.get("kamas", [0, 0])
		if k.size() != 2 or int(k[0]) > int(k[1]) or int(k[0]) < 0:
			out.append(at + "kamas %s" % [k])
		for d: Dictionary in g.get("drops", []):
			if int(d.get("item", 0)) <= 0 or float(d.get("pct", 0)) <= 0.0 or float(d.get("pct", 0)) > 100.0:
				out.append(at + "drop %s" % [d])
		for sid: Variant in g.get("spells", []):
			var msgs := spell_errors(int(sid))
			for msg: String in msgs:
				out.append(at + msg)
	return out


## What is wrong with a spell of a monster that the spell data has: not complete (partial, an effect
## without contract) unless SpellGaps declares it. A spell the data does not have is no error here: it is
## counted by `absent_spells` and pinned by the golden file (the extraction only converted the spells of
## the monsters of Incarnam and Astrub, see docs/DECOUVERTES.md H.04).
static func spell_errors(spell_id: int) -> PackedStringArray:
	if SpellBook.get_spell(spell_id).is_empty():
		return PackedStringArray()
	return SpellCoverage.missing(spell_id)


## How many spell references of the grades of `e` the spell data does not have: [absent, total].
static func absent_spells(e: Dictionary) -> Array:
	var absent := 0
	var total := 0
	for g: Dictionary in e["grades"]:
		for sid: Variant in g.get("spells", []):
			total += 1
			if SpellBook.get_spell(int(sid)).is_empty():
				absent += 1
	return [absent, total]


# ── appearance ──────────────────────────────────────────────────────────────────────────────────────

static func appearance_errors(e: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	for g: Dictionary in e["grades"]:
		var f := MonsterGame.monster(g)
		var at := "grade %d: " % int(g.get("grade", -1))
		if f.team != 1 or not f.ai or f.monster != e["id"] or f.grade != int(g["grade"]):
			out.append(at + "not an AI monster of team 1 with its id and grade")
		if f.level != int(g["level"]) or f.max_hp != int(g["hp"]) or f.hp != f.max_hp:
			out.append(at + "level / life differ from the data (%d, %d/%d)" % [f.level, f.hp, f.max_hp])
		if f.max_ap != int(g["ap"]) or f.max_mp != int(g["mp"]) or f.ap != f.max_ap or f.mp != f.max_mp:
			out.append(at + "AP / MP differ from the data (%d/%d)" % [f.max_ap, f.max_mp])
		for el: String in ELEMENTS:
			if f.stat("res_" + el) != int((g["res"] as Dictionary)[el]):
				out.append(at + "resistance %s is %d, data %d" % [el, f.stat("res_" + el), int(g["res"][el])])
		for stat: String in g["stats"]:
			if int(f.stats.get(stat, 0)) != int(g["stats"][stat]):
				out.append(at + "stat %s is %d, data %d" % [stat, int(f.stats.get(stat, 0)), int(g["stats"][stat])])
		var present := (g.get("spells", []) as Array).filter(func(s: Variant) -> bool: return not SpellBook.get_spell(int(s)).is_empty()).size()
		if f.spells.size() != present:
			out.append(at + "%d spells loaded of %d the spell data has" % [f.spells.size(), present])
		if int(f.loot.get("xp", -1)) != int(g["xp"]) or f.loot.get("drops", []).size() != (g.get("drops", []) as Array).size():
			out.append(at + "loot differs from the data")
	return out


# ── game ────────────────────────────────────────────────────────────────────────────────────────────

## What the family promises of the game `r` (MonsterGame.play): the same fight, a different expectation.
static func family_errors(r: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	var hit: bool = int(r["dummy_lost"]) > 0
	if not r["alive"] and r["family"] != MonsterFamily.BOMB and not r["mortal"]:
		out.append("the monster died against a dummy that does not fight")
	# H.04d: a monster whose spells only buff, debuff, move or summon has nothing to hurt the dummy with (no damage, steal
	# or kill effect on another fighter): a profile read from "everything else" (FightAI.profile) is not a hitter, so what
	# it promises is to play its turns: cast one of its spells or walk
	var supports: bool = not r["can_hurt"] and not (r["family"] == MonsterFamily.HEALER and r["heals_others"])
	if supports and [MonsterFamily.MELEE, MonsterFamily.SHOOTER, MonsterFamily.HEALER].has(r["family"]):
		if int(r["casts"]) == 0 and not r["moved"]:
			out.append("a monster of support spells neither cast nor walked in %d turns" % MonsterGame.TURNS)
		return out
	match r["family"]:
		MonsterFamily.PASSIVE: # no spell: it walks but never hurts nor summons (its start spell may: hooks, H.04d)
			if (hit or int(r["summons"]) > 0) and not r["start"]:
				out.append("a monster without spell hurt the dummy or summoned")
		MonsterFamily.MELEE:
			if not hit:
				out.append("a hitter never hurt the dummy in %d turns" % MonsterGame.TURNS)
		MonsterFamily.SHOOTER:
			if not hit:
				out.append("a shooter never hurt the dummy in %d turns" % MonsterGame.TURNS)
		MonsterFamily.HEALER: # heals its hurt ally, else hits
			if not hit and not r["ally_healed"]:
				out.append("a healer neither healed its ally nor hurt the dummy")
		MonsterFamily.SUMMONER: # calls its creatures, else hits
			if not hit and int(r["summons"]) == 0:
				out.append("a summoner neither summoned nor hurt the dummy")
		MonsterFamily.BOMB: # its spell kills it
			if r["alive"] and not hit:
				out.append("a bomb neither exploded nor hurt the dummy")
	return out


## The digest of a game, as stored in the golden file.
static func digest(e: Dictionary, r: Dictionary) -> Dictionary:
	var abs := absent_spells(e)
	return {"family": r["family"], "grades": (e["grades"] as Array).size(), "spells_absent": abs[0], "spells_total": abs[1],
			"dummy_lost": r["dummy_lost"], "hp": r["hp"], "alive": r["alive"], "fighters": r["fighters"],
			"summons": r["summons"], "moved": r["moved"], "gap": r["gap"], "ally_healed": r["ally_healed"]}


static func read_golden() -> Dictionary:
	var f := FileAccess.open(GOLDEN, FileAccess.READ)
	if f == null:
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	return (data as Dictionary).get("monsters", {}) if data is Dictionary else {}


static func write_golden(rows: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GOLDEN.get_base_dir()))
	var f := FileAccess.open(GOLDEN, FileAccess.WRITE)
	f.store_string(JSON.stringify({"_doc": "Golden de la matrice monstres (tests/monsters/monster_matrix.gd) : une partie de %d tours contre le mannequin standard par monstre (dernier grade). Regenerer avec GOLDEN_UPDATE=1 (docs/COMMANDES.md), relire le diff." % MonsterGame.TURNS,
			"monsters": rows}, "\t", true) + "\n")


static func normalized(v: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(v, "", true))
