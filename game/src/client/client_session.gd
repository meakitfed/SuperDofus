## Client root: owns a GameBackend, turns player input into commands and game
## events into views. It never touches the game logic directly, so the same
## client runs standalone (LocalBackend) or against a server (future backend).
##   left click: walk (shift: run) · click an exit cell: change map · click a
##   monster group: fight · wheel: zoom · I: characteristics and inventory
## Events go through a small sequencer (like the Dofus client): while a visual
## sequence plays (a spell…), later events wait, so nothing is cut short.
class_name ClientSession
extends Node2D

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
var _camera: Camera2D
var _hud: Label
## what the last click waits for once the player stands beside it (exit, door, zaap, phoenix, NPC, element)
var _pending := PendingAction.new()
## elements harvested and not grown back yet (interactive_state): element id -> sim time they grow back
var _depleted := {}
## top-left map label (area, subarea, coordinates) and the black map-change fade
var _map_label: Label
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
## the other players: names, tooltip, menu (P3.01)
var _others: OtherPlayers
## the fight view's life: start, watch, join, end (P3.04b)
var _flow: FightFlow


func _ready() -> void:
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
	_camera = Camera2D.new()
	add_child(_camera)
	_hud_layer = CanvasLayer.new()
	add_child(_hud_layer)
	_hud = Label.new()
	_hud.theme = ClientTheme.get_theme()
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hud.add_theme_constant_override("outline_size", 4)
	_hud.position = Vector2(12, 8)
	_hud_layer.add_child(_hud)
	_map_label = UiStyle.label("", UiStyle.TEXT, 15)
	_map_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_map_label.add_theme_constant_override("outline_size", 5)
	_map_label.position = Vector2(14, 8)
	_hud_layer.add_child(_map_label)
	_hud.position = Vector2(12, 56)
	_hud.add_theme_font_size_override("font_size", 12)
	_minimap_box = PanelContainer.new()
	_minimap_box.add_theme_stylebox_override("panel", UiStyle.panel(Color(UiStyle.BG, 0.85), UiStyle.BORDER, 6, 4))
	_hud_layer.add_child(_minimap_box)
	_minimap = WorldMapView.new()
	_minimap.interactive = false
	_minimap.zoom = 0.3
	_minimap.custom_minimum_size = Vector2(200, 130)
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

	backend = backend if backend != null else _make_backend() # the launch screen hands over its server connection
	player_hud = PlayerHud.new()
	_hud_layer.add_child(player_hud)
	player_hud.setup(backend)
	chat = ChatPanel.new()
	chat.backend = backend
	_hud_layer.add_child(chat)
	player_hud.contacts.whisper.connect(chat.whisper)
	_others = OtherPlayers.new(self)
	_flow = FightFlow.new(self)
	backend.event.connect(_on_event)
	player_hud.visible = false # until a character plays
	backend.send(Protocol.hello(world_id, player_name, player_look if player_name != "" else ""))


## The single place that decides standalone vs server.
func _make_backend() -> GameBackend:
	var local := LocalBackend.new()
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
	if fight != null:
		fight.update(now)
	_try_pending(now)
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
		help = "clic : marcher (Maj : courir) · clic sur un groupe : combattre · bord éclairci : changer de map · I : inventaire · C : caractéristiques · S : sorts · Q : quêtes · Entrée : commande (/tp) · molette : zoom"
	player_hud.visible = fight == null
	_hud.text = "%s · %d fps · %s" % [world_info.get("name", "…"), Engine.get_frames_per_second(), help]
	_map_label.visible = fight == null
	_minimap_box.visible = fight == null and map != null and map.world_map >= 0 and player_hud.visible
	_minimap_box.position = Vector2(get_viewport_rect().size.x - _minimap_box.size.x - 12, 12)
	player_hud.tracker.position = Vector2(get_viewport_rect().size.x - player_hud.tracker.size.x - 12,
			_minimap_box.position.y + _minimap_box.size.y + 8 if _minimap_box.visible else 12)
	_banner.visible = Time.get_ticks_msec() < _banner_until
	player_hud.party.position = Vector2(12, 84)
	chat.position = Vector2(12, 230) if fight != null else Vector2(12, get_viewport_rect().size.y - chat.size.y - 110) # in a fight: under the challenges, clear of the bar
	chat.visible = player_hud.visible or fight != null # the team talks during a fight (general = same fight)
	_banner.position = (get_viewport_rect().size - _banner.size) * Vector2(0.5, 0.3)


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


