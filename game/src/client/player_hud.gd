## Roleplay HUD, a bottom dock like the Dofus banner: the XP gauge on top, then level and HP bar
## (regenerating, computed from the game time like Movement) on the left, the spell bar in the
## middle, the kamas and the window buttons (HudMenu) on the right; plus the game windows.
## Fed by player_stats events.
class_name PlayerHud
extends Control

## the bottom band changed height (reserved_bottom): the map is fitted again
signal band_changed
## a button of the window row was pressed (HudMenu): the session opens the window like its shortcut
signal menu_pressed(action: String)

## the two side blocks of the dock have the same width, so the spell bar stays centred
const SIDE_WIDTH := 212

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
var market: MarketWindow
var craft: CraftWindow
var jobs: JobsWindow
var achievements: AchievementsWindow
var smith: SmithmagicWindow
var quests: QuestWindow
var tracker: QuestTracker
var party: PartyFrame
var trade: TradeWindow
var contacts: ContactsWindow
var trade_invites: TradeInvites
var duel_invites: DuelInvites
var dungeon: DungeonIndicator
var spell_bar: SpellBar
var menu: HudMenu
var _bar_box: PanelContainer

var _dock: VBoxContainer
var _level: Label
var _xp: UiBar
var _hp: UiBar
var _kamas: Label


func setup(p_backend: GameBackend) -> void:
	backend = p_backend
	theme = ClientTheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	market = MarketWindow.new()
	add_child(market)
	market.setup_window(backend)
	market.inventory = inventory
	craft = CraftWindow.new()
	add_child(craft)
	craft.setup_window(backend)
	craft.inventory = inventory
	jobs = JobsWindow.new()
	add_child(jobs)
	jobs.setup_window()
	achievements = AchievementsWindow.new()
	add_child(achievements)
	achievements.setup_window(backend)
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
	duel_invites = DuelInvites.new() # P3.10: the challenges received, same column
	party.add_child(duel_invites)
	duel_invites.setup(backend)
	dungeon = DungeonIndicator.new()
	add_child(dungeon)
	dungeon.setup(backend)
	_build_dock()


## The bottom dock (built last: above the windows, like the banner of the Dofus client).
func _build_dock() -> void:
	_dock = VBoxContainer.new()
	_dock.add_theme_constant_override("separation", 5)
	_dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dock)
	_dock.resized.connect(func() -> void: band_changed.emit())
	_xp = UiBar.new(UiStyle.XP, 8)
	_xp.custom_minimum_size = Vector2(0, 8)
	_dock.add_child(_xp)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dock.add_child(row)
	# left: level and life
	var vitals := PanelContainer.new()
	vitals.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	vitals.add_theme_stylebox_override("panel", UiStyle.panel(Color(UiStyle.BG, 0.88), UiStyle.BORDER, UiStyle.RADIUS, 8))
	row.add_child(vitals)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	vitals.add_child(v)
	_level = UiStyle.heading("")
	v.add_child(_level)
	_hp = UiBar.new(UiStyle.HP, 20)
	v.add_child(_hp)
	# middle: the spell bar
	_bar_box = PanelContainer.new()
	_bar_box.add_theme_stylebox_override("panel", UiStyle.panel(Color(UiStyle.BG, 0.88), UiStyle.BORDER, UiStyle.RADIUS, 6))
	row.add_child(_bar_box)
	spell_bar = SpellBar.new()
	spell_bar.moved.connect(func(spell: int, slot: int) -> void: backend.send(Protocol.move_spell(spell, slot)))
	_bar_box.add_child(spell_bar)
	# right: the purse and the window buttons
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 8)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right)
	var purse := PanelContainer.new()
	purse.add_theme_stylebox_override("panel", UiStyle.panel(Color(UiStyle.BG, 0.88), UiStyle.BORDER, UiStyle.RADIUS, 5))
	right.add_child(purse)
	_kamas = UiStyle.label("", UiStyle.KAMAS, UiStyle.FS_BODY)
	_kamas.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_kamas.tooltip_text = "Kamas"
	purse.add_child(_kamas)
	menu = HudMenu.new()
	menu.alignment = BoxContainer.ALIGNMENT_END
	menu.pressed.connect(func(action: String) -> void: menu_pressed.emit(action))
	right.add_child(menu)


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
	market.set_stats(s)
	trade.set_stats(s)
	jobs.set_stats(s)


## Height of the bottom band (dock and its margins): the map is fitted above it, like the
## Dofus banner that never covers the map.
func reserved_bottom() -> float:
	return _dock.size.y + 2.0 * HudLayout.MARGIN


## HP now: regenerates out of fight (Protocol "character dict").
func hp_now() -> int:
	if stats.is_empty():
		return 0
	var elapsed := maxi(0, backend.time_ms() - int(stats["hp_t0"]))
	return mini(int(stats["max_hp"]), int(stats["hp"]) + elapsed / maxi(1, int(stats["regen_ms"])))


func _process(_delta: float) -> void:
	var vp := get_viewport_rect().size
	if size != vp:
		size = vp
	_dock.position = Vector2((vp.x - _dock.size.x) * 0.5, vp.y - _dock.size.y - HudLayout.MARGIN)
	if not stats.is_empty():
		var hp := hp_now()
		_hp.set_values(hp, int(stats["max_hp"]), "%d / %d" % [hp, int(stats["max_hp"])])
		characteristics.set_hp(hp, int(stats["max_hp"]))
