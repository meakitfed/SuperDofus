## The single layer through which the engine reads the DATA and the ASSETS of a world
## (C.01, docs/PLAN_SERVEUR.md). Nobody else opens res://content, res://data or
## res://worlds: not the client, not the sim (through DataFiles), not the renderer (through
## its injected provider, client/content_provider.gd).
##
## Logical paths, relative to the game root, whatever the root is:
##   content/...        extracted assets (Content/Data, Characters, Picto, Fonts, Maps...)
##   data/...           light generated tables (spells.json, items.json, tables/...)
##   worlds/<id>/...    the definition of a world (world.json, maps, quests...)
##   mods/...           add-on content
## A path that already has a scheme (res://, user://) or is absolute is a physical path
## and goes through untouched (test fixtures).
##
## Two roots:
##   dev    res://<logical path>: development and solo play (the default, nothing changes);
##   cache  user://worlds/<id>/ : what the client downloaded from a server (C.02 / C.03). It
##          mirrors the logical layout (content/, data/, mods/) and holds the active world's
##          definition in world/ (logical worlds/<id>/x is the file world/x). Its presence is
##          marked by manifest.json. The cache holds raw PNG / WebP / JSON, never .import files:
##          images are decoded with Image.load_from_file.
## `use_world(id)` selects the active world: as long as it has no cache, the dev root answers.
## A ready cache answers alone (a file it lacks is missing, never silently read from res://).
##
## A world is data: nothing in here knows what the game is.
class_name ContentSource
extends RefCounted

const DEV_ROOT := "res://"
const CACHE_BASE := "user://worlds"
const MANIFEST := "manifest.json"
const IMAGE_EXTENSIONS: PackedStringArray = ["png", "webp"]
## logical roots a cache mirrors as they are
const MIRRORED: PackedStringArray = ["content", "data", "mods"]

static var _base := CACHE_BASE # where the caches of the downloaded worlds live (C.04: any folder)
static var _world := ""
static var _cache := "" # physical cache folder of the active world, "" = dev root
static var _dev_abs := "" # DEV_ROOT on disk (raw files under .gdignore'd folders load without import)
static var _changed: Array[Callable] = []
static var _trace := {} # logical path -> true while tracing (tools: which files a run reads)
static var _tracing := false


## Selects the active world and its cache (`cache_base`/<id>/, default user://worlds). The
## dev root answers while that cache has no manifest. Drops every table the old world loaded.
static func use_world(id: String, cache_base := "") -> void:
	var dir := cache_dir_for(id, cache_base)
	var cache := dir if id != "" and FileAccess.file_exists(dir.path_join(MANIFEST)) else ""
	var changed := cache != _cache
	_world = id
	_cache = cache
	if changed: # same root (dev): what the readers cached is not stale
		_notify()


## X.01: moves the dev root to a folder on disk (absolute path holding content/, data/, worlds/,
## mods/). An exported server has none of them in its PCK: they sit beside the executable.
## "" restores res://. Drops what the readers cached when the root changes.
static func set_dev_root(abs_dir: String) -> void:
	var root := abs_dir.replace("\\", "/").trim_suffix("/")
	if root == "":
		root = ProjectSettings.globalize_path(DEV_ROOT).trim_suffix("/")
	if root == _dev_abs:
		return
	_dev_abs = root
	if _cache == "":
		_notify()


## The dev root on disk (what `resolve` uses without a cache).
static func dev_root() -> String:
	if _dev_abs == "":
		_dev_abs = ProjectSettings.globalize_path(DEV_ROOT).trim_suffix("/")
	return _dev_abs


## Back to the dev root (res://), no active world.
static func use_dev() -> void:
	var changed := _cache != ""
	_world = ""
	_cache = ""
	if changed:
		_notify()


static func world() -> String:
	return _world


static func using_cache() -> bool:
	return _cache != ""


## The physical folder of the cache of the active world ("" on the dev root).
static func cache_dir() -> String:
	return _cache


## C.04: the folder that holds the caches of all the downloaded worlds (default user://worlds; the
## player may point it anywhere, D:/Games/...). Nothing is moved by this call.
static func set_cache_base(path: String) -> void:
	_base = path.replace("\\", "/").trim_suffix("/") if path.strip_edges() != "" else CACHE_BASE


static func cache_base() -> String:
	return _base


## Cache folder where `world_id` is (to be) downloaded; `cache_base` "" = the configured folder.
static func cache_dir_for(world_id: String, cache_base := "") -> String:
	return (_base if cache_base == "" else cache_base).path_join(world_id)


