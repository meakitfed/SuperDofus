## Inventory window (I), roadmap P1.05: kamas, pods gauge (red when
## overloaded), sort, then the item stacks by category tabs (all, equipment,
## consumables, resources, quest) in a grid of ItemSlots with rich tooltips
## (rolled effects). Double-click uses an item, right-click opens Use /
## Destroy. Fed by inventory / item_added / item_removed and player_stats; the
## game decides everything (use_item, destroy_item).
class_name InventoryWindow
extends UiWindow

const COLUMNS := 7
const MIN_SLOTS := 28
## tab -> the item categories it shows (itemtypes.categoryId: 0 equipment,
## 1 consumables, 2 resources, 3 quest items); [] = all
const TABS := [["Tout", "UI/Figma/menuIcons/1x/inventory", []],
		["Équipement", "UI/Figma/menuIcons/1x/equipments", [0]],
		["Consommables", "UI/Figma/menuIcons/1x/consumables", [1]],
		["Ressources", "UI/Figma/menuIcons/1x/resources", [2]],
		["Quête", "UI/Figma/menuIcons/1x/quest", [3]]]
const SORTS := ["Type", "Nom", "Niveau", "Poids", "Quantité"]

var backend: GameBackend
## shows the worn items (pos >= 0), which the bag grids leave out
var equipment: EquipmentWindow
var _look := ""
var _kamas: Label
var _pods: UiBar
var _sort: OptionButton
var _grids: Array[GridContainer] = []
var _items := {} # uid -> item dict
var _dirty := false


func setup_window(p_backend: GameBackend = null) -> void:
	backend = p_backend
	setup("inventory", "Inventaire", "UI/Figma/menuIcons/1x/inventory")
	default_anchor = Vector2(0.92, 0.35)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	body.add_child(top)
	top.add_child(UiStyle.icon("UI/Figma/characteristics/characteristicIcon/1x/tx_pods", 20, Color.WHITE))
	_pods = UiBar.new(UiStyle.GOOD, 16)
	_pods.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_pods)
	_kamas = UiStyle.label("0 K", UiStyle.KAMAS, 16)
	top.add_child(_kamas)
	var sort_row := HBoxContainer.new()
	body.add_child(sort_row)
	sort_row.add_child(UiStyle.label("Trier par", UiStyle.TEXT_MUTED, 13))
	_sort = OptionButton.new()
	_sort.focus_mode = Control.FOCUS_NONE
	for s: String in SORTS:
		_sort.add_item(s)
	_sort.item_selected.connect(func(_i: int) -> void: _fill())
	sort_row.add_child(_sort)
	var tabs := UiTabs.new()
	tabs.icons_only = true
	body.add_child(tabs)
	for t: Array in TABS:
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(COLUMNS * (ItemSlot.SIZE + 4), 4 * (ItemSlot.SIZE + 4))
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var grid := GridContainer.new()
		grid.columns = COLUMNS
		grid.add_theme_constant_override("h_separation", 4)
		grid.add_theme_constant_override("v_separation", 4)
		scroll.add_child(grid)
		_grids.append(grid)
		tabs.add_tab(t[0], scroll, t[1])
	_fill()


func set_stats(s: Dictionary) -> void:
	if str(s.get("look", "")) != _look:
		_look = str(s.get("look", ""))
		_refill()
	_kamas.text = "%s K" % UiStyle.thousands(int(s.get("kamas", 0)))
	var w := int(s.get("weight", 0))
	var mw := int(s.get("max_weight", 1000))
	_pods.set_values(w, mw, "%s / %s pods" % [UiStyle.thousands(w), UiStyle.thousands(mw)])
	_pods.add_theme_stylebox_override("fill", UiStyle.bar_fill(UiStyle.BAD if w > mw else UiStyle.GOOD))
	_pods.tooltip_text = "Surchargé : impossible de bouger" if w > mw else "Pods : 1 000 + 5 × Force"


## inventory event: every stack.
func set_items(items: Array) -> void:
	_items.clear()
	for it: Dictionary in items:
		_items[int(it["uid"])] = it
	_refill()


## item_added: a stack appears or changes quantity.
func put_item(it: Dictionary) -> void:
	_items[int(it["uid"])] = it
	_refill()


## item_removed.
func remove_item(uid: int) -> void:
	_items.erase(uid)
	_refill()


## The stacks in the bag (not worn), by uid (the shop's Vendre tab).
func bag_items() -> Array:
	var out := _items.values().filter(func(it: Dictionary) -> bool: return int(it.get("pos", -1)) < 0)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["uid"]) < int(b["uid"]))
	return out


