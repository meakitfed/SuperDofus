## Roleplay HUD (bottom left): level, HP bar (regenerating, computed from the
## game time like Movement), XP bar and kamas, plus the characteristics (C)
## and inventory (I) windows, the spell bar (bottom centre) and the spell
## book (S). Fed by player_stats events.
class_name PlayerHud
extends Control

var backend: GameBackend
var stats := {} # last "character dict" (Protocol)
var characteristics: CharacteristicsWindow
var inventory: InventoryWindow
var spell_book: SpellBookWindow
var equipment: EquipmentWindow
var world_map: WorldMapWindow
var zaap: ZaapWindow
var dialog: DialogWindow
var shop: ShopWindow
var bank: BankWindow
var craft: CraftWindow
var smith: SmithmagicWindow
var quests: QuestWindow
var tracker: QuestTracker
var party: PartyFrame
var trade: TradeWindow
var contacts: ContactsWindow
var trade_invites: TradeInvites
var spell_bar: SpellBar
var _bar_box: PanelContainer

var _box: PanelContainer
var _level: Label
var _xp: UiBar
var _hp: UiBar
var _kamas: Label


func setup(p_backend: GameBackend) -> void:
	backend = p_backend
	theme = ClientTheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box = PanelContainer.new()
	_box.add_theme_stylebox_override("panel", UiStyle.panel(Color(UiStyle.BG, 0.85), UiStyle.BORDER, 6, 8))
	add_child(_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_box.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	v.add_child(top)
	_level = UiStyle.label("", UiStyle.TEXT)
	top.add_child(_level)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	_kamas = UiStyle.label("", UiStyle.KAMAS)
	top.add_child(_kamas)
	_hp = UiBar.new(UiStyle.HP, 16)
	_hp.custom_minimum_size = Vector2(260, 16)
	v.add_child(_hp)
	_xp = UiBar.new(UiStyle.XP, 8)
	v.add_child(_xp)
	characteristics = CharacteristicsWindow.new()
	add_child(characteristics)
	characteristics.setup_window(backend)
	inventory = InventoryWindow.new()
	add_child(inventory)
	inventory.setup_window(backend)
	equipment = EquipmentWindow.new()
	add_child(equipment)
	equipment.setup_window(backend)
	inventory.equipment = equipment
	spell_book = SpellBookWindow.new()
	add_child(spell_book)
	spell_book.setup_window(backend)
	world_map = WorldMapWindow.new()
	add_child(world_map)
	world_map.setup_window()
	zaap = ZaapWindow.new()
	add_child(zaap)
	zaap.setup_window(backend)
	dialog = DialogWindow.new()
	add_child(dialog)
	dialog.setup_window(backend)
	shop = ShopWindow.new()
	add_child(shop)
	shop.setup_window(backend)
	shop.inventory = inventory
	bank = BankWindow.new()
	add_child(bank)
	bank.setup_window(backend)
	bank.inventory = inventory
	craft = CraftWindow.new()
	add_child(craft)
	craft.setup_window(backend)
	craft.inventory = inventory
	smith = SmithmagicWindow.new()
	add_child(smith)
	smith.setup_window(backend)
	smith.inventory = inventory
	quests = QuestWindow.new()
	add_child(quests)
	quests.setup_window(backend)
	tracker = QuestTracker.new()
	add_child(tracker)
	tracker.setup(quests)
	party = PartyFrame.new()
	add_child(party)
	party.setup(backend)
	trade = TradeWindow.new()
	add_child(trade)
	trade.setup_window(backend)
	trade.inventory = inventory
	contacts = ContactsWindow.new()
	add_child(contacts)
	contacts.setup_window(backend)
	trade_invites = TradeInvites.new() # under the group frame (same column)
	party.add_child(trade_invites)
	trade_invites.setup(backend, trade)
	_bar_box = PanelContainer.new()
	_bar_box.add_theme_stylebox_override("panel", UiStyle.panel(Color(UiStyle.BG, 0.85), UiStyle.BORDER, 6, 6))
	add_child(_bar_box)
	spell_bar = SpellBar.new()
	spell_bar.moved.connect(func(spell: int, slot: int) -> void: backend.send(Protocol.move_spell(spell, slot)))
	_bar_box.add_child(spell_bar)


## The bag changed: the windows that show it follow.
func bags_changed() -> void:
	craft.refresh_bag()
	smith.refresh_bag()
	trade.refresh_bag()


func set_stats(s: Dictionary) -> void:
	stats = s
	var floor_xp := int(s["xp_floor"])
	_level.text = "Niveau %d" % int(s["level"]) + ("  ·  Fantôme" if int(s.get("life", 0)) == 2 else "")
	_level.add_theme_color_override("font_color", UiStyle.GHOST if int(s.get("life", 0)) == 2 else UiStyle.TEXT)
	_xp.set_values(int(s["xp"]) - floor_xp, int(s["xp_next"]) - floor_xp)
	_xp.tooltip_text = "%s / %s XP" % [UiStyle.thousands(int(s["xp"])), UiStyle.thousands(int(s["xp_next"]))]
	_kamas.text = "%s K" % UiStyle.thousands(int(s["kamas"]))
	characteristics.set_stats(s)
	inventory.set_stats(s)
	spell_book.set_stats(s)
	spell_bar.set_bar(s.get("bar", []))
	zaap.set_save_map(int(s.get("save_map", -1)))
	shop.set_stats(s)
	bank.set_stats(s)
	trade.set_stats(s)


## HP now: regenerates out of fight (Protocol "character dict").
func hp_now() -> int:
	if stats.is_empty():
		return 0
	var elapsed := maxi(0, backend.time_ms() - int(stats["hp_t0"]))
	return mini(int(stats["max_hp"]), int(stats["hp"]) + elapsed / maxi(1, int(stats["regen_ms"])))


func _process(_delta: float) -> void:
	size = get_viewport_rect().size
	_box.position = Vector2(12, size.y - _box.size.y - 12)
	_bar_box.position = Vector2((size.x - _bar_box.size.x) * 0.5, size.y - _bar_box.size.y - 12)
	if not stats.is_empty():
		var hp := hp_now()
		_hp.set_values(hp, int(stats["max_hp"]), "%d / %d" % [hp, int(stats["max_hp"])])
		characteristics.set_hp(hp, int(stats["max_hp"]))
