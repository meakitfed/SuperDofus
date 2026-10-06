## The authoritative game: one world, its live maps, connected players.
## Pure logic (no nodes), driven by tick(delta_ms). It is the future server:
## a transport feeds it commands (handle) and ships events (drain).
## WorldSim is the thin router (connection, tick, drain, dispatch); the rules of each
## domain live in the WorldHandler classes below (R.01), one per domain.
class_name WorldSim
extends RefCounted

var source: WorldSource
## durable state, injected by the host (memory, files in standalone, a DB on a server)
var persistence: Persistence
## real-world date (never read Time/OS in the sim)
var clock: Clock
var info := {}
var now := 0 # ms since the world started
var seed := 1
var maps := {} # map id -> MapInstance (created on demand)
var players := {} # player id -> PlayerActor
var fights := {} # fight id -> Fight
var _next_id := 1
## sessions the sim ended itself (character logged in elsewhere): id -> last events
var _closed := {}
## the world's randomness out of fights (item rolls, consumables), seeded
var rng := RandomNumberGenerator.new()
## monster groups by subarea, and their stars (P1.09)
var spawner: MonsterSpawner
var stars: SubareaBonus
## resurrection phoenixes of the world [{map, coords, world_map}] (world.json "phoenixes")
var phoenixes: Array = []

## the domain handlers
var items: WorldItems
var travel: WorldTravel
var npcs: WorldNpcs
var quests: WorldQuests
var jobs: WorldJobs
var crafting: WorldCrafting
var smithmagic: WorldSmithmagic
var death: WorldDeath
var combat: WorldFights
var chat: WorldChat
var party: WorldParty
var contacts: WorldContacts
var trade: WorldTrade
var watch: WorldFightWatch
var resume: WorldResume
var admin: WorldAdmin


func _init(p_source: WorldSource, p_seed := 1, p_persistence: Persistence = null, p_clock: Clock = null) -> void:
	source = p_source
	info = source.get_info()
	seed = p_seed
	persistence = p_persistence if p_persistence != null else Persistence.new()
	clock = p_clock if p_clock != null else Clock.new()
	rng.seed = p_seed
	items = WorldItems.new(self)
	travel = WorldTravel.new(self)
	npcs = WorldNpcs.new(self)
	quests = WorldQuests.new(self)
	jobs = WorldJobs.new(self)
	crafting = WorldCrafting.new(self)
	smithmagic = WorldSmithmagic.new(self)
	death = WorldDeath.new(self)
	combat = WorldFights.new(self)
	chat = WorldChat.new(self)
	party = WorldParty.new(self)
	contacts = WorldContacts.new(self)
	trade = WorldTrade.new(self)
	watch = WorldFightWatch.new(self)
	resume = WorldResume.new(self)
	admin = WorldAdmin.new(self)
	spawner = MonsterSpawner.new(source.get_monsters(), int(info.get("max_groups", 3)))
	stars = SubareaBonus.new(persistence, world_id())
	for id: Variant in info.get("phoenixes", []):
		if source.has_map(int(id)):
			var m := source.get_map(int(id))
			phoenixes.append({"map": m.id, "coords": [m.coords.x, m.coords.y], "world_map": m.world_map})


# ── sessions ───────────────────────────────────────────────────────────────────

