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
var _qty: QtyStepper
var _kamas_amount: QtyStepper
var _search: LineEdit
var _deposit: Button
var _withdraw: Button
var _bag_title: Label
var _bank_title: Label
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
	default_anchor = Vector2(0.06, 0.4) # left, clear of the map centre
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	body.add_child(top)
	_search = UiSearch.field("Rechercher un objet", _fill)
	top.add_child(_search)
	_cost_label = UiStyle.label("", UiStyle.TEXT_MUTED, 13)
	top.add_child(_cost_label)
	var qty_row := HBoxContainer.new()
	qty_row.add_theme_constant_override("separation", 10)
	body.add_child(qty_row)
	qty_row.add_child(UiStyle.label("Quantité déplacée", UiStyle.TEXT_MUTED, 13))
	_qty = QtyStepper.new(1, BankRules.MAX_QTY)
	qty_row.add_child(_qty)
	var hint := UiStyle.label("Double-clic : déplacer", UiStyle.TEXT_MUTED, UiStyle.FS_SMALL)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	qty_row.add_child(hint)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	body.add_child(cols)
	_bag_grid = _column(cols, "Sac")
	_bank_grid = _column(cols, "Coffre")
	var kamas_box := PanelContainer.new()
	kamas_box.add_theme_stylebox_override("panel", UiStyle.row())
	body.add_child(kamas_box)
	var kamas_row := HBoxContainer.new()
	kamas_row.add_theme_constant_override("separation", 8)
	kamas_box.add_child(kamas_row)
	_bag_kamas = UiStyle.label("0 K", UiStyle.KAMAS, 15)
	kamas_row.add_child(_bag_kamas)
	_deposit = Button.new()
	_deposit.text = "Déposer >"
	_deposit.pressed.connect(func() -> void: backend.send(Protocol.bank_kamas(int(_kamas_amount.value), BankRules.IN)))
	kamas_row.add_child(_deposit)
	_kamas_amount = QtyStepper.new(1, 2000000000, false)
	_kamas_amount.value_changed.connect(func(_v: float) -> void: _fill_kamas())
	kamas_row.add_child(_kamas_amount)
	_withdraw = Button.new()
	_withdraw.text = "< Retirer"
	_withdraw.pressed.connect(func() -> void: backend.send(Protocol.bank_kamas(int(_kamas_amount.value), BankRules.OUT)))
	kamas_row.add_child(_withdraw)
	_bank_kamas = UiStyle.label("0 K", UiStyle.KAMAS, 15)
	kamas_row.add_child(_bank_kamas)
	closed.connect(func() -> void:
		if not _ending:
			backend.send(Protocol.bank_close()))


func _column(parent: HBoxContainer, title: String) -> GridContainer:
	var box := VBoxContainer.new()
	parent.add_child(box)
	var head := UiStyle.heading(title)
	box.add_child(head)
	if title == "Sac":
		_bag_title = head
	else:
		_bank_title = head
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
	_search.clear()
	_qty.value = 1
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
	if _bag_grid == null:
		return
	var bank_stacks: Array = _items.values()
	bank_stacks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["uid"]) < int(b["uid"]))
	var bag: Array = inventory.bag_items() if inventory != null else []
	_bag_title.text = "Sac (%d)" % bag.size()
	_bank_title.text = "Coffre (%d)" % bank_stacks.size()
	_fill_kamas()
	_grid(_bag_grid, bag.filter(_in_search), BankRules.IN)
	_grid(_bank_grid, bank_stacks.filter(_in_search), BankRules.OUT)


func _in_search(it: Dictionary) -> bool:
	return UiSearch.matches(UiTooltips.item_name(int(it["id"])), _search.text)


## The two purses and the move buttons, greyed when the amount typed is more than the source holds.
func _fill_kamas() -> void:
	var mine := int(_stats.get("kamas", 0))
	_bag_kamas.text = "%s K" % UiStyle.thousands(mine)
	_bank_kamas.text = "%s K" % UiStyle.thousands(_kamas)
	_kamas_amount.max_value = maxf(1, maxf(mine, _kamas))
	var amount := int(_kamas_amount.value)
	_deposit.disabled = amount > mine
	_deposit.tooltip_text = "Vous n'avez pas autant de kamas" if _deposit.disabled else ""
	_withdraw.disabled = amount > _kamas
	_withdraw.tooltip_text = "Le coffre n'en contient pas autant" if _withdraw.disabled else ""


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
