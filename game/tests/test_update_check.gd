## Pure rules of the client self-update (roadmap X.02): release parsing, build comparison, swap script.
extends TestCase


func _release(tag: String, asset := "SuperDofus.exe", digest := "sha256:abc") -> String:
	return JSON.stringify({"tag_name": tag, "assets": [
		{"name": "notes.txt", "browser_download_url": "https://x/notes"},
		{"name": asset, "browser_download_url": "https://x/exe", "size": 12345, "digest": digest}]})


func test_tag_to_build() -> void:
	eq(UpdateCheck.build_of_tag("build-42"), 42)
	eq(UpdateCheck.build_of_tag("v1.2"), 0)
	eq(UpdateCheck.build_of_tag("build-x"), 0)


func test_parse_latest_release() -> void:
	var r := UpdateCheck.parse(_release("build-7"))
	eq(r["build"], 7)
	eq(r["url"], "https://x/exe")
	eq(r["size"], 12345)
	eq(r["sha256"], "abc")
	eq(UpdateCheck.parse(_release("build-7", "SuperDofus.exe", ""))["sha256"], "", "no digest: not checked")


func test_parse_refuses_what_is_not_a_client_release() -> void:
	eq(UpdateCheck.parse("not json"), {})
	eq(UpdateCheck.parse(_release("v1")), {})
	eq(UpdateCheck.parse(_release("build-7", "other.exe")), {}, "no client asset")
	eq(UpdateCheck.parse("{\"message\": \"Not Found\"}"), {})


func test_only_a_numbered_build_updates_to_a_newer_one() -> void:
	check(UpdateCheck.is_newer(5, 6))
	check(not UpdateCheck.is_newer(6, 6))
	check(not UpdateCheck.is_newer(7, 6))
	check(not UpdateCheck.is_newer(0, 6), "a dev build never self-updates")


func test_swap_script_moves_then_restarts() -> void:
	var s := UpdateCheck.swap_script("C:/Jeux/SuperDofus.exe", "C:/u/SuperDofus.exe")
	check(s.contains("move /Y \"C:\\u\\SuperDofus.exe\" \"C:\\Jeux\\SuperDofus.exe\""))
	check(s.contains("start \"\" \"C:\\Jeux\\SuperDofus.exe\""))
	check(s.find("move") < s.find("start"))
