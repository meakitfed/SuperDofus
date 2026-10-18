## NPC shop window, roadmap P2.02: opened by shop_open (items and prices from the
## sim, NpcShop). Two tabs: "Acheter" (what the NPC sells) and "Vendre" (the bag,
## bought back at price / sell_divisor). The quantity box applies to both. The sim
## decides everything (kamas, pods, distance): the buttons only grey out what
## cannot work, using NpcShop (shared with the sim). Closing sends shop_close.
class_name ShopWindow
extends UiWindow

var backend: GameBackend
## the bag (stacks shown in the Vendre tab)
var inventory: InventoryWindow
var _qty: QtyStepper
var _search: LineEdit
var _tabs: UiTabs
var _kamas_label: Label
var _buy_rows: VBoxContainer
var _sell_rows: VBoxContainer
var _offers: Array = []
var _divisor := NpcShop.SELL_DIVISOR
var _stats: Dictionary = {}
var _ending := false


func setup_window(p_backend: GameBackend) -> void:
	backend = p_backend
	setup("shop", "Boutique", "UI/Figma/menuIcons/1x/inventory")
	default_anchor = Vector2(0.06, 0.4) # left, clear of the map centre
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	body.add_child(top)
	_search = UiSearch.field("Rechercher un objet", _fill)
	top.add_child(_search)
	_kamas_label = UiStyle.label("0 K", UiStyle.KAMAS, 16)
	top.add_child(_kamas_label)
	var qty_row := HBoxContainer.new()
	qty_row.add_theme_constant_override("separation", 10)
	body.add_child(qty_row)
	qty_row.add_child(UiStyle.label("Quantité", UiStyle.TEXT_MUTED, UiStyle.FS_SMALL + 1))
	_qty = QtyStepper.new(1, NpcShop.MAX_QTY)
	_qty.value_changed.connect(func(_v: float) -> void: _fill())
	qty_row.add_child(_qty)
	_tabs = UiTabs.new()
	body.add_child(_tabs)
	_buy_rows = _tab(_tabs, "Acheter")
	_sell_rows = _tab(_tabs, "Vendre")
	_tabs.tab_changed.connect(func(_i: int) -> void: _fill())
	closed.connect(func() -> void:
		if not _ending:
			backend.send(Protocol.shop_close()))


func _tab(tabs: UiTabs, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 4)
	scroll.add_child(rows)
	tabs.add_tab(title, scroll)
	return rows


## shop_open event.
func show_shop(ev: Dictionary, npc_name: String, stats: Dictionary) -> void:
	title_label.text = npc_name if npc_name != "" else "Boutique"
	_offers = ev["items"]
	_divisor = maxi(1, int(ev.get("sell_divisor", NpcShop.SELL_DIVISOR)))
	_stats = stats
	_search.clear()
	_qty.value = 1
	_tabs.select(0)
	_fill()
	open()


## shop_end: the sim closed it.
func end_shop() -> void:
	_ending = true
	close_window()
	_ending = false


## After each player_stats (kamas, pods and the bag changed).
func set_stats(s: Dictionary) -> void:
	_stats = s
	if visible:
		_fill()


func _fill() -> void:
	if _buy_rows == null:
		return
	var kamas := int(_stats.get("kamas", 0))
	var weight := int(_stats.get("weight", 0))
	var max_weight := int(_stats.get("max_weight", 1000))
	_kamas_label.text = "%s K" % UiStyle.thousands(kamas)
	var stacks: Array = inventory.bag_items() if inventory != null else []
	# "Max": the most this tab can do (what the cheapest offer lets you pay, or the biggest stack)
	if _tabs.current == 1:
		var biggest := 1
		for it: Dictionary in stacks:
			biggest = maxi(biggest, int(it["qty"]))
		_qty.max_value = minf(biggest, NpcShop.MAX_QTY)
	else:
		var cheapest := 0
		for o: Dictionary in _offers:
			var p := int(o["price"])
			cheapest = p if cheapest == 0 else mini(cheapest, p)
		_qty.max_value = clampf(kamas / cheapest if cheapest > 0 else NpcShop.MAX_QTY, 1, NpcShop.MAX_QTY)
	var qty := int(_qty.value)
	var q := _search.text
	for c: Node in _buy_rows.get_children():
		c.queue_free()
	var shown := 0
	for o: Dictionary in _offers:
		var id := int(o["item"])
		if not UiSearch.matches(UiTooltips.item_name(id), q):
			continue
		shown += 1
		var err := NpcShop.check_buy({"items": [id]}, id, qty, kamas, weight, max_weight)
		var cost := int(o["price"]) * qty
		var sub := "%s K l'unité" % UiStyle.thousands(int(o["price"])) if qty > 1 else ""
		_buy_rows.add_child(UiRow.offer(id, 1, [], sub, "%s K" % UiStyle.thousands(cost),
				UiStyle.KAMAS if kamas >= cost else UiStyle.BAD, "Acheter", err != "", _tip(err),
				func() -> void: _buy(id, qty, cost, kamas), UiStyle.V_PRIMARY))
	if _offers.is_empty():
		_buy_rows.add_child(UiStyle.label("Cette boutique est vide.", UiStyle.TEXT_MUTED, 13))
	elif shown == 0:
		_buy_rows.add_child(UiStyle.label("Aucun objet ne correspond.", UiStyle.TEXT_MUTED, 13))
	for c: Node in _sell_rows.get_children():
		c.queue_free()
	shown = 0
	for it: Dictionary in stacks:
		var id := int(it["id"])
		if not UiSearch.matches(UiTooltips.item_name(id), q):
			continue
		shown += 1
		var n := mini(qty, int(it["qty"]))
		var gain := NpcShop.sell_price(id) * n
		var ok := NpcShop.sellable(id) and qty <= int(it["qty"])
		var uid := int(it["uid"])
		var sellable := NpcShop.sellable(id)
		_sell_rows.add_child(UiRow.offer(id, int(it["qty"]), it["effects"], "", "%s K" % UiStyle.thousands(gain) if sellable else "Non racheté",
				UiStyle.KAMAS if sellable else UiStyle.TEXT_MUTED, "Vendre", not ok,
				"Pas assez d'exemplaires" if sellable else "Ce PNJ ne rachète pas cet objet",
				func() -> void: backend.send(Protocol.shop_sell(uid, qty))))
	if stacks.is_empty():
		_sell_rows.add_child(UiStyle.label("Votre sac ne contient rien à vendre.", UiStyle.TEXT_MUTED, 13))
	elif shown == 0:
		_sell_rows.add_child(UiStyle.label("Aucun objet ne correspond.", UiStyle.TEXT_MUTED, 13))


## A purchase: asked first when it is big (ConfirmPolicy), else sent at once.
func _buy(id: int, qty: int, cost: int, kamas: int) -> void:
	if ConfirmPolicy.spend(cost, kamas):
		UiConfirm.ask(self, "Confirmer l'achat",
				ConfirmPolicy.buy_text("Acheter %d x %s" % [qty, UiTooltips.item_name(id)], cost, kamas),
				"Acheter", func() -> void: backend.send(Protocol.shop_buy(id, qty)), false)
	else:
		backend.send(Protocol.shop_buy(id, qty))


func _tip(err: String) -> String:
	match err:
		Protocol.E_NOT_ENOUGH_KAMAS:
			return "Vous n'avez pas assez de kamas"
		Protocol.E_OVERLOADED:
			return "Vous seriez surchargé"
	return ""
