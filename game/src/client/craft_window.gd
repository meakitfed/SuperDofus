## Workshop window, roadmap P2.06b: opened by a craft skill (craft_state). Left, the bag (double-click a
## stack puts the quantity of the box down); middle, the ingredient slots, the result and the Fabriquer
## button; right, the recipe book (click a recipe puts its ingredients down). The sim decides everything
## (recipes, slots, ingredients): the state is a CraftModel, the window only shows it.
## Closing sends craft_close.
class_name CraftWindow
extends UiWindow

const COLUMNS := 5
const BAG_ROWS := 5

var backend: GameBackend
## the bag (stacks shown on the left)
var inventory: InventoryWindow
var model := CraftModel.new()
var _qty: SpinBox
var _count: SpinBox
var _bag_grid: GridContainer
var _slot_box: GridContainer
var _result_box: HBoxContainer
var _make: Button
var _job_label: Label
var _book_rows: VBoxContainer
var _ending := false
## the skill of the last workshop (the J key opens it again)
var _last_skill := 20
var _skills: OptionButton


func setup_window(p_backend: GameBackend) -> void:
	backend = p_backend
	setup("craft", "Atelier", "UI/Figma/menuIcons/1x/inventory")
	default_anchor = Vector2(0.25, 0.3)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	body.add_child(top)
	_skills = OptionButton.new()
	for sk: int in Crafting.craft_skills():
		_skills.add_item(DofusI18n.text(int(Jobs.skill(sk).get("nameId", 0)), "Compétence %d" % sk), sk)
	_skills.item_selected.connect(func(i: int) -> void: backend.send(Protocol.craft_open(_skills.get_item_id(i))))
	top.add_child(_skills)
	_job_label = UiStyle.label("", UiStyle.TEXT_MUTED, 13)
	top.add_child(_job_label)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	body.add_child(cols)
	var bag := VBoxContainer.new()
	cols.add_child(bag)
	var qty_row := HBoxContainer.new()
	bag.add_child(qty_row)
	qty_row.add_child(UiStyle.label("Sac, quantité", UiStyle.TEXT, 14))
	_qty = SpinBox.new()
	_qty.min_value = 1
	_qty.max_value = 999
	_qty.value = 1
	qty_row.add_child(_qty)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(COLUMNS * (ItemSlot.SIZE + 4) + 8, BAG_ROWS * (ItemSlot.SIZE + 4))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bag.add_child(scroll)
	_bag_grid = _grid(scroll)
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 8)
	cols.add_child(mid)
	mid.add_child(UiStyle.label("Ingrédients", UiStyle.TEXT, 14))
	_slot_box = GridContainer.new()
	_slot_box.columns = 4
	_slot_box.add_theme_constant_override("h_separation", 4)
	_slot_box.add_theme_constant_override("v_separation", 4)
	mid.add_child(_slot_box)
	mid.add_child(UiStyle.label("Résultat", UiStyle.TEXT, 14))
	_result_box = HBoxContainer.new()
	_result_box.add_theme_constant_override("separation", 8)
	mid.add_child(_result_box)
	var make_row := HBoxContainer.new()
	mid.add_child(make_row)
	_count = SpinBox.new()
	_count.min_value = 1
	_count.max_value = 999
	_count.value = 1
	make_row.add_child(_count)
	_make = Button.new()
	_make.text = "Fabriquer"
	_make.pressed.connect(func() -> void:
		var m: Variant = model.make(int(_count.value))
		if m != null:
			backend.send(m))
	make_row.add_child(_make)
	var clear := Button.new()
	clear.text = "Vider"
	clear.pressed.connect(func() -> void: backend.send(Protocol.craft_set([])))
	make_row.add_child(clear)
	var book := VBoxContainer.new()
	cols.add_child(book)
	book.add_child(UiStyle.label("Recettes", UiStyle.TEXT, 14))
	var book_scroll := ScrollContainer.new()
	book_scroll.custom_minimum_size = Vector2(260, BAG_ROWS * (ItemSlot.SIZE + 4))
	book_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	book.add_child(book_scroll)
	_book_rows = VBoxContainer.new()
	_book_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_book_rows.add_theme_constant_override("separation", 3)
	book_scroll.add_child(_book_rows)
	closed.connect(func() -> void:
		model.close()
		if not _ending:
			backend.send(Protocol.craft_close()))


