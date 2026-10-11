## Dungeons (P4.01), a WorldSim handler. The rules are in shared/Dungeon, the messages in
## shared/ProtocolDungeon; nothing here knows one dungeon: the definition comes from the world's
## dungeons.json (WorldSource.get_dungeon).
## A run = one player, or the whole group (WorldParty) of the one who opens the door. Each room is
## a PRIVATE MapInstance of the room's map (key < 0, see MapInstance.key): the run's own actors and
## monster groups, composed by Dungeon.compose_room. Rooms are chained by the rule (the maps have no
## exits): the room is cleared when all its groups are beaten, the run moves on to the next one, and
## after the last one (the boss) it ends `won`. Nothing is persisted: a character that is saved
## inside a run is saved at the door.
class_name WorldDungeons
extends WorldHandler

## run id -> {id, def, room, key, left (groups to beat), members [player ids], entry {player id: cell}, keys [instance keys]}
var runs := {}
## player id -> run
var of := {}
## instance key -> run
var by_key := {}
## entrance map id -> [{id, name, min_level}] (built on first use)
var _entrances := {}
var _indexed := false


# ── entrance map: the dungeons that start there ────────────────────────────────

## The map dict of map_enter, extended with `dungeons` [{id, name, min_level}] when the map is the
## entrance of some dungeons (the real map only, never a room).
func annotate(map: MapInstance, d: Dictionary) -> Dictionary:
	if map.is_instance():
		return d
	if not _indexed:
		_index()
	var list: Array = _entrances.get(map.data.id, [])
	if not list.is_empty():
		d["dungeons"] = list
	return d


func _index() -> void:
	_indexed = true
	var ids: Array = sim.source.get_dungeons().keys()
	ids.sort()
	for id: int in ids:
		var def := sim.source.get_dungeon(id)
		var at := int(def.get("entrance_map", -1))
		if not _entrances.has(at):
			_entrances[at] = []
		_entrances[at].append({"id": id, "name": str(def.get("name", "")), "min_level": int(def.get("min_level", 0))})


# ── commands ───────────────────────────────────────────────────────────────────

func on_command(p: PlayerActor, type: String, cmd: Dictionary) -> void:
	var err := _enter(p, int(cmd["dungeon"])) if type == ProtocolDungeon.ENTER else _leave(p)
	if err != "":
		p.outbox.append(Protocol.error(err, "", type))


func _enter(p: PlayerActor, id: int) -> String:
	var def := sim.source.get_dungeon(id)
	if def.is_empty() or Dungeon.room_count(def) == 0 or sim.source.get_map(Dungeon.room_map(def, 0)) == null:
		return ProtocolDungeon.E_DUNGEON_UNKNOWN
	if p.map_id != int(def.get("entrance_map", -1)):
		return ProtocolDungeon.E_DUNGEON_NOT_AT_ENTRANCE
	if p.character.is_ghost():
		return Protocol.E_GHOST
	var members: Array[PlayerActor] = [p]
	var party := sim.party.party_of(p.name)
	if party != null:
		if party.leader() != p.name:
			return ProtocolParty.E_NOT_PARTY_LEADER
		for name: String in party.members: # the members standing at the door come in with the leader
			var q := sim.chat.find_player(name)
			if q != null and q != p and q.map_id == p.map_id and q.fight_id == 0 and q.spectating == 0 and not q.character.is_ghost():
				members.append(q)
	var bag := {}
	for it: Dictionary in p.character.inventory.items.values():
		if int(it.get("pos", Inventory.BAG)) == Inventory.BAG:
			bag[int(it["id"])] = int(bag.get(int(it["id"]), 0)) + int(it["qty"])
	match Dungeon.check_entry(def, p.character.level, bag):
		"level":
			return ProtocolDungeon.E_DUNGEON_LEVEL
		"key":
			return ProtocolDungeon.E_DUNGEON_KEY
	var keyless := def.duplicate()
	keyless["keys"] = []
	for q in members: # APPROX(P4.01): every member needs the level, the key is taken once, from the leader
		if Dungeon.check_entry(keyless, q.character.level, {}) != "":
			return ProtocolDungeon.E_DUNGEON_LEVEL
	for k: Dictionary in Dungeon.keys_to_consume(def):
		for t: Dictionary in p.character.inventory.take(int(k["item"]), int(k["qty"])):
			p.outbox.append(Protocol.item_added(t["left"]) if not (t["left"] as Dictionary).is_empty() else Protocol.item_removed(int(t["uid"])))
	var run := {"id": sim.alloc_id(), "def": def, "room": -1, "key": 0, "left": 0, "members": [], "entry": {}, "keys": []}
	for q in members:
		q.settle(sim.now)
		run["members"].append(q.id)
		run["entry"][q.id] = q.dest_cell()
		of[q.id] = run
	runs[run["id"]] = run
	_open_room(run, 0)
	return ""


