## Marketplace window, roadmap P2.10b: opened by hdv_opened (the dialog of an auction house manager).
## Three tabs: "Acheter" (search by name and category, the lots with price, unit price and the
## comparison with the average price, pages), "Vendre" (the bag: lot size, price, the tax shown)
## and "Mes lots" (on sale / expired, take back). The sim decides everything; MarketModel keeps the
## state and builds the messages. Closing sends hdv_close.
class_name MarketWindow
extends UiWindow

var backend: GameBackend
## the bag (stacks shown in the Vendre tab)
var inventory: InventoryWindow
var model := MarketModel.new()
var tabs: UiTabs
var _name_edit: LineEdit
var _category: OptionButton
var _results: VBoxContainer
var _page_label: Label
var _prev: Button
var _next: Button
var _sell_rows: VBoxContainer
var _mine_rows: VBoxContainer
var _kamas_label: Label
var _stats: Dictionary = {}
var _ending := false
## per bag stack (uid): the lot size index and the price typed, kept across refreshes
var _draft := {}


func setup_window(p_backend: GameBackend) -> void:
	backend = p_backend
	setup("market", "Hôtel de vente", "UI/Figma/menuIcons/1x/inventory")
	default_anchor = Vector2(0.06, 0.35) # left, clear of the map centre
	_kamas_label = UiStyle.label("0 K", UiStyle.KAMAS, 16)
	_kamas_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	body.add_child(_kamas_label)
	tabs = UiTabs.new()
	body.add_child(tabs)
	tabs.add_tab("Acheter", _buy_page())
	_sell_rows = _list_tab("Vendre")
	_mine_rows = _list_tab("Mes lots")
	closed.connect(func() -> void:
		if not _ending:
			backend.send(ProtocolMarket.close()))


func _list_tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 320)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 4)
	scroll.add_child(rows)
	tabs.add_tab(title, scroll)
	return rows


func _buy_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	page.add_child(bar)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Nom de l'objet"
	_name_edit.clear_button_enabled = true
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_submitted.connect(func(_t: String) -> void: search())
	bar.add_child(_name_edit)
	_category = OptionButton.new()
	for c: Array in MarketModel.CATEGORIES:
		_category.add_item(str(c[1]), int(c[0]) + 1) # ids must be >= 0
	bar.add_child(_category)
	var go := Button.new()
	go.text = "Chercher"
	go.theme_type_variation = UiStyle.V_PRIMARY
	go.pressed.connect(search)
	bar.add_child(go)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 280)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_results = VBoxContainer.new()
	_results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_results.add_theme_constant_override("separation", 4)
	scroll.add_child(_results)
	var pager := HBoxContainer.new()
	pager.alignment = BoxContainer.ALIGNMENT_CENTER
	pager.add_theme_constant_override("separation", 10)
	page.add_child(pager)
	_prev = Button.new()
	_prev.text = "<"
	_prev.pressed.connect(func() -> void: _turn(-1))
	pager.add_child(_prev)
	_page_label = UiStyle.label("", UiStyle.TEXT_MUTED, 13)
	pager.add_child(_page_label)
	_next = Button.new()
	_next.text = ">"
	_next.pressed.connect(func() -> void: _turn(1))
	pager.add_child(_next)
	return page


## Sends the search typed in the bar.
func search() -> void:
	backend.send(model.search(_category.get_selected_id() - 1, _name_edit.text))


func _turn(delta: int) -> void:
	var m: Variant = model.turn(delta)
	if m != null:
		backend.send(m)


## hdv_opened event.
func show_market(ev: Dictionary, stats: Dictionary) -> void:
	model.apply_opened(ev)
	_stats = stats
	_draft.clear()
	tabs.select(0)
	_fill_all()
	open()
	search() # the whole market on the first page


## hdv_end: the sim closed it.
func end_market() -> void:
	model.apply_end()
	if not visible:
		return
	_ending = true
	close_window()
	_ending = false


func on_event(t: String, ev: Dictionary) -> void:
	match t:
		ProtocolMarket.RESULTS:
			model.apply_results(ev)
			_fill_results()
		ProtocolMarket.MINE:
			model.apply_mine(ev)
			_fill_sell()
			_fill_mine()


## After each player_stats (kamas and the bag changed).
func set_stats(s: Dictionary) -> void:
	_stats = s
	if visible:
		_kamas_label.text = "%s K" % UiStyle.thousands(int(s.get("kamas", 0)))
		_fill_sell()
		_fill_results()


func _fill_all() -> void:
	_kamas_label.text = "%s K" % UiStyle.thousands(int(_stats.get("kamas", 0)))
	_fill_results()
	_fill_sell()
	_fill_mine()


static func _clear(box: Container) -> void:
	for c: Node in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _fill_results() -> void:
	_clear(_results)
	var kamas := int(_stats.get("kamas", 0))
	for l: Dictionary in model.listings:
		var price := int(l["price"])
		var sub := ""
		if int(l["qty"]) > 1:
			sub = "%s K l'unité" % UiStyle.thousands(MarketModel.unit_price(l))
		var avg := int(l.get("avg", 0))
		if avg > 0:
			sub += (" · " if sub != "" else "") + "moy. %s K (%s)" % [UiStyle.thousands(avg), MarketModel.versus_average(l)]
		var id := int(l["id"])
		_row(_results, l, "%s K" % UiStyle.thousands(price), UiStyle.KAMAS if kamas >= price else UiStyle.BAD, sub,
				"Acheter", kamas < price, "Vous n'avez pas assez de kamas", func() -> void: _buy(id, price, kamas), UiStyle.V_PRIMARY)
	if model.listings.is_empty():
		_results.add_child(UiStyle.label("Aucun lot ne correspond.", UiStyle.TEXT_MUTED, 13))
	_page_label.text = "Page %d / %d · %d lot(s)" % [model.page + 1, model.pages, model.total]
	_prev.disabled = model.page <= 0
	_next.disabled = model.page + 1 >= model.pages


