## A quantity box: [-] [field] [+] [+10] [Max]. Typed text is clamped to [min_value, max_value] when it is
## validated (Enter or focus lost); the buttons clamp too. Same members as a SpinBox (`value`, `min_value`,
## `max_value`, `value_changed`) so a window swaps one for the other. `max_value` follows what the
## window can afford; "Max" jumps to it.
class_name QtyStepper
extends HBoxContainer

signal value_changed(v: float)

var min_value := 1.0:
	set(v):
		min_value = v
		_update()
var max_value := 999.0:
	set(v):
		max_value = maxf(v, min_value)
		if value > max_value:
			value = max_value
		_update()
var value := 1.0:
	set(v):
		var c := clampf(roundf(v), min_value, max_value)
		var changed := c != value
		value = c
		_update()
		if changed:
			value_changed.emit(value)
var _edit: LineEdit
var _minus: Button
var _plus: Button
var _ten: Button
var _max: Button


func _init(p_min := 1, p_max := 999, show_ten := true, show_max := true) -> void:
	add_theme_constant_override("separation", 3)
	min_value = p_min
	max_value = p_max
	value = p_min
	_minus = _button("−", "Moins", func() -> void: value -= 1)
	_edit = LineEdit.new()
	_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_edit.custom_minimum_size = Vector2(68, 0)
	_edit.select_all_on_focus = true
	_edit.text_submitted.connect(func(_t: String) -> void: _commit())
	_edit.focus_exited.connect(_commit)
	add_child(_edit)
	_plus = _button("+", "Plus", func() -> void: value += 1)
	_ten = _button("+10", "Dix de plus", func() -> void: value += 10)
	_ten.visible = show_ten
	_max = _button("Max", "Le plus possible", func() -> void: value = max_value)
	_max.visible = show_max
	_update()


func _button(text: String, tip: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	UiStyle.compact(b, 44 if text.length() > 1 else 30)
	b.pressed.connect(on_press)
	add_child(b)
	return b


## Applies what was typed ("12", "1 200"); anything else keeps the old value.
func _commit() -> void:
	var digits := _edit.text.replace(" ", "")
	if digits.is_valid_int():
		value = float(digits.to_int())
	_update()


func set_enabled(on: bool) -> void:
	for b: Button in [_minus, _plus, _ten, _max]:
		b.disabled = not on
	_edit.editable = on
	if on:
		_update()


func _update() -> void:
	if _edit == null:
		return
	if not _edit.has_focus():
		_edit.text = str(int(value))
	_minus.disabled = value <= min_value
	_plus.disabled = value >= max_value
	_ten.disabled = value >= max_value
	_max.disabled = value >= max_value
