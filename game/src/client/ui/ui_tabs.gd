## Tabs (icon and/or text) over one page shown at a time.
##   var tabs := UiTabs.new(); tabs.add_tab("Équipement", page, "UI/Figma/menuIcons/1x/equipments")
class_name UiTabs
extends VBoxContainer

signal tab_changed(index: int)

var current := -1
## tabs show only their icon (title in the tooltip), for narrow windows
var icons_only := false
var _bar: HBoxContainer
var _pages: Array[Control] = []
var _buttons: Array[Button] = []


func _init() -> void:
	add_theme_constant_override("separation", 8)
	_bar = HBoxContainer.new()
	_bar.add_theme_constant_override("separation", 4)
	add_child(_bar)


func add_tab(title: String, page: Control, icon_path := "") -> int:
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.text = title
	if icon_path != "":
		b.icon = UiStyle.texture(icon_path)
		b.add_theme_constant_override("icon_max_width", 22)
		if icons_only and b.icon != null:
			b.text = ""
			b.tooltip_text = title
			b.custom_minimum_size = Vector2(40, 34)
	var index := _pages.size()
	b.pressed.connect(func() -> void: select(index))
	_bar.add_child(b)
	_buttons.append(b)
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(page)
	_pages.append(page)
	if current < 0:
		select(0)
	else:
		page.visible = false
	return index


func select(index: int) -> void:
	current = index
	for i in _pages.size():
		_pages[i].visible = i == index
		_buttons[i].set_pressed_no_signal(i == index)
	tab_changed.emit(index)
