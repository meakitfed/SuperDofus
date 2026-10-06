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
var _qty: SpinBox
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
	default_anchor = Vector2(0.3, 0.4)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	body.add_child(top)
	top.add_child(UiStyle.label("Quantité", UiStyle.TEXT_MUTED, 13))
	_qty = SpinBox.new()
	_qty.min_value = 1
	_qty.max_value = NpcShop.MAX_QTY
	_qty.value = 1
	_qty.value_changed.connect(func(_v: float) -> void: _fill())
	top.add_child(_qty)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(gap)
	_kamas_label = UiStyle.label("0 K", UiStyle.KAMAS, 16)
	top.add_child(_kamas_label)
	var tabs := UiTabs.new()
	body.add_child(tabs)
	_buy_rows = _tab(tabs, "Acheter")
	_sell_rows = _tab(tabs, "Vendre")
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
	var kamas := int(_stats.get("kamas", 0))
	var weight := int(_stats.get("weight", 0))
	var max_weight := int(_stats.get("max_weight", 1000))
	_kamas_label.text = "%s K" % UiStyle.thousands(kamas)
	var qty := int(_qty.value)
	for c: Node in _buy_rows.get_children():
		c.queue_free()
	for o: Dictionary in _offers:
		var id := int(o["item"])
		var err := NpcShop.check_buy({"items": [id]}, id, qty, kamas, weight, max_weight)
		var cost := int(o["price"]) * qty
		_row(_buy_rows, id, 1, "%s K" % UiStyle.thousands(cost), UiStyle.KAMAS if kamas >= cost else UiStyle.BAD,
				"Acheter", err != "", _tip(err), func() -> void: backend.send(Protocol.shop_buy(id, qty)))
	if _offers.is_empty():
		_buy_rows.add_child(UiStyle.label("Cette boutique est vide.", UiStyle.TEXT_MUTED, 13))
	for c: Node in _sell_rows.get_children():
		c.queue_free()
	var stacks: Array = inventory.bag_items() if inventory != null else []
	for it: Dictionary in stacks:
		var id := int(it["id"])
		var n := mini(qty, int(it["qty"]))
		var gain := NpcShop.sell_price(id) * n
		var ok := NpcShop.sellable(id) and qty <= int(it["qty"])
		var uid := int(it["uid"])
		_row(_sell_rows, id, int(it["qty"]), "%s K" % UiStyle.thousands(gain) if NpcShop.sellable(id) else "Non racheté",
				UiStyle.KAMAS if NpcShop.sellable(id) else UiStyle.TEXT_MUTED, "Vendre", not ok,
				"Pas assez d'exemplaires" if NpcShop.sellable(id) else "Ce PNJ ne rachète pas cet objet",
				func() -> void: backend.send(Protocol.shop_sell(uid, qty)), it["effects"])
	if stacks.is_empty():
		_sell_rows.add_child(UiStyle.label("Votre sac ne contient rien à vendre.", UiStyle.TEXT_MUTED, 13))


func _row(parent: VBoxContainer, item_id: int, have: int, price_text: String, price_color: Color, button_text: String,
		disabled: bool, why: String, on_press: Callable, effects: Array = []) -> void:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UiStyle.panel(UiStyle.BG_INSET, UiStyle.BORDER, 4, 6))
	parent.add_child(row)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	row.add_child(h)
	var slot := ItemSlot.new(item_id, have)
	slot.instance = {"effects": effects} if not effects.is_empty() else {}
	h.add_child(slot)
	var name := UiStyle.label(UiTooltips.item_name(item_id), UiStyle.TEXT, 14)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(name)
	h.add_child(UiStyle.label(price_text, price_color, 14))
	var b := Button.new()
	b.text = button_text
	b.disabled = disabled
	b.tooltip_text = why if disabled else ""
	b.pressed.connect(on_press)
	h.add_child(b)


func _tip(err: String) -> String:
	match err:
		Protocol.E_NOT_ENOUGH_KAMAS:
			return "Vous n'avez pas assez de kamas"
		Protocol.E_OVERLOADED:
			return "Vous seriez surchargé"
	return ""