## Where a logical path of `world_id`'s package goes inside its cache folder (the layout the
## header describes), "" if the path is not part of a package of that world.
static func cache_relative(path: String, world_id: String) -> String:
	var first := path.get_slice("/", 0)
	if MIRRORED.has(first):
		return path
	var prefix := "worlds/%s/" % world_id
	if path.begins_with(prefix) and path.length() > prefix.length():
		return "world/" + path.substr(prefix.length())
	return ""


## C.02b: records every logical path asked of `resolve` until `trace_stop` (a tool compares them with
## the package of a world: WorldAssets.uncovered). Off by default; costs nothing then.
static func trace_start() -> void:
	_trace.clear()
	_tracing = true


## The logical paths asked since `trace_start`, sorted.
static func trace_stop() -> PackedStringArray:
	_tracing = false
	var out := PackedStringArray(_trace.keys())
	out.sort()
	_trace.clear()
	return out


## Called after the active world changed (renderer caches, tables...). Not thread safe: set up
## once at startup.
static func on_changed(cb: Callable) -> void:
	if not _changed.has(cb):
		_changed.append(cb)


## res://<logical path>: where tools WRITE generated data (reads never use it).
static func dev_path(logical: String) -> String:
	return DEV_ROOT + logical


## Physical path of a logical one on the active root.
static func resolve(path: String) -> String:
	if path.contains("://") or path.is_absolute_path():
		return path
	if _tracing:
		_trace[path] = true
	if _cache == "":
		return _dev(path)
	var first := path.get_slice("/", 0)
	if MIRRORED.has(first):
		return _cache.path_join(path)
	if first == "worlds":
		var parts := path.split("/", false, 2)
		if parts.size() >= 2 and parts[1] == _world:
			return _cache.path_join("world").path_join(parts[2] if parts.size() > 2 else "")
	return _cache.path_join("unavailable").path_join(path) # not part of this world's package


static func exists(path: String) -> bool:
	return FileAccess.file_exists(resolve(path))


static func dir_exists(path: String) -> bool:
	return DirAccess.dir_exists_absolute(resolve(path))


static func read_bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(resolve(path))


static func read_text(path: String) -> String:
	return FileAccess.get_file_as_string(resolve(path))


## {ok, data (PackedByteArray), error}: a missing file says which logical file and where it
## looked, so a bad cache or a bad path is found at the source.
static func read_result(path: String) -> Dictionary:
	var phys := resolve(path)
	if not FileAccess.file_exists(phys):
		return {"ok": false, "data": PackedByteArray(), "error": "ContentSource: file not found: %s (looked in %s)" % [path, phys]}
	return {"ok": true, "data": FileAccess.get_file_as_bytes(phys), "error": ""}


## Parsed JSON, or null when the file is missing or invalid (invalid = push_error).
static func read_json(path: String) -> Variant:
	var phys := resolve(path)
	if not FileAccess.file_exists(phys):
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(phys)) != OK:
		push_error("ContentSource: invalid JSON in %s (line %d: %s)" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


## `<path_without_ext>.png` or `.webp` as an Image, null when missing or unreadable.
static func load_image(path_without_ext: String) -> Image:
	for ext in IMAGE_EXTENSIONS:
		var img := _image("%s.%s" % [path_without_ext, ext])
		if img != null:
			return img
	return null


## Same, with the extension in the path.
static func load_image_file(path: String) -> Image:
	return _image(path)


static func load_texture(path_without_ext: String) -> Texture2D:
	var img := load_image(path_without_ext)
	return ImageTexture.create_from_image(img) if img != null else null


## An imported Godot resource of the game itself (scenes, .tres) is not content: it stays in
## the project. Kept here for the raw-image case: PNG / WebP paths become a texture.
static func load_resource(path: String) -> Resource:
	if IMAGE_EXTENSIONS.has(path.get_extension().to_lower()):
		var img := _image(path)
		return ImageTexture.create_from_image(img) if img != null else null
	var phys := resolve(path)
	return ResourceLoader.load(phys) if ResourceLoader.exists(phys) else null


static func list_files(path: String) -> PackedStringArray:
	return DirAccess.get_files_at(resolve(path))


static func list_dirs(path: String) -> PackedStringArray:
	return DirAccess.get_directories_at(resolve(path))


static func _image(path: String) -> Image:
	var phys := resolve(path)
	if not FileAccess.file_exists(phys):
		return null
	var img := Image.load_from_file(phys)
	return img


static func _dev(path: String) -> String:
	if _dev_abs == "":
		_dev_abs = ProjectSettings.globalize_path(DEV_ROOT).trim_suffix("/")
	return _dev_abs.path_join(path)


static func _notify() -> void:
	GameData.clear_cache()
	SpellBook.reload()
	_changed = _changed.filter(func(cb: Callable) -> bool: return cb.is_valid()) # an owner freed since
	for cb in _changed:
		cb.call()
