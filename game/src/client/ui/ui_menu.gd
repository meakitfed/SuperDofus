## Building blocks of the full-screen menus (launch, world loading, character choice and
## creation, world folder): backdrop, centred card, labelled field, primary button, notice
## block, step trail, collapsible section. Colours, sizes and shapes come from UiStyle.
class_name UiMenu
extends RefCounted

## Width of the centred card of the account / world / folder screens (design px).
const CARD_W := 460
const FIELD_H := 38
const BUTTON_H := 44


## Full-screen background of the menus: a warm radial light and, if given, a faint class
## symbol (real Dofus texture) behind the content.
static func backdrop(breed := 0) -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := TextureRect.new()
	var grad := GradientTexture2D.new()
	grad.fill = GradientTexture2D.FILL_RADIAL
	grad.fill_from = Vector2(0.5, 0.42)
	grad.fill_to = Vector2(1.05, 1.0)
	grad.gradient = Gradient.new()
	grad.gradient.set_color(0, UiStyle.BACKDROP_CENTER)
	grad.gradient.set_color(1, UiStyle.BACKDROP_EDGE)
	bg.texture = grad
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	if breed > 0:
		var tex := UiStyle.texture("UI/classes/symbol_%d" % breed)
		if tex != null:
			var mark := TextureRect.new()
			mark.texture = tex
			mark.modulate = Color(UiStyle.GOLD, 0.035)
			mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
			mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			mark.offset_left = 60
			mark.offset_right = -60
			mark.offset_top = 40
			mark.offset_bottom = -40
			root.add_child(mark)
	return root


## A full-screen centring layer holding a card; returns the VBox of the card's content.
## The card takes the width asked for (never wider than the screen minus the margins).
static func card(parent: Control, width := CARD_W) -> VBoxContainer:
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	var style := UiStyle.panel(UiStyle.BG, UiStyle.BORDER_LIGHT, 8, 28)
	style.shadow_size = 24
	panel.add_theme_stylebox_override("panel", style)
	centre.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	panel.add_child(body)
	return body


## Title block: the name in gold, a muted line under it, both centred.
static func header(body: Control, title: String, subtitle := "", size := 34) -> void:
	var t := UiStyle.title(title, size)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(t)
	if subtitle != "":
		var s := UiStyle.muted(subtitle)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(s)


## The main action of a screen (gold fill): one per screen.
static func primary(text: String, min_width := 220) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = UiStyle.V_PRIMARY
	b.custom_minimum_size = Vector2(min_width, BUTTON_H)
	b.add_theme_font_size_override("font_size", UiStyle.FS_TITLE + 2)
	return b


## A secondary action (neutral).
static func secondary(text: String, min_width := 120) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, BUTTON_H)
	return b


## A caption over a text field; returns the LineEdit (its parent box is `box`).
static func field(body: Control, caption: String, placeholder := "", secret := false) -> LineEdit:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(UiStyle.label(caption, UiStyle.TEXT_MUTED, UiStyle.FS_SMALL))
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.secret = secret
	edit.custom_minimum_size = Vector2(0, FIELD_H)
	box.add_child(edit)
	body.add_child(box)
	return edit


## A block that says what happens (progress, failure). `kind`: "info" | "error" | "ok".
## Hidden while the text is empty; `say` updates it.
class Notice extends PanelContainer:
	var label: Label

	func _init() -> void:
		label = UiStyle.label("", UiStyle.TEXT, UiStyle.FS_BODY)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(label)
		visible = false

	func say(text: String, kind := "info") -> void:
		label.text = text
		visible = text != ""
		var edge: Color = {"error": UiStyle.BAD, "ok": UiStyle.GOOD}.get(kind, UiStyle.BORDER_LIGHT)
		var s := UiStyle.panel(UiStyle.BG_INSET, edge, UiStyle.RADIUS_SMALL, 10)
		s.shadow_size = 0
		if kind == "error":
			s.border_width_left = 4
		add_theme_stylebox_override("panel", s)
		label.add_theme_color_override("font_color", UiStyle.BAD if kind == "error" else UiStyle.TEXT)


static func notice() -> Notice:
	return Notice.new()


## "Serveur › Compte › Monde › Personnage": the path of a connection, `current` in gold,
## the steps before it ticked.
static func steps(labels: Array, current: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	for i in labels.size():
		if i > 0:
			row.add_child(UiStyle.label("›", UiStyle.TEXT_DISABLED, UiStyle.FS_SMALL))
		var color := UiStyle.GOOD if i < current else (UiStyle.GOLD if i == current else UiStyle.TEXT_MUTED)
		var text := ("✓ " if i < current else "") + str(labels[i])
		var l := UiStyle.label(text, color, UiStyle.FS_SMALL)
		if i == current:
			l.add_theme_font_override("font", UiStyle.font("heading"))
		row.add_child(l)
	return row


## A "Options avancées" toggle that shows / hides `content`; returns the button.
static func disclosure(body: Control, caption: String, content: Control, open := false) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.theme_type_variation = UiStyle.V_TAB
	b.focus_mode = Control.FOCUS_ALL
	b.button_pressed = open
	var sync := func() -> void:
		b.text = ("▾ " if b.button_pressed else "▸ ") + caption
		content.visible = b.button_pressed
	b.toggled.connect(func(_on: bool) -> void: sync.call())
	sync.call()
	body.add_child(b)
	body.add_child(content)
	return b


## "C:/Users/…/worlds" shortened in the middle to `max_chars` (the full path goes in a tooltip).
static func elide_path(path: String, max_chars := 44) -> String:
	if path.length() <= max_chars:
		return path
	var keep := (max_chars - 1) / 2
	return path.substr(0, keep) + "…" + path.substr(path.length() - keep)


## The pedestal of a character preview (flattened disc and gold rim), drawn on `canvas`.
static func draw_pedestal(canvas: CanvasItem, radius: float) -> void:
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.42))
	canvas.draw_circle(Vector2.ZERO, radius, Color(UiStyle.SHADOW, 0.35))
	canvas.draw_arc(Vector2.ZERO, radius, 0, TAU, 64, Color(UiStyle.GOLD, 0.45), 2.0, true)
