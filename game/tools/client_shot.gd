## Runs the real client (windowed, needs a GPU) for a while, sending commands
## through its backend like clicks would, and saves screenshots.
##   godot --path game -s res://tools/client_shot.gd -- --out=shot.png --seconds=6 \
##         [--cmd=1000:move:320] [--cmd=4000:change_map:right] [--world=test] [--shot=2500]
## Commands (<at_ms>:<type>[:arg]):
##   move:<cell>[!]   change_map:<dir>   trigger:<cell> (door on that cell)   door:<cell> (click on that door, or on a resource: harvest)   attack (nearest monster group)
##   goto:<map id>[:<cell>] (tool shortcut: teleports in the local sim)   zaap (click on the zaap)   npc (click on the first NPC: dialog / shop)   buy:<item>[:<n>] / sell:<item>[:<n>] (shop window open)   travel:<map id>   worldmap (M)   kamas:<n> (tool shortcut)   grid (shows the cell grid, exits and doors)
##   option:<name> (fight: locked, party_only, secret, help)   fmove (fight: walk towards the nearest enemy)   cast:<spell id> (on the nearest
##   enemy, or on yourself for heals)   endturn   leave   ready   place (another placement cell)
##   win (tool shortcut: kills the monsters in the local sim)   inventory (I)   characteristics (C)
##   hover (mouse over a monster group: its tooltip)   tip (fight: mouse over the nearest enemy's timeline tile)   spells[:<spell id>] (S: the spell book)
##   friends[:friend|enemy|ignored] (F: the contacts window)   friend_add:<name> / enemy_add:<name> / ignore_add:<name>
##   quests (Q: the quest journal; reply:<1000000 + quest id> accepts a quest)   console:<line> (Entrée: the command line, "_" = space, e.g. console:/tp_5_-18)
##   stars:<pct> (tool shortcut: the stars of the map's subarea)   aggro (tool shortcut: the map's groups become aggressive)
##   summon:<castable id> (fight, tool shortcut: learns the spell, casts it next to you)
##   lay:<castable id> (same, for a trap / glyph: on the closest free cell)   self:<castable id> (same, on yourself)
##   carry:<castable id> (fight, tool shortcut: learns it, puts the nearest enemy next to you, casts it on it)
##   throw:<castable id> (fight: casts it on the farthest cell it reaches: the throw of a carrier)
##   mirror:<castable id> (fight, tool shortcut: the two nearest enemies on either side of you, cast on the first: Frappe de Xélor swaps them, a Telefrag)
##   energy:<n> (tool shortcut; 0 = a ghost)   phoenix (click on the map's phoenix)   lose (tool shortcut: the monsters win)
##   level:<n>[:<capital>] (tool shortcut)   boost:<stat>[:<capital>]   tab:<n>   points:<stat>[:<n>[:ok]] (batch spending window, ok = Investir)
##   give:<item id>[:<qty>] (tool shortcut)   use:<item id>   equip:<item id>[:<slot>] (characteristics window)   variant:<spell id>   movespell:<spell id>:<slot>
##   cast:<slot> (a spell bar slot < 100) / fselect:<slot> / fweapon (fight: shows the spell's range)
##   aim:<castable id>:<dx>:<dy> (fight: selects that bar spell, hovers your cell + (dx, dy): its area preview)
##   --trace=<file>: writes the logical content paths the run read (WorldAssets coverage check)
##   --server=<ip:port>: the client plays on a server (tool shortcuts that touch the local sim do nothing)
##   --mate=<name>: a second player on the same server (P3.01); mate:<command>[:<args>] drives it: mate:move:<cell>, mate:goto:<map id>:<cell>
##   (tool shortcut), mate:change_map:<dir>, mate:attack (nearest group)
##   join / watch / swordsmenu (the first fight on the map: Rejoindre, Regarder, the click menu) · mate:attack starts one
##   mate:invite (the mate invites us into a group)   partyaccept (accept the invitation received)   inviteplayer (we invite the first other player)
##   trade (we invite the first other player to trade)   tradeaccept (accept the invitation received)   tradeput:<item>[:<qty>] (offer an item, double-click)   tradekamas:<n>   tradeready   mate:trade / mate:tradeput:<item>[:<qty>[:<kamas>]] / mate:tradeready (the mate does the same)
##   hoverplayer (mouse over the first other player: its tooltip)   playermenu (the right-click menu of the first other player)
##   --lobby=1: start at the character selection (no saved characters: in memory);
##   then create:<name>[:m|f[:<breed>]]  select:<name>  delete:<name> (opens the confirmation)
##   newchar[:<name>] (the creation screen)  breed:<id>[:<sex>[:<face index>[:<color 1 hex>]]]
## The character is not saved (fresh level 1 each run).
## Several --shot=<ms> produce <out>_<ms>.png. Lets an agent check visuals without a human.
extends SceneTree

