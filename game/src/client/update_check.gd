## Pure rules of the client self-update (roadmap X.02): reading the answer of GitHub's
## `releases/latest`, comparing builds, and the script that swaps the running exe for the new one.
## A release is tagged `build-<n>` (n = the CI run number) and carries `SuperDofus.exe`.
class_name UpdateCheck
extends RefCounted

const TAG_PREFIX := "build-"
const ASSET := "SuperDofus.exe"


static func latest_url(repo: String) -> String:
	return "https://api.github.com/repos/%s/releases/latest" % repo


## 12 for "build-12", 0 for anything else.
static func build_of_tag(tag: String) -> int:
	if not tag.begins_with(TAG_PREFIX):
		return 0
	var n := tag.substr(TAG_PREFIX.length())
	return int(n) if n.is_valid_int() else 0


## {build, url, size, sha256} of the newest release, {} when the answer is not a client release.
## `sha256` is "" when GitHub gave no digest for the asset.
static func parse(json_text: String) -> Dictionary:
	var json := JSON.new() # not parse_string: a bad answer must not print an engine error
	if json.parse(json_text) != OK or not json.data is Dictionary:
		return {}
	var data: Dictionary = json.data
	var build := build_of_tag(String(data.get("tag_name", "")))
	if build <= 0 or not data.get("assets") is Array:
		return {}
	for a: Variant in data["assets"]:
		if a is Dictionary and a.get("name") == ASSET:
			var digest := String(a.get("digest", ""))
			return {
				"build": build,
				"url": String(a.get("browser_download_url", "")),
				"size": int(a.get("size", 0)),
				"sha256": digest.trim_prefix("sha256:") if digest.begins_with("sha256:") else "",
			}
	return {}


## A dev build (0) never updates.
static func is_newer(current: int, latest: int) -> bool:
	return current > 0 and latest > current


## Batch file run after the game quit: moves `new_exe` over `exe` (retries while the old process
## still locks it, about 30 s), starts the new one, then deletes itself.
static func swap_script(exe: String, new_exe: String) -> String:
	var e := exe.replace("/", "\\")
	var n := new_exe.replace("/", "\\")
	return "\r\n".join([
		"@echo off",
		"set tries=0",
		":retry",
		"set /a tries+=1",
		"move /Y \"%s\" \"%s\" >nul 2>&1" % [n, e],
		"if not errorlevel 1 goto done",
		"if %tries% geq 30 exit /b 1",
		"ping -n 2 127.0.0.1 >nul",
		"goto retry",
		":done",
		"start \"\" \"%s\"" % e,
		"(goto) 2>nul & del \"%~f0\"",
		"",
	])
