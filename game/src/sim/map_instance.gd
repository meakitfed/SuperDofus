## A live map in the sim: its actors, its monster AI, and the fan-out of events
## to the players standing on it.
class_name MapInstance
extends RefCounted

var data: MapData
var pathfinder: MapPathfinder
var actors := {} # id -> SimActor
var rng := RandomNumberGenerator.new()
var wander_ms := Vector2i(8000, 20000)
var respawn_ms := 20000
var _next_id: Callable
var _respawns: Array = [] # [{at, spawn}]
## composes the groups of {subarea} spawn slots (null: fixed groups only)
var spawner: MonsterSpawner
## (subarea, area) -> the subarea's stars in % (SubareaBonus), set by WorldSim
var stars: Callable
## groups ready to attack a player: [[MonsterGroup, PlayerActor]], taken by WorldSim.tick
var aggressions: Array = []
## the harvestable elements and their state (P2.05)
var interactives: InteractiveState

## Dofus 2.45 aggression (https://dofus.jeuxonline.info/actualite/53581): the
## group's leader "gère la zone de vision" (monsters.aggressiveZoneSize cells);
## a character standing in it "pendant plus de 3 secondes" is attacked when the
## leader's level is more than monsters.aggressiveLevelDiff above theirs (−200:
## always, like Wabbits); "en priorité le premier personnage qu'il aura aperçu
## et en cas d'égalité [...] le niveau est le plus faible". Immune:
## monsters.aggressiveImmunityCriterion (CriteriaEval, e.g. PO=9910).
## APPROX(P1.09): monsters.aggressiveAttackDelay (10000 ms) is not used, its
## meaning is unknown; the devblog's 3 s is.
const AGGRESSION_MS := 3000


func _init(p_data: MapData, seed: int) -> void:
	data = p_data
	pathfinder = MapPathfinder.new(data)
	interactives = InteractiveState.new(data.interactives)
	rng.seed = seed


func spawn_groups(spawns: Array, next_id: Callable, now: int) -> void:
	_next_id = next_id
	for s: Dictionary in spawns:
		_spawn_group(s, now)


## NPCs of the map: [{npc, cell, dir, look?, name_id?}] (WorldSource.get_npcs); `dialog_for` gives the tree of a template ({} = silent).
func spawn_npcs(placed: Array, next_id: Callable, dialog_for: Callable) -> void:
	for n: Dictionary in placed:
		var row := GameData.row("npcs", int(n["npc"]))
		if row.is_empty() and not n.has("look"): # a hand-made NPC carries its own look
			continue
		row = row.duplicate()
		row.merge({"look": n.get("look", ""), "nameId": n.get("name_id", 0), "actions": [3]}, false)
		var a := NpcActor.new()
		a.id = next_id.call()
		a.map_id = data.id
		a.npc_id = int(n["npc"])
		a.name_id = int(row.get("nameId", 0))
		a.actions = row.get("actions", [])
		a.cell = int(n["cell"])
		a.dir = int(n.get("dir", 1))
		a.looks = PackedStringArray([str(row.get("look", ""))])
		a.dialog = dialog_for.call(a.npc_id)
		actors[a.id] = a


## A spawn entry is {name?, members: [{look, name, level, hp, ap, mp}]}, {looks: [...]}
## (fixed groups) or {subarea} (composed by the spawner, anew at each respawn).
func _spawn_group(s: Dictionary, now: int) -> MonsterGroup:
	var members: Array = s.get("members", [])
	if members.is_empty() and s.has("subarea"):
		if spawner == null:
			return null
		members = spawner.compose(int(s["subarea"]), rng)
		if members.is_empty():
			return null
	var cell := random_free_cell()
	if cell < 0:
		return null
	var g := MonsterGroup.new()
	g.id = _next_id.call()
	g.name = str(s.get("name", "Groupe"))
	g.map_id = data.id
	g.cell = cell
	g.home_cell = cell
	g.dir = rng.randi_range(0, 3) * 2 + 1 # diagonal facings, as on Dofus maps
	g.spawn = s
	g.members = members
	g.subarea = int(s.get("subarea", data.subarea))
	g.bonus = int(stars.call(g.subarea, data.area)) if stars.is_valid() else 0
	if g.members.is_empty():
		g.members = s.get("looks", []).map(func(l: String) -> Dictionary: return {"look": l})
	g.looks = PackedStringArray(g.members.map(func(m: Dictionary) -> String: return str(m.get("look", ""))))
	g.next_think = now + rng.randi_range(1000, wander_ms.y)
	actors[g.id] = g
	return g


