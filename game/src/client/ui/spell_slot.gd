## One spell cell (spell bar, spell book): Dofus slot texture, spell icon,
## shortcut key (top left), an overlay text (cooldown, "PA"…), dimmed when
## unusable, rich tooltip (UiTooltips.spell). Drag and drop: a spell can be
## dragged (drag data {"spell": spells.id}) and dropped on a slot that accepts
## it (`drop_slot` >= 0: emits `dropped`).
## Empty slot: spell_id 0.
class_name SpellSlot
extends Control

signal clicked(slot: SpellSlot, button: int)
signal dropped(spell: int, slot: int)

const SIZE := 48

## castable id (SpellBook) shown, 0 = empty
var spell_id := 0
## spell bar slot index this cell stands for (-1 = not a drop target)
var drop_slot := -1
var draggable := true
var key_text := ""
var overlay := "":
	set(v):
		overlay = v
		queue_redraw()
var dimmed := false:
	set(v):
		dimmed = v
		queue_redraw()
var selected := false:
	set(v):
		selected = v
		queue_redraw()
var _hover := false
var _icon: Texture2D
var _size := SIZE
## a spell not in SpellBook (the weapon hit: Equipment.weapon_spell); {} = SpellBook's
var _own := {}

static var _icons := {} # icon id -> Texture2D (shared by every slot)


func _init(p_spell := 0, p_size := SIZE) -> void:
	_size = p_size
	custom_minimum_size = Vector2(_size, _size)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw())
	set_spell(p_spell)


func set_spell(id: int) -> void:
	spell_id = id
	_own = {}
	_icon = icon_texture(int(SpellBook.get_spell(id).get("icon", 0))) if id != 0 else null
	if id != 0 and int(SpellBook.get_spell(id).get("icon", 0)) == 0: # Coup de poing has no picto
		_icon = UiStyle.texture("UI/darkStone/texture/slot/icon_slot_weapon_inventory")
	tooltip_text = " " if id != 0 else "" # non-empty: Godot then asks _make_custom_tooltip
	queue_redraw()


## A fighter-own spell (the weapon hit): its item's icon.
func set_spell_dict(spell: Dictionary) -> void:
	set_spell(int(spell.get("id", 0)))
	_own = spell
	_icon = ClientTheme.texture("Picto/Items/%d" % int(spell.get("item_icon", 0)))


## Content/Picto/Spells/<icon> (extracted by spells.py), cached.
static func icon_texture(icon: int) -> Texture2D:
	if not _icons.has(icon):
		var img := DofusContent.get_provider().load_image("Content/Picto/Spells/%d" % icon)
		_icons[icon] = ImageTexture.create_from_image(img) if img != null else null
	return _icons[icon]


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var bg := UiStyle.texture(UiStyle.SLOT_EMPTY)
	if bg != null:
		draw_texture_rect(bg, r, false)
	else:
		draw_style_box(UiStyle.panel(UiStyle.BG_INSET, UiStyle.BORDER, 4, 0), r)
	var inner := r.grow(-3)
	if _icon != null:
		draw_texture_rect(_icon, inner, false, Color(0.35, 0.35, 0.35) if dimmed else Color.WHITE)
	var font := get_theme_default_font()
	if key_text != "":
		draw_string_outline(font, Vector2(4, 13), key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color.BLACK)
		draw_string(font, Vector2(4, 13), key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiStyle.TEXT)
	if overlay != "":
		var fs := 18 if overlay.length() <= 2 else 13
		var w := font.get_string_size(overlay, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := Vector2((size.x - w) * 0.5, size.y * 0.5 + fs * 0.35)
		draw_string_outline(font, at, overlay, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color.BLACK)
		draw_string(font, at, overlay, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	var frame := UiStyle.texture(UiStyle.SLOT_SELECTED if selected else UiStyle.SLOT_OVER) if (selected or _hover) else null
	if frame != null:
		draw_texture_rect(frame, r, false)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		clicked.emit(self, (event as InputEventMouseButton).button_index)
		accept_event()
	elif event is InputEventMouseButton and not event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and Rect2(Vector2.ZERO, size).has_point((event as InputEventMouseButton).position):
		clicked.emit(self, MOUSE_BUTTON_LEFT) # on release: a press that turns into a drag is not a click


func _get_drag_data(_at: Vector2) -> Variant:
	if spell_id == 0 or not draggable:
		return null
	var preview := TextureRect.new()
	preview.texture = _icon
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.size = Vector2(SIZE, SIZE)
	preview.modulate = Color(1, 1, 1, 0.8)
	set_drag_preview(preview)
	if not _own.is_empty():
		return null # the weapon is not a spell of the bar
	return {"spell": int(SpellBook.get_spell(spell_id).get("spell", 0))}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return drop_slot >= 0 and data is Dictionary and int((data as Dictionary).get("spell", 0)) != 0


func _drop_data(_at: Vector2, data: Variant) -> void:
	dropped.emit(int(data["spell"]), drop_slot)


func _make_custom_tooltip(_for_text: String) -> Object:
	if not _own.is_empty():
		return UiTooltips.spell(_own)
	return UiTooltips.spell(SpellBook.get_spell(spell_id)) if spell_id != 0 else null
