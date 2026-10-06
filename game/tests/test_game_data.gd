## GameData: generic lazy access to Dofus 3 tables (docs/data_catalog.md).
extends TestCase

const FIXTURES: PackedStringArray = ["res://tests/fixtures/data/derived", "res://tests/fixtures/data/raw"]


func _with_fixtures(body: Callable) -> void:
	GameData.roots = FIXTURES
	GameData.clear_cache()
	body.call()
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()


func test_derived_table_wins_over_raw_content() -> void:
	_with_fixtures(func() -> void:
		eq(str(GameData.row("things", 1)["name"]), "derived", "first root wins")
		eq(GameData.row("things", 2), {}, "the derived copy is the whole table")
		eq(str(GameData.row("other", "7")["v"]), "only raw", "falls back to <name>dataroot.json, string ids too"))


func test_missing_or_broken_tables_do_not_crash() -> void:
	_with_fixtures(func() -> void:
		eq(GameData.table("nope"), {})
		check(not GameData.has_table("nope"))
		eq(GameData.row("nope", 1), {})
		eq(GameData.table("broken"), {}, "invalid JSON")
		eq(GameData.row("other", 999), {}, "missing row"))


func test_shipped_derived_tables() -> void:
	GameData.clear_cache()
	var breeds := GameData.table("breeds")
	eq(breeds.size(), 19, "breeds shipped in res://data/tables")
	check(str(GameData.row("breeds", 12).get("maleLook", "")).begins_with("{"), "Pandawa look")
	var rules := GameData.row("namingrules", 0)
	check(int(rules.get("maxLength", 0)) > 0, "naming rules shipped")
	eq(GameData.xp_floor(1), 0, "XP table still works")
