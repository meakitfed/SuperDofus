## Client root: owns a GameBackend, turns player input into commands and game
## events into views. It never touches the game logic directly, so the same
## client runs standalone (LocalBackend) or against a server (future backend).
##   left click: walk (double click or shift: run) · click an exit cell: change map · click a
##   monster group: fight · wheel: zoom · I: characteristics and inventory
## Events go through a small sequencer (like the Dofus client): while a visual
## sequence plays (a spell…), later events wait, so nothing is cut short.
class_name ClientSession
extends Node2D

## the windows a shortcut (or a button of the dock) opens and closes
const WINDOW_ACTIONS := ["inventory", "characteristics", "spells", "worldmap", "quests", "jobs", "achievements", "friends"]

## "dofus" = every Dofus map (tools/extractor/maps.py full), "incarnam" = Incarnam only (maps.py world, the tests), "test" = generated placeholder world
@export var world_id := "dofus"
var content_id := "" # the world whose content is read (S.04b: an instance of another world); "" = world_id
## "" = the character selection screen (the real game); a name = play it at
## once, created if needed (tools, quick tests)
@export var player_name := ""
## save the character in user://saves (tools turn it off)
@export var persistent := true
@export var player_look := "{1|120,2195,4072,4941,3963,5716|1=13418918,2=4077879,3=16022817,4=14386944,5=4275500,6=9904435|56|1@0={1420|||90}}"

var backend: GameBackend
var you := -1
var world_info := {}
var map: MapData
var finder: MapPathfinder
var views := {} # actor id -> ActorView | GroupView

var _dofus_map: DofusMapNode
var _map_view: MapView
## y-sorted: roleplay actors, map sortable elements, fighters
var _world_sort: Node2D
var _actors: Node2D
var _foreground: Node2D
var frame: MapFrame
var _camera: Camera2D
## what the map may use: the HUD bands and panels are kept out of it (GameArea)
var _area := GameArea.new()
## what the last click waits for once the player stands beside it (exit, door, zaap, phoenix, NPC, element)
var _pending := PendingAction.new()
## elements harvested and not grown back yet (interactive_state): element id -> sim time they grow back
var _depleted := {}
## top-left place block (area, subarea, coordinates, status) and the black map-change fade
var _info: MapInfo
## the HUD parts are placed again only when this signature (window shape, sizes, visibility) changes
var _hud_sig := ""
var _fade: ColorRect
## top-right minimap (the world map around the player; click: world map)
var _minimap: WorldMapView
var _minimap_box: PanelContainer
var toast: Toast
## map_markers of the current map (P2.04b): [{kind: offer | goal, quest, npc, map}]
var _markers: Array = []
## the chat window (P3.02); Entrée types in it (chat and GM commands like /tp)
var chat: ChatPanel
## monster group tooltip (hover, like Dofus): group id shown, -1 = none
var _group_tip: PanelContainer
var _group_tip_id := -1
var _hud_layer: CanvasLayer
var _banner: Label
var _banner_until := 0
var fight: FightView
var player_hud: PlayerHud
var _result_window: FightResultWindow
var _queue: Array = []
## character selection, shown until welcome
var character_select: CharacterSelectScreen
## the connection side: reconnection banner, resume (S.02c)
var _link: SessionLink
## zones on demand (C.02d), set by the launch screen for a zoned server world
var zone_gate: ZoneGate
var back_to_launch := false # started from the launch screen: a lost session goes back to it
var _blocked := false
var _in_dispatch := false
var _done_in_dispatch := false
## the other players: names, tooltip, menu (P3.01)
var _others: OtherPlayers
## the fight view's life: start, watch, join, end (P3.04b)
var _flow: FightFlow
## roleplay clicks on the map and the action waiting beside its target
var clicks: MapClick
## what the mouse points at: lit sprites, tooltip, cursor
var _hover: MapHover


