## Headless test runner:
##   godot --headless --path game -s res://tests/run_tests.gd
## TEST_ONLY=<substring of the file name>[,<substring>…] runs only those files (quick loop; the full run stays the reference).
## TEST_SKIP=<substring>[,…] leaves those files out (to run them apart).
## TEST_CASE=<substring> runs only the matching cases of parameterized tests (TestCase.sub), e.g. a spell id.
## TEST_TIER=fast runs only the spell contracts, cases, the monster matrix and scenarios; the file/test count is guarded by tests/baseline.json
## (TEST_UPDATE_BASELINE=1 rewrites it after an intended change); a test file that does not parse fails the run.
## Runs every `test_*` method of every tests/test_*.gd script; exit code 1 on failure.
extends SceneTree

## Test files of the "fast" tier: spell contracts, multi-turn cases, reference scenarios.
const FAST_TIER: PackedStringArray = ["test_spell_", "test_monster_", "test_scenarios"]
const BASELINE_PATH := "res://tests/baseline.json" # per-file count of test methods; may only go up


func _initialize() -> void:
	# the root joins the tree only after _initialize: tests that need nodes (client sessions) run on the first frame
	Engine.set_meta("test_tree", self)
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var total := 0
	var failed: PackedStringArray = []
	var files := DirAccess.get_files_at("res://tests")
	files.sort()
	var only := OS.get_environment("TEST_ONLY").split(",", false)
	var skip := OS.get_environment("TEST_SKIP").split(",", false)
	var tier := OS.get_environment("TEST_TIER") # "", "full" = everything; "fast" = spell contracts + cases + scenarios
	var full_run := only.is_empty() and skip.is_empty() and tier != "fast"
	var count_only := OS.get_environment("TEST_UPDATE_BASELINE") == "1" # rewrites tests/baseline.json from the test methods, runs nothing
	var baseline := _read_baseline()
	var counts := {} # file -> number of test_ methods found
	var rows: Array = [] # [file, tests, failures, ms]
	for file in files:
		if not file.begins_with("test_") or not file.ends_with(".gd") or file == "test_case.gd":
			continue
		if tier == "fast" and not _matches(file, FAST_TIER):
			continue
		if (not only.is_empty() and not _matches(file, only)) or _matches(file, skip):
			continue
		var script: GDScript = load("res://tests/" + file)
		# a file that does not parse loads but cannot be instantiated: that used to be silent (H.01)
		if script == null or not script.can_instantiate():
			print("• ", file)
			print("    FAIL ", file, " (parse error: the file does not load, none of its tests ran)")
			failed.append("%s: parse error" % file)
			rows.append([file, 0, 1, 0])
			continue
		print("• ", file)
		var methods: PackedStringArray = []
		for method in script.get_script_method_list():
			if String(method["name"]).begins_with("test_"):
				methods.append(method["name"])
		counts[file] = methods.size()
		if count_only:
			continue
		var t0 := Time.get_ticks_msec()
		var file_tests := 0
		var file_failures := 0
		for name in methods:
			_reset_statics() # R.04: no static state leaks from one test to the next (order independence)
			var suite: TestCase = script.new()
			suite._set_current("%s::%s" % [file.get_basename(), name])
			suite.call(name)
			total += 1
			file_tests += 1
			if suite.failures.is_empty():
				print("    ok   ", name)
			else:
				print("    FAIL ", name)
				for f in suite.failures:
					print("         ", f)
				failed.append_array(suite.failures)
				file_failures += suite.failures.size()
		rows.append([file, file_tests, file_failures, Time.get_ticks_msec() - t0])
	if count_only:
		_write_baseline(counts)
		quit(0)
		return
	# H.01 guard: the number of tests of a file may only go up (tests/baseline.json, updated on purpose)
	for file in counts:
		var known := int(baseline.get(file, 0))
		if int(counts[file]) < known:
			var msg := "%s: %d tests, baseline %d (a test disappeared)" % [file, counts[file], known]
			print("    FAIL baseline ", msg)
			failed.append(msg)
	if full_run:
		for file in baseline:
			if not counts.has(file):
				var msg2 := "%s: in baseline but missing or not run" % file
				print("    FAIL baseline ", msg2)
				failed.append(msg2)
	_print_summary(rows, tier)
	print("
%d tests, %d failures" % [total, failed.size()])
	DofusContent.wait_preloads() # sprites made by the client tests decode their clips on worker threads
	DofusContent.clear_caches()
	quit(1 if not failed.is_empty() else 0)


func _print_summary(rows: Array, tier: String) -> void:
	print("
== Recapitulatif%s ==" % ((" (tier " + tier + ")") if tier != "" else ""))
	var slow := rows.duplicate()
	slow.sort_custom(func(a, b): return a[3] > b[3])
	var bad := rows.filter(func(r): return r[2] > 0)
	print("%d fichiers, %d en echec" % [rows.size(), bad.size()])
	for r in bad:
		print("  ECHEC  %s : %d tests, %d echecs" % [r[0], r[1], r[2]])
	for r in slow.slice(0, 5):
		print("  lent   %s : %d tests, %.1f s" % [r[0], r[1], r[3] / 1000.0])


static func _read_baseline() -> Dictionary:
	var f := FileAccess.open(BASELINE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var data = JSON.parse_string(f.get_as_text())
	return data.get("files", {}) if data is Dictionary else {}


static func _write_baseline(counts: Dictionary) -> void:
	var f := FileAccess.open(BASELINE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"total": counts.values().reduce(func(a, b): return a + b, 0), "files": counts}, "	", true) + "
")
	print("baseline ecrite : %d fichiers" % counts.size())


## Back to the default static state; a test's _init() then sets what it needs.
static func _reset_statics() -> void:
	SpellBook.use_file("")
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()


static func _matches(file: String, parts: PackedStringArray) -> bool:
	for p in parts:
		if p in file:
			return true
	return false