## A purchase: asked first when it is big (ConfirmPolicy), else sent at once.
func _buy(id: int, price: int, kamas: int) -> void:
	if ConfirmPolicy.spend(price, kamas):
		UiConfirm.ask(self, "Confirmer l'achat", ConfirmPolicy.buy_text("Acheter ce lot", price, kamas), "Acheter",
				func() -> void: backend.send(ProtocolMarket.buy(id)), false)
	else:
		backend.send(ProtocolMarket.buy(id))


func _fill_sell() -> void:
	_clear(_sell_rows)
	var kamas := int(_stats.get("kamas", 0))
	var stacks: Array = inventory.bag_items() if inventory != null else []
	var shown := 0
	for it: Dictionary in stacks:
		if not MarketRules.sellable(int(it["id"])):
			continue
		shown += 1
		_sell_row(it, kamas)
	if shown == 0:
		_sell_rows.add_child(UiStyle.label("Votre sac ne contient rien à vendre.", UiStyle.TEXT_MUTED, 13))


func _sell_row(it: Dictionary, kamas: int) -> void:
	var uid := int(it["uid"])
	var have := int(it["qty"])
	var sizes := model.lot_sizes(have)
	var row := UiRow.new()
	_sell_rows.add_child(row)
	var h := row.h
	var slot := ItemSlot.new(int(it["id"]), have)
	slot.instance = {"effects": it["effects"]} if not (it["effects"] as Array).is_empty() else {}
	h.add_child(slot)
	var name := UiStyle.label(UiTooltips.item_name(int(it["id"])), UiStyle.TEXT, 14)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(name)
	var draft: Dictionary = _draft.get(uid, {"lot": 0, "price": maxi(1, int(GameData.item(int(it["id"])).get("price", 1)))})
	var lot_box := OptionButton.new()
	lot_box.tooltip_text = "Taille du lot"
	for q: Variant in sizes:
		lot_box.add_item("x%d" % int(q), int(q))
	h.add_child(lot_box)
	var price := QtyStepper.new(1, MarketRules.MAX_PRICE, false, false)
	price.value = int(draft["price"])
	price.tooltip_text = "Prix du lot, en kamas"
	h.add_child(price)
	var tax := UiStyle.label("", UiStyle.TEXT_MUTED, 12)
	h.add_child(tax)
	var go := Button.new()
	go.text = "Vendre"
	go.theme_type_variation = UiStyle.V_PRIMARY
	h.add_child(go)
	if sizes.is_empty():
		lot_box.disabled = true
		go.disabled = true
		go.tooltip_text = "Pas assez d'exemplaires"
		return
	lot_box.select(clampi(int(draft["lot"]), 0, sizes.size() - 1))
	var refresh := func() -> void:
		var lot := lot_box.get_selected_id()
		_draft[uid] = {"lot": lot_box.selected, "price": int(price.value)}
		var problem := model.sell_problem(have, lot, 1, int(price.value), kamas)
		tax.text = "taxe %s K" % UiStyle.thousands(MarketModel.tax_for(int(price.value), 1))
		go.disabled = problem != ""
		go.tooltip_text = problem
	lot_box.item_selected.connect(func(_i: int) -> void: refresh.call())
	price.value_changed.connect(func(_v: float) -> void: refresh.call())
	go.pressed.connect(func() -> void:
		var msg: Dictionary = model.sell(uid, lot_box.get_selected_id(), int(price.value), 1)
		if ConfirmPolicy.listing(int(price.value)):
			UiConfirm.ask(self, "Mettre en vente", "Mettre ce lot en vente à %s K ? La taxe de %s K n'est pas remboursée."
					% [UiStyle.thousands(int(price.value)), UiStyle.thousands(MarketModel.tax_for(int(price.value), 1))],
					"Vendre", func() -> void: backend.send(msg), false)
		else:
			backend.send(msg))
	refresh.call()


func _fill_mine() -> void:
	_clear(_mine_rows)
	for l: Dictionary in model.mine:
		var id := int(l["id"])
		var expired := bool(l.get("expired", false))
		_row(_mine_rows, l, "%s K" % UiStyle.thousands(int(l["price"])), UiStyle.BAD if expired else UiStyle.KAMAS,
				MarketModel.status(l), "Reprendre", false, "", func() -> void: backend.send(ProtocolMarket.cancel(id)))
	if model.mine.is_empty():
		_mine_rows.add_child(UiStyle.label("Vous n'avez aucun lot en vente.", UiStyle.TEXT_MUTED, 13))
	else:
		_mine_rows.add_child(UiStyle.label("%d / %d lots" % [model.mine.size(), model.max_listings], UiStyle.TEXT_MUTED, 12))


func _row(parent: VBoxContainer, l: Dictionary, price_text: String, price_color: Color, sub: String, button_text: String,
		disabled: bool, why: String, on_press: Callable, variant := "") -> void:
	parent.add_child(UiRow.offer(int(l["item"]), int(l["qty"]), l.get("effects", []), sub, price_text, price_color,
			button_text, disabled, why, on_press, variant))