func _ready() -> void:
	UiScale.apply(get_window())
	ContentSource.use_world(content_id if content_id != "" else world_id if backend is NetBackend else "") # server: its cache; solo: res:// (the sim needs the maps, absent from a cache)
	# draw order: map background < ground overlays < (map sortables + entities, y-sorted) < map foreground
	_dofus_map = DofusMapNode.new()
	add_child(_dofus_map)
	_map_view = MapView.new()
	add_child(_map_view)
	_world_sort = Node2D.new()
	_world_sort.y_sort_enabled = true
	add_child(_world_sort)
	_actors = Node2D.new()
	_actors.y_sort_enabled = true
	_world_sort.add_child(_actors)
	_foreground = Node2D.new()
	add_child(_foreground)
	frame = MapFrame.new() # a light blur outside the cells while an exit arrow shows
	add_child(frame)
	_camera = Camera2D.new()
	add_child(_camera)
	_hud_layer = CanvasLayer.new()
	add_child(_hud_layer)
	_info = MapInfo.new()
	_hud_layer.add_child(_info)
	_minimap_box = PanelContainer.new()
	_minimap_box.add_theme_stylebox_override("panel", UiStyle.panel(Color(UiStyle.BG, 0.85), UiStyle.BORDER, 6, 4))
	_hud_layer.add_child(_minimap_box)
	_minimap = WorldMapView.new()
	_minimap.interactive = false
	_minimap.zoom = 0.3
	_minimap.custom_minimum_size = Vector2(HudLayout.side_width(UiScale.BASE), 130)
	_minimap.tooltip_text = Shortcuts.label("worldmap")
	_minimap.clicked.connect(func() -> void: player_hud.world_map.toggle())
	_minimap_box.add_child(_minimap)
	_minimap_box.visible = false
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.modulate.a = 0.0
	_hud_layer.add_child(_fade)
	_banner = Label.new()
	_banner.theme = ClientTheme.get_theme()
	_banner.add_theme_font_size_override("font_size", 48)
	_banner.add_theme_color_override("font_outline_color", Color.BLACK)
	_banner.add_theme_constant_override("outline_size", 10)
	_hud_layer.add_child(_banner)
	toast = Toast.new()
	_hud_layer.add_child(toast)
	_link = SessionLink.new(self)
	_hud_layer.add_child(_link.banner)
	get_viewport().size_changed.connect(_fit_camera)
	_area.changed.connect(_fit_camera)

	backend = backend if backend != null else _make_backend() # the launch screen hands over its server connection
	player_hud = PlayerHud.new()
	_hud_layer.add_child(player_hud)
	player_hud.setup(backend)
	player_hud.band_changed.connect(_fit_camera)
	player_hud.menu_pressed.connect(toggle_window)
	chat = ChatPanel.new()
	chat.backend = backend
	_hud_layer.add_child(chat)
	_hud_layer.move_child(chat, player_hud.get_index()) # under the windows (it fades, they do not)
	player_hud.contacts.whisper.connect(chat.whisper)
	_others = OtherPlayers.new(self)
	_flow = FightFlow.new(self)
	clicks = MapClick.new(self)
	_hover = MapHover.new(self)
	backend.event.connect(_on_event)
	player_hud.visible = false # until a character plays
	backend.send(Protocol.hello(world_id, player_name, player_look if player_name != "" else ""))


## The single place that decides standalone vs server.
func _make_backend() -> GameBackend:
	var local := LocalBackend.new()
	local.rates_options = LocalBackend.cmdline_rates() # S.06: --xp-rate=3 --bonus-drops ... in standalone too
	if persistent:
		local.persistence = FilePersistence.new("user://saves") # the character persists between sessions
		local.clock = SystemClock.new()
	return local


func _exit_tree() -> void:
	if backend != null:
		backend.close()


func _process(delta: float) -> void:
	backend.poll(delta)
	var now := backend.time_ms()
	for v: Node in views.values():
		v.update(now)
		if v is ActorView:
			MapTip.keep_readable(v, _camera.zoom.x)
	if fight != null:
		fight.update(now)
	clicks.try_pending(now)
	if not _map_view.preview.is_empty() and views.has(you) and not views[you].is_moving(now):
		_map_view.preview = []
		_map_view.queue_redraw()
	_map_view.show_hover = fight != null
	var hover := MapGeometry.screen_to_cell(get_global_mouse_position())
	if hover != _map_view.hover:
		_map_view.hover = hover
		_map_view.queue_redraw()
	_update_group_tip()
	_others.update(_hud_layer, fight == null and get_viewport().gui_get_hovered_control() == null)
	_hover.update(fight == null and get_viewport().gui_get_hovered_control() == null)
	var help := ""
	if fight != null and fight.spectator and fight.phase == "placement":
		help = "spectateur : le placement est en cours · Quitter pour revenir sur la map"
	elif fight != null and fight.phase == "placement":
		help = "placement : clic sur une case rouge · Espace = prêt"
	elif fight != null and fight.spectator:
		help = "spectateur : vous ne pouvez pas agir · Quitter pour revenir sur la map"
	elif fight != null:
		help = "combat : clic = se déplacer · 1-9 = sort puis clic sur la cible · clic droit = annuler · Espace = fin du tour"
	else:
		help = "clic : se déplacer (court au-delà de 3 cases, double-clic : courir) · clic sur un groupe : combattre · flèche au bord : changer de map · Tab : éléments interactifs · I : inventaire · C : caractéristiques · S : sorts · Q : quêtes · Entrée : commande (/tp) · molette : zoom"
	player_hud.visible = fight == null
	_info.set_status("%s · %d fps" % [world_info.get("name", "…"), Engine.get_frames_per_second()], help.replace(" · ", "\n"))
	_info.set_place(_map_title() if map != null else "", map.coords if map != null else Vector2i.ZERO, fight == null and map != null)
	_minimap_box.visible = fight == null and map != null and map.world_map >= 0 and player_hud.visible
	_banner.visible = Time.get_ticks_msec() < _banner_until
	chat.visible = player_hud.visible or fight != null # the team talks during a fight (general = same fight)
	_banner.position = (get_viewport_rect().size - _banner.size) * Vector2(0.5, 0.3)
	_layout_hud()
	_sync_area()