## Top-left label (title and coordinates), minimap and world map follow the map.
func _update_map_label() -> void:
	_map_label.text = "%s\n%d, %d" % [_map_title(), map.coords.x, map.coords.y]
	if _minimap.set_world(map.world_map):
		_minimap.player = map.coords
		_minimap.zaaps = player_hud.stats.get("zaaps", []).filter(func(z: Dictionary) -> bool: return z.has("coords"))
		_minimap.focus(map.coords)
	player_hud.world_map.refresh(map, _map_title(), player_hud.stats)


func _input(event: InputEvent) -> void:
	var typing := get_viewport().gui_get_focus_owner() is LineEdit
	if fight != null and not typing and Shortcuts.pressed(event, "command"): # chat during a fight
		chat.open()
		get_viewport().set_input_as_handled()
		return
	if (typing or not player_hud.visible) and not Shortcuts.pressed(event, "close"):
		return # game shortcuts wait for a character (and never eat typed letters)
	if Shortcuts.pressed(event, "inventory"): # the bag and the equipment together (Dofus)
		player_hud.inventory.toggle(); ZoneGate.ask_equipment(zone_gate) # C.02g: the skins of the items are a zone of their own
		if player_hud.inventory.visible != player_hud.equipment.visible:
			player_hud.equipment.toggle()
	elif Shortcuts.pressed(event, "characteristics"):
		player_hud.characteristics.toggle()
	elif Shortcuts.pressed(event, "spells"):
		player_hud.spell_book.toggle()
	elif Shortcuts.pressed(event, "worldmap"):
		player_hud.world_map.toggle()
	elif Shortcuts.pressed(event, "workshop") or Shortcuts.pressed(event, "smithmagic"):
		(player_hud.craft if Shortcuts.pressed(event, "workshop") else player_hud.smith).toggle_workshop()
	elif Shortcuts.pressed(event, "quests"):
		player_hud.quests.toggle()
	elif Shortcuts.pressed(event, "friends"):
		player_hud.contacts.toggle()
	elif Shortcuts.pressed(event, "command"):
		chat.open()
	elif Shortcuts.pressed(event, "close") and UiWindow.close_top():
		pass # a window was closed; otherwise Escape goes on (fight: unselect the spell)
	else:
		return
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if map == null:
		return
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if fight == null:
					_click(get_global_mouse_position(), mb.shift_pressed)
			MOUSE_BUTTON_RIGHT:
				var group := _group_at(get_global_mouse_position()) if fight == null else -1
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


