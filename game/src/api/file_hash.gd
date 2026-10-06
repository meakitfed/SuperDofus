## SHA-256 of a file on disk, read by blocks (roadmap C.02): the server hashes the files of a
## package with it, the content client verifies what it downloaded. Not game logic.
class_name FileHash
extends RefCounted

const BLOCK := 1024 * 1024


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