## Localized map (subarea) name, like the top-left label of the Dofus client.
func map_name() -> String:
	if map == null:
		return ""
	return DofusI18n.text(map.name_id, map.name if map.name != "" else "Map %d" % map.id)


## "Area - Subarea", like the top-left label of the Dofus client.
func _map_title() -> String:
	var title := map_name()
	if map.area_name_id != 0:
		var area := DofusI18n.text(map.area_name_id, "")
		if area != "" and area != title:
			title = "%s - %s" % [area, title]
	return title


## The minimap and the world map follow the map (the place block reads it each frame).
func _update_map_label() -> void:
	if _minimap.set_world(map.world_map):
		_minimap.player = map.coords
		_minimap.zaaps = player_hud.stats.get("zaaps", []).filter(func(z: Dictionary) -> bool: return z.has("coords"))
		_minimap.focus(map.coords)
	player_hud.world_map.refresh(map, _map_title(), player_hud.stats)


## Tactical mode (T): decor hidden, flat cells (MapView). Kept across maps.
func set_tactical(on: bool, real := _dofus_map.map_id != 0) -> void:
	_map_view.tactical = on
	_dofus_map.set_decor_visible(not on)
	var bg := Color(0.3, 0.3, 0.3)
	if on:
		bg = UiStyle.TACTICAL_BG
	elif real:
		bg = _dofus_map.background_color()
	RenderingServer.set_default_clear_color(bg)


func _input(event: InputEvent) -> void:
	var typing := get_viewport().gui_get_focus_owner() is LineEdit
	if fight != null and not typing and Shortcuts.pressed(event, "command"): # chat during a fight
		chat.open()
		get_viewport().set_input_as_handled()
		return
	if (typing or not player_hud.visible) and not Shortcuts.pressed(event, "close"):
		return # game shortcuts wait for a character (and never eat typed letters)
	var window_action := ""
	for action: String in WINDOW_ACTIONS:
		if Shortcuts.pressed(event, action):
			window_action = action
			break
	if window_action != "":
		toggle_window(window_action)
	elif Shortcuts.pressed(event, "command"):
		chat.open()
	elif Shortcuts.pressed(event, "tactical"):
		set_tactical(not _map_view.tactical)
	elif UiScale.handle_key(event, get_window()):
		pass # Ctrl+PageUp / PageDown: interface size, Ctrl+Home: windows back to their places
	elif Shortcuts.pressed(event, "close") and UiWindow.close_top():
		pass # a window was closed; otherwise Escape goes on (fight: unselect the spell)
	else:
		return
	get_viewport().set_input_as_handled()


## Opens or closes the window of a shortcut or of a button of the dock (HudMenu).
func toggle_window(action: String) -> void:
	match action:
		"inventory": # the bag and the equipment together (Dofus)
			player_hud.inventory.toggle()
			ZoneGate.ask_equipment(zone_gate) # C.02g: the skins of the items are a zone of their own
			if player_hud.inventory.visible != player_hud.equipment.visible:
				player_hud.equipment.toggle()
		"characteristics":
			player_hud.characteristics.toggle()
		"spells":
			player_hud.spell_book.toggle()
		"worldmap":
			player_hud.world_map.toggle()
		"quests":
			player_hud.quests.toggle()
		"jobs":
			player_hud.jobs.toggle()
		"achievements":
			player_hud.achievements.toggle()
		"friends":
			player_hud.contacts.toggle()


