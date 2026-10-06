## Read-only access to the static game data for shared/ and sim/ (data/, worlds/<id>/,
## extracted tables). Since C.01 it reads through ContentSource, so the standalone game, the
## server and a client with a downloaded world cache read the same bytes. Paths are logical
## ("data/spells.json", "worlds/dofus/npcs.json"). Anything written (characters, accounts...)
## goes through Persistence, never here.
class_name DataFiles
extends RefCounted


## Parsed JSON, or null when the file is missing or invalid.
static func read_json(path: String) -> Variant:
	return ContentSource.read_json(path)