func item_count(item_id: int) -> int:
	var n := 0
	for it: Dictionary in _items.values():
		if int(it["id"]) == item_id:
			n += int(it["qty"])
	return n


## Several events in one frame rebuild the grids once.
func _refill() -> void:
	if not _dirty:
		_dirty = true
		_fill.call_deferred()


func _sorted() -> Array:
	var list: Array = _items.values()
	var key := _sort.selected if _sort != null else 0
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := GameData.item(int(a["id"]))
		var db := GameData.item(int(b["id"]))
		var ka: Variant
		var kb: Variant
		match key:
			1: ka = UiTooltips.item_name(int(a["id"])); kb = UiTooltips.item_name(int(b["id"]))
			2: ka = -int(da.get("level", 0)); kb = -int(db.get("level", 0))
			3: ka = -int(da.get("weight", 0)) * int(a["qty"]); kb = -int(db.get("weight", 0)) * int(b["qty"])
			4: ka = -int(a["qty"]); kb = -int(b["qty"])
			_: ka = int(da.get("type", 0)); kb = int(db.get("type", 0))
		return ka < kb if ka != kb else int(a["uid"]) < int(b["uid"]))
	return list


func _fill() -> void:
	_dirty = false
	var list := _sorted()
	for i in _grids.size():
		var grid := _grids[i]
		for c: Node in grid.get_children():
			c.queue_free()
		var wanted: Array = TABS[i][2]
		var n := 0
		for it: Dictionary in list:
			if int(it.get("pos", -1)) >= 0:
				continue # worn: in the equipment window
			var type := GameData.row("itemtypes", int(GameData.item(int(it["id"])).get("type", 0)))
			if wanted.is_empty() or int(type.get("categoryId", -1)) in wanted:
				var slot := ItemSlot.new()
				slot.set_instance(it)
				slot.activated.connect(func(s: ItemSlot) -> void: _use(s.instance))
				slot.clicked.connect(_on_slot_clicked)
				_bag_drop(slot)
				grid.add_child(slot)
				n += 1
		for j in range(n, maxi(MIN_SLOTS, n + (COLUMNS - n % COLUMNS) % COLUMNS)):
			grid.add_child(_bag_drop(ItemSlot.new()))
	if equipment != null:
		equipment.refresh(_items, _look)


## Every bag cell takes a worn item back (unequip).
func _bag_drop(slot: ItemSlot) -> ItemSlot:
	slot.drop_slot = -1
	slot.dropped.connect(func(uid: int, _to: int) -> void:
		var it: Dictionary = _items.get(uid, {})
		if not it.is_empty() and int(it.get("pos", -1)) >= 0:
			backend.send(Protocol.unequip(int(it["pos"]))))
	return slot


func _on_slot_clicked(slot: ItemSlot, button: int) -> void:
	if button != MOUSE_BUTTON_RIGHT or slot.item_id == 0:
		return
	var it := slot.instance
	var usable := bool(GameData.item(slot.item_id).get("usable", false))
	var entries: Array = [["Utiliser", func() -> void: _use(it), usable]]
	if not Equipment.positions(slot.item_id).is_empty():
		entries.append(["Équiper", func() -> void: _equip(it)])
	entries.append(["Détruire…", func() -> void: _confirm_destroy(it)])
	ContextMenu.popup(self, get_global_mouse_position(), UiTooltips.item_name(slot.item_id), entries)


func _use(it: Dictionary) -> void:
	if backend == null:
		return
	if bool(GameData.item(int(it["id"])).get("usable", false)):
		backend.send(Protocol.use_item(int(it["uid"])))
	elif not Equipment.positions(int(it["id"])).is_empty():
		_equip(it)


## Into the first free slot it fits (else the first one: the worn item comes back).
func _equip(it: Dictionary) -> void:
	var slots := Equipment.positions(int(it["id"]))
	var taken := {}
	for other: Dictionary in _items.values():
		taken[int(other.get("pos", -1))] = true
	var free := slots.filter(func(s: int) -> bool: return not taken.has(s))
	backend.send(Protocol.equip(int(it["uid"]), int(free[0]) if not free.is_empty() else int(slots[0])))


func _confirm_destroy(it: Dictionary) -> void:
	var qty := int(it["qty"])
	var what := UiTooltips.item_name(int(it["id"])) + (" (×%d)" % qty if qty > 1 else "")
	UiConfirm.ask(get_parent(), "Détruire", "Détruire définitivement %s ?" % what, "Détruire",
			func() -> void: backend.send(Protocol.destroy_item(int(it["uid"]))))