## The HUD parts go to the corners of HudLayout, and the GameArea learns what they cover. Cheap
## when nothing moved: the signature of the inputs is compared, positions are set only on a change.
func _layout_hud() -> void:
	var vp := get_viewport_rect().size
	var parts := {"mapinfo": _info, "minimap": _minimap_box, "tracker": player_hud.tracker, "party": player_hud.party,
			"dungeon": player_hud.dungeon, "chat": chat}
	var in_fight := fight != null and fight.hud != null
	var band := fight.hud.reserved_bottom() if in_fight else (player_hud.reserved_bottom() if player_hud.visible else 0.0)
	chat.fit(vp)
	var sizes := {}
	var sig := "%s|%d" % [vp, int(band)]
	for k: String in parts:
		var c: Control = parts[k]
		var shown := c.visible and c.is_visible_in_tree()
		if k == "party" or k == "dungeon":
			shown = shown and player_hud.visible
		if shown:
			sizes[k] = c.size
			sig += "|%s%s" % [k, c.size]
	if sig == _hud_sig:
		return
	_hud_sig = sig
	var spots := HudLayout.place(vp, sizes, band)
	for k: String in spots:
		(parts[k] as Control).position = spots[k]


func _unhandled_input(event: InputEvent) -> void:
	if map == null:
		return
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if fight == null:
					clicks.press(get_global_mouse_position(), mb.shift_pressed)
			MOUSE_BUTTON_RIGHT:
				var group := clicks.group_at(get_global_mouse_position()) if fight == null else -1
				var other := _others.player_at(get_global_mouse_position()) if fight == null and group < 0 else -1
				if group >= 0:
					ContextMenu.popup(self, get_viewport().get_mouse_position(), "Groupe de monstres",
							[["Attaquer", func() -> void: backend.send(Protocol.fight_attack(group))]])
				elif other >= 0:
					_others.menu(other, get_viewport().get_mouse_position())
			MOUSE_BUTTON_WHEEL_UP:
				_camera.zoom *= 1.1
			MOUSE_BUTTON_WHEEL_DOWN:
				_camera.zoom /= 1.1


func _update_group_tip() -> void:
	var over_ui := get_viewport().gui_get_hovered_control() != null
	var gid := clicks.group_at(get_global_mouse_position()) if fight == null and not over_ui else -1
	if gid != _group_tip_id:
		_group_tip_id = gid
		if is_instance_valid(_group_tip):
			_group_tip.queue_free()
		_group_tip = null
		var members: Array = views[gid].get_meta("members", []) if gid >= 0 else []
		if not members.is_empty():
			_group_tip = PanelContainer.new()
			_group_tip.theme = ClientTheme.get_theme()
			_group_tip.add_theme_stylebox_override("panel", ClientTheme.get_theme().get_stylebox("panel", "TooltipPanel"))
			_group_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var bonus := int(views[gid].get_meta("bonus", 0))
			var s := player_hud.stats
			var wisdom := 0
			for part: String in ["stats", "additional", "bonus"]:
				wisdom += int((s.get(part, {}) as Dictionary).get("wisdom", 0))
			var xp := FightXp.estimate(members, int(s.get("level", 1)), wisdom, bonus) if not s.is_empty() else -1
			_group_tip.add_child(UiTooltips.monster_group(members, bonus, xp))
			_hud_layer.add_child(_group_tip)
	if _group_tip != null:
		var vp := get_viewport_rect().size
		_group_tip.position = (get_viewport().get_mouse_position() + Vector2(18, 18)).clamp(Vector2.ZERO, vp - _group_tip.size)


# ── game events ────────────────────────────────────────────────────────────────

func _on_event(ev: Dictionary) -> void:
	_queue.append(ev)
	_pump()


func _pump() -> void:
	while not _queue.is_empty() and not _blocked:
		_in_dispatch = true
		_done_in_dispatch = false
		var started := _dispatch(_queue.pop_front())
		_in_dispatch = false
		# A sequence that ended before _dispatch returned already emitted sequence_done: do not block.
		if started and not _done_in_dispatch:
			_blocked = true


func _on_sequence_done() -> void:
	if _in_dispatch:
		_done_in_dispatch = true
		return
	_blocked = false
	_pump()


