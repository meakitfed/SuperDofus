## Free space of the disk that holds a folder (roadmap C.03): Godot has no API for it, so the
## answer comes from the system (`dir` on Windows, `df` elsewhere). -1 = unknown (the download
## then starts anyway: the write itself reports a full disk). Not game logic.
class_name DiskSpace
extends RefCounted


## Free bytes on the disk of `path` (a user:// or absolute path, created if missing), or -1.
static func free_bytes(path: String) -> int:
	var abs := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(abs)
	var out := []
	if OS.get_name() == "Windows":
		# last line: "<n> dir(s) <free> bytes free" in the user's language; the numbers are enough
		if OS.execute("cmd", ["/c", "dir", "/-c", abs.replace("/", "\\")], out, true) != OK:
			return -1
		return parse_dir_output(str(out[0]) if not out.is_empty() else "")
	if OS.execute("df", ["-Pk", abs], out, true) != OK:
		return -1
	return parse_df_output(str(out[0]) if not out.is_empty() else "")


## The last number of the last non-empty line of `dir /-c`.
static func parse_dir_output(text: String) -> int:
	var lines := text.strip_edges().split("\n")
	if lines.is_empty():
		return -1
	var re := RegEx.create_from_string("\\d+")
	var last := -1
	for m in re.search_all(lines[lines.size() - 1]):
		last = int(m.get_string())
	var tail := lines[lines.size() - 1]
	# two numbers on the line (directories, free bytes): the free space is the last one
	return last if re.search_all(tail).size() >= 2 else -1


## `df -Pk`: 1024-blocks, the "Available" column of the last line, in bytes.
static func parse_df_output(text: String) -> int:
	var lines := text.strip_edges().split("\n")
	if lines.size() < 2:
		return -1
	var cols := lines[lines.size() - 1].split(" ", false)
	if cols.size() < 4 or not cols[3].is_valid_int():
		return -1
	return int(cols[3]) * 1024