func _click(p: Vector2, run: bool) -> void:
	if _pending.kind == PendingAction.Kind.INTERACTIVE:
		_pending.clear()
	var swords := _swords_at(p)
	if swords != null: # a fight on the map: join or watch
		swords.menu(self, get_viewport().get_mouse_position())
		return
	var group := _group_at(p)
	if group >= 0:
		backend.send(Protocol.fight_attack(group))
		return
	var npc := _npc_at(p)
	if npc >= 0: # walk beside it (the closest cell), then talk
		var me_cell: int = views[you].dest_cell() if views.has(you) else 0
		var spot := _npc_spot(npc, me_cell)
		_pending.set_to(PendingAction.Kind.NPC, npc)
		if spot == me_cell:
			_try_pending(backend.time_ms())
		elif spot >= 0:
			backend.send(Protocol.move(spot, run))
		return
	if _pending.kind == PendingAction.Kind.NPC:
		_pending.clear()
	var cell := MapGeometry.screen_to_cell(p)
	var element := map.interactive_near(cell) if cell >= 0 else {}
	if not element.is_empty(): # a resource: walk beside it (the closest cell), then harvest it
		var me_cell: int = views[you].dest_cell() if views.has(you) else cell
		var near := map.use_cells(int(element["cell"]))
		near.sort_custom(func(a: int, b: int) -> bool: return MapGeometry.distance(a, me_cell) < MapGeometry.distance(b, me_cell))
		if near.is_empty():
			return
		_pending.set_to(PendingAction.Kind.INTERACTIVE, int(element["e"]))
		if near[0] == me_cell:
			_try_pending(backend.time_ms())
		else:
			backend.send(Protocol.move(near[0], run))
		return
	var phoenix := cell >= 0 and _map_view.is_phoenix(cell)
	var door := map.door_near(cell) if cell >= 0 else -1
	if cell >= 0 and (_map_view.is_zaap(cell) or phoenix or door >= 0): # walk beside it (the closest cell), then use it
		var me_cell: int = views[you].dest_cell() if views.has(you) else cell
		var near := map.use_cells(door if door >= 0 else map.phoenix if phoenix else map.zaap)
		near.sort_custom(func(a: int, b: int) -> bool: return MapGeometry.distance(a, me_cell) < MapGeometry.distance(b, me_cell))
		if near.is_empty():
			return
		if door >= 0:
			_pending.set_to(PendingAction.Kind.TRIGGER, door)
		else:
			_pending.set_to(PendingAction.Kind.PHOENIX if phoenix else PendingAction.Kind.ZAAP)
		if near[0] == me_cell:
			_try_pending(backend.time_ms())
		else:
			backend.send(Protocol.move(near[0], run))
		return
	if cell < 0 or not map.is_walkable(cell):
		return
	_pending.set_exit(PendingAction.exit_for(map, cell, p))
	var me: ActorView = views[you] if views.has(you) else null
	if me != null and me.dest_cell() == cell and not me.is_moving(backend.time_ms()):
		_try_pending(backend.time_ms())
		return
	backend.send(Protocol.move(cell, run))


func _update_group_tip() -> void:
	var over_ui := get_viewport().gui_get_hovered_control() != null
	var gid := _group_at(get_global_mouse_position()) if fight == null and not over_ui else -1
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


## Monster group under the mouse (sprite box around each member), -1 if none.
func _group_at(p: Vector2) -> int:
	for id: int in views:
		if views[id] is GroupView:
			for m: ActorView in (views[id] as GroupView).members:
				if Rect2(m.position + Vector2(-35, -110), Vector2(70, 120)).has_point(p):
					return id
	return -1


## The swords of a fight under the mouse, null if none.
func _swords_at(p: Vector2) -> FightSwords:
	for v: Node in views.values():
		if v is FightSwords and (v as FightSwords).contains(p):
			return v
	return null


## NPC under the mouse (sprite box), -1 if none.
func _npc_at(p: Vector2) -> int:
	for id: int in views:
		if views[id].has_meta("npc") and Rect2(views[id].position + Vector2(-35, -110), Vector2(70, 120)).has_point(p):
			return id
	return -1


## The cell to talk to an NPC from: standing beside it (its own cell excluded), the closest to `from`.
func _npc_spot(npc: int, from: int) -> int:
	var at: int = views[npc].cell
	var near := map.use_cells(at).filter(func(c: int) -> bool: return c != at)
	if near.is_empty():
		return -1
	near.sort_custom(func(a: int, b: int) -> bool: return MapGeometry.distance(a, from) < MapGeometry.distance(b, from))
	return near[0]