## A session starts: the host (LocalBackend, later the server after login)
## gives the account it authenticated. Returns the player id the host uses
## for handle / drain. A character plays in one session at a time: logging
## in again ends the previous session (Dofus behaviour).
func connect_player(name: String, look: String, account := "") -> int:
	for other: PlayerActor in players.values():
		if other.name == name:
			other.outbox.append(Protocol.error(Protocol.E_CONNECTED_ELSEWHERE))
			_closed[other.id] = other.outbox
			disconnect_player(other.id)
			break
	var p := PlayerActor.new()
	p.id = alloc_id()
	p.name = name
	var saved := persistence.load_character(world_id(), name)
	p.character = Character.from_dict(saved, now) if not saved.is_empty() else Character.new()
	p.character.name = name
	if p.character.account == "":
		p.character.account = account
	if look != "":
		p.character.look = look
	for uid: int in p.character.inventory.items.keys(): # items saved before uids (P1.05)
		if uid <= 0:
			var it: Dictionary = p.character.inventory.items[uid]
			p.character.inventory.items.erase(uid)
			p.character.inventory.add(int(it["id"]), int(it["qty"]), it["effects"], items.new_item_uid)
	p.looks = PackedStringArray([p.character.display_look()])
	p.character.phoenixes = phoenixes
	# energy regained while logged out (Energy.offline_gain), not by a ghost
	var regained := 0
	if not saved.is_empty() and not p.character.is_ghost() and saved.has("saved_at"):
		regained = p.character.gain_energy(Energy.offline_gain(clock.now_unix_ms() - int(saved["saved_at"]), p.character.rest_x2))
	for id: int in p.character.known_zaaps:
		travel.add_zaap_info(p.character, id)
	players[p.id] = p
	p.outbox.append(Protocol.welcome(p.id, now, {"id": info.get("id", ""), "name": info.get("name", "")}))
	p.outbox.append(Protocol.player_stats(p.character.public_dict(now)))
	p.outbox.append(Protocol.inventory(p.character.inventory.to_array()))
	p.outbox.append(Protocol.quest_list(quests.views(p), quests.finished(p)))
	contacts.on_connect(p) # P3.05: its lists, and the notice to its friends
	if regained > 0:
		p.outbox.append(Protocol.info(Protocol.I_ENERGY_REGAINED, [regained]))
	var map_id := p.character.map_id if source.has_map(p.character.map_id) else int(info.get("start_map", 0))
	var map := get_map(map_id)
	if map == null:
		p.outbox.append(Protocol.error(Protocol.E_NO_START_MAP, "start map missing"))
		return p.id
	var cell := p.character.cell if map_id == p.character.map_id and p.character.cell >= 0 else int(info.get("start_cell", 0))
	enter_map(p, map, map.data.nearest_walkable(cell))
	return p.id


## A GM throws a player out (A1.01): it gets `code` (kicked, banned) as its last event, the
## session ends (the host drops the connection) and the character is saved and leaves the world.
func kick_player(p: PlayerActor, code := ProtocolAdmin.E_KICKED) -> void:
	p.outbox.append(Protocol.error(code))
	_closed[p.id] = p.outbox
	disconnect_player(p.id)


func disconnect_player(id: int) -> void:
	var p: PlayerActor = players.get(id)
	if p == null:
		return
	if p.spectating != 0 and fights.has(p.spectating):
		fights[p.spectating].spectators.erase(p.id)
	if fights.has(p.fight_id):
		var fight: Fight = fights[p.fight_id]
		fight.handle(p.id, Protocol.fight_leave(), now)
		if fight.result != "": # the last one out ends it; with others in it, only this player leaves (P3.04)
			combat.finish_fight(fight)
	jobs.cancel_harvest(p)
	party.on_disconnect(p)
	trade.on_disconnect(p)
	contacts.on_disconnect(p)
	var map := get_map(p.map_id)
	if map:
		map.remove_actor(p)
	save_player(p)
	players.erase(id)


func world_id() -> String:
	return str(info.get("id", ""))


## Persists the player's character (and where it stands).
func save_player(p: PlayerActor) -> void:
	var w := character_write(p)
	persistence.save_character(world_id(), p.name, w["data"])


## The write of a character (Persistence.commit), with the position updated.
func character_write(p: PlayerActor) -> Dictionary:
	if p.fight_id == 0:
		p.character.map_id = p.map_id
		p.character.cell = p.dest_cell()
		var here := get_map(p.map_id)
		p.character.rest_x2 = here != null and here.data.tavern
	var data := p.character.to_dict(now)
	data["saved_at"] = clock.now_unix_ms()
	return {"collection": Persistence.CHARACTERS, "key": world_id() + "/" + p.name, "data": data}


# ── commands ───────────────────────────────────────────────────────────────────

## Applies one command of a session. The sim never trusts the client: the
## message is checked against Protocol.SCHEMA first, then by the rules. Errors
## it causes carry `ref` = the command's seq.
func handle(player_id: int, cmd: Dictionary) -> void:
	var p: PlayerActor = players.get(player_id)
	if p == null:
		return
	var before := p.outbox.size()
	_handle(p, cmd)
	if cmd.has("seq"):
		for i in range(before, p.outbox.size()):
			if p.outbox[i]["t"] == Protocol.ERROR:
				p.outbox[i]["ref"] = int(cmd["seq"])


