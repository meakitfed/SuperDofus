## The look of every window and widget (Dofus 3 "darkStone" theme): one
## palette, the stylebox factories, and the real UI textures (extracted with
## tools/extractor/ui.py under Content/UI). Widgets never hard-code colours.
class_name UiStyle
extends RefCounted

## Surfaces: three levels of depth (window, raised block, hollow inset) and the header.
const BG := Color(0.09, 0.094, 0.104, 0.97)
const BG_RAISED := Color(0.145, 0.15, 0.164, 1.0)
const BG_HEADER := Color(0.125, 0.13, 0.145, 1.0)
const BG_INSET := Color(0.055, 0.058, 0.066, 0.92)
const BORDER := Color(0.27, 0.26, 0.24, 1.0)
const BORDER_LIGHT := Color(0.44, 0.42, 0.38, 1.0)
## Text: three levels (main, secondary, disabled), all AA (4.5:1) on BG / BG_RAISED / BG_INSET.
const TEXT := Color(0.93, 0.91, 0.86)
const TEXT_MUTED := Color(0.67, 0.65, 0.61)
const TEXT_DISABLED := Color(0.5, 0.49, 0.47)
## text on an accent-coloured fill (primary button)
const TEXT_ON_ACCENT := Color(0.13, 0.095, 0.03)
## Accent (gold): titles, selection, primary action; FOCUS is the keyboard focus ring.
const GOLD := Color(0.93, 0.74, 0.33)
const ACCENT := GOLD
const ACCENT_DIM := Color(0.62, 0.48, 0.2)
const FOCUS := Color(1.0, 0.88, 0.5)
const KAMAS := Color(1.0, 0.85, 0.4)
const XP := Color(0.33, 0.64, 1.0)
const HP := Color(0.93, 0.42, 0.39)
const ENERGY := Color(0.96, 0.78, 0.22)
## a ghost (Energy.GHOST): pale, see-through
const GHOST := Color(0.72, 0.88, 1.0, 0.55)
## resurrection phoenix (map glow, world map markers)
const PHOENIX := Color(1.0, 0.45, 0.2)
## the dim behind a modal question
const SCRIM := Color(0.02, 0.02, 0.03, 0.6)
const SHADOW := Color(0, 0, 0, 0.45)
## Type scale (px at the 1280x720 design screen) and the Lexend weight of each role.
const FS_TITLE := 18
const FS_HEADING := 15
const FS_BODY := 14
const FS_SMALL := 12
const FS_TINY := 11
## Shape and motion.
const RADIUS := 6
const RADIUS_SMALL := 4
const T_FAST := 0.08
const T_BASE := 0.14
## theme type variations (Button.theme_type_variation, Label.theme_type_variation)
const V_PRIMARY := "ButtonPrimary"
const V_DANGER := "ButtonDanger"
const V_TAB := "ButtonTab"
const V_TITLE := "LabelTitle"
const V_HEADING := "LabelHeading"
const V_MUTED := "LabelMuted"
## tactical mode (MapView): background, free cells (two tones), obstacles, exits, doors
const TACTICAL_BG := Color(0.13, 0.15, 0.18)
const TACTICAL_FREE := [Color(0.34, 0.40, 0.46), Color(0.29, 0.35, 0.41)]
const TACTICAL_WALL := Color(0.08, 0.09, 0.11)
const TACTICAL_EXIT := Color(0.4, 1.0, 0.4)
const TACTICAL_DOOR := Color(0.3, 0.6, 1.0)
## a veil over a slot whose item cannot be used yet (level too low)
const VEIL := Color(0.75, 0.1, 0.08, 0.32)
## list rows (UiRow): hovered, chosen
const ROW_HOVER := Color(0.105, 0.11, 0.125, 0.96)
const ROW_SELECTED := Color(0.16, 0.14, 0.095, 0.98)
## world map (WorldMapView): ground behind the tiles and the markers
const MAP_BG := Color(0.05, 0.06, 0.08)
const MAP_ZAAP := Color(0.3, 0.95, 0.85)
const MAP_PLAYER := Color(1.0, 0.35, 0.25)
const MAP_OUTLINE := Color(0, 0, 0)
const MAP_CURSOR := Color(1, 1, 1)
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


static var _fonts := {}


