## The look of every window and widget (Dofus 3 "darkStone" theme): one
## palette, the stylebox factories, and the real UI textures (extracted with
## tools/extractor/ui.py under Content/UI). Widgets never hard-code colours.
class_name UiStyle
extends RefCounted

const BG := Color(0.094, 0.098, 0.106, 0.96)
const BG_HEADER := Color(0.13, 0.135, 0.145, 1.0)
const BG_INSET := Color(0.06, 0.063, 0.07, 0.9)
const BORDER := Color(0.27, 0.26, 0.24, 1.0)
const BORDER_LIGHT := Color(0.42, 0.40, 0.36, 1.0)
const TEXT := Color(0.92, 0.89, 0.83)
const TEXT_MUTED := Color(0.62, 0.60, 0.56)
const GOLD := Color(0.93, 0.74, 0.33)
const KAMAS := Color(1.0, 0.85, 0.4)
const XP := Color(0.33, 0.64, 1.0)
const HP := Color(0.89, 0.36, 0.33)
const ENERGY := Color(0.96, 0.78, 0.22)
## a ghost (Energy.GHOST): pale, see-through
const GHOST := Color(0.72, 0.88, 1.0, 0.55)
## resurrection phoenix (map glow, world map markers)
const PHOENIX := Color(1.0, 0.45, 0.2)
const GOOD := Color(0.58, 0.83, 0.33)
const BAD := Color(1.0, 0.42, 0.36)
const AP := Color(0.36, 0.62, 1.0)
const MP := Color(0.45, 0.82, 0.38)
const ELEMENTS := {"neutral": Color(0.8, 0.8, 0.8), "earth": Color(0.72, 0.5, 0.25), "fire": Color(1.0, 0.45, 0.25),
		"water": Color(0.35, 0.65, 1.0), "air": Color(0.45, 0.85, 0.4)}

const SLOT_EMPTY := "UI/darkStone/texture/slot/inventoryEmptySlot"
const SLOT_OVER := "UI/darkStone/texture/slot/over"
const SLOT_SELECTED := "UI/darkStone/texture/slot/selected"
## monster group stars (empty / full)
const STAR_EMPTY := "UI/darkStone/texture/star0"
const STAR_FULL := "UI/darkStone/texture/star1"


static func panel(bg := BG, border := BORDER, radius := 6, margin := 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 6 if bg.a > 0.9 else 0
	return s


static func header() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = BG_HEADER
	s.border_color = BORDER
	s.border_width_bottom = 1
	s.corner_radius_top_left = 6
	s.corner_radius_top_right = 6
	s.content_margin_left = 14
	s.content_margin_right = 6
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


static func button(state := "normal") -> StyleBoxFlat:
	var bg := {"normal": Color(0.19, 0.195, 0.205), "hover": Color(0.25, 0.255, 0.265),
			"pressed": Color(0.33, 0.28, 0.17), "disabled": Color(0.13, 0.13, 0.14)}
	var s := panel(bg.get(state, bg["normal"]), GOLD if state == "pressed" else BORDER_LIGHT, 4, 6)
	s.shadow_size = 0
	s.content_margin_left = 12
	s.content_margin_right = 12
	return s


static func bar_fill(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(3)
	return s


static func bar_bg() -> StyleBoxFlat:
	var s := panel(BG_INSET, BORDER, 3, 0)
	s.shadow_size = 0
	return s


## A real Dofus UI texture, or null (content not extracted).
static func texture(path: String) -> Texture2D:
	return ClientTheme.texture(path)


## Label in the theme font, with a colour and size.
static func label(text: String, color := TEXT, size := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	return l


## An icon (UI texture) tinted, e.g. the monochrome btnIcon / menuIcons.
static func icon(path: String, size := 20, tint := TEXT) -> TextureRect:
	var r := TextureRect.new()
	r.texture = texture(path)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(size, size)
	r.modulate = tint
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Dofus i18n text without its markup ("{{spell,24036,1::Saoul}}" -> "Saoul", <color=…> tags dropped).
static func plain_text(s: String) -> String:
	var re := RegEx.create_from_string("\\{\\{[^}]*::([^}]*)\\}\\}")
	s = re.sub(s, "$1", true)
	return RegEx.create_from_string("<[^>]*>").sub(s, "", true).strip_edges()


## "12 345" (Dofus style thousands).
static func thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## Applied once to ClientTheme: every Button, ProgressBar, tooltip… gets the look.
static func apply(theme: Theme) -> void:
	for st in ["normal", "hover", "pressed", "disabled"]:
		theme.set_stylebox(st, "Button", button(st))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", GOLD)
	theme.set_color("font_disabled_color", "Button", TEXT_MUTED * Color(1, 1, 1, 0.6))
	theme.set_color("font_color", "Label", TEXT)
	theme.set_stylebox("background", "ProgressBar", bar_bg())
	theme.set_stylebox("fill", "ProgressBar", bar_fill(XP))
	theme.set_stylebox("panel", "TooltipPanel", panel(Color(0.07, 0.072, 0.08, 0.97), BORDER_LIGHT, 5, 8))
	theme.set_color("font_color", "TooltipLabel", TEXT)
	theme.set_stylebox("panel", "PanelContainer", panel())
	theme.set_stylebox("panel", "PopupMenu", panel(Color(0.07, 0.072, 0.08, 0.97), BORDER_LIGHT, 5, 4))
	theme.set_stylebox("hover", "PopupMenu", bar_fill(Color(0.25, 0.23, 0.18)))
	theme.set_color("font_color", "PopupMenu", TEXT)
	theme.set_color("font_hover_color", "PopupMenu", GOLD)
