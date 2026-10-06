## Bank window, roadmap P2.08: opened by bank_open (the account chest). Two grids,
## the bag on the left and the chest on the right; double-click a stack moves the
## quantity of the box to the other side, and a kamas row deposits or withdraws.
## The sim decides everything (pods, kamas, distance): the window only displays.
## Closing sends bank_close.
class_name BankWindow
extends UiWindow

const COLUMNS := 5
const ROWS := 5

var backend: GameBackend
## the bag (stacks shown on the left)
var inventory: InventoryWindow
var _qty: SpinBox
var _kamas_amount: SpinBox
var _bag_kamas: Label
var _bank_kamas: Label
var _cost_label: Label
var _bag_grid: GridContainer
var _bank_grid: GridContainer
var _items := {} # uid -> stack of the chest
var _kamas := 0
var _stats: Dictionary = {}
var _ending := false


func setup_window(p_backend: GameBackend) -> void:
	backend = p_backend
	setup("bank", "Coffre", "UI/Figma/menuIcons/1x/inventory")
	default_anchor = Vector2(0.4, 0.4)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	body.add_child(top)
	top.add_child(UiStyle.label("Quantité", UiStyle.TEXT_MUTED, 13))
	_qty = SpinBox.new()
	_qty.min_value = 1
	_qty.max_value = BankRules.MAX_QTY
	_qty.value = 1
	top.add_child(_qty)
	_cost_label = UiStyle.label("", UiStyle.TEXT_MUTED, 13)
	_cost_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_cost_label)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	body.add_child(cols)
	_bag_grid = _column(cols, "Sac")
	_bank_grid = _column(cols, "Coffre")
	var kamas_row := HBoxContainer.new()
	kamas_row.add_theme_constant_override("separation", 8)
	body.add_child(kamas_row)
	_bag_kamas = UiStyle.label("0 K", UiStyle.KAMAS, 15)
	kamas_row.add_child(_bag_kamas)
	var deposit := Button.new()
	deposit.text = "Déposer >"
	deposit.pressed.connect(func() -> void: backend.send(Protocol.bank_kamas(int(_kamas_amount.value), BankRules.IN)))
	kamas_row.add_child(deposit)
	_kamas_amount = SpinBox.new()
	_kamas_amount.min_value = 1
	_kamas_amount.max_value = 2000000000
	_kamas_amount.value = 1
	kamas_row.add_child(_kamas_amount)
	var withdraw := Button.new()
	withdraw.text = "< Retirer"
	withdraw.pressed.connect(func() -> void: backend.send(Protocol.bank_kamas(int(_kamas_amount.value), BankRules.OUT)))
	kamas_row.add_child(withdraw)
	_bank_kamas = UiStyle.label("0 K", UiStyle.KAMAS, 15)
	kamas_row.add_child(_bank_kamas)
	closed.connect(func() -> void:
		if not _ending:
			backend.send(Protocol.bank_close()))


func _column(parent: HBoxContainer, title: String) -> GridContainer:
	var box := VBoxContainer.new()
	parent.add_child(box)
	box.add_child(UiStyle.label(title, UiStyle.TEXT, 14))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(COLUMNS * (ItemSlot.SIZE + 4) + 8, ROWS * (ItemSlot.SIZE + 4))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(grid)
	return grid


## bank_open event.
func show_bank(ev: Dictionary, npc_name: String, stats: Dictionary) -> void:
	title_label.text = npc_name if npc_name != "" else "Coffre"
	_items.clear()
	for it: Dictionary in ev["items"]:
		_items[int(it["uid"])] = it
	_kamas = int(ev["kamas"])
	_stats = stats
	var cost := int(ev.get("cost", 0))
	_cost_label.text = "Accès payé : %s K" % UiStyle.thousands(cost) if cost > 0 else "Accès gratuit"
	_fill()
	open()


## bank_update event: the chest's kamas and the stacks that changed (qty 0 = gone).
func update_bank(ev: Dictionary) -> void:
	_kamas = int(ev["kamas"])
	for it: Dictionary in ev["items"]:
		if int(it["qty"]) <= 0:
			_items.erase(int(it["uid"]))
		else:
			_items[int(it["uid"])] = it
	_fill()


## bank_end: the sim closed it.
func end_bank() -> void:
	_ending = true
	close_window()
	_ending = false


## After each player_stats (kamas and the bag changed).
func set_stats(s: Dictionary) -> void:
	_stats = s
	if visible:
		_fill()


func _fill() -> void:
	_bag_kamas.text = "%s K" % UiStyle.thousands(int(_stats.get("kamas", 0)))
	_bank_kamas.text = "%s K" % UiStyle.thousands(_kamas)
	var bank_stacks: Array = _items.values()
	bank_stacks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["uid"]) < int(b["uid"]))
	_grid(_bag_grid, inventory.bag_items() if inventory != null else [], BankRules.IN)
	_grid(_bank_grid, bank_stacks, BankRules.OUT)


func _grid(grid: GridContainer, stacks: Array, dir: String) -> void:
	for c: Node in grid.get_children():
		c.queue_free()
	for it: Dictionary in stacks:
		var slot := ItemSlot.new()
		slot.set_instance(it)
		slot.activated.connect(func(s: ItemSlot) -> void:
			backend.send(Protocol.bank_move(int(s.instance["uid"]), mini(int(_qty.value), int(s.instance["qty"])), dir)))
		grid.add_child(slot)
	for j in range(stacks.size(), maxi(COLUMNS * ROWS, stacks.size() + (COLUMNS - stacks.size() % COLUMNS) % COLUMNS)):
		grid.add_child(ItemSlot.new())