func _grid(parent: Control) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)
	return grid


## craft_state event: opens the window on the first one.
func show_state(ev: Dictionary) -> void:
	model.apply_state(ev)
	_last_skill = model.skill
	_skills.select(maxi(0, _skills.get_item_index(model.skill)))
	var job_id := int(model.job.get("job", 0))
	_job_label.text = "%s, niveau %d  ·  %d cases" % [DofusI18n.text(int(Jobs.job(job_id).get("nameId", 0)), "Métier"), int(model.job.get("level", 1)), model.slots]
	_fill()
	open()


## craft_done: the toast.
static func done_text(ev: Dictionary) -> String:
	return "%d x %s fabriqué" % [int(ev["count"]), UiTooltips.item_name(int(ev["item"]))]


## The J key: closes the workshop, or opens the last one.
func toggle_workshop() -> void:
	if visible:
		close_window()
	else:
		backend.send(Protocol.craft_open(_last_skill))


## craft_end-like: the map changed, the sim dropped the workshop.
func end_craft() -> void:
	_ending = true
	close_window()
	_ending = false


## After inventory events (the bag changed).
func refresh_bag() -> void:
	if visible:
		_fill()


func _fill() -> void:
	for c: Node in _bag_grid.get_children():
		c.queue_free()
	var stacks: Array = inventory.bag_items() if inventory != null else []
	for it: Dictionary in stacks:
		var slot := ItemSlot.new()
		slot.set_instance(it)
		slot.activated.connect(func(s: ItemSlot) -> void:
			var m: Variant = model.add(int(s.instance["id"]), mini(int(_qty.value), int(s.instance["qty"])))
			if m != null:
				backend.send(m))
		_bag_grid.add_child(slot)
	for j in range(stacks.size(), maxi(COLUMNS * BAG_ROWS, stacks.size() + (COLUMNS - stacks.size() % COLUMNS) % COLUMNS)):
		_bag_grid.add_child(ItemSlot.new())
	for c: Node in _slot_box.get_children():
		c.queue_free()
	for i in model.slots:
		var slot := ItemSlot.new()
		if i < model.ingredients.size():
			var g: Dictionary = model.ingredients[i]
			slot.set_item(int(g["item"]), int(g["qty"]))
			slot.activated.connect(func(_s: ItemSlot) -> void: backend.send(model.remove(int(g["item"]))))
		_slot_box.add_child(slot)
	for c: Node in _result_box.get_children():
		c.queue_free()
	if model.result != 0:
		_result_box.add_child(ItemSlot.new(model.result, 1))
		_result_box.add_child(UiStyle.label("%s (x%d possible)" % [UiTooltips.item_name(model.result), model.max_count], UiStyle.TEXT, 13))
	else:
		_result_box.add_child(UiStyle.label("Aucune recette", UiStyle.TEXT_MUTED, 13))
	_make.disabled = not model.can_craft()
	_count.max_value = maxi(1, model.max_count)
	for c: Node in _book_rows.get_children():
		c.queue_free()
	for r: Dictionary in model.book:
		var recipe := r
		var b := Button.new()
		b.text = "%s (niv. %d)" % [UiTooltips.item_name(int(r["item"])), int(r["level"])]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = ", ".join((r["ingredients"] as Array).map(func(g: Dictionary) -> String:
			return "%d x %s" % [int(g["qty"]), UiTooltips.item_name(int(g["item"]))]))
		b.pressed.connect(func() -> void: backend.send(model.fill_from(recipe)))
		_book_rows.add_child(b)
	if model.book.is_empty():
		_book_rows.add_child(UiStyle.label("Aucune recette à ce niveau.", UiStyle.TEXT_MUTED, 13))
