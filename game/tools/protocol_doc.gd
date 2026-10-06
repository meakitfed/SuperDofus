## Regenerates docs/PROTOCOL.md from Protocol.SCHEMA:
##   godot --headless --path game -s res://tools/protocol_doc.gd
## tests/test_protocol.gd fails while the file is stale.
extends SceneTree

const OUT := "res://../docs/PROTOCOL.md"


func _init() -> void:
	var path := ProjectSettings.globalize_path(OUT).simplify_path()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write " + path)
		quit(1)
		return
	f.store_string(ProtocolDoc.describe())
	print("wrote ", path)
	quit(0)
