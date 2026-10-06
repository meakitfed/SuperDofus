## Several content roots seen as one: the first layer holding a file wins. Used for
## add-on content (mods) laid out like the extracted `Content/...` tree: new bones,
## skins… sit in their own folder and never touch the extracted data.
class_name DofusLayeredContentProvider
extends DofusContentProvider

var layers: Array[DofusContentProvider] = []


func _init(p_layers: Array[DofusContentProvider]) -> void:
	layers = p_layers


func _layer_of(rel_path: String) -> DofusContentProvider:
	for l in layers:
		if l.exists(rel_path):
			return l
	return null


func exists(rel_path: String) -> bool:
	return _layer_of(rel_path) != null


func read_bytes(rel_path: String) -> PackedByteArray:
	var l := _layer_of(rel_path)
	return l.read_bytes(rel_path) if l != null else PackedByteArray()


func read_text(rel_path: String) -> String:
	var l := _layer_of(rel_path)
	return l.read_text(rel_path) if l != null else ""


func load_image(rel_path_without_ext: String) -> Image:
	for l in layers:
		var img := l.load_image(rel_path_without_ext)
		if img != null:
			return img
	return null


func list_dirs(rel_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	for l in layers:
		for d in l.list_dirs(rel_path):
			if not out.has(d):
				out.append(d)
	return out