## Applies one event; true if it started a visual sequence to wait for.
func _dispatch(ev: Dictionary) -> bool:
	var t := str(ev.get("t", ""))
	if _link.handle(t, ev):
		return false
	if fight != null and t in [Protocol.FIGHT_TURN, Protocol.FIGHTER_MOVE, Protocol.SPELL_CAST, Protocol.ERROR,
			Protocol.FIGHTER_PLACED, Protocol.FIGHTER_READY, Protocol.FIGHT_BEGIN, Protocol.CHALLENGE_LIST,
			Protocol.CHALLENGE_UPDATE, Protocol.FIGHT_OPTIONS]:
		return fight.handle(ev)
	match t:
		Protocol.CHARACTERS, Protocol.CHARACTER_CREATED, Protocol.WELCOME:
			_on_login_event(t, ev)
		Protocol.MAP_ENTER, Protocol.ACTOR_ADD, Protocol.ACTOR_REMOVE, Protocol.ACTOR_LOOK, Protocol.ACTOR_MOVE, Protocol.GROUP_ALERT:
			_on_actor_event(t, ev)
			player_hud.party.sync_marks(views)
		Protocol.ERROR:
			toast.show_text(ErrorTexts.text(ev))
		Protocol.INFO:
			toast.show_text(InfoTexts.text(ev))
		Protocol.FIGHT_START, Protocol.FIGHT_END, ProtocolWatch.WATCH, ProtocolWatch.JOINED, ProtocolWatch.LEFT:
			_flow.handle(t, ev)
		Protocol.INVENTORY, Protocol.ITEM_ADDED, Protocol.ITEM_REMOVED, Protocol.FM_RESULT:
			_on_item_event(t, ev)
		Protocol.ZAAP_LIST, Protocol.DIALOG, Protocol.DIALOG_END, Protocol.SHOP_OPEN, Protocol.SHOP_END, \
				Protocol.BANK_OPEN, Protocol.BANK_UPDATE, Protocol.BANK_END:
			_on_npc_event(t, ev)
		ProtocolMarket.OPENED, ProtocolMarket.RESULTS, ProtocolMarket.MINE, ProtocolMarket.END, ProtocolMarket.BOUGHT, ProtocolMarket.SOLD:
			_on_market_event(t, ev)
		ProtocolParty.INVITED, ProtocolParty.UPDATE, ProtocolParty.LEFT, ProtocolParty.DECLINED:
			player_hud.party.on_event(t, ev, toast, views, you)
		ProtocolTrade.INVITED, ProtocolTrade.OPEN, ProtocolTrade.UPDATE, ProtocolTrade.END:
			player_hud.trade.on_event(t, ev, toast)
			player_hud.trade_invites.refresh()
		ProtocolEmote.EMOTE_PLAY:
			var who: Variant = views.get(int(ev["actor"]))
			if who is ActorView:
				var row := GameData.row("emoticons", int(ev["emote"]))
				(who as ActorView).play_emote(str(ev["anim"]), str(row.get("persistantAnimName", "")) if int(row.get("persistancy", 0)) != 0 else "")
		ProtocolDuel.REQUESTED, ProtocolDuel.END:
			player_hud.duel_invites.on_event(t, ev, toast)
		ProtocolDungeon.ROOM, ProtocolDungeon.END:
			player_hud.dungeon.on_event(t, ev, toast)
		ProtocolContacts.CONTACTS:
			player_hud.contacts.set_lists(ev)
		ProtocolContacts.STATUS:
			toast.show_text(player_hud.contacts.model.status(ev), UiStyle.GOOD if bool(ev["online"]) else UiStyle.TEXT_MUTED)
			player_hud.contacts.refresh()
		Protocol.MAP_MARKERS:
			_markers = ev["markers"]
			_apply_markers()
		Protocol.QUEST_LIST, Protocol.QUEST_START, Protocol.QUEST_UPDATE, Protocol.QUEST_COMPLETE:
			QuestEvents.apply(t, ev, player_hud, toast)
		Protocol.INTERACTIVE_START, Protocol.INTERACTIVE_STATE, Protocol.JOB_XP, Protocol.ZAAP_KNOWN, \
				Protocol.CRAFT_STATE, Protocol.CRAFT_DONE:
			_on_job_event(t, ev)
		ProtocolAchievement.LIST, ProtocolAchievement.UNLOCKED:
			player_hud.achievements.on_event(t, ev)
			if t == ProtocolAchievement.UNLOCKED:
				toast.show_text(AchievementsModel.unlocked_text(ev), UiStyle.GOOD)
		Protocol.PLAYER_STATS:
			_on_player_stats(ev)
		ProtocolAdmin.ADMIN_RESULT, ProtocolAdmin.ANNOUNCE:
			chat.on_admin(ev)
		Protocol.CHAT_MSG:
			chat.on_message(ev)
			if str(ev["channel"]) == Chat.GENERAL and views.get(int(ev["from_id"])) is Node2D:
				ChatBubble.show_over(views[int(ev["from_id"])], ChatPanel.plain_text(ev))
	return false