func _leave(p: PlayerActor) -> String:
	var run: Dictionary = of.get(p.id, {})
	if run.is_empty():
		return ProtocolDungeon.E_DUNGEON_NOT_IN
	_exit(run, p, ProtocolDungeon.REASON_LEFT, true)
	return ""


# ── rooms ──────────────────────────────────────────────────────────────────────

## Builds the private instance of room `idx`, puts its groups on it and brings the run's members in.
func _open_room(run: Dictionary, idx: int) -> void:
	var def: Dictionary = run["def"]
	var data := sim.source.get_map(Dungeon.room_map(def, idx))
	var key := -sim.alloc_id()
	var m := MapInstance.new(data, hash([sim.seed, key]))
	m.key = key
	var w: Array = sim.info.get("wander_ms", [8000, 20000])
	m.wander_ms = Vector2i(int(w[0]), int(w[1]))
	m.stars = func(_subarea: int, _area: int) -> int: return 0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([sim.seed, key, 7])
	var spawns: Array = []
	for g: Dictionary in Dungeon.compose_room(def, idx, rng, _pool(def, data, Dungeon.has_boss(def, idx))):
		spawns.append({"name": "Groupe", "members": g["members"], "subarea": data.subarea})
	m.spawn_groups(spawns, sim.alloc_id, sim.now)
	sim.maps[key] = m
	by_key[key] = run
	run["keys"].append(key)
	run["room"] = idx
	run["key"] = key
	run["left"] = m.actors.values().filter(func(a: SimActor) -> bool: return a is MonsterGroup).size()
	_sync(run)
	var old: Array = (run["keys"] as Array).filter(func(k: int) -> bool: return k != key)
	for k: int in old: # the rooms behind are dropped once nobody is left in them
		if not _occupied(k):
			_drop(run, k)
	if Dungeon.room_cleared(int(run["left"])): # nothing to fight here (APPROX(P4.01): empty pool): straight on
		_advance(run)


## Brings every member that is free (not in a fight) and not yet in the current room into it.
func _sync(run: Dictionary) -> void:
	var def: Dictionary = run["def"]
	var m: MapInstance = sim.maps[int(run["key"])]
	var spot := _spot(m.data)
	var idx := int(run["room"])
	for pid: int in (run["members"] as Array).duplicate():
		var q: PlayerActor = sim.players.get(pid)
		if q == null or q.fight_id != 0 or q.spectating != 0 or q.map_id == m.key:
			continue
		sim.teleport(q, m.key, spot)
		q.outbox.append(ProtocolDungeon.room(int(def["id"]), idx, Dungeon.room_count(def), Dungeon.has_boss(def, idx), str(def.get("name", ""))))


## Where the players arrive in a room: the first red placement cell (fight cells), else the centre.
func _spot(data: MapData) -> int:
	var red: Array = data.placement.get("red", [])
	return data.nearest_walkable(int(red[0]) if not red.is_empty() else 300)


## The monsters a room may hold, as the fiches Dungeon.compose_room reads ({id, grades}): the ones of the
## room's subarea (else of the entrance's), and on the boss room the bosses of the dungeon.
## APPROX(P4.01): the real compositions are server data.
func _pool(def: Dictionary, data: MapData, with_boss: bool) -> Array:
	var ids := sim.spawner.pool(data.subarea)
	if ids.is_empty():
		var door := sim.source.get_map(int(def.get("entrance_map", -1)))
		ids = sim.spawner.pool(door.subarea) if door != null else []
	var out: Array = []
	for id: Variant in ids:
		out.append({"id": int(id), "grades": sim.spawner.monsters[str(int(id))]["grades"]})
	if with_boss:
		for b: Variant in def.get("bosses", []):
			var boss := sim.source.get_boss(int(b))
			if not boss.is_empty():
				out.append({"id": int(b), "grades": boss.get("grades", [])})
	return out


