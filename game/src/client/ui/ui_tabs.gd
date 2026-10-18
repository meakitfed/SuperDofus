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
	add_theme_constant_override("separation", 6)
	_bar = HBoxContainer.new()
	_bar.add_theme_constant_override("separation", 2)
	add_child(_bar)
	var rule := HSeparator.new() # the line the current tab's underline sits on
	var line := StyleBoxLine.new()
	line.color = UiStyle.BORDER
	rule.add_theme_stylebox_override("separator", line)
	rule.add_theme_constant_override("separation", 1)
	add_child(rule)


func add_tab(title: String, page: Control, icon_path := "") -> int:
	var b := Button.new()
	b.toggle_mode = true
	b.theme_type_variation = UiStyle.V_TAB
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


## Narrow tabs (small text, tight padding) for a panel that must stay small, like the chat.
func set_compact() -> void:
	for b in _buttons:
		b.add_theme_font_size_override("font_size", UiStyle.FS_SMALL)
		# on a map the panel's background fades: an outline keeps the titles readable
		b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		b.add_theme_constant_override("outline_size", 3)
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			var st := UiStyle.tab("pressed" if state == "hover_pressed" else state)
			st.content_margin_left = 8
			st.content_margin_right = 8
			st.content_margin_top = 3
			st.content_margin_bottom = 3
			b.add_theme_stylebox_override(state, st)


## A control at the right end of the tab row (an options button).
func add_to_bar(c: Control) -> void:
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(gap)
	_bar.add_child(c)


func set_title(index: int, title: String) -> void:
	if index >= 0 and index < _buttons.size() and _buttons[index].text != title:
		_buttons[index].text = title


## A tab with something new in it: its title turns gold.
func set_alert(index: int, on: bool) -> void:
	if index >= 0 and index < _buttons.size():
		if on:
			_buttons[index].add_theme_color_override("font_color", UiStyle.GOLD)
		else:
			_buttons[index].remove_theme_color_override("font_color")


func select(index: int) -> void:
	current = index
	for i in _pages.size():
		_pages[i].visible = i == index
		_buttons[i].set_pressed_no_signal(i == index)
	tab_changed.emit(index)
