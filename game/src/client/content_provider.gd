## The renderer's content provider, backed by ContentSource (C.01): bones, skins, maps,
## fonts, textures and data tables come from res:// in dev and solo, or from the cache
## downloaded from a server, without the add-on knowing. The add-on stays standalone: it
## only knows its DofusContentProvider interface and the project setting
## `dofus_renderer/content_provider_script`, which points at this script.
##
## Layers, the first one holding a file wins: the enabled mods (mods/<id>/, same `Content/...`
## layout, see Mods), then content/.
class_name ContentSourceProvider
extends DofusContentProvider

const BASE := "content"

var _layers := PackedStringArray()


func _init() -> void:
	ContentSource.on_changed(_world_changed)


## The active world changed: the layers and everything the renderer cached are stale.
func _world_changed() -> void:
	_layers = PackedStringArray()
	if DofusContent.get_provider() == self: # not a throwaway instance (tests)
		DofusContent.set_provider(self)


func _prefixes() -> PackedStringArray:
	if _layers.is_empty():
		for id: Variant in Mods.enabled():
			var dir := "mods/%s" % str(id)
			if ContentSource.dir_exists(dir):
				_layers.append(dir)
		_layers.append(BASE)
	return _layers


## Logical path of `rel_path` in the first layer that has it, "" when none does.
func _find(rel_path: String) -> String:
	for prefix in _prefixes():
		var p := prefix + "/" + rel_path
		if ContentSource.exists(p):
			return p
	return ""


func exists(rel_path: String) -> bool:
	return _find(rel_path) != ""


func read_bytes(rel_path: String) -> PackedByteArray:
	var p := _find(rel_path)
	return ContentSource.read_bytes(p) if p != "" else PackedByteArray()


func read_text(rel_path: String) -> String:
	var p := _find(rel_path)
	return ContentSource.read_text(p) if p != "" else ""


func read_json(rel_path: String) -> Variant:
	var p := _find(rel_path)
	return ContentSource.read_json(p) if p != "" else null


func load_image(rel_path_without_ext: String) -> Image:
	for prefix in _prefixes():
		var img := ContentSource.load_image(prefix + "/" + rel_path_without_ext)
		if img != null:
			return img
	return null


func list_dirs(rel_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	for prefix in _prefixes():
		for d in ContentSource.list_dirs(prefix + "/" + rel_path):
			if not out.has(d):
				out.append(d)
	return out
