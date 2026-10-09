## SHA-256 of a file on disk, read by blocks (roadmap C.02): the server hashes the files of a
## package with it, the content client verifies what it downloaded. Not game logic.
class_name FileHash
extends RefCounted

const BLOCK := 1024 * 1024


## Size of a file in bytes, -1 when it does not exist. NEVER opens the file: on Windows an open makes the
## antivirus scan the content (8 to 20 ms a file when cold, measured), a stat costs 0.05 ms. Use it, and
## `FileAccess.get_modified_time`, for every "is it there / has it changed" question over many files.
static func size_of(path: String) -> int:
	if FileAccess.get_modified_time(path) == 0 and not FileAccess.file_exists(path):
		return -1
	return FileAccess.get_size(path)


## Hex SHA-256 of the file, "" if it cannot be read.
static func sha256(abs_path: String) -> String:
	var f := FileAccess.open(abs_path, FileAccess.READ)
	if f == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	while not f.eof_reached():
		var chunk := f.get_buffer(BLOCK)
		if chunk.is_empty():
			break
		ctx.update(chunk)
	return ctx.finish().hex_encode()