## Connection: the character selection, then the welcome.
func _on_login_event(t: String, ev: Dictionary) -> void:
	match t:
		Protocol.CHARACTERS:
			_show_character_select(ev)
		Protocol.CHARACTER_CREATED:
			if character_select != null:
				character_select.on_created(ev["character"])
		Protocol.WELCOME:
			if character_select != null:
				character_select.queue_free()
				character_select = null
			player_hud.visible = true
			you = int(ev["you"])
			world_info = ev.get("world", {})
			chat.on_rates(world_info.get("rates", {})) # S.06

## The map and the actors on it.
func _on_actor_event(t: String, ev: Dictionary) -> void:
	match t:
		Protocol.MAP_ENTER:
			_markers = []
			player_hud.dungeon.on_map(ev["map"])
			_enter_map(MapData.from_dict(ev["map"]), ev["actors"])
			_apply_markers()
		Protocol.ACTOR_ADD:
			_add_actor(ev["actor"])
		Protocol.ACTOR_REMOVE:
			_remove_actor(int(ev["id"]))
		Protocol.ACTOR_LOOK:
			var looks: Array = ev["looks"]
			if views.get(int(ev["id"])) is ActorView and not looks.is_empty():
				(views[int(ev["id"])] as ActorView).set_look(str(looks[0]))
		Protocol.ACTOR_MOVE:
			_move_actor(int(ev["id"]), _ints(ev["path"]), int(ev["t0"]), bool(ev["run"]))
		Protocol.GROUP_ALERT:
			if views.get(int(ev["group"])) is GroupView:
				(views[int(ev["group"])] as GroupView).show_alert()


func _on_item_event(t: String, ev: Dictionary) -> void:
	match t:
		Protocol.INVENTORY:
			player_hud.inventory.set_items(ev["items"])
		Protocol.ITEM_ADDED:
			player_hud.inventory.put_item(ev["item"])
		Protocol.ITEM_REMOVED:
			player_hud.inventory.remove_item(int(ev["uid"]))
		Protocol.FM_RESULT:
			toast.show_text(player_hud.smith.show_result(ev))
	player_hud.bags_changed()


## Zaap, dialogs, shops and the bank.
func _on_npc_event(t: String, ev: Dictionary) -> void:
	match t:
		Protocol.ZAAP_LIST:
			player_hud.zaap.show_list(ev, int(player_hud.stats.get("kamas", 0)))
		Protocol.DIALOG:
			var npc_view: Node2D = views.get(int(ev["npc"]))
			player_hud.dialog.show_dialog(ev, DofusI18n.text(int(npc_view.get_meta("name_id", 0)), "") if npc_view != null else "")
		Protocol.DIALOG_END:
			player_hud.dialog.end_dialog()
		Protocol.SHOP_OPEN:
			var merchant: Node2D = views.get(int(ev["npc"]))
			player_hud.shop.show_shop(ev, DofusI18n.text(int(merchant.get_meta("name_id", 0)), "") if merchant != null else "", player_hud.stats)
		Protocol.SHOP_END:
			player_hud.shop.end_shop()
		Protocol.BANK_OPEN:
			var banker: Node2D = views.get(int(ev["npc"]))
			player_hud.bank.show_bank(ev, DofusI18n.text(int(banker.get_meta("name_id", 0)), "") if banker != null else "", player_hud.stats)
		Protocol.BANK_UPDATE:
			player_hud.bank.update_bank(ev)
		Protocol.BANK_END:
			player_hud.bank.end_bank()


## The marketplace (P2.10b).
func _on_market_event(t: String, ev: Dictionary) -> void:
	match t:
		ProtocolMarket.OPENED:
			player_hud.market.show_market(ev, player_hud.stats)
		ProtocolMarket.END:
			player_hud.market.end_market()
		ProtocolMarket.BOUGHT:
			toast.show_text(MarketModel.bought_text(ev), UiStyle.GOOD)
			if player_hud.market.visible:
				player_hud.market.search() # the lot is gone: refresh the page
		ProtocolMarket.SOLD:
			toast.show_text(MarketModel.sold_text(ev), UiStyle.GOOD)
		_:
			player_hud.market.on_event(t, ev)


