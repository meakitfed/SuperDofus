## Replays every reference scenario (tests/scenarios/*.jsonl) on LocalBackend.
## A failure means the game rules changed: either a regression, or an
## intended change and the scenario must be re-recorded (sim_cli --record,
## command in the scenario's header `doc` / docs/RULES_SOURCES.md).
## The network server will replay the same files (roadmap S.07).
extends TestCase

const DIR := "res://tests/scenarios"


func _init() -> void:
	SpellBook.use_file("") # the real game data (other suites switch to test fixtures)
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()


func test_reference_scenarios() -> void:
	var files := Array(DirAccess.get_files_at(DIR)).filter(func(f: String) -> bool: return f.ends_with(".jsonl"))
	check(files.size() >= 3, "exploration, won fight, lost fight")
	for f: String in files:
		var s := Scenario.load_file(DIR.path_join(f))
		check(not s.header.is_empty() and not s.expects.is_empty(), "%s: header and expectations" % f)
		for failure in s.check(s.run(LocalBackend.new())):
			check(false, "%s: %s" % [f, failure])


func test_replay_is_deterministic() -> void:
	var s := Scenario.load_file(DIR.path_join("fight_won.jsonl"))
	var a := s.run(LocalBackend.new())
	var b := s.run(LocalBackend.new())
	eq(a.size(), b.size())
	eq(JSON.stringify(a), JSON.stringify(b), "same seed + same commands = same events")


func test_check_detects_a_difference() -> void:
	var s := Scenario.load_file(DIR.path_join("explore.jsonl"))
	var events := s.run(LocalBackend.new())
	eq(s.check(events), PackedStringArray(), "recorded file passes")
	var wrong := Scenario.load_file(DIR.path_join("explore.jsonl"))
	var first_map := wrong.expects.filter(func(x: Dictionary) -> bool: return x["expect"]["t"] == Protocol.MAP_ENTER)[0] as Dictionary
	first_map["expect"]["map"]["id"] = 999
	eq(wrong.check(events).size(), 1, "another map id is caught")
	var late := Scenario.load_file(DIR.path_join("explore.jsonl"))
	late.expects[3]["at"] = int(late.expects[3]["at"]) + 50
	eq(late.check(events).size(), 1, "a timing change is caught")


func test_partial_matching_rules() -> void:
	check(Scenario._matches({"a": 1}, {"a": 1.0, "b": 2}), "extra fields ignored, 1 == 1.0")
	check(not Scenario._matches({"a": 1}, {"b": 1}), "missing field")
	check(Scenario._matches({"x": {"y": [1, {"z": true}]}}, {"x": {"y": [1, {"z": true, "w": 0}], "k": 3}}), "nested")
	check(not Scenario._matches({"y": [1]}, {"y": [1, 2]}), "arrays keep their length")
