## `--check` of the server (roadmap X.01): what to verify before inviting friends. Reads the disk
## and tries the ports, never starts anything. Nothing here knows which game a world runs.
##
## Returns {ok: bool, lines: PackedStringArray}: one line per check, prefixed "OK", "WARN" (the
## server starts anyway) or "FAIL" (it would not).
class_name ServerCheck
extends RefCounted


## `root`: absolute folder holding worlds/, data/, content/. `http_port` 0 = no content API.
static func run(worlds: PackedStringArray, root: String, package_dir: String, save_dir: String,
		port: int, http_port: int) -> Dictionary:
	var lines := PackedStringArray()
	var ok := true
	for id in worlds:
		var def := root.path_join("worlds").path_join(id).path_join("world.json")
		if FileAccess.file_exists(def):
			lines.append("OK   monde %s : %s" % [id, def])
		else:
			lines.append("FAIL monde %s : %s introuvable" % [id, def])
			ok = false
	if DirAccess.dir_exists_absolute(root.path_join("data")):
		lines.append("OK   dossier data : " + root.path_join("data"))
	else:
		lines.append("FAIL dossier data absent : " + root.path_join("data"))
		ok = false
	if DirAccess.dir_exists_absolute(root.path_join("content")):
		lines.append("OK   dossier content : " + root.path_join("content"))
	else:
		lines.append("WARN dossier content absent : les mondes sans assets seulement")
	var test := _writable(save_dir)
	if test == "":
		lines.append("OK   sauvegardes : " + save_dir)
	else:
		lines.append("FAIL sauvegardes non inscriptibles (%s) : %s" % [save_dir, test])
		ok = false
	for id in worlds:
		var manifest := package_dir.path_join(id).path_join("manifest.json")
		if FileAccess.file_exists(manifest):
			lines.append("OK   paquet %s construit" % id)
		else:
			lines.append("WARN paquet %s pas encore construit (il le sera au demarrage, --build-packages pour le faire avant)" % id)
	for p in [port, http_port]:
		if int(p) <= 0:
			continue
		var tcp := TCPServer.new()
		var err := tcp.listen(int(p), "*")
		tcp.stop()
		if err == OK:
			lines.append("OK   port %d libre" % int(p))
		else:
			lines.append("FAIL port %d occupe (%s) : un autre serveur tourne deja ?" % [int(p), error_string(err)])
			ok = false
	return {"ok": ok, "lines": lines}


## "" when `dir` can be created and written, else the reason.
static func _writable(dir: String) -> String:
	var abs_dir := ProjectSettings.globalize_path(dir) if dir.begins_with("user://") else dir
	var err := DirAccess.make_dir_recursive_absolute(abs_dir)
	if err != OK:
		return error_string(err)
	var path := abs_dir.path_join(".check")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return error_string(FileAccess.get_open_error())
	f.store_string("ok")
	f.close()
	DirAccess.remove_absolute(path)
	return ""