## Harvesting, job XP and new zaaps.
func _on_job_event(t: String, ev: Dictionary) -> void:
	match t:
		Protocol.INTERACTIVE_START:
			_harvest_start(ev)
		Protocol.INTERACTIVE_STATE:
			if bool(ev["ready"]):
				_depleted.erase(int(ev["element"]))
			else:
				_depleted[int(ev["element"])] = int(ev["until"])
			ResourceView.apply(_dofus_map.elements_at, map.interactive(int(ev["element"])), not bool(ev["ready"]))
		Protocol.JOB_XP:
			for line: String in JobTexts.xp_lines(ev):
				toast.show_text(line, UiStyle.GOOD)
			player_hud.jobs.on_xp(ev)
		Protocol.CRAFT_STATE:
			player_hud.craft.show_state(ev)
		Protocol.CRAFT_DONE:
			toast.show_text(CraftWindow.done_text(ev), UiStyle.GOOD)
		Protocol.ZAAP_KNOWN:
			toast.show_text("Nouveau zaap enregistré : %s" % map_name())


func _on_player_stats(ev: Dictionary) -> void:
	player_hud.set_stats(ev["stats"])
	chat.me = str(ev["stats"].get("name", chat.me))
	_map_view.ghost = int(ev["stats"].get("life", 0)) == 2
	_map_view.queue_redraw()
	if map != null:
		player_hud.world_map.refresh(map, _map_title(), ev["stats"])
		_minimap.zaaps = ev["stats"].get("zaaps", []).filter(func(z: Dictionary) -> bool: return z.has("coords"))
		_minimap.queue_redraw()
	if fight != null: # the bar arranged during the fight
		fight.set_bar(ev["stats"].get("bar", []))


## A player starts harvesting: it faces the element and plays the skill's animation (skills.useAnimation).
func _harvest_start(ev: Dictionary) -> void:
	var view: Variant = views.get(int(ev["player"]))
	var el := map.interactive(int(ev["element"]))
	if not view is ActorView or el.is_empty():
		return
	var actor := view as ActorView
	var d := MapGeometry.facing(actor.dest_cell(), int(el["cell"]))
	var anim := str(Jobs.skill(int(ev["skill"])).get("useAnimation", ""))
	actor.play_action([anim], d)


func _show_character_select(ev: Dictionary) -> void:
	if character_select == null:
		character_select = CharacterSelectScreen.new()
		_hud_layer.add_child(character_select)
		character_select.setup(backend, zone_gate)
		_hud_layer.move_child(toast, -1) # refusals (name taken…) stay readable
	character_select.set_characters(ev)


func show_banner(text: String, seconds: float) -> void:
	_banner.text = text
	_banner_until = Time.get_ticks_msec() + int(seconds * 1000)


func _enter_map(data: MapData, actors: Array) -> void:
	for id: int in views.keys():
		_remove_actor(id)
	if map != null and map.id != data.id: # map change: a short fade from black
		_fade.modulate.a = 1.0
		create_tween().tween_property(_fade, "modulate:a", 0.0, 0.35).set_delay(0.05)
	map = data
	_depleted = {}
	finder = MapPathfinder.new(map)
	_pending.clear()
	player_hud.dialog.end_dialog()
	player_hud.shop.end_shop()
	player_hud.bank.end_bank()
	player_hud.market.end_market()
	player_hud.trade.end_trade()
	player_hud.craft.end_craft()
	if player_hud.zaap.visible: # the zaap stays behind
		player_hud.zaap.close_window()
	_update_map_label()
	var real := _dofus_map.build(map.visual, _world_sort, _foreground)
	_map_view.draw_ground = not real
	_map_view.set_map(map)
	set_tactical(_map_view.tactical, real)
	for a: Dictionary in actors:
		_add_actor(a)
	_fit_camera()


