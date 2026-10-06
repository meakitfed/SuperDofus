## One item cell (inventory, rewards, equipment, shops…): Dofus slot texture,
## item icon, quantity, hover/selected frames, rich tooltip (UiTooltips.item).
## Empty slot: item_id 0 (optionally a placeholder icon, e.g. an equipment type).
class_name ItemSlot
extends Control

signal clicked(slot: ItemSlot, button: int)
## double-click (inventory: use the item)
signal activated(slot: ItemSlot)
## an item (uid) was dropped here (drop_slot: an Equipment slot, or Inventory.BAG)
signal dropped(uid: int, slot: int)

const NO_DROP := -2

const SIZE := 48

var item_id := 0
var qty := 0
## the instance shown (inventory): uid and rolled effects; {} = the item in general
var instance := {}
## what this cell accepts when an item is dragged on it: an Equipment slot,
## -1 the bag, NO_DROP nothing (item cells can always be dragged)
var drop_slot := NO_DROP
var selected := false:
	set(v):
		selected = v
		queue_redraw()
var _hover := false
var _icon: Texture2D
var _placeholder: Texture2D
var _qty: Label


func _init(p_item_id := 0, p_qty := 0, placeholder_path := "") -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if placeholder_path != "":
		_placeholder = UiStyle.texture(placeholder_path)
	_qty = UiStyle.label("", Color.WHITE, 12)
	_qty.add_theme_color_override("font_outline_color", Color.BLACK)
	_qty.add_theme_constant_override("outline_size", 4)
	_qty.position = Vector2(4, SIZE - 20)
	_qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_qty)
	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw())
	set_item(p_item_id, p_qty)


func set_item(p_item_id: int, p_qty := 1) -> void:
	item_id = p_item_id
	qty = p_qty
	var data := GameData.item(item_id) if item_id != 0 else {}
	_icon = ClientTheme.texture("Picto/Items/%d" % int(data["icon"])) if data.has("icon") else null
	_qty.text = str(qty) if item_id != 0 and qty > 1 else ""
	tooltip_text = " " if item_id != 0 else "" # non-empty: Godot then asks _make_custom_tooltip
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var bg := UiStyle.texture(UiStyle.SLOT_EMPTY)
	if bg != null:
		draw_texture_rect(bg, r, false)
	else:
		draw_style_box(UiStyle.panel(UiStyle.BG_INSET, UiStyle.BORDER, 4, 0), r)
	var inner := r.grow(-4)
	if _icon != null:
		draw_texture_rect(_icon, inner, false)
	elif item_id != 0:
		draw_string(get_theme_default_font(), inner.position + Vector2(8, 26), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UiStyle.TEXT_MUTED)
	elif _placeholder != null:
		draw_texture_rect(_placeholder, inner, false, Color(1, 1, 1, 0.55))
	var frame := UiStyle.texture(UiStyle.SLOT_SELECTED if selected else UiStyle.SLOT_OVER) if (selected or _hover) else null
	if frame != null:
		draw_texture_rect(frame, r, false)


## An inventory stack (item dict: {uid, id, qty, effects}).
func set_instance(it: Dictionary) -> void:
	instance = it
	set_item(int(it["id"]), int(it["qty"]))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if (event as InputEventMouseButton).double_click and item_id != 0:
			activated.emit(self)
		else:
			clicked.emit(self, (event as InputEventMouseButton).button_index)
		accept_event()


func _get_drag_data(_at: Vector2) -> Variant:
	if instance.is_empty():
		return null
	var preview := TextureRect.new()
	preview.texture = _icon
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.size = Vector2(SIZE, SIZE)
	preview.modulate = Color(1, 1, 1, 0.8)
	set_drag_preview(preview)
	return {"uid": int(instance["uid"]), "id": int(instance["id"]), "pos": int(instance.get("pos", -1))}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if drop_slot == NO_DROP or not (data is Dictionary and (data as Dictionary).has("uid")):
		return false
	if drop_slot == -1: # the bag takes worn items back
		return int(data["pos"]) != -1
	return Equipment.positions(int(data["id"])).has(drop_slot) and int(data["pos"]) != drop_slot


func _drop_data(_at: Vector2, data: Variant) -> void:
	dropped.emit(int(data["uid"]), drop_slot)


func _make_custom_tooltip(_for_text: String) -> Object:
	return UiTooltips.item(item_id, qty, instance.get("effects", [])) if item_id != 0 else null