func _handle(p: PlayerActor, cmd: Dictionary) -> void:
	var type := str(cmd.get("t", ""))
	var invalid := Protocol.validate(cmd, Protocol.C2S)
	if invalid != "" or type == Protocol.HELLO:
		p.outbox.append(Protocol.error(Protocol.E_BAD_MESSAGE, invalid if invalid != "" else "already connected", type))
		return
	if type == Protocol.MOVE_SPELL: # the bar can be arranged in fight too
		character_changed(p, type, p.character.move_spell(int(cmd["spell"]), int(cmd["slot"])))
		return
	if type == Protocol.CHAT_SEND: # in fight too (general = the fighters, private, world channels)
		chat.on_chat_send(p, str(cmd["channel"]), str(cmd["text"]), str(cmd.get("to", "")))
		return
	if type == ProtocolContacts.GET or type == ProtocolContacts.ADD or type == ProtocolContacts.REMOVE: # friends: in fight too
		contacts.on_command(p, type, cmd)
		return
	if type.begins_with("party_"): # groups: in fight too
		party.on_command(p, type, cmd)
		return
	if p.spectating != 0: # a spectator can only leave (P3.04)
		if type == Protocol.FIGHT_LEAVE:
			watch.stop(p)
		else:
			p.outbox.append(Protocol.error(ProtocolWatch.E_SPECTATING, "", type))
		return
	if p.fight_id != 0:
		var fight: Fight = fights[p.fight_id]
		var err: String = fight.handle(p.id, cmd, now) if type.begins_with("fight_") and type not in [ProtocolWatch.JOIN, ProtocolWatch.SPECTATE] else Protocol.E_IN_FIGHT
		if err != "":
			p.outbox.append(Protocol.error(err, "", type))
		watch.after_command(p, fight)
		return
	if p.character.overloaded() and type in [Protocol.MOVE, Protocol.CHANGE_MAP, Protocol.USE_TRIGGER, Protocol.ZAAP_TRAVEL]:
		p.outbox.append(Protocol.error(Protocol.E_OVERLOADED, "%d / %d pods" % [p.character.weight(), p.character.max_weight()], type))
		return
	if p.character.is_ghost() and type in WorldDeath.GHOST_FORBIDDEN:
		p.outbox.append(Protocol.error(Protocol.E_GHOST, "", type))
		return
	if not p.harvest.is_empty() and type in WorldJobs.CANCELLED_BY:
		jobs.cancel_harvest(p)
	if type.begins_with("trade_"): # trades: out of fight only (the fight and spectator cases above)
		trade.on_command(p, type, cmd)
		return
	trade.cancel_for(p, ProtocolTrade.REASON_ACTION) # anything else a trader does ends the trade
	npcs.walk_away(p, type)
	_dispatch(p, get_map(p.map_id), type, cmd)