func _occupied(key: int) -> bool:
	var m: MapInstance = sim.maps.get(key)
	return m != null and m.has_players()


func _drop(run: Dictionary, key: int) -> void:
	sim.maps.erase(key)
	by_key.erase(key)
	(run["keys"] as Array).erase(key)


## The room is cleared: next room, or the end (won) after the last one.
func _advance(run: Dictionary) -> void:
	var next := Dungeon.next_room(run["def"], int(run["room"]))
	if next < 0:
		run["ending"] = true # the followers a leader drags out are not "leaving"
		for pid: int in (run["members"] as Array).duplicate():
			var q: PlayerActor = sim.players.get(pid)
			if q != null:
				_exit(run, q, ProtocolDungeon.REASON_WON, true)
		return
	_open_room(run, next)


## A fight of a room is over (WorldFights.finish_fight, on an instance only): a win counts the group,
## a defeat takes its fighters out of the run (they are already at the save point), and a cleared
## room moves the run on.
func after_fight(fight: Fight, map: MapInstance, fought: Array) -> void:
	var run: Dictionary = by_key.get(map.key, {})
	if run.is_empty():
		return
	if fight.result == "win":
		if map.key == int(run["key"]):
			run["left"] = int(run["left"]) - 1
	elif fight.result == "lose":
		for p: PlayerActor in fought:
			if of.get(p.id) == run:
				_exit(run, p, ProtocolDungeon.REASON_DEFEAT, false)
	if not runs.has(run["id"]):
		return
	if fight.result == "win" and map.key == int(run["key"]) and Dungeon.room_cleared(int(run["left"])):
		_advance(run)
	else:
		_sync(run)


# ── leaving ────────────────────────────────────────────────────────────────────

## `p` leaves the run (`reason` is what it is told); `out` = walks out through the door. The run
## is dropped when nobody is left.
func _exit(run: Dictionary, p: PlayerActor, reason: String, out: bool) -> void:
	(run["members"] as Array).erase(p.id)
	of.erase(p.id)
	if out:
		var def: Dictionary = run["def"]
		var exit_id := int(def.get("exit_map", -1))
		if not sim.source.has_map(exit_id):
			exit_id = int(def.get("entrance_map", -1))
		var m := sim.get_map(exit_id)
		if m == null:
			exit_id = int(sim.info.get("start_map", 0))
			m = sim.get_map(exit_id)
		# APPROX(P4.01): the cell of the door is the one the player entered from (same map), else the centre
		var cell := int(run["entry"].get(p.id, 300)) if exit_id == int(def.get("entrance_map", -1)) else 300
		sim.teleport(p, exit_id, m.data.nearest_walkable(cell))
	p.outbox.append(ProtocolDungeon.end(int(run["def"]["id"]), reason))
	if (run["members"] as Array).is_empty():
		_destroy(run)


func _destroy(run: Dictionary) -> void:
	for k: int in (run["keys"] as Array).duplicate():
		_drop(run, k)
	runs.erase(run["id"])


## A player disconnects (WorldSim.disconnect_player, already off its map): out of its run, and
## the character is saved at the door. The other members go on; an empty run is dropped.
func on_disconnect(p: PlayerActor) -> void:
	var run: Dictionary = of.get(p.id, {})
	if run.is_empty():
		return
	p.map_id = int(run["def"].get("entrance_map", p.map_id))
	p.cell = int(run["entry"].get(p.id, 300))
	p.path = []
	(run["members"] as Array).erase(p.id)
	of.erase(p.id)
	if (run["members"] as Array).is_empty():
		_destroy(run)


## The character is saved from inside a room: at the door (WorldSim.character_write).
func saved_spot(p: PlayerActor) -> void:
	var run: Dictionary = of.get(p.id, {})
	if not run.is_empty():
		p.character.map_id = int(run["def"].get("entrance_map", p.character.map_id))
		p.character.cell = int(run["entry"].get(p.id, p.character.cell))


## A player was teleported (WorldSim.teleport): out of a room by something else (recall potion, GM tp)
## it leaves the run.
func on_teleported(p: PlayerActor) -> void:
	var run: Dictionary = of.get(p.id, {})
	if not run.is_empty() and not run.has("ending") and not by_key.has(p.map_id):
		_exit(run, p, ProtocolDungeon.REASON_LEFT, false)
