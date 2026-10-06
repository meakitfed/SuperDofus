## Self-update of the exported client (roadmap X.02). `start()` asks GitHub for the latest release;
## when its build is newer than `BuildInfo.BUILD` the new exe is downloaded to user://update/, checked
## against the release digest, and `apply()` quits the game after launching UpdateCheck.swap_script.
## Only an exported Windows client with a numbered build updates; `--no-update` turns it off.
class_name SelfUpdater
extends Node

signal status(text: String)
## the new exe is on disk and verified: the owner calls apply()
signal ready_to_apply

const DIR := "user://update"
const NEW_EXE := "user://update/SuperDofus.exe"

var current_build := BuildInfo.BUILD
var latest := {}
var _check: HTTPRequest
var _download: HTTPRequest
var _progress := false


static func enabled(opts: Dictionary) -> bool:
	return BuildInfo.BUILD > 0 and not OS.has_feature("editor") and OS.get_name() == "Windows" \
		and not opts.has("no-update")


func start() -> void:
	_check = HTTPRequest.new()
	add_child(_check)
	_check.request_completed.connect(_on_checked)
	if _check.request(UpdateCheck.latest_url(BuildInfo.REPO), ["Accept: application/vnd.github+json"]) != OK:
		status.emit("") # offline: play on, ask again at the next launch


func _on_checked(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		status.emit("")
		return
	latest = UpdateCheck.parse(body.get_string_from_utf8())
	if latest.is_empty() or not UpdateCheck.is_newer(current_build, int(latest["build"])):
		status.emit("")
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	_download = HTTPRequest.new()
	_download.download_file = ProjectSettings.globalize_path(NEW_EXE)
	add_child(_download)
	_download.request_completed.connect(_on_downloaded)
	if _download.request(String(latest["url"])) != OK:
		status.emit("")
		return
	_progress = true
	status.emit("Mise à jour %d en cours…" % int(latest["build"]))


func _process(_delta: float) -> void:
	if _progress and _download != null:
		var total := _download.get_body_size()
		if total > 0:
			status.emit("Mise à jour %d : %d %%" % [int(latest["build"]), 100 * _download.get_downloaded_bytes() / total])


func _on_downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_progress = false
	var path := ProjectSettings.globalize_path(NEW_EXE)
	var want := String(latest.get("sha256", ""))
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 \
			or (want != "" and FileAccess.get_sha256(path) != want):
		DirAccess.remove_absolute(path)
		status.emit("Mise à jour impossible (téléchargement), réessai au prochain lancement.")
		return
	status.emit("Redémarrage…")
	ready_to_apply.emit()


## Launches the swap script and quits: the script returns once the exe is replaced and restarts the game.
func apply() -> void:
	var script := ProjectSettings.globalize_path(DIR + "/swap.bat")
	var f := FileAccess.open(script, FileAccess.WRITE)
	if f == null:
		status.emit("Mise à jour impossible (écriture).")
		return
	f.store_string(UpdateCheck.swap_script(OS.get_executable_path(), ProjectSettings.globalize_path(NEW_EXE)))
	f.close()
	OS.create_process("cmd.exe", ["/c", script])
	get_tree().quit()
