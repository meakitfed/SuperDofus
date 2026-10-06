## Reads extracted content from a folder (absolute path, `res://` or `user://`).
class_name DofusFsContentProvider
extends DofusContentProvider

var root: String


func _init(p_root: String) -> void:
	# globalise so raw files under a .gdignore'd res:// folder load without import
	root = ProjectSettings.globalize_path(p_root).trim_suffix("/")


func _abs(rel_path: String) -> String:
	return "%s/%s" % [root, rel_path]


func exists(rel_path: String) -> bool:
	return FileAccess.file_exists(_abs(rel_path))


func read_bytes(rel_path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(_abs(rel_path))


func read_text(rel_path: String) -> String:
	return FileAccess.get_file_as_string(_abs(rel_path))


func load_image(rel_path_without_ext: String) -> Image:
	for ext in ["png", "webp"]:
		var path := "%s.%s" % [_abs(rel_path_without_ext), ext]
		if FileAccess.file_exists(path):
			var img := Image.new()
			if img.load(path) == OK:
				return img
	return null


func list_dirs(rel_path: String) -> PackedStringArray:
	return DirAccess.get_directories_at(_abs(rel_path))
