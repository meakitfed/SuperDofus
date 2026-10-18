## Smithmagic window (K), roadmap P2.07b: pick a forgemagus workshop, an equipment of the bag and a rune,
## read the preview (chance, critical, overmax refused, puits), apply (fm_apply) and follow the history of
## fm_result. The rules are Smithmagic (shared) and the sim's; the state is a SmithmagicModel, the window
## only shows it.
class_name SmithmagicWindow
extends UiWindow

const COLUMNS := 5
const ROWS := 3
const OUTCOME_COLORS := {
	Smithmagic.CRIT: UiStyle.GOLD,
	Smithmagic.SUCCESS: UiStyle.GOOD,
	Smithmagic.NEUTRAL: UiStyle.TEXT_MUTED,
	Smithmagic.FAIL: UiStyle.BAD,
	Smithmagic.OVERMAX: UiStyle.XP,
}

var backend: GameBackend
## the bag (stacks shown on the left)
var inventory: InventoryWindow
var model := SmithmagicModel.new()
var _skills: OptionButton
var _item_grid: GridContainer
var _rune_grid: GridContainer
var _item_box: VBoxContainer
var _preview: Label
var _chance: UiBar
var _search: LineEdit
var _reserve: Label
var _apply: Button
var _history: VBoxContainer
var _dirty := false


func setup_window(p_backend: GameBackend) -> void:
	backend = p_backend
	setup("smithmagic", "Forgemagie", "UI/Figma/menuIcons/1x/equipments")
	default_anchor = Vector2(0.06, 0.25) # left, clear of the map centre
	_skills = OptionButton.new()
	for sk: int in Smithmagic.workshops():
		_skills.add_item(DofusI18n.text(int(Jobs.skill(sk).get("nameId", 0)), "Atelier %d" % sk), sk)
	_skills.item_selected.connect(func(i: int) -> void:
		model.set_skill(_skills.get_item_id(i))
		_fill())
	body.add_child(_skills)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	body.add_child(cols)
	var bag := VBoxContainer.new()
	cols.add_child(bag)
	_search = UiSearch.field("Rechercher un équipement", _fill, 120)
	bag.add_child(_search)
	bag.add_child(UiStyle.heading("Équipements du sac"))
	_item_grid = _grid(bag)
	bag.add_child(UiStyle.heading("Runes"))
	_rune_grid = _grid(bag)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 6)
	side.custom_minimum_size = Vector2(300, 0)
	cols.add_child(side)
	side.add_child(UiStyle.heading("Objet à forger"))
	_item_box = VBoxContainer.new()
	side.add_child(_item_box)
	_reserve = UiStyle.label("", UiStyle.TEXT_MUTED, 13)
	side.add_child(_reserve)
	_chance = UiBar.new(UiStyle.GOOD, 16)
	side.add_child(_chance)
	_preview = UiStyle.label("", UiStyle.TEXT, 13)
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_preview)
	_apply = Button.new()
	_apply.text = "Forger"
	_apply.theme_type_variation = UiStyle.V_PRIMARY
	_apply.pressed.connect(_forge)
	side.add_child(_apply)
	side.add_child(UiStyle.heading("Historique"))
	_history = VBoxContainer.new()
	side.add_child(_history)


## Forge: a try with a low chance is confirmed first (the item can lose characteristics).
func _forge() -> void:
	var bag := _bag()
	var m: Variant = model.apply(bag)
	if m == null:
		return
	var pv := model.preview(bag)
	if not pv.is_empty() and str(pv["kind"]) != Smithmagic.OVERMAX and ConfirmPolicy.forge(int(pv["chance"])):
		UiConfirm.ask(self, "Forger", "Seulement %d %% de réussite : l'objet peut perdre des caractéristiques. Forger quand même ?" % int(pv["chance"]),
				"Forger", func() -> void: backend.send(m))
	else:
		backend.send(m)


func _grid(parent: Control) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)
	return grid


func _bag() -> Array:
	return inventory.bag_items() if inventory != null else []


## The K key.
func toggle_workshop() -> void:
	if visible:
		close_window()
	else:
		_fill()
		open()