## One command out of fight, to the handler of its domain.
func _dispatch(p: PlayerActor, map: MapInstance, type: String, cmd: Dictionary) -> void:
	match type:
		Protocol.QUEST_ABANDON:
			quests.abandon(p, int(cmd["quest"]))
		Protocol.NPC_TALK:
			npcs.on_npc_talk(p, map, int(cmd["npc"]))
		Protocol.DIALOG_REPLY:
			npcs.on_dialog_reply(p, map, int(cmd["reply"]))
		Protocol.DIALOG_CLOSE:
			npcs.end_dialog(p)
		Protocol.SHOP_BUY:
			npcs.on_shop_buy(p, map, int(cmd["item"]), int(cmd["qty"]))
		Protocol.SHOP_SELL:
			npcs.on_shop_sell(p, map, int(cmd["uid"]), int(cmd["qty"]))
		Protocol.SHOP_CLOSE:
			npcs.end_shop(p)
		Protocol.BANK_MOVE:
			npcs.on_bank_move(p, map, int(cmd["uid"]), int(cmd["qty"]), str(cmd["dir"]))
		Protocol.BANK_KAMAS:
			npcs.on_bank_kamas(p, map, int(cmd["amount"]), str(cmd["dir"]))
		Protocol.BANK_CLOSE:
			npcs.end_bank(p)
		Protocol.USE_ITEM:
			character_changed(p, type, items.use_item(p, int(cmd["uid"])))
		Protocol.EQUIP:
			items.apply_items(p, type, p.character.equip(int(cmd["uid"]), int(cmd["slot"]), items.new_item_uid))
		Protocol.UNEQUIP:
			items.apply_items(p, type, p.character.unequip(int(cmd["slot"])))
		Protocol.DESTROY_ITEM:
			character_changed(p, type, items.destroy_item(p, int(cmd["uid"]), int(cmd.get("qty", 0))))
		Protocol.FIGHT_ATTACK:
			combat.on_fight_attack(p, map, int(cmd.get("group", -1)))
		ProtocolWatch.JOIN, ProtocolWatch.SPECTATE:
			watch.on_command(p, map, type, cmd)
		Protocol.MOVE:
			# APPROX(P1.10): a ghost walks (the sources only say it is slow)
			travel.on_move(p, map, int(cmd.get("cell", -1)), bool(cmd.get("run", false)) and not p.character.is_ghost())
		Protocol.CHANGE_MAP:
			travel.on_change_map(p, map, str(cmd.get("dir", "")))
		Protocol.USE_TRIGGER:
			travel.on_use_trigger(p, map, int(cmd.get("cell", -1)))
		Protocol.INTERACTIVE_USE:
			jobs.on_interactive_use(p, map, int(cmd["element"]), int(cmd["skill"]))
		Protocol.CRAFT_OPEN:
			crafting.on_craft_open(p, int(cmd["skill"]))
		Protocol.CRAFT_SET:
			crafting.on_craft_set(p, cmd["ingredients"])
		Protocol.CRAFT_DO:
			crafting.on_craft_do(p, int(cmd["count"]))
		Protocol.CRAFT_CLOSE:
			crafting.on_craft_close(p)
		Protocol.FM_APPLY:
			smithmagic.on_fm_apply(p, int(cmd["uid"]), int(cmd["rune"]))
		Protocol.USE_ZAAP:
			travel.on_use_zaap(p, map)
		Protocol.ZAAP_TRAVEL:
			travel.on_zaap_travel(p, map, int(cmd.get("map", -1)))
		Protocol.SET_SAVE_POINT:
			travel.on_set_save_point(p, map)
		Protocol.USE_PHOENIX:
			death.on_use_phoenix(p, map)
		Protocol.BOOST_STAT:
			character_changed(p, type, p.character.boost(str(cmd.get("stat", "")), int(cmd.get("points", 0))))
		Protocol.RESET_STATS:
			p.character.reset_stats(now)
			character_changed(p, type, "")
		Protocol.ADMIN_CMD:
			admin.on_cmd(p, str(cmd["cmd"]), cmd["args"])
		Protocol.CHOOSE_VARIANT: # APPROX(P1.03): out of fight only (Dofus: the spell book is locked in fight), not in the data
			character_changed(p, type, p.character.choose_variant(int(cmd["spell"])))
		var t:
			p.outbox.append(Protocol.error(Protocol.E_UNKNOWN_COMMAND, "", t))


## After a character command: the error, or the new stats (saved).
func character_changed(p: PlayerActor, type: String, err: String) -> void:
	if err != "":
		p.outbox.append(Protocol.error(err, "", type))
	else:
		p.outbox.append(Protocol.player_stats(p.character.public_dict(now)))
		save_player(p)


# ── time and events ────────────────────────────────────────────────────────────

func tick(delta_ms: int) -> void:
	now += delta_ms
	for m: MapInstance in maps.values():
		m.tick(now)
		for ag: Array in m.aggressions:
			var p: PlayerActor = ag[1]
			if p.fight_id == 0 and p.map_id == m.data.id and m.actors.has(ag[0].id):
				combat.start_fight(p, m, ag[0])
		m.aggressions.clear()
	jobs.tick()
	combat.tick()
	watch.tick()
	party.tick()
	trade.tick()
	resume.tick()


## True once for a session the sim ended itself (after its last events were
## drained): the host then drops the connection.
func take_closed(player_id: int) -> bool:
	if not _closed.has(player_id) or not (_closed[player_id] as Array).is_empty():
		return false
	_closed.erase(player_id)
	return true


