## The audit file of the server (A1.01): one JSON object per line, appended for every GM
## command (accepted or refused): {at (unix ms), world, account, name, cmd, args, ok, code}.
## Written by whoever hosts the sims (WorldAdmin.audit_sink = log.append), never read by the
## game. Never holds a password: GM commands carry none. Not used by sim/, shared/ or client/.
class_name AuditLog
extends RefCounted

var path := ""
## entries written since the start (for logs and tests)
var written := 0


func _init(p_path: String) -> void:
	path = p_path
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())


func append(entry: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f == null:
		push_error("audit: cannot write %s" % path)
		return
	f.seek_end()
	f.store_line(JSON.stringify(entry))
	written += 1


## The entries of the file (oldest first); lines that are not JSON objects are skipped.
func read_all() -> Array:
	var out := []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line := f.get_line()
		var parsed: Variant = JSON.parse_string(line) if line != "" else null
		if parsed is Dictionary:
			out.append(parsed)
	return out