## fm_result: follows the item and the history; returns the line for the toast.
func show_result(ev: Dictionary) -> String:
	model.on_result(ev)
	_refill()
	return SmithmagicModel.result_text(model.history[0])


## After inventory events (the bag changed).
func refresh_bag() -> void:
	if visible:
		_refill()


## Several events in one frame rebuild the window once.
func _refill() -> void:
	if not _dirty:
		_dirty = true
		_fill.call_deferred()


func _fill() -> void:
	if _search == null:
		return
	_dirty = false
	var bag := _bag()
	var q := _search.text
	var items := model.forgeable(bag).filter(func(it: Dictionary) -> bool: return UiSearch.matches(UiTooltips.item_name(int(it["id"])), q))
	_fill_slots(_item_grid, items, func(s: ItemSlot) -> void: model.item_uid = int(s.instance["uid"]); _fill(), model.item_uid)
	_fill_slots(_rune_grid, SmithmagicModel.runes_in(bag), func(s: ItemSlot) -> void: model.rune = int(s.instance["id"]); _fill(), 0)
	for c: Node in _item_box.get_children():
		c.queue_free()
	var it := model.picked(bag)
	if it.is_empty():
		_item_box.add_child(UiStyle.label("Choisissez un équipement.", UiStyle.TEXT_MUTED, 13))
	else:
		_item_box.add_child(UiStyle.label(UiTooltips.item_name(int(it["id"])), UiStyle.GOLD, 14))
		for e: Array in it["effects"]:
			var max_value := Smithmagic.maximum(int(it["id"]), int(e[0]))
			var line := "%s : %d" % [SmithmagicModel.effect_name(int(e[0])), int(e[1])]
			_item_box.add_child(UiStyle.label(line + (" / %d" % max_value if max_value > 0 else ""), UiStyle.TEXT, 13))
	_reserve.text = "Puits : %s" % UiStyle.thousands(int(it.get("reserve", 0)) / 100) if not it.is_empty() else ""
	var pv := model.preview(bag)
	var usable := not pv.is_empty() and str(pv["refused"]) == ""
	_chance.visible = usable and str(pv["kind"]) != Smithmagic.OVERMAX
	if _chance.visible:
		var chance := int(pv["chance"])
		_chance.add_theme_stylebox_override("fill", UiStyle.bar_fill(UiStyle.GOOD if chance >= 50 else (UiStyle.ENERGY if chance >= 25 else UiStyle.BAD)))
		_chance.set_values(chance, 100, "%d %%" % chance)
	if pv.is_empty():
		_preview.text = "Choisissez un équipement et une rune." if model.rune == 0 or it.is_empty() else ""
	elif str(pv["refused"]) != "":
		_preview.text = SmithmagicModel.refused_text(str(pv["refused"]))
	elif str(pv["kind"]) == Smithmagic.OVERMAX:
		_preview.text = "Dépassement du maximum : réussite sûre, la rune est payée par le puits."
	else:
		_preview.text = "Réussite %d %%, dont critique %d %%." % [int(pv["chance"]), int(pv["crit"])]
	_apply.disabled = not model.can_apply(bag)
	for c: Node in _history.get_children():
		c.queue_free()
	for h: Dictionary in model.history.slice(0, 6):
		_history.add_child(UiStyle.label(SmithmagicModel.result_text(h), OUTCOME_COLORS.get(h["outcome"], UiStyle.TEXT), 13))


func _fill_slots(grid: GridContainer, stacks: Array, on_click: Callable, selected_uid: int) -> void:
	for c: Node in grid.get_children():
		c.queue_free()
	for it: Dictionary in stacks:
		var slot := ItemSlot.new()
		slot.set_instance(it)
		slot.selected = (selected_uid != 0 and int(it["uid"]) == selected_uid) or (selected_uid == 0 and grid == _rune_grid and int(it["id"]) == model.rune)
		slot.clicked.connect(func(s: ItemSlot, _b: int) -> void: on_click.call(s))
		grid.add_child(slot)
	for j in range(stacks.size(), maxi(COLUMNS * ROWS, stacks.size() + (COLUMNS - stacks.size() % COLUMNS) % COLUMNS)):
		grid.add_child(ItemSlot.new())
