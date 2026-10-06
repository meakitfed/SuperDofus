## Trade window (P3.11b), opened by trade_open. Top: my offer (left) and the other player's (right),
## each with its kamas and its "validé" state; bottom: my bag (double-click a stack puts the
## quantity of the box into the offer, double-click an offered stack takes it back). Valider / Annuler
## at the bottom. The sim decides everything: the state is a TradeModel, the window only shows it
## and sends ProtocolTrade messages. Closing the window cancels the trade.
class_name TradeWindow
extends UiWindow

const COLUMNS := 5
const OFFER_ROWS := 3
const BAG_ROWS := 3

var backend: GameBackend
## the bag (stacks shown at the bottom)
var inventory: InventoryWindow
var model := TradeModel.new()
var _stats: Dictionary = {}
var _qty: SpinBox
var _kamas: SpinBox
var _mine_title: Label
var _theirs_title: Label
var _mine_state: Label
var _theirs_state: Label
var _theirs_kamas: Label
var _mine_grid: GridContainer
var _theirs_grid: GridContainer
var _bag_grid: GridContainer
var _ready_button: Button
var _ending := false


func setup_window(p_backend: GameBackend) -> void:
	backend = p_backend
	setup("trade", "Échange", "UI/Figma/menuIcons/1x/inventory")
	default_anchor = Vector2(0.45, 0.35)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	body.add_child(cols)
	var left := _side(cols)
	_mine_title = left[0]
	_mine_grid = left[1]
	_mine_state = left[2]
	var kamas_row := HBoxContainer.new()
	kamas_row.add_theme_constant_override("separation", 6)
	left[3].add_child(kamas_row)
	kamas_row.add_child(UiStyle.label("Kamas", UiStyle.KAMAS, 13))
	_kamas = SpinBox.new()
	_kamas.min_value = 0
	_kamas.max_value = TradeRules.MAX_QTY * 1000
	_kamas.custom_minimum_size = Vector2(110, 0)
	kamas_row.add_child(_kamas)
	var put := Button.new()
	put.text = "Poser"
	put.pressed.connect(func() -> void: _send(model.with_kamas(int(_kamas.value), int(_stats.get("kamas", 0)))))
	kamas_row.add_child(put)
	var right := _side(cols)
	_theirs_title = right[0]
	_theirs_grid = right[1]
	_theirs_state = right[2]
	_theirs_kamas = UiStyle.label("0 K", UiStyle.KAMAS, 14)
	right[3].add_child(_theirs_kamas)
	var bag_row := HBoxContainer.new()
	bag_row.add_theme_constant_override("separation", 10)
	body.add_child(bag_row)
	bag_row.add_child(UiStyle.label("Votre sac, quantité", UiStyle.TEXT, 14))
	_qty = SpinBox.new()
	_qty.min_value = 1
	_qty.max_value = TradeRules.MAX_QTY
	_qty.value = 1
	bag_row.add_child(_qty)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(COLUMNS * (ItemSlot.SIZE + 4) + 8, BAG_ROWS * (ItemSlot.SIZE + 4))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_bag_grid = _grid()
	scroll.add_child(_bag_grid)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	body.add_child(buttons)
	var cancel := Button.new()
	cancel.text = "Annuler"
	cancel.pressed.connect(func() -> void: close_window())
	buttons.add_child(cancel)
	_ready_button = Button.new()
	_ready_button.text = "Valider"
	_ready_button.pressed.connect(func() -> void:
		if model.can_ready():
			backend.send(ProtocolTrade.ready()))
	buttons.add_child(_ready_button)
	closed.connect(func() -> void:
		if not _ending and model.is_open:
			backend.send(ProtocolTrade.cancel())
		model.close())