func _add_actor(a: Dictionary) -> void:
	var id := int(a["id"])
	if views.has(id):
		_remove_actor(id)
	var looks: Array = a.get("looks", [])
	var cell := int(a["cell"])
	var dir := int(a.get("dir", 1))
	var v: Node2D
	if str(a["kind"]) == "fight": # the swords of a fight (P3.04b)
		var sw := FightSwords.new()
		_actors.add_child(sw)
		sw.setup(a)
		v = sw
	elif str(a["kind"]) == "monster_group":
		var g := GroupView.new()
		_actors.add_child(g)
		g.setup(looks, cell, dir, finder)
		g.set_meta("members", a.get("members", []))
		g.set_meta("bonus", int(a.get("bonus", 0)))
		v = g
	else:
		var s := ActorView.new()
		_actors.add_child(s)
		s.setup(str(looks[0]) if not looks.is_empty() else "", cell, dir)
		if str(a["kind"]) == "npc":
			s.set_meta("npc", int(a["npc"]))
			s.set_meta("name_id", int(a.get("name_id", 0)))
			OtherPlayers.add_tag(s, UiStyle.plain_text(DofusI18n.text(int(a.get("name_id", 0)), str(a.get("name", "")))), UiStyle.GOLD)
		elif str(a["kind"]) == "player" and id != you:
			OtherPlayers.decorate(s, a)
		if int(a.get("life", 0)) == 2: # a ghost (Energy)
			s.modulate = UiStyle.GHOST
		v = s
		if str(a["kind"]) == "npc":
			call_deferred("_apply_markers")
	v.name = "Actor%d" % id
	views[id] = v
	if a.has("move"):
		var m: Dictionary = a["move"]
		_move_actor(id, _ints(m["path"]), int(m["t0"]), bool(m["run"]))


## Quest badges above the NPCs (P2.04b): "!" = offers a quest, "?" = an objective of a quest under way is here; and the
## world map / minimap badge on the player's map.
func _apply_markers() -> void:
	var offers := {}
	var goals := {}
	var place := false
	for m: Dictionary in _markers:
		var npc := int(m["npc"])
		if str(m["kind"]) == "offer":
			offers[npc] = true
		elif npc == 0:
			place = true
		else:
			goals[npc] = true
	for id: int in views:
		var v: Node2D = views[id]
		if not v.has_meta("npc"):
			continue
		var old := v.get_node_or_null("QuestMark")
		if old != null:
			old.free()
		var npc := int(v.get_meta("npc"))
		var glyph := "?" if goals.has(npc) else ("!" if offers.has(npc) else "")
		if glyph == "":
			continue
		var tag := UiStyle.label(glyph, UiStyle.GOLD if glyph == "!" else UiStyle.XP, 30)
		tag.name = "QuestMark"
		tag.add_theme_color_override("font_outline_color", Color.BLACK)
		tag.add_theme_constant_override("outline_size", 8)
		tag.position = Vector2(-tag.get_minimum_size().x / 2.0, -172)
		v.add_child(tag)
	var any: bool = not _markers.is_empty()
	_minimap.quest_mark = any
	_minimap.queue_redraw()
	player_hud.world_map.view.quest_mark = any
	player_hud.world_map.view.queue_redraw()


func _remove_actor(id: int) -> void:
	if views.has(id):
		(views[id] as Node).queue_free()
		views.erase(id)


func _move_actor(id: int, path: Array, t0: int, run: bool) -> void:
	var v: Node2D = views.get(id)
	if v is GroupView:
		(v as GroupView).set_move(path, t0, run, backend.time_ms())
	elif v is ActorView:
		(v as ActorView).set_move(path, t0, run)
	if id == you:
		_map_view.preview = path
		_map_view.queue_redraw()


## The HUD's bands and panels tell the GameArea what they cover; the map is fitted in what is left.
func _sync_area() -> void:
	var top := 0.0
	var bottom := 0.0
	var blocks := {}
	if fight != null and fight.hud != null:
		top = fight.hud.reserved_top()
		bottom = fight.hud.reserved_bottom()
		var challenges := fight.hud.banner_rect()
		if challenges.size.y > 0.0:
			blocks["challenges"] = challenges
	elif player_hud.visible:
		bottom = player_hud.reserved_bottom()
	var panels := {"chat": chat, "minimap": _minimap_box, "tracker": player_hud.tracker}
	for k: String in panels:
		var c: Control = panels[k]
		if c.visible and c.size.x > 0.0 and c.size.y > 0.0 and c.is_visible_in_tree():
			blocks[k] = Rect2(c.position, c.size)
	_area.set_layout(top, bottom, blocks)
	toast.top = top + 12.0 if top > 0.0 else 70.0 # never over the timeline


## The whole map in the free part of the screen (GameArea.fit), like the Dofus client.
func _fit_camera() -> void:
	_area.fit(_camera, get_viewport_rect().size)


static func _ints(a: Array) -> Array:
	return a.map(func(x: Variant) -> int: return int(x))