## Defeated groups come back after a while, somewhere else on the map.
func schedule_respawn(g: MonsterGroup, now: int) -> void:
	_respawns.append({"at": now + respawn_ms, "spawn": g.spawn})


func random_free_cell() -> int:
	for attempt in 200:
		var c := rng.randi_range(0, MapGeometry.CELL_COUNT - 1)
		if data.is_walkable(c) and not MapGeometry.is_edge(c):
			return c
	return -1


func tick(now: int) -> void:
	for e: int in interactives.tick(now):
		broadcast(Protocol.interactive_state(e, true))
	for r: Dictionary in _respawns.duplicate():
		if now >= int(r["at"]):
			_respawns.erase(r)
			var g := _spawn_group(r["spawn"], now)
			if g != null:
				broadcast(Protocol.actor_add(g.to_dict(now)))
	for a: SimActor in actors.values():
		a.update(now)
		if a is MonsterGroup:
			MonsterGroupAI.think(a, self, now, rng, wander_ms)
	for a: SimActor in actors.values():
		if a is MonsterGroup:
			_watch(a, now)


## Aggression: who stands in the leader's vision, and for how long.
func _watch(g: MonsterGroup, now: int) -> void:
	var leader: Dictionary = g.members[0] if not g.members.is_empty() else {}
	var aggro: Dictionary = leader.get("aggro", {})
	var zone := int(aggro.get("zone", 0))
	if not data.monster_aggression or zone <= 0:
		return
	var ready: Array = []
	for a: SimActor in actors.values():
		if not a is PlayerActor:
			continue
		var p := a as PlayerActor
		if MapGeometry.distance(g.cell, p.cell) > zone or not _aggresses(leader, aggro, p):
			g.seen.erase(p.id)
			continue
		if not g.seen.has(p.id):
			g.seen[p.id] = now
			broadcast(Protocol.group_alert(g.id, p.id))
		elif now - int(g.seen[p.id]) >= AGGRESSION_MS:
			ready.append(p)
	if ready.is_empty():
		return
	ready.sort_custom(func(x: PlayerActor, y: PlayerActor) -> bool:
		return int(g.seen[x.id]) < int(g.seen[y.id]) or (int(g.seen[x.id]) == int(g.seen[y.id]) and x.character.level < y.character.level))
	g.seen.clear()
	aggressions.append([g, ready[0]])


static func _aggresses(leader: Dictionary, aggro: Dictionary, p: PlayerActor) -> bool:
	if p.character.is_ghost(): # a ghost cannot fight (Energy)
		return false
	if int(leader.get("level", 1)) - p.character.level <= int(aggro.get("level_diff", 0)):
		return false
	var immunity := str(aggro.get("immunity", ""))
	return immunity == "" or not CriteriaEval.ok(immunity, p.character.criteria_values())


func has_players() -> bool:
	for a: SimActor in actors.values():
		if a is PlayerActor:
			return true
	return false


func add_actor(a: SimActor, now: int) -> void:
	a.map_id = data.id
	actors[a.id] = a
	broadcast(Protocol.actor_add(a.to_dict(now)), a.id)


func remove_actor(a: SimActor) -> void:
	actors.erase(a.id)
	broadcast(Protocol.actor_remove(a.id))


func move_actor(a: SimActor, path: Array, t0: int, run: bool) -> void:
	a.start_move(path, t0, run)
	broadcast(Protocol.actor_move(a.id, path, t0, run))


func actors_dicts(now: int) -> Array:
	var out: Array = []
	for a: SimActor in actors.values():
		out.append(a.to_dict(now))
	return out


func broadcast(ev: Dictionary, except_id := -1) -> void:
	for a: SimActor in actors.values():
		if a is PlayerActor and a.id != except_id:
			(a as PlayerActor).outbox.append(ev)
