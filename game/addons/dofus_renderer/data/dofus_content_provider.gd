## Abstract access to extracted content (`Content/...` layout produced by tools/extractor).
## Swap implementations to read from a folder, a .pck/.zip, or a remote CDN cache.
class_name DofusContentProvider
extends RefCounted


func exists(_rel_path: String) -> bool:
	return false


func read_bytes(_rel_path: String) -> PackedByteArray:
	return PackedByteArray()


func read_text(rel_path: String) -> String:
	return read_bytes(rel_path).get_string_from_utf8()


func read_json(rel_path: String) -> Variant:
	var text := read_text(rel_path)
	if text.is_empty():
		return null
	return JSON.parse_string(text)


## Loads `<rel_path_without_ext>.png` (or .webp) as an Image, null when missing.
func load_image(rel_path_without_ext: String) -> Image:
	for ext in ["png", "webp"]:
		var rel := "%s.%s" % [rel_path_without_ext, ext]
		if not exists(rel):
			continue
		var bytes := read_bytes(rel)
		var img := Image.new()
		var err := img.load_png_from_buffer(bytes) if ext == "png" else img.load_webp_from_buffer(bytes)
		if err == OK:
			return img
	return null


func list_dirs(_rel_path: String) -> PackedStringArray:
	return PackedStringArray()