func drain(player_id: int) -> Array:
	var p: PlayerActor = players.get(player_id)
	if p == null:
		if not _closed.has(player_id):
			return []
		var last: Array = _closed[player_id]
		_closed[player_id] = []
		return last
	var out := []
	for ev: Dictionary in p.outbox:
		p.seq += 1
		var stamped := ev.duplicate() # events may be shared by several outboxes (broadcasts)
		stamped["seq"] = p.seq
		out.append(stamped)
	p.outbox = []
	return out


# ── maps ───────────────────────────────────────────────────────────────────────

func get_map(id: int) -> MapInstance:
	if maps.has(id):
		return maps[id]
	var data := source.get_map(id)
	if data == null:
		return null
	var m := MapInstance.new(data, hash([seed, id]))
	var w: Array = info.get("wander_ms", [8000, 20000])
	m.wander_ms = Vector2i(int(w[0]), int(w[1]))
	m.spawner = spawner
	m.stars = func(subarea: int, area: int) -> int: return stars.bonus(subarea, area, clock.now_unix_ms())
	# mod groups (Mods) come after the map's own ones: its spawns and rolls are unchanged
	m.spawn_npcs(source.get_npcs(id), alloc_id, npcs.dialog_for)
	m.spawn_groups(spawner.spawns_for(data, source.get_spawns(id), m.rng) + source.get_mod_spawns(id), alloc_id, now)
	maps[id] = m
	return m


## Moves a player (out of fight) to another map / cell: map_enter, saved.
## Map changes, triggers, recall potions and zaaps go through here.
func teleport(p: PlayerActor, map_id: int, cell: int) -> void:
	var dest := get_map(map_id)
	var from_map := p.map_id
	get_map(p.map_id).remove_actor(p)
	enter_map(p, dest, cell)
	save_player(p)
	trade.cancel_for(p, ProtocolTrade.REASON_MOVED)
	party.on_moved(p, from_map)


func enter_map(p: PlayerActor, map: MapInstance, cell: int) -> void:
	p.cell = cell
	p.path = []
	map.add_actor(p, now)
	for a: SimActor in map.actors.values(): # the stars grow with time: shown as they are now
		if a is MonsterGroup:
			a.bonus = stars.bonus(a.subarea, map.data.area, clock.now_unix_ms())
	p.outbox.append(Protocol.map_enter(map.data.to_dict(), map.actors_dicts(now)))
	quests.send_markers(p)
	for d: Dictionary in map.interactives.depleted():
		p.outbox.append(Protocol.interactive_state(int(d["e"]), false, int(d["until"])))
	for other: PlayerActor in players.values():
		if other != p and not other.harvest.is_empty() and other.harvest["map"] == map.data.id:
			p.outbox.append(Protocol.interactive_start(other.id, int(other.harvest["element"]), int(other.harvest["skill"]), int(other.harvest["end"])))
	quests.event(p, {"kind": "map", "map": map.data.id, "subarea": map.data.subarea})
	# APPROX(P1.08): a zaap is registered when its map is entered (the roadmap's
	# "first visit"; Dofus may require using it once), not in the client data
	if map.data.zaap >= 0 and not p.character.known_zaaps.has(map.data.id):
		p.character.known_zaaps.append(map.data.id)
		travel.add_zaap_info(p.character, map.data.id)
		p.outbox.append(Protocol.zaap_known(map.data.id))
		p.outbox.append(Protocol.player_stats(p.character.public_dict(now)))


func alloc_id() -> int:
	_next_id += 1
	return _next_id - 1


# ── public API kept for hosts, tools and tests (the handlers do the work) ─────

## Gives `qty` new items to a player (drop, craft, quest…): WorldItems.give_item.
func give_item(p: PlayerActor, item_id: int, qty := 1, quest_event := true) -> void:
	items.give_item(p, item_id, qty, quest_event)


## The save point [map id, cell]: WorldTravel.save_point.
func save_point(c: Character) -> Array:
	return travel.save_point(c)


## The known zaaps a player can travel to from the zaap of `here`: WorldTravel.zaap_destinations.
func zaap_destinations(c: Character, here: MapData) -> Array:
	return travel.zaap_destinations(c, here)


## Test hooks (the player's fighter, the quest views and events).
func _player_fighter(p: PlayerActor) -> Fighter:
	return combat.player_fighter(p)


func _quest_views(p: PlayerActor) -> Array:
	return quests.views(p)


func _quest_event(p: PlayerActor, ev: Dictionary) -> bool:
	return quests.event(p, ev)
