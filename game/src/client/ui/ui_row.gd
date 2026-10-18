## One row of a list window (shop offers, market lots, zaap destinations, quests, contacts…): an inset
## panel that lights up under the mouse and shows a gold edge when `selected`. `h` is the line to fill.
## `UiRow.offer(...)` builds the usual "slot, name, price, button" row.
class_name UiRow
extends PanelContainer

signal activated

var h: HBoxContainer
var selected := false:
	set(v):
		selected = v
		_restyle()
var clickable := false
var _hover := false


func _init(p_clickable := false) -> void:
	clickable = p_clickable
	h = HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	add_child(h)
	mouse_entered.connect(func() -> void:
		_hover = true
		_restyle())
	mouse_exited.connect(func() -> void:
		_hover = false
		_restyle())
	if clickable:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_restyle()


func _restyle() -> void:
	add_theme_stylebox_override("panel", UiStyle.row("selected" if selected else ("hover" if _hover else "normal")))


func _gui_input(event: InputEvent) -> void:
	if clickable and event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		activated.emit()


## slot + name (+ muted `sub` line) + price + action button. `variant` = UiStyle.V_PRIMARY / V_DANGER / "".
static func offer(item_id: int, qty: int, effects: Array, sub: String, price_text: String, price_color: Color,
		button_text: String, disabled: bool, why: String, on_press: Callable, variant := "") -> UiRow:
	var row := UiRow.new()
	var slot := ItemSlot.new(item_id, qty)
	slot.instance = {"effects": effects} if not effects.is_empty() else {}
	row.h.add_child(slot)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	row.h.add_child(texts)
	var name := UiStyle.label(UiTooltips.item_name(item_id), UiStyle.TEXT, UiStyle.FS_BODY)
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texts.add_child(name)
	if sub != "":
		texts.add_child(UiStyle.label(sub, UiStyle.TEXT_MUTED, UiStyle.FS_SMALL))
	if price_text != "":
		row.h.add_child(UiStyle.label(price_text, price_color, UiStyle.FS_BODY))
	var b := Button.new()
	b.text = button_text
	b.disabled = disabled
	b.tooltip_text = why if disabled else ""
	if variant != "":
		b.theme_type_variation = variant
	b.pressed.connect(on_press)
	row.h.add_child(b)
	return row