## A surface: fill, 1px border, rounded, a soft drop shadow when it floats (opaque fills).
static func panel(bg := BG, border := BORDER, radius := RADIUS, margin := 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	s.shadow_color = SHADOW
	s.shadow_size = 10 if bg.a > 0.9 else 0
	s.shadow_offset = Vector2(0, 3)
	return s


## Window title bar: slightly lighter, a thin accent line under it.
static func header() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = BG_HEADER
	s.border_color = ACCENT_DIM
	s.border_width_bottom = 2
	s.corner_radius_top_left = RADIUS
	s.corner_radius_top_right = RADIUS
	s.content_margin_left = 14
	s.content_margin_right = 6
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


## state: normal / hover / pressed / disabled. variant: "" (neutral), V_PRIMARY (gold fill), V_DANGER.
static func button(state := "normal", variant := "") -> StyleBoxFlat:
	var bg := {"normal": Color(0.20, 0.205, 0.22), "hover": Color(0.27, 0.275, 0.295),
			"pressed": Color(0.15, 0.145, 0.13), "disabled": Color(0.13, 0.133, 0.142)}
	var edge := {"normal": BORDER_LIGHT, "hover": ACCENT_DIM, "pressed": ACCENT, "disabled": BORDER}
	var fill: Color = bg[state]
	var line: Color = edge[state]
	if variant == V_PRIMARY and state != "disabled":
		fill = {"normal": GOLD, "hover": GOLD.lightened(0.18), "pressed": GOLD.darkened(0.18)}[state]
		line = GOLD.lightened(0.3) if state == "hover" else ACCENT_DIM
	elif variant == V_DANGER and state != "disabled":
		fill = {"normal": Color(0.3, 0.13, 0.12), "hover": Color(0.4, 0.17, 0.15), "pressed": Color(0.22, 0.1, 0.09)}[state]
		line = BAD.darkened(0.25)
	var s := panel(fill, line, RADIUS_SMALL, 6)
	s.shadow_size = 0
	s.content_margin_left = 14
	s.content_margin_right = 14
	if state == "normal" and variant != "":
		s.border_width_bottom = 2
	return s


## A list row: inset, lighter when hovered, gold edge when chosen.
static func row(state := "normal") -> StyleBoxFlat:
	var s := panel({"normal": BG_INSET, "hover": ROW_HOVER, "selected": ROW_SELECTED}[state],
			{"normal": BORDER, "hover": ACCENT_DIM, "selected": ACCENT}[state], RADIUS_SMALL, 6)
	s.shadow_size = 0
	return s


## A small square button (+, -, x): the neutral look with tight side margins.
static func compact(b: Button, min_width := 30) -> void:
	for st in ["normal", "hover", "pressed", "disabled"]:
		var box := button(st)
		box.content_margin_left = 6
		box.content_margin_right = 6
		b.add_theme_stylebox_override(st, box)
	b.custom_minimum_size = Vector2(min_width, 0)


## A tab: flat, a gold underline when it is the current one.
static func tab(state := "normal") -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = {"normal": Color(0, 0, 0, 0), "hover": Color(1, 1, 1, 0.06), "pressed": Color(1, 1, 1, 0.04),
			"disabled": Color(0, 0, 0, 0)}[state]
	s.border_color = ACCENT if state == "pressed" else Color(0, 0, 0, 0)
	s.border_width_bottom = 3
	s.set_corner_radius_all(RADIUS_SMALL)
	s.corner_radius_bottom_left = 0
	s.corner_radius_bottom_right = 0
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 6
	s.content_margin_bottom = 4
	return s


## The keyboard focus ring: an outline over whatever has the focus, nothing inside.
static func focus_ring(radius := RADIUS_SMALL) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.border_color = FOCUS
	s.set_border_width_all(2)
	s.set_corner_radius_all(radius)
	s.expand_margin_left = 1
	s.expand_margin_right = 1
	s.expand_margin_top = 1
	s.expand_margin_bottom = 1
	return s


## Gauge fill: the colour with a lighter top edge so it reads as lit from above.
static func bar_fill(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = color.lightened(0.35)
	s.border_width_top = 1
	s.set_corner_radius_all(3)
	return s


static func bar_bg() -> StyleBoxFlat:
	var s := panel(BG_INSET, BORDER, 3, 0)
	s.shadow_size = 0
	return s


## A real Dofus UI texture, or null (content not extracted).
static func texture(path: String) -> Texture2D:
	return ClientTheme.texture(path)


## Lexend weight for a role: "title" (bold), "heading" (semi-bold), "body" (medium, the default).
static func font(role := "body") -> Font:
	if not _fonts.has(role):
		var name := {"title": "Lexend-Bold", "heading": "Lexend-SemiBold"}.get(role, "Lexend-Medium") as String
		_fonts[role] = ClientTheme.load_font(name)
	return _fonts[role]


## Label in the theme font, with a colour and size.
static func label(text: String, color := TEXT, size := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	return l


## Window / section title (bold, gold), block heading (semi-bold) and secondary text.
static func title(text: String, size := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.theme = ClientTheme.get_theme() # a tooltip popup does not inherit it
	l.theme_type_variation = V_TITLE
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	return l


static func heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme = ClientTheme.get_theme() # a tooltip popup does not inherit it
	l.theme_type_variation = V_HEADING
	return l


static func muted(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme = ClientTheme.get_theme() # a tooltip popup does not inherit it
	l.theme_type_variation = V_MUTED
	return l


## Contrast ratio (WCAG) of two colours, the alpha of `fg` composited on `bg`.
static func contrast(fg: Color, bg: Color) -> float:
	var f := Color(bg, 1.0).lerp(Color(fg, 1.0), fg.a)
	var a := _luminance(f)
	var b := _luminance(Color(bg, 1.0))
	return (maxf(a, b) + 0.05) / (minf(a, b) + 0.05)


static func _luminance(c: Color) -> float:
	return 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b)


static func _lin(v: float) -> float:
	return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)


## Hover / selection frame of a slot (ItemSlot, SpellSlot): the Dofus textures, a soft accent ring that
## fades with `hover` (0..1, tweened by the slot) and a solid gold ring when selected.
static func draw_slot_frame(c: CanvasItem, r: Rect2, hover: float, selected: bool) -> void:
	if selected:
		var tex := texture(SLOT_SELECTED)
		if tex != null:
			c.draw_texture_rect(tex, r, false)
		c.draw_style_box(ring(ACCENT, 2, 5), r)
	elif hover > 0.01:
		var tex := texture(SLOT_OVER)
		if tex != null:
			c.draw_texture_rect(tex, r, false, Color(1, 1, 1, hover))
		c.draw_style_box(ring(Color(ACCENT_DIM, hover), 1, 5), r)


static func ring(color: Color, width: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.border_color = color
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	return s


## Tweens `hover` (0..1) of a slot towards `to` (instant in headless runs).
static func ease_hover(c: Control, from: float, to: float, setter: Callable) -> void:
	if DisplayServer.get_name() == "headless" or not c.is_inside_tree():
		setter.call(to)
		return
	var tw := c.create_tween()
	tw.tween_method(setter, from, to, T_FAST)


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


## Applied once to ClientTheme: every Button, ProgressBar, tooltip, line edit... gets the look.
static func apply(theme: Theme) -> void:
	for type in [V_PRIMARY, V_DANGER, V_TAB]:
		theme.set_type_variation(type, "Button")
	for st in ["normal", "hover", "pressed", "disabled"]:
		theme.set_stylebox(st, "Button", button(st))
		theme.set_stylebox(st, V_PRIMARY, button(st, V_PRIMARY))
		theme.set_stylebox(st, V_DANGER, button(st, V_DANGER))
		theme.set_stylebox(st, V_TAB, tab(st))
	theme.set_stylebox("hover_pressed", V_TAB, tab("pressed"))
	theme.set_stylebox("hover_pressed", "Button", button("pressed"))
	for type in ["Button", V_PRIMARY, V_DANGER, V_TAB, "CheckBox", "OptionButton", "LineEdit", "TextEdit"]:
		theme.set_stylebox("focus", type, focus_ring())
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", GOLD)
	theme.set_color("font_hover_pressed_color", "Button", GOLD)
	theme.set_color("font_focus_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", TEXT_DISABLED)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		theme.set_color(c, V_PRIMARY, TEXT_ON_ACCENT)
		theme.set_color(c, V_DANGER, Color(1.0, 0.82, 0.79))
	theme.set_color("font_disabled_color", V_PRIMARY, TEXT_DISABLED)
	theme.set_color("font_color", V_TAB, TEXT_MUTED)
	theme.set_color("font_hover_color", V_TAB, TEXT)
	theme.set_color("font_pressed_color", V_TAB, GOLD)
	theme.set_color("font_hover_pressed_color", V_TAB, GOLD)
	theme.set_color("font_focus_color", V_TAB, TEXT)
	if font("heading") != null:
		theme.set_font("font", V_TAB, font("heading"))
	theme.set_color("font_color", "Label", TEXT)
	# text roles: title (gold, bold), heading (semi-bold), muted (secondary)
	for t: Array in [[V_TITLE, "title", FS_TITLE, GOLD], [V_HEADING, "heading", FS_HEADING, TEXT], [V_MUTED, "body", FS_SMALL + 1, TEXT_MUTED]]:
		theme.set_type_variation(t[0], "Label")
		if font(t[1]) != null:
			theme.set_font("font", t[0], font(t[1]))
		theme.set_font_size("font_size", t[0], t[2])
		theme.set_color("font_color", t[0], t[3])
	theme.set_stylebox("background", "ProgressBar", bar_bg())
	theme.set_stylebox("fill", "ProgressBar", bar_fill(XP))
	var tip := panel(Color(0.065, 0.068, 0.076, 0.98), BORDER_LIGHT, 5, 9)
	tip.shadow_size = 8
	theme.set_stylebox("panel", "TooltipPanel", tip)
	theme.set_color("font_color", "TooltipLabel", TEXT)
	theme.set_stylebox("panel", "PanelContainer", panel())
	theme.set_stylebox("panel", "PopupMenu", panel(Color(0.065, 0.068, 0.076, 0.98), BORDER_LIGHT, 5, 4))
	var hov := bar_fill(Color(0.26, 0.23, 0.16))
	hov.border_width_top = 0
	theme.set_stylebox("hover", "PopupMenu", hov)
	theme.set_color("font_color", "PopupMenu", TEXT)
	theme.set_color("font_hover_color", "PopupMenu", GOLD)
	var edit := panel(BG_INSET, BORDER_LIGHT, RADIUS_SMALL, 6)
	edit.shadow_size = 0
	theme.set_stylebox("normal", "LineEdit", edit)
	theme.set_stylebox("read_only", "LineEdit", edit)
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", TEXT_MUTED)
	theme.set_color("caret_color", "LineEdit", GOLD)
	theme.set_color("selection_color", "LineEdit", Color(GOLD, 0.35))
