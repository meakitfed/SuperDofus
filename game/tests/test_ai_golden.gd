## Golden of the AI (H.05): the first turn of an AI fighter written as a trace of actions (AiTrace) and
## compared with tests/golden/monsters/ai_*.json. Any drift in how the AI chooses a target, a cell, a
## spell or the order of its actions shows up as a diff.
##   ai_profiles.json   one trace per scene of AiScenes (the situations of test_ai_profiles.gd), by profile;
##   ai_<family>.json   the first turn of every monster of the worlds (MonsterMatrix) against the standard
##                      dummy (MonsterGame), grouped by family (passive, aggressive, cautious, healer...).
## TEST_CASE=<scene or monster key> runs only some; GOLDEN_UPDATE=1 (or `-- --update-golden`) rewrites the
## files, then read the diff before committing.
extends TestCase

const PROFILES_FILE := "ai_profiles.json"
const PROFILES_DOC := "Golden de l'IA par profil (tests/ai/ai_scenes.gd) : trace du premier tour. Regenerer avec GOLDEN_UPDATE=1, relire le diff."
const MONSTER_DOC := "Golden de l'IA des monstres (tests/test_ai_golden.gd) : actions du premier tour de chaque monstre de la famille %s contre le mannequin standard. Regenerer avec GOLDEN_UPDATE=1, relire le diff."


func _init() -> void:
	SpellBook.use_file("")


func test_ai_profile_scenes_match_the_golden() -> void:
	var golden := AiTrace.read(PROFILES_FILE)
	var rows := {}
	var scenes := AiScenes.scenes()
	for name: String in scenes:
		var s: Dictionary = scenes[name]
		if not sub(name):
			continue
		var r := AiScenes.play(s)
		eq(r["profile"], s["profile"], "profile found in the spells")
		var trace: Array = AiTrace.as_array(r["trace"])
		check(trace.size() >= 2, "the monster did nothing at all: %s" % [trace])
		check(not str(trace.back()).begins_with("hang"), str(trace.back()))
		rows[name] = {"profile": s["profile"], "trace": trace}
		if AiTrace.updating():
			continue
		if not golden.has(name):
			fail("no golden for this scene (GOLDEN_UPDATE=1)")
		elif str(golden[name]) != str(AiTrace.normalized(rows[name])):
			fail("trace differs from the golden:\n  expected %s\n  got      %s" % [golden[name], rows[name]])
	sub("")
	if AiTrace.updating() and _case_filter == "":
		AiTrace.write(PROFILES_FILE, rows, PROFILES_DOC)


func test_every_scene_has_a_golden_row_and_every_profile_a_scene() -> void:
	var scenes := AiScenes.scenes()
	var seen := {}
	for name: String in scenes:
		seen[scenes[name]["profile"]] = true
	for p: String in [FightAI.AGGRESSIVE, FightAI.CAUTIOUS, FightAI.HEALER, FightAI.SUMMONER, FightAI.KAMIKAZE]:
		check(seen.has(p), "no scene for the profile %s" % p)
	if AiTrace.updating():
		return
	var golden := AiTrace.read(PROFILES_FILE)
	for name: String in scenes:
		check(golden.has(name), "scene %s has no golden row" % name)
	for k: String in golden:
		check(scenes.has(k), "golden row %s: no such scene" % k)


func test_every_monster_first_turn_matches_the_golden() -> void:
	var by_family := {} # family -> {key: trace}
	var golden := {}
	for fam: String in MonsterFamily.ALL:
		golden[fam] = AiTrace.read("ai_%s.json" % fam)
	for e: Dictionary in MonsterMatrix.entries():
		if not sub(MonsterMatrix.label(e)):
			continue
		var st := MonsterGame.setup(MonsterMatrix.played_grade(e))
		var passive: Array = [st["dummy"]]
		if st["ally"] != null:
			passive.append(st["ally"])
		var fam: String = st["family"]
		var arr: Array = AiTrace.as_array(AiTrace.first_turn(st["fight"], st["events"], st["mon"], passive))
		if not by_family.has(fam):
			by_family[fam] = {}
		by_family[fam][e["key"]] = arr
		check(not str(arr.back()).begins_with("hang") and not str(arr.back()).begins_with("no fighter"), str(arr.back()))
		if AiTrace.updating():
			continue
		var want: Variant = (golden[fam] as Dictionary).get(e["key"])
		if want == null:
			fail("no golden row in ai_%s.json (GOLDEN_UPDATE=1)" % fam)
		elif str(want) != str(arr):
			fail("first turn differs from the golden:\n  expected %s\n  got      %s" % [want, arr])
	sub("")
	if AiTrace.updating() and _case_filter == "":
		for fam: String in MonsterFamily.ALL:
			AiTrace.write("ai_%s.json" % fam, by_family.get(fam, {}), MONSTER_DOC % fam)


## A monster the data no longer has leaves a stale row; a monster with no row, or in two family files, fails.
func test_no_stale_or_missing_ai_golden_row() -> void:
	if AiTrace.updating():
		return
	var keys := {}
	for e: Dictionary in MonsterMatrix.entries():
		keys[e["key"]] = true
	var found := {}
	for fam: String in MonsterFamily.ALL:
		for k: String in AiTrace.read("ai_%s.json" % fam):
			check(keys.has(k), "ai_%s.json: row %s, the data has no such monster" % [fam, k])
			check(not found.has(k), "row %s is in two family files (%s and %s)" % [k, found.get(k, ""), fam])
			found[k] = fam
	for k: String in keys:
		check(found.has(k), "monster %s has no AI golden row (GOLDEN_UPDATE=1)" % k)


## The trace bites: another situation is another line, and a scene replays identically.
func test_a_changed_situation_changes_the_trace() -> void:
	var base: Dictionary = AiScenes.scenes()["aggressive_far"]
	var a := Array(AiScenes.play(base)["trace"])
	var other := base.duplicate()
	other["gap"] = 5
	check(a != Array(AiScenes.play(other)["trace"]), "two different situations gave the same trace")
	eq(Array(AiScenes.play(base)["trace"]), a, "the same scene replays identically")
