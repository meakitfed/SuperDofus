## The monster matrix (H.04, tests/monsters/): one sub-test per monster of the worlds incarnam and dofus
## (monsters and dungeon bosses), TEST_CASE=<key or id> runs only some ("dofus:4108", "4108").
## Data, appearance in a fight, a 6-turn game against the standard dummy (what its family promises,
## and the same game written in tests/golden/monsters/matrix.json), XP / kamas / drops of FightRewards.
## GOLDEN_UPDATE=1 rewrites the golden file (read the diff).
extends TestCase

static var _golden := {}
static var _rows := {} # the games played by test_every_monster_plays (for the golden rewrite)


func _init() -> void:
	SpellBook.use_file("")
	if _golden.is_empty():
		_golden = MonsterMatrix.read_golden()


func test_the_data_of_every_monster_reads_and_its_spells_are_complete() -> void:
	for e: Dictionary in MonsterMatrix.entries():
		if sub(MonsterMatrix.label(e)):
			for msg: String in MonsterMatrix.data_errors(e):
				fail(msg)
	sub("")


func test_every_monster_appears_in_a_fight_as_its_data_says() -> void:
	for e: Dictionary in MonsterMatrix.entries():
		if sub(MonsterMatrix.label(e)):
			for msg: String in MonsterMatrix.appearance_errors(e):
				fail(msg)
	sub("")


func test_every_monster_plays() -> void:
	_rows = {}
	for e: Dictionary in MonsterMatrix.entries():
		if not sub(MonsterMatrix.label(e)):
			continue
		var r := MonsterGame.play(MonsterMatrix.played_grade(e))
		for msg: String in r["errors"]:
			fail(msg)
		for msg: String in MonsterMatrix.family_errors(r):
			fail("%s: %s" % [r["family"], msg])
		var digest := MonsterMatrix.digest(e, r)
		_rows[e["key"]] = digest
		if MonsterMatrix.updating():
			continue
		if not _golden.has(e["key"]):
			fail("no row in the golden file (GOLDEN_UPDATE=1)")
			continue
		var want: Dictionary = _golden[e["key"]]
		var got: Dictionary = MonsterMatrix.normalized(digest)
		for k: String in got:
			if str(want.get(k)) != str(got[k]):
				fail("golden %s: expected %s, got %s" % [k, want.get(k), got[k]])
	sub("")
	if MonsterMatrix.updating() and _case_filter == "":
		MonsterMatrix.write_golden(_rows)


func test_every_monster_rewards_what_fight_rewards_computes() -> void:
	for e: Dictionary in MonsterMatrix.entries():
		if not sub(MonsterMatrix.label(e)):
			continue
		for g: Dictionary in e["grades"]:
			var rw := MonsterGame.rewards(g)
			var at := "grade %d: " % int(g["grade"])
			eq(int(rw["xp"]), int(rw["expected_xp"]), at + "XP")
			if int(g["xp"]) > 0:
				check(int(rw["xp"]) > 0, at + "a monster worth %d XP gives none" % int(g["xp"]))
			var k: Array = g["kamas"]
			check(int(rw["kamas"]) >= int(k[0]) and int(rw["kamas"]) <= maxi(int(k[0]), int(k[1])), at + "kamas %d outside %s" % [int(rw["kamas"]), k])
			var want := {}
			for d: Dictionary in g.get("drops", []):
				want[int(d["item"])] = true
			var got: Dictionary = rw["all_drops"]
			for item: Variant in got:
				check(want.has(int(item)), at + "item %d drops but is not in the data" % int(item))
			for item: Variant in want:
				check(got.has(int(item)), at + "item %d never drops" % int(item))
	sub("")


# ── coverage guard ──────────────────────────────────────────────────────────────────────────────────

## A monster with no row in the golden file fails, and so does a row of a monster the data no longer has.
func test_every_monster_has_a_golden_row() -> void:
	if MonsterMatrix.updating():
		return
	var keys := {}
	for e: Dictionary in MonsterMatrix.entries():
		keys[e["key"]] = true
		check(_golden.has(e["key"]), "%s has no row in tests/golden/monsters/matrix.json (GOLDEN_UPDATE=1)" % MonsterMatrix.label(e))
	for k: String in _golden:
		check(keys.has(k), "golden row %s: the data has no such monster" % k)


func test_the_worlds_hold_monsters() -> void:
	var worlds := {}
	for e: Dictionary in MonsterMatrix.entries():
		worlds[e["world"]] = int(worlds.get(e["world"], 0)) + 1
	for w: String in MonsterMatrix.WORLDS:
		check(int(worlds.get(w, 0)) > 0, "world %s has no monster" % w)


## Every family is played by at least one real monster, except the bombs (no monster of the data kills
## itself: the bombs are summons, tests/test_bombs.gd and test_ai_profiles.gd).
func test_every_family_has_monsters() -> void:
	if MonsterMatrix.updating():
		return
	var seen := {}
	for e: Dictionary in MonsterMatrix.entries():
		var row: Dictionary = _golden.get(e["key"], {})
		seen[str(row.get("family", ""))] = true
	for fam: String in MonsterFamily.ALL:
		if fam != MonsterFamily.BOMB:
			check(seen.has(fam), "no monster of family %s" % fam)


## The family expectations bite: a hitter that never hits, a dummy hurt by a monster without spell.
func test_the_family_expectations_catch_a_broken_monster() -> void:
	var idle := {"family": MonsterFamily.MELEE, "dummy_lost": 0, "summons": 0, "alive": true, "ally_healed": false}
	check(not MonsterMatrix.family_errors(idle).is_empty(), "a hitter that does nothing must fail")
	var hurts := {"family": MonsterFamily.PASSIVE, "dummy_lost": 5, "summons": 0, "alive": true, "ally_healed": false}
	check(not MonsterMatrix.family_errors(hurts).is_empty(), "a monster without spell that hurts must fail")
	var dead := {"family": MonsterFamily.SHOOTER, "dummy_lost": 5, "summons": 0, "alive": false, "ally_healed": false}
	check(not MonsterMatrix.family_errors(dead).is_empty(), "a shooter dead against a dummy must fail")
	var bomb := {"family": MonsterFamily.BOMB, "dummy_lost": 5, "summons": 0, "alive": false, "ally_healed": false}
	eq(MonsterMatrix.family_errors(bomb).size(), 0, "a bomb that exploded passes")
	var walker := {"family": MonsterFamily.PASSIVE, "dummy_lost": 0, "summons": 0, "alive": true, "ally_healed": false}
	eq(MonsterMatrix.family_errors(walker).size(), 0, "a monster without spell that walks passes")
