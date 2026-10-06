## UI theme built from the Dofus 3 assets (tools/extractor/ui.py): Lexend fonts,
## HUD textures. Falls back to Godot's defaults when the content is missing.
class_name ClientTheme
extends RefCounted

static var _theme: Theme
static var _textures := {}


static func get_theme() -> Theme:
	if _theme == null:
		_theme = Theme.new()
		var font := load_font("Lexend-Medium")
		if font != null:
			_theme.default_font = font
		_theme.default_font_size = 15
		UiStyle.apply(_theme)
	return _theme


static func load_font(name: String) -> FontFile:
	var provider := DofusContent.get_provider()
	for ext in ["ttf", "otf"]:
		var path := "Content/Fonts/%s.%s" % [name, ext]
		if provider.exists(path):
			var f := FontFile.new()
			f.data = provider.read_bytes(path)
			return f
	return null


## Content/<rel_path_without_ext>.webp|png as a texture (cached), null if missing.
static func texture(rel_path_without_ext: String) -> Texture2D:
	if not _textures.has(rel_path_without_ext):
		var img := DofusContent.get_provider().load_image("Content/" + rel_path_without_ext)
		_textures[rel_path_without_ext] = ImageTexture.create_from_image(img) if img != null else null
	return _textures[rel_path_without_ext]