## One column: [title, grid, state label, the box for the kamas line].
func _side(parent: HBoxContainer) -> Array:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	parent.add_child(box)
	var title := UiStyle.label("", UiStyle.TEXT, 14)
	box.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(COLUMNS * (ItemSlot.SIZE + 4) + 8, OFFER_ROWS * (ItemSlot.SIZE + 4))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var grid := _grid()
	scroll.add_child(grid)
	var kamas_box := VBoxContainer.new()
	box.add_child(kamas_box)
	var state := UiStyle.label("", UiStyle.TEXT_MUTED, 13)
	box.add_child(state)
	return [title, grid, state, kamas_box]


func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	return grid


func _send(msg: Variant) -> void:
	if msg != null:
		backend.send(msg)


## The trade events, routed here by ClientSession. `invites_changed` is called for the invitation list.
func on_event(t: String, ev: Dictionary, toast: Toast) -> void:
	match t:
		ProtocolTrade.INVITED:
			model.apply_invited(str(ev["from"]), Time.get_ticks_msec())
			if toast != null:
				toast.show_text("%s vous propose un échange" % str(ev["from"]))
		ProtocolTrade.OPEN:
			model.apply_open(ev)
			_kamas.value = 0
			_fill()
			open()
		ProtocolTrade.UPDATE:
			if model.is_open:
				model.apply_update(ev)
				_fill()
		ProtocolTrade.END:
			end_trade()
			var text := TradeModel.end_text(str(ev["reason"]), str(ev.get("code", "")))
			if toast != null and text != "":
				toast.show_text(text)


## The sim ended it (or the map changed): close without cancelling again.
func end_trade() -> void:
	_ending = true
	close_window()
	_ending = false
	model.close()


## After each player_stats (kamas changed).
func set_stats(s: Dictionary) -> void:
	_stats = s
	if visible:
		_fill()


## The bag changed (a stack arrived or left).
func refresh_bag() -> void:
	if visible:
		_fill()


func _fill() -> void:
	_mine_title.text = "Vous"
	_theirs_title.text = model.with
	_mine_state.text = model.status_text(model.mine)
	_mine_state.add_theme_color_override("font_color", UiStyle.GOLD if bool(model.mine["ready"]) else UiStyle.TEXT_MUTED)
	_theirs_state.text = model.status_text(model.theirs)
	_theirs_state.add_theme_color_override("font_color", UiStyle.GOLD if bool(model.theirs["ready"]) else UiStyle.TEXT_MUTED)
	_theirs_kamas.text = "%s K" % UiStyle.thousands(int(model.theirs["kamas"]))
	_kamas.max_value = maxi(int(_stats.get("kamas", 0)), 0)
	_kamas.value = model.my_kamas()
	_ready_button.disabled = not model.can_ready()
	_offer_grid(_mine_grid, model.mine["items"], true)
	_offer_grid(_theirs_grid, model.theirs["items"], false)
	_bag()


func _offer_grid(grid: GridContainer, stacks: Array, mine: bool) -> void:
	for c: Node in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	for it: Dictionary in stacks:
		var slot := ItemSlot.new()
		slot.set_instance(it)
		if mine:
			slot.activated.connect(func(s: ItemSlot) -> void: _send(model.remove(int(s.instance["uid"]))))
		grid.add_child(slot)
	for j in range(stacks.size(), COLUMNS * OFFER_ROWS):
		grid.add_child(ItemSlot.new())


func _bag() -> void:
	for c: Node in _bag_grid.get_children():
		_bag_grid.remove_child(c)
		c.queue_free()
	var shown := 0
	for it: Dictionary in inventory.bag_items() if inventory != null else []:
		var left := int(it["qty"]) - model.offered_qty(int(it["uid"]))
		if left < 1:
			continue
		var stack := it.duplicate()
		stack["qty"] = left
		var slot := ItemSlot.new()
		slot.set_instance(stack)
		slot.activated.connect(func(s: ItemSlot) -> void:
			_send(model.add(int(s.instance["uid"]), int(_qty.value), int(s.instance["qty"]) + model.offered_qty(int(s.instance["uid"])))))
		_bag_grid.add_child(slot)
		shown += 1
	for j in range(shown, COLUMNS * BAG_ROWS):
		_bag_grid.add_child(ItemSlot.new())
