## The row of window buttons at the bottom right (the Dofus widget bar): characteristics, spells,
## bag, quests, world map, friends. A press asks for the same action as its shortcut, so the
## session has one place that opens each window (`pressed(action)`). Icons are the Dofus menu icons.
class_name HudMenu
extends HBoxContainer

signal pressed(action: String)

const SIZE := 32
## action (Shortcuts) -> menu icon
const ENTRIES := [
	["characteristics", "UI/Figma/menuIcons/1x/characteristic"],
	["spells", "UI/Figma/menuIcons/1x/spells"],
	["inventory", "UI/Figma/menuIcons/1x/inventory"],
	["quests", "UI/Figma/menuIcons/1x/quest"],
	["worldmap", "UI/Figma/menuIcons/1x/map"],
	["friends", "UI/Figma/menuIcons/1x/social"],
]

var buttons := {}


func _init() -> void:
	add_theme_constant_override("separation", 2)
	for e: Array in ENTRIES:
		var action: String = e[0]
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(SIZE, SIZE)
		b.tooltip_text = Shortcuts.label(action)
		var tex := UiStyle.texture(str(e[1]))
		if tex != null: # the icons have their own proportions (the quest "!" is tall): fitted in the square
			var pic := TextureRect.new()
			pic.texture = tex
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
			b.add_child(pic)
		else:
			b.text = Shortcuts.label_key(action) # content not extracted: the key stands in
		b.pressed.connect(func() -> void: pressed.emit(action))
		add_child(b)
		buttons[action] = b