var _client: ClientSession
var _opts := {"out": "client_shot.png", "seconds": "6", "world": "test"}
var _cmds: Array = []
var _shots: Array = []
var _t := 0.0
## --mate: the server both players share, and the second player
var _server: LocalServer
var _mate: LocalBackend


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"cmd":
				_cmds.append(kv[1].split(":"))
			"shot":
				_shots.append(int(kv[1]))
			_:
				_opts[kv[0]] = kv[1]
	_cmds.sort_custom(func(a: PackedStringArray, b: PackedStringArray) -> bool: return int(a[0]) < int(b[0]))
	if _opts.has("trace"): # --trace=<file>: every content path read, for tools/world_assets.gd --check-trace
		ContentSource.trace_start()
	_client = (load("res://scenes/client/client.tscn") as PackedScene).instantiate()
	_client.world_id = _opts["world"]
	_client.persistent = false
	_client.player_name = "" if _opts.has("lobby") else "Joueur"
	if _opts.has("server"): # --server=<ip:port>: play on a running server (src/server/main.gd) instead of in this process
		var net := NetBackend.new()
		net.connect_to(_opts["server"])
		_client.backend = net
	if _opts.has("mate"):
		_server = LocalServer.new()
		var lb := LocalBackend.new()
		lb.server = _server
		_client.backend = lb
		_mate = LocalBackend.new()
		_mate.server = _server
		_mate.account = "mate" # its own account (contacts name accounts)
		_mate.send(Protocol.hello(_opts["world"], _opts["mate"], _client.player_look.replace("13418918", "3377000")))
	UiWindow.reset_layout()
	root.add_child(_client)


