## The UI kit on one page (roadmap P0.06): every widget, windows and the rich
## tooltips shown inline, then a screenshot. Needs a GPU (like client_shot).
##   godot --path game -s res://tools/ui_demo.gd -- --out=ui_demo.png
extends SceneTree

var _out := "ui_demo.png"
var _frames := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	UiWindow.reset_layout()
	root.size = Vector2i(1280, 900)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.36, 0.33, 0.26)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)

	var stats := {"name": "Pandawa", "level": 12, "xp": 30100, "xp_floor": 25200, "xp_next": 32600, "kamas": 12450,
			"capital": 4, "hp": 88, "max_hp": 122, "ap": 6, "mp": 3,
			"stats": {"vitality": 12, "wisdom": 3, "strength": 25, "intelligence": 0, "chance": 0, "agility": 5},
			"weight": 23, "max_weight": 1125}
	var chars := CharacteristicsWindow.new()
	layer.add_child(chars)
	chars.setup_window(GameBackend.new())
	chars.set_stats(stats)
	chars.set_hp(88, 122)
	chars.open()
	var inv := InventoryWindow.new()
	layer.add_child(inv)
	inv.setup_window()
	inv.set_stats(stats)
	inv.set_items([{"uid": 1, "id": 16512, "qty": 12, "effects": []}, {"uid": 2, "id": 519, "qty": 3, "effects": []},
			{"uid": 3, "id": 1182, "qty": 4, "effects": [[110, 11, 0, 0]]}, {"uid": 4, "id": 2473, "qty": 1, "effects": [[118, 5, 0, 0]]}])
	inv.open()

	var kit := UiWindow.new()
	layer.add_child(kit)
	kit.setup("ui_demo", "Kit d'interface", "UI/Figma/menuIcons/1x/guide")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	kit.body.add_child(row)
	var b := Button.new()
	b.text = "Bouton"
	row.add_child(b)
	var d := Button.new()
	d.text = "Désactivé"
	d.disabled = true
	row.add_child(d)
	var p := Button.new()
	p.text = "Enfoncé"
	p.toggle_mode = true
	p.button_pressed = true
	row.add_child(p)
	for c: Array in [[UiStyle.HP, 70, "70 / 100 PV"], [UiStyle.XP, 40, "XP"], [UiStyle.GOOD, 90, "Pods"]]:
		var bar := UiBar.new(c[0], 16)
		bar.set_values(c[1], 100, c[2])
		kit.body.add_child(bar)
	var slots := HBoxContainer.new()
	kit.body.add_child(slots)
	slots.add_child(ItemSlot.new())
	slots.add_child(ItemSlot.new(0, 0, "UI/darkStone/texture/slot/tx_slot_helmet"))
	slots.add_child(ItemSlot.new(16512, 12))
	var sel := ItemSlot.new(519, 1)
	sel.selected = true
	slots.add_child(sel)
	var spell_ids := SpellBook.known_ids(12, 10)
	for i in mini(3, spell_ids.size()):
		var sp := SpellSlot.new(spell_ids[i])
		sp.key_text = str(i + 1)
		sp.overlay = "2" if i == 2 else ""
		sp.dimmed = i == 2
		slots.add_child(sp)
	var tips := HBoxContainer.new()
	tips.add_theme_constant_override("separation", 10)
	kit.body.add_child(tips)
	for tip: Control in [UiTooltips.item(44, 1, [[100, 8, 10, 0], [118, 9, 0, 0], [422, 1, 0, 0]]), UiTooltips.item(683, 2),
			UiTooltips.spell(SpellBook.get_spell(spell_ids[0]) if not spell_ids.is_empty() else {}),
			UiTooltips.monster_group([{"name": "Tofu Chimérique", "level": 5}, {"name": "Tofu Chimérique", "level": 4},
				{"name": "Pissenlit Diabolique", "level": 6}])]:
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", ClientTheme.get_theme().get_stylebox("panel", "TooltipPanel"))
		panel.add_child(tip)
		tips.add_child(panel)
	kit.body.add_child(UiStyle.label("Raccourcis : %s · %s · %s" % [Shortcuts.label("inventory"),
			Shortcuts.label("characteristics"), Shortcuts.label("close")], UiStyle.TEXT_MUTED, 13))
	kit.open()
	var toast := Toast.new()
	layer.add_child(toast)
	toast.show_text("Pas assez de PA")
	toast.show_text("Ce n'est pas votre tour")
	# a layout like a player would leave it
	_place.call_deferred(chars, Vector2(16, 16))
	_place.call_deferred(inv, Vector2(410, 470))
	_place.call_deferred(kit, Vector2(380, 16))


func _place(w: Control, at: Vector2) -> void:
	w.position = at


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 20:
		root.get_texture().get_image().save_png(_out)
		print("saved ", _out)
		return true
	return false