## Like the Dofus client: the map change (or the door, the zaap, the NPC, the
## element) is requested once the player has arrived beside its target.
func _try_pending(now: int) -> void:
	if not _pending.is_set() or not views.has(you):
		return
	var me: ActorView = views[you]
	if me.is_moving(now):
		return
	var at := me.dest_cell()
	var t := _pending.target
	match _pending.kind:
		PendingAction.Kind.NPC:
			if not views.has(t) or MapGeometry.distance(at, views[t].cell) > 1 or at == views[t].cell:
				return
			backend.send(Protocol.npc_talk(t))
		PendingAction.Kind.ZAAP:
			if not map.use_cells(map.zaap).has(at):
				return
			backend.send(Protocol.use_zaap())
		PendingAction.Kind.PHOENIX:
			if not map.use_cells(map.phoenix).has(at):
				return
			backend.send(Protocol.use_phoenix())
		PendingAction.Kind.TRIGGER:
			if not map.use_cells(t).has(at):
				return
			backend.send(Protocol.use_trigger(t))
		PendingAction.Kind.INTERACTIVE:
			var el := map.interactive(t)
			if el.is_empty() or not map.use_cells(int(el["cell"])).has(at):
				return
			backend.send(Protocol.craft_open(int(el["skill"])) if Crafting.is_craft_skill(int(el["skill"])) else Protocol.interactive_use(int(el["e"]), int(el["skill"])))
		PendingAction.Kind.EXIT:
			if not map.can_exit(at, _pending.exit):
				return # not there yet (the move may not have started)
			backend.send(Protocol.change_map(_pending.exit))
	_pending.clear()


# ── game events ────────────────────────────────────────────────────────────────

func _on_event(ev: Dictionary) -> void:
	_queue.append(ev)
	_pump()


func _pump() -> void:
	while not _queue.is_empty() and not _blocked:
		if _dispatch(_queue.pop_front()):
			_blocked = true


func _on_sequence_done() -> void:
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
		ProtocolParty.INVITED, ProtocolParty.UPDATE, ProtocolParty.LEFT, ProtocolParty.DECLINED:
			player_hud.party.on_event(t, ev, toast, views, you)
		ProtocolTrade.INVITED, ProtocolTrade.OPEN, ProtocolTrade.UPDATE, ProtocolTrade.END:
			player_hud.trade.on_event(t, ev, toast)
			player_hud.trade_invites.refresh()
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
		Protocol.PLAYER_STATS:
			_on_player_stats(ev)
		ProtocolAdmin.ADMIN_RESULT, ProtocolAdmin.ANNOUNCE:
			chat.on_admin(ev)
		Protocol.CHAT_MSG:
			chat.on_message(ev)
			if str(ev["channel"]) == Chat.GENERAL and views.get(int(ev["from_id"])) is Node2D:
				ChatBubble.show_over(views[int(ev["from_id"])], str(ev["text"]))
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


## The map and the actors on it.
func _on_actor_event(t: String, ev: Dictionary) -> void:
	match t:
		Protocol.MAP_ENTER:
			_markers = []
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
		Protocol.JOB_XP:
			for line: String in JobTexts.xp_lines(ev):
				toast.show_text(line, UiStyle.GOOD)
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
	player_hud.trade.end_trade()
	player_hud.craft.end_craft()
	if player_hud.zaap.visible: # the zaap stays behind
		player_hud.zaap.close_window()
	_update_map_label()
	var real := _dofus_map.build(map.visual, _world_sort, _foreground)
	RenderingServer.set_default_clear_color(_dofus_map.background_color() if real else Color(0.3, 0.3, 0.3))
	_map_view.draw_ground = not real
	_map_view.set_map(map)
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


func _fit_camera() -> void:
	var b := MapGeometry.screen_bounds()
	_camera.position = b.get_center()
	var vp := get_viewport_rect().size
	var z := minf(vp.x / b.size.x, vp.y / b.size.y)
	_camera.zoom = Vector2(z, z)


static func _ints(a: Array) -> Array:
	return a.map(func(x: Variant) -> int: return int(x))