func _process(delta: float) -> bool:
	_t += delta
	if _mate != null:
		_server.tick(int(delta * 1000.0))
		_mate.poll(delta)
	var ms := int(_t * 1000.0)
	while not _cmds.is_empty() and int(_cmds[0][0]) <= ms:
		_run(_cmds.pop_front())
	for s: int in _shots.duplicate():
		if ms >= s:
			_shots.erase(s)
			_save(_opts["out"].get_basename() + "_%d.png" % s)
	if _t >= float(_opts["seconds"]):
		_save(_opts["out"])
		DofusContent.wait_preloads() # quitting while the sprites decode their clips crashes the engine
		if _opts.has("trace"):
			var f := FileAccess.open(_opts["trace"], FileAccess.WRITE)
			f.store_string("
".join(ContentSource.trace_stop()))
			f.close()
		return true
	return false


func _run(c: PackedStringArray) -> void:
	if c[1] == "mate":
		_run_mate(c)
		return
	var b := _client.backend
	match c[1]:
		"move":
			b.send(Protocol.move(int(c[2]), c[2].ends_with("!")))
		"change_map":
			b.send(Protocol.change_map(c[2]))
		"attack":
			var me: Vector2 = _client.views[_client.you].position if _client.views.has(_client.you) else Vector2.ZERO
			var best := -1
			for id: int in _client.views:
				if _client.views[id] is GroupView and (best < 0 or me.distance_to(_client.views[id].position) < me.distance_to(_client.views[best].position)):
					best = id
			if best >= 0:
				b.send(Protocol.fight_attack(best))
		"create":
			b.send(Protocol.create_character(c[2], int(c[4]) if c.size() > 4 else 12, 1 if c.size() > 3 and c[3] == "f" else 0))
		"select":
			b.send(Protocol.select_character(c[2]))
		"delete":
			if _client.character_select != null:
				_client.character_select.selected = c[2]
				_client.character_select._ask_delete()
		"newchar":
			if _client.character_select != null:
				_client.character_select._open_create()
				if c.size() > 2:
					_client.character_select.creation.focus_name(c[2])
		"breed": # creation screen: pick a class (breeds.id), sex, face index, color 1
			var cs := _client.character_select.creation if _client.character_select != null else null
			if cs != null:
				cs._select_breed(int(c[2]))
				if c.size() > 3:
					cs.sex = int(c[3])
				if c.size() > 4:
					cs.face = int(LookBuilder.faces(cs.breed, cs.sex)[int(c[4])]["id"])
				if c.size() > 5:
					cs.colors = [c[5].hex_to_int()]
				cs._refresh_choices()
		"hover": # mouse over the nearest monster group (its tooltip)
			var me: Vector2 = _client.views[_client.you].position if _client.views.has(_client.you) else Vector2.ZERO
			for id: int in _client.views:
				if _client.views[id] is GroupView:
					var leader: Vector2 = (_client.views[id] as GroupView).members[0].position + Vector2(0, -40)
					root.warp_mouse(root.get_canvas_transform() * leader)
					break
		"hoverplayer", "playermenu": # the first other player: tooltip (mouse over it) / right-click menu
			for id: int in _client.views:
				if _client.views[id].has_meta("player"):
					var at: Vector2 = root.get_canvas_transform() * (_client.views[id].position + Vector2(0, -40))
					if c[1] == "hoverplayer":
						root.warp_mouse(at)
						var motion := InputEventMouseMotion.new() # the real mouse of the machine may move meanwhile
						motion.position = at
						motion.global_position = at
						Input.parse_input_event(motion)
					else:
						_client._others.menu(id, at)
					break
		"partyaccept": # accept the first invitation received (the frame's button)
			var party: PartyFrame = _client.player_hud.party
			if not party.invites.is_empty():
				party.accept(str(party.invites[0]["from"]))
		"invitemenu": # the right-click menu of the first other player, then its invitation entry
			for id: int in _client.views:
				if _client.views[id].has_meta("player"):
					_client._others.menu(id, root.get_canvas_transform() * (_client.views[id].position + Vector2(0, -40)))
					break
		"trade", "tradeaccept", "tradeput", "tradekamas", "tradeready": # exchange (P3.11b): the window's own entry points
			var tw: TradeWindow = _client.player_hud.trade
			match c[1]:
				"trade":
					for id: int in _client.views:
						if _client.views[id].has_meta("player"):
							b.send(ProtocolTrade.invite(str(_client.views[id].get_meta("player_name"))))
							break
				"tradeaccept":
					if not tw.model.invites.is_empty():
						_client.player_hud.trade_invites.accept(str(tw.model.invites[0]["from"]))
				"tradeput":
					for s: Node in tw._bag_grid.get_children():
						if s is ItemSlot and (s as ItemSlot).item_id == int(c[2]):
							tw._qty.value = int(c[3]) if c.size() > 3 else 1
							(s as ItemSlot).activated.emit(s)
							break
				"tradekamas": # after the last tradeput (the offer is built from the last confirmed one)
					tw._kamas.value = int(c[2])
					tw._send(tw.model.with_kamas(int(c[2]), int(_client.player_hud.stats.get("kamas", 0))))
				"tradeready":
					tw._ready_button.pressed.emit()
		"inviteplayer": # click "Inviter dans le groupe" on the first other player
			for id: int in _client.views:
				if _client.views[id].has_meta("player"):
					_client.player_hud.party.invite(str(_client.views[id].get_meta("player_name")))
					break
		"tip": # mouse over the nearest enemy's timeline tile (its tooltip: HP, buffs); tip:me = one's own
			var f := _client.fight
			var tile: Control = f.hud._tiles.get(f.you if c.size() > 2 and c[2] == "me" else _nearest_enemy_id(), null)
			if tile != null:
				root.warp_mouse(tile.get_global_rect().get_center())
		"fmove":
			var f := _client.fight
			var me: Dictionary = f.me()
			var enemy := _nearest_enemy()
			var reach := FightRules.reachable(f.map, f.occupied(f.you), int(me["cell"]), int(me["mp"]))
			var target := int(me["cell"])
			for cell: int in reach:
				if FightRules.distance(cell, enemy) < FightRules.distance(target, enemy):
					target = cell
			b.send(Protocol.fight_move(target))
		"cast": # castable id, or a spell bar slot (< 100)
			var id := int(c[2]) if int(c[2]) >= 100 else _client.fight.hud.spell_bar.slots[int(c[2])].spell_id
			var spell := SpellBook.get_spell(id)
			var heal: bool = not spell["effects"].is_empty() and spell["effects"][0]["kind"] == "heal"
			b.send(Protocol.fight_cast(id, int(_client.fight.me()["cell"]) if heal else _nearest_enemy()))
		"self": # self:<castable id> (fight, tool shortcut: learns it) cast on your own cell
			var lb := b as LocalBackend
			for fight: Fight in lb.sim.fights.values():
				var f: Fighter = fight.fighters.get(lb.player_id)
				if f != null:
					if not f.spells.has(int(c[2])):
						f.spells.append(int(c[2]))
					b.send(Protocol.fight_cast(int(c[2]), f.cell))
		"at": # at:<castable id>:<dx>:<dy> (fight, tool shortcut: learns it) cast on your cell + (dx, dy) in the iso grid
			var lb := b as LocalBackend
			for fight: Fight in lb.sim.fights.values():
				var f: Fighter = fight.fighters.get(lb.player_id)
				if f != null:
					if not f.spells.has(int(c[2])):
						f.spells.append(int(c[2]))
					var cell := MapGeometry.from_iso(MapGeometry.to_iso(f.cell) + Vector2i(int(c[3]), int(c[4])))
					b.send(Protocol.fight_cast(int(c[2]), cell))
		"wall": # wall:<castable id> (fight, tool shortcut: learns it) two casts on free cells in a line, 2 cells between (bombs: a wall)
			var lb := b as LocalBackend
			var id := int(c[2])
			for fight: Fight in lb.sim.fights.values():
				var f: Fighter = fight.fighters.get(lb.player_id)
				if f == null:
					continue
				if not f.spells.has(id):
					f.spells.append(id)
				var done := false
				for c1: int in FightRules.reachable(MapData.new(), {}, f.cell, 5).keys():
					for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
						var cells: Array = []
						for k in 4:
							cells.append(MapGeometry.from_iso(MapGeometry.to_iso(c1) + d * k))
						if done or cells.has(-1) or cells.has(f.cell) or cells.any(func(x: int) -> bool:
								return not fight.map.is_fight_walkable(x) or fight.fighter_at(x) != null):
							continue
						if fight.cast_check(f, id, cells[0]) == "" and fight.cast_check(f, id, cells[3]) == "":
							if FightRules.distance(f.cell, cells[0]) < FightRules.distance(f.cell, cells[3]):
								cells.reverse() # the farther first: the nearer bomb would hide it
							b.send(Protocol.fight_cast(id, cells[0]))
							b.send(Protocol.fight_cast(id, cells[3]))
							done = true
		"on", "project": # on:<castable id> on the nearest enemy where it stands; project:<castable id> on a
			# free portal of yours (P1.13f: the sim projects it) (fight, tool shortcut: learns it)
			var lb := b as LocalBackend
			for fight: Fight in lb.sim.fights.values():
				var f: Fighter = fight.fighters.get(lb.player_id)
				if f == null:
					continue
				if not f.spells.has(int(c[2])):
					f.spells.append(int(c[2]))
				var cell := _nearest_enemy()
				if c[1] == "project":
					for m: Dictionary in fight.marks:
						if m["kind"] == "portal" and int(m["caster"]) == f.id and fight.fighter_at(int(m["cell"])) == null:
							cell = int(m["cell"])
				b.send(Protocol.fight_cast(int(c[2]), cell))
		"detonate": # detonate:<castable id> (fight, tool shortcut: learns it) cast on your first bomb
			var lb := b as LocalBackend
			for fight: Fight in lb.sim.fights.values():
				var f: Fighter = fight.fighters.get(lb.player_id)
				if f == null:
					continue
				if not f.spells.has(int(c[2])):
					f.spells.append(int(c[2]))
				for g: Fighter in fight.fighters.values():
					if g.alive and g.summoner == f.id and SpellBook.summon(g.monster).has("explode"):
						b.send(Protocol.fight_cast(int(c[2]), g.cell))
						break
		"summon", "lay": # summon:<castable id> (tool shortcut: the fighter learns it) cast on the closest free cell
			var lb := b as LocalBackend
			var id := int(c[2])
			for fight: Fight in lb.sim.fights.values():
				var f: Fighter = fight.fighters.get(lb.player_id)
				if f != null and not f.spells.has(id):
					f.spells.append(id)
				if f != null:
					var cells: Array = FightRules.reachable(fight.map, fight.occupied(), f.cell, 3).keys()
					cells.sort_custom(func(x: int, y: int) -> bool: return FightRules.distance(x, f.cell) < FightRules.distance(y, f.cell))
					for cell: int in cells:
						if fight.cast_check(f, id, cell) == "":
							b.send(Protocol.fight_cast(id, cell))
							break
		"carry", "throw":
			var lb := b as LocalBackend
			var id := int(c[2])
			for fight: Fight in lb.sim.fights.values():
				var f: Fighter = fight.fighters.get(lb.player_id)
				if f == null:
					continue
				if not f.spells.has(id):
					f.spells.append(id)
				var cells: Array = FightRules.reachable(MapData.new(), {}, f.cell, 6).keys()
				cells.sort_custom(func(x: int, y: int) -> bool: return FightRules.distance(x, f.cell) > FightRules.distance(y, f.cell) or (FightRules.distance(x, f.cell) == FightRules.distance(y, f.cell) and x < y))
				if c[1] == "carry":
					var foe: Fighter = null
					for g: Fighter in fight.fighters.values():
						if g.alive and g.team != f.team and (foe == null or FightRules.distance(g.cell, f.cell) < FightRules.distance(foe.cell, f.cell)):
							foe = g
					for n in FightRules.neighbors4(f.cell):
						if foe != null and FightRules.distance(foe.cell, f.cell) > 1 and fight.map.is_fight_walkable(n) and fight.fighter_at(n) == null:
							foe.cell = n
							fight._emit.call(Protocol.fighter_placed(foe.id, n))
					cells = [foe.cell] if foe != null else []
				for cell: int in cells:
					if fight.cast_check(f, id, cell) == "":
						b.send(Protocol.fight_cast(id, cell))
						break
		"mirror": # mirror:<castable id> (fight, tool shortcut: learns it) two enemies on either side of you, cast on the first (Frappe de Xélor: a Telefrag)
			var lb := b as LocalBackend
			var id := int(c[2])
			for fight: Fight in lb.sim.fights.values():
				var f: Fighter = fight.fighters.get(lb.player_id)
				if f == null:
					continue
				if not f.spells.has(id):
					f.spells.append(id)
				var foes: Array = fight.fighters.values().filter(func(g: Fighter) -> bool: return g.alive and g.team != f.team)
				foes.sort_custom(func(x: Fighter, y: Fighter) -> bool: return FightRules.distance(x.cell, f.cell) < FightRules.distance(y.cell, f.cell))
				if foes.size() < 2:
					continue
				for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
					var pair: Array = [MapGeometry.from_iso(MapGeometry.to_iso(f.cell) + d), MapGeometry.from_iso(MapGeometry.to_iso(f.cell) - d)]
					if pair.any(func(x: int) -> bool: return x < 0 or not fight.map.is_fight_walkable(x) \
							or (fight.fighter_at(x) != null and not foes.slice(0, 2).has(fight.fighter_at(x)))):
						continue
					for k in 2:
						foes[k].cell = -1
					for k in 2:
						foes[k].cell = pair[k]
						fight._emit.call(Protocol.fighter_placed(foes[k].id, pair[k]))
					b.send(Protocol.fight_cast(id, pair[0]))
					break
		"fweapon": # fight: select the weapon hit
			_client.fight.select_spell(_client.fight.hud.weapon.spell_id)
		"fselect": # fight: select a spell bar slot (shows its range)
			_client.fight.select_spell(_client.fight.hud.spell_bar.slots[int(c[2])].spell_id)
		"aim": # aim:<castable id>:<dx>:<dy> (fight) select that spell of the bar and hover your cell + (dx, dy): its area preview
			var fv: FightView = _client.fight
			fv.select_spell(int(c[2]))
			fv._hover = MapGeometry.from_iso(MapGeometry.to_iso(int(fv.me()["cell"])) + Vector2i(int(c[3]), int(c[4])))
			fv._refresh_overlays()
		"option": # option:<locked|party_only|secret|help> (fight): switches it on
			b.send(Protocol.fight_option(c[2], true))
		"endturn":
			b.send(Protocol.fight_end_turn())
		"ready":
			b.send(Protocol.fight_ready())
		"place":
			var f := _client.fight
			for cell: int in f.placement[f.my_team()]:
				if not f.occupied().has(cell):
					b.send(Protocol.fight_place(cell))
					break
		"win":
			var sim: WorldSim = (b as LocalBackend).sim
			for fight: Fight in sim.fights.values():
				for m: Fighter in fight.fighters.values():
					if m.team == 1:
						m.alive = false
						m.hp = 0
				fight._check_end()
		"inventory":
			_client.player_hud.inventory.toggle()
			_client.player_hud.equipment.toggle()
		"equip": # equip:<item id>[:<slot>] the first stack of an item id
			var inv := _client.player_hud.inventory
			for uid: int in inv._items:
				if int(inv._items[uid]["id"]) == int(c[2]) and int(inv._items[uid].get("pos", -1)) < 0:
					if c.size() > 3:
						b.send(Protocol.equip(uid, int(c[3])))
					else:
						inv._equip(inv._items[uid])
					break
		"spells": # the spell book, optionally showing a spell (spells.id)
			_client.player_hud.spell_book.open()
			if c.size() > 2:
				_client.player_hud.spell_book._selected = int(c[2])
				_client.player_hud.spell_book._fill()
		"level": # tool shortcut: sets the character's level (and capital) in the local sim
			var lb := b as LocalBackend
			var p: PlayerActor = lb.sim.players[lb.player_id]
			p.character.level = int(c[2])
			p.character.capital = int(c[3]) if c.size() > 3 else p.character.capital
			p.outbox.append(Protocol.player_stats(p.character.public_dict(lb.sim.now)))
		"variant":
			b.send(Protocol.choose_variant(int(c[2])))
		"movespell":
			b.send(Protocol.move_spell(int(c[2]), int(c[3])))
		"characteristics": # C, optionally on a tab
			_client.player_hud.characteristics.toggle()
		"goto": # tool shortcut: teleports in the local sim (goto:<map id>[:<cell>])
			var lb := b as LocalBackend
			var dest := lb.sim.get_map(int(c[2]))
			lb.sim.teleport(lb.sim.players[lb.player_id], int(c[2]),
					dest.data.nearest_walkable(int(c[3]) if c.size() > 3 else 300))
		"zaap": # like a click on the zaap: walks beside it, then use_zaap (the zaap window opens)
			_client._click(MapGeometry.to_screen(_client.map.zaap), false)
		"npc": # like a click on the first NPC of the map: walks beside it, then npc_talk (the dialog window opens)
			for id: int in _client.views:
				if _client.views[id].has_meta("npc") and (c.size() < 3 or int(_client.views[id].get_meta("npc")) == int(c[2])): # npc[:<npcs.id>]
					_client._click(_client.views[id].position + Vector2(0, -40), false)
					break
		"friends": # F: the contacts window, optionally on a tab (friends | enemy | ignored)
			_client.player_hud.contacts.open()
			if c.size() > 2:
				_client.player_hud.contacts._tabs.select(Contacts.KINDS.find(str(c[2])))
		"friend_add", "enemy_add", "ignore_add": # friend_add:<name> (like typing /friend <name>)
			b.send(ProtocolContacts.add(str(c[1]).trim_suffix("_add").replace("ignore", Contacts.IGNORED), str(c[2])))
		"quests": # Q: the quest journal
			_client.player_hud.quests.toggle()
		"reply": # reply:<id> (dialog open; a quest offered = 1000000 + its id)
			b.send(Protocol.dialog_reply(int(c[2])))
		"buy": # buy:<item id>[:<qty>] (shop window open)
			b.send(Protocol.shop_buy(int(c[2]), int(c[3]) if c.size() > 3 else 1))
		"sell": # sell:<item id>[:<qty>] (the first bag stack of that item)
			for it: Dictionary in _client.player_hud.inventory.bag_items():
				if int(it["id"]) == int(c[2]):
					b.send(Protocol.shop_sell(int(it["uid"]), int(c[3]) if c.size() > 3 else 1))
					break
		"craft": # craft:<skill id> (the workshop window opens, like the J key or a click on a workshop)
			b.send(Protocol.craft_open(int(c[2])))
		"craft_put": # craft_put:<item id>:<qty> (a bag item goes down), craft_recipe:<item id> puts a book recipe down
			var cm: Variant = _client.player_hud.craft.model.add(int(c[2]), int(c[3]))
			if cm != null:
				b.send(cm)
		"craft_recipe":
			for r: Dictionary in _client.player_hud.craft.model.book:
				if int(r["item"]) == int(c[2]):
					b.send(_client.player_hud.craft.model.fill_from(r))
		"craft_make": # craft_make:<count>
			var mk: Variant = _client.player_hud.craft.model.make(int(c[2]))
			if mk != null:
				b.send(mk)
		"forge": # forge (the K key: smithmagic window), forge_pick:<item id>:<rune id> picks the first bag stacks, forge_apply
			_client.player_hud.smith.toggle_workshop()
		"forge_pick":
			var sm: SmithmagicWindow = _client.player_hud.smith
			for it: Dictionary in sm._bag():
				if int(it["id"]) == int(c[2]):
					sm.model.item_uid = int(it["uid"])
					for w: int in Smithmagic.workshops():
						if Smithmagic.accepts(w, int(it["id"])):
							sm.model.set_skill(w)
							sm.model.item_uid = int(it["uid"])
							sm._skills.select(sm._skills.get_item_index(w))
			sm.model.rune = int(c[3])
			sm._fill()
		"forge_apply":
			var fa: Variant = _client.player_hud.smith.model.apply(_client.player_hud.smith._bag())
			if fa != null:
				b.send(fa)
		"bank_in": # bank_in:<item id>[:<qty>] (chest open: the first bag stack of that item goes in)
			for it: Dictionary in _client.player_hud.inventory.bag_items():
				if int(it["id"]) == int(c[2]):
					b.send(Protocol.bank_move(int(it["uid"]), int(c[3]) if c.size() > 3 else int(it["qty"]), BankRules.IN))
					break
		"bank_out": # bank_out:<item id>[:<qty>] (the first chest stack of that item comes out)
			for it: Dictionary in _client.player_hud.bank._items.values():
				if int(it["id"]) == int(c[2]):
					b.send(Protocol.bank_move(int(it["uid"]), int(c[3]) if c.size() > 3 else int(it["qty"]), BankRules.OUT))
					break
		"bank_kamas": # bank_kamas:in|out:<amount>
			b.send(Protocol.bank_kamas(int(c[3]), c[2]))
		"phoenix": # like a click on the phoenix: walks beside it, then use_phoenix
			_client._click(MapGeometry.to_screen(_client.map.phoenix), false)
		"energy": # tool shortcut: energy:<n>, 0 = a ghost (re-enters the map so that others see it)
			var lb := b as LocalBackend
			var p: PlayerActor = lb.sim.players[lb.player_id]
			p.character.energy = int(c[2])
			p.character.life = Energy.GHOST if int(c[2]) <= 0 else Energy.ALIVE
			p.settle(lb.sim.now)
			lb.sim.teleport(p, p.map_id, p.cell)
			p.outbox.append(Protocol.player_stats(p.character.public_dict(lb.sim.now)))
		"travel": # travel:<map id> (zaap window open)
			b.send(Protocol.zaap_travel(int(c[2])))
		"worldmap": # M
			_client.player_hud.world_map.toggle()
		"kamas": # tool shortcut: kamas:<n>
			var lb := b as LocalBackend
			var p: PlayerActor = lb.sim.players[lb.player_id]
			p.character.kamas = int(c[2])
			p.outbox.append(Protocol.player_stats(p.character.public_dict(lb.sim.now)))
		"console": # Entrée, types the line (a "_" = a space) and sends it: console:/tp_5_-18
			_client.chat.open()
			_client.chat.submit(":".join(c.slice(2)).replace("_", " "))
		"say": # say:<line> ("_" = space): types in the chat box, e.g. say:/w_Bob_salut ; tab:<n> = open that chat tab
			_client.chat.submit(":".join(c.slice(2)).replace("_", " "))
		"trigger":
			b.send(Protocol.use_trigger(int(c[2])))
		"door": # like a click on the door on <cell>: walks beside it, then use_trigger
			_client._click(MapGeometry.to_screen(int(c[2])), false)
		"stars": # tool shortcut: stars:<pct> for the map's subarea, then re-enters the map to show them
			var lb := b as LocalBackend
			var p: PlayerActor = lb.sim.players[lb.player_id]
			var m := lb.sim.get_map(p.map_id)
			lb.sim.stars.set_bonus(m.data.subarea, float(c[2]), lb.sim.clock.now_unix_ms())
			p.settle(lb.sim.now)
			lb.sim.teleport(p, p.map_id, p.cell)
		"aggro": # tool shortcut: every group of the map attacks whoever stays 3 s within 15 cells
			var lb := b as LocalBackend
			for a: SimActor in lb.sim.get_map(lb.sim.players[lb.player_id].map_id).actors.values():
				if a is MonsterGroup:
					a.members[0]["aggro"] = {"zone": 15, "level_diff": -200, "immunity": ""}
		"mark": # mark:<cell>[:<cell>...] paints cells red (finding door cells)
			for i in range(2, c.size()):
				_client._map_view.overlays[int(c[i])] = Color(1, 0, 0, 0.6)
			_client._map_view.queue_redraw()
		"grid":
			_client._map_view.debug = true
			_client._map_view.queue_redraw()
		"give": # tool shortcut: gives items in the local sim (give:<item id>[:<qty>])
			var lb := b as LocalBackend
			lb.sim.give_item(lb.sim.players[lb.player_id], int(c[2]), int(c[3]) if c.size() > 3 else 1)
		"use": # use the first stack of an item id (give it first)
			var inv := _client.player_hud.inventory
			for uid: int in inv._items:
				if int(inv._items[uid]["id"]) == int(c[2]):
					b.send(Protocol.use_item(uid))
					break
		"boost":
			b.send(Protocol.boost_stat(c[2], int(c[3]) if c.size() > 3 else 0))
		"points": # the characteristics' batch spending window (points:<stat>[:<n> points])
			_client.player_hud.characteristics.ask_points(c[2])
			if c.size() > 3:
				var spin: SpinBox = _client.find_children("", "SpinBox", true, false)[-1]
				spin.value = int(c[3])
			if c.size() > 4: # points:<stat>:<n>:ok = then "Investir"
				(_client.find_children("PointsDialog", "", true, false)[0].find_children("", "Button", true, false) \
						.filter(func(x: Button) -> bool: return x.text == "Investir")[0] as Button).pressed.emit()
		"tab": # the characteristics window's tab
			(_client.player_hud.characteristics.find_children("", "UiTabs", true, false)[0] as UiTabs).select(int(c[2]))
		"leave":
			b.send(Protocol.fight_leave())
		"join", "watch", "swordsmenu": # the swords of a fight on the map (P3.04b): join = Rejoindre, watch = Regarder, swordsmenu = their click menu
			for id: int in _client.views:
				var sw := _client.views[id] as FightSwords
				if sw != null:
					if c[1] == "swordsmenu":
						sw.menu(_client, _client.get_viewport().get_visible_rect().size / 2.0)
					else:
						b.send(ProtocolWatch.join(id, 0) if c[1] == "join" else ProtocolWatch.spectate(id))
					break


## mate:<command>: the second player (--mate) does what the first would
func _run_mate(c: PackedStringArray) -> void:
	var sim := _mate.sim
	var me: PlayerActor = sim.players[_mate.player_id]
	match c[2]:
		"move":
			_mate.send(Protocol.move(int(c[3]), c[3].ends_with("!")))
		"change_map":
			_mate.send(Protocol.change_map(c[3]))
		"goto":
			sim.teleport(me, int(c[3]), sim.get_map(int(c[3])).data.nearest_walkable(int(c[4]) if c.size() > 4 else 300))
		"say": # mate:say:<line> ("_" = space): the chat line, as typed (/w, /b ...)
			_mate.send(Protocol.chat_send(Chat.GENERAL, ":".join(c.slice(3)).replace("_", " ")))
		"invite": # mate:invite = the mate invites us into a group
			_mate.send(ProtocolParty.invite(_client.player_name))
		"give": # mate:give:<item>[:<qty>] (tool shortcut)
			sim.give_item(me, int(c[3]), int(c[4]) if c.size() > 4 else 1)
		"trade": # mate:trade = the mate invites us to trade
			_mate.send(ProtocolTrade.invite(_client.player_name))
		"tradeput", "tradeready": # the mate's side of the window, by the messages the window would send
			if c[2] == "tradeready":
				_mate.send(ProtocolTrade.ready())
			else:
				var stack := {}
				for it: Dictionary in me.character.inventory.to_array():
					if int(it["id"]) == int(c[3]):
						stack = it
				if not stack.is_empty():
					_mate.send(ProtocolTrade.set_offer([{"uid": int(stack["uid"]), "qty": int(c[4]) if c.size() > 4 else 1}], int(c[5]) if c.size() > 5 else 0))
		"attack":
			for a: SimActor in sim.get_map(me.map_id).actors.values():
				if a is MonsterGroup:
					_mate.send(Protocol.fight_attack(a.id))
					break


func _nearest_enemy_id() -> int:
	var f := _client.fight
	var from := int(f.me()["cell"])
	var best := -1
	for id: int in f.fighters:
		var e: Dictionary = f.fighters[id]
		if int(e["team"]) == 1 and e["alive"] and (best < 0 or FightRules.distance(from, int(e["cell"])) < FightRules.distance(from, int(f.fighters[best]["cell"]))):
			best = id
	return best


func _nearest_enemy() -> int:
	var f := _client.fight
	var from := int(f.me()["cell"])
	var best := -1
	for id: int in f.fighters:
		var e: Dictionary = f.fighters[id]
		if int(e["team"]) == 1 and e["alive"] and (best < 0 or FightRules.distance(from, int(e["cell"])) < FightRules.distance(from, best)):
			best = int(e["cell"])
	return best


func _save(path: String) -> void:
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
