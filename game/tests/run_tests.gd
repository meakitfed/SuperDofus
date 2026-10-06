## Headless test runner:
##   godot --headless --path game -s res://tests/run_tests.gd
## TEST_ONLY=<substring of the file name> runs only those files (quick loop; the full run stays the reference).
## TEST_SKIP=<substring> leaves those files out (to run them apart).
## Runs every `test_*` method of every tests/test_*.gd script; exit code 1 on failure.
extends SceneTree


func _initialize() -> void:
	# the root joins the tree only after _initialize: tests that need nodes (client sessions) run on the first frame
	Engine.set_meta("test_tree", self)
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var total := 0
	var failed: PackedStringArray = []
	var files := DirAccess.get_files_at("res://tests")
	var only := OS.get_environment("TEST_ONLY")
	var skip := OS.get_environment("TEST_SKIP")
	for file in files:
		if not file.begins_with("test_") or not file.ends_with(".gd") or file == "test_case.gd" or (only != "" and not only in file) or (skip != "" and skip in file):
			continue
		var script: GDScript = load("res://tests/" + file)
		print("• ", file)
		for method in script.get_script_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			var suite: TestCase = script.new()
			suite._set_current("%s::%s" % [file.get_basename(), name])
			suite.call(name)
			total += 1
			if suite.failures.is_empty():
				print("    ok   ", name)
			else:
				print("    FAIL ", name)
				for f in suite.failures:
					print("         ", f)
				failed.append_array(suite.failures)
	print("\n%d tests, %d failures" % [total, failed.size()])
	DofusContent.wait_preloads() # sprites made by the client tests decode their clips on worker threads
	DofusContent.clear_caches()
	quit(1 if not failed.is_empty() else 0)
