## L'Ascension (worlds/ascension, built by `npm run recipe -- ../worlds_src/ascension/recipe.json` in atelier/): five
## floors of real Dofus maps, each closed on itself (its maps only lead to each other), and on each floor's hub a
## stair keeper whose dialogue goes up and down. Driven through LocalBackend like a client. The world holds data
## taken from Dofus and is never committed: skipped when it is not built on this machine.
## Its monsters (`npm run recipe -- ... --monsters`): the Dofus monsters by level band, one per floor, rising
## with the distance to the hub (no monster on the hub), dungeon bosses now and then, and a loot of bonus
## equipment only (world.json "rates").
extends TestCase

const WORLD := "ascension"
const FLOORS := 5
const MAX_FLOOR_MAPS := 20
## the level band of each floor (worlds_src/ascension/recipe.json "monsters.bands")
const BANDS := [[1, 40], [41, 80], [81, 120], [121, 160], [161, 200]]


class Conn:
	var backend := LocalBackend.new()
	var events: Array = []
	var npcs := {} # npc id -> actor id
	var map := 0

	func _init(server: LocalServer) -> void:
		backend.server = server
		backend.account = "local"
		backend.event.connect(func(ev: Dictionary) -> void:
			events.append(ev)
			if ev["t"] == Protocol.MAP_ENTER:
				map = int(ev["map"]["id"])
				npcs.clear()
				for a: Dictionary in ev["actors"]:
					if a["kind"] == "npc":
						npcs[int(a["npc"])] = int(a["id"]))

	func send(cmd: Dictionary) -> Array:
		events = []
		backend.send(cmd)
		backend.poll(0.0)
		return events

	func take(type: String) -> Array:
		return events.filter(func(e: Dictionary) -> bool: return e["t"] == type)


func _enter() -> bool:
	if not ContentSource.exists("worlds/%s/world.json" % WORLD):
		skip("world %s not built" % WORLD)
		return false
	ContentSource.use_world(WORLD)
	return true


func _leave() -> void:
	ContentSource.use_dev()


## The stair keepers by map: {hub map id: npc id}.
static func keepers() -> Dictionary:
	var out := {}
	var placed: Dictionary = ContentSource.read_json("worlds/%s/npcs.json" % WORLD)["maps"]
	for mid: String in placed:
		for row: Dictionary in placed[mid]:
			out[int(mid)] = int(row["npc"])
	return out


## The maps reached from `start` by walking map edges only.
static func floor_of(start: int) -> Dictionary:
	var seen := {start: true}
	var todo := [start]
	while not todo.is_empty():
		var m: Dictionary = ContentSource.read_json("worlds/%s/maps/%d.json" % [WORLD, todo.pop_back()])
		for to: Variant in (m.get("neighbors", {}) as Dictionary).values():
			if not seen.has(int(to)):
				seen[int(to)] = true
				todo.append(int(to))
	return seen


func test_five_closed_floors() -> void:
	if not _enter():
		return
	var info: Dictionary = ContentSource.read_json("worlds/%s/world.json" % WORLD)
	var hubs := keepers()
	eq(hubs.size(), FLOORS, "one stair keeper per floor")
	check(hubs.has(int(info["start_map"])), "players start on a floor's hub")
	var covered := {}
	for hub: int in hubs:
		var floor := floor_of(hub)
		check(floor.size() <= MAX_FLOOR_MAPS, "floor of %d: %d maps, no bigger than Incarnam" % [hub, floor.size()])
		for other: int in hubs:
			if other != hub:
				check(not floor.has(other), "floor of %d does not walk into the floor of %d" % [hub, other])
		for m: int in floor:
			check(not covered.has(m), "map %d belongs to one floor only" % m)
			covered[m] = true
	eq(covered.size(), (info["maps"] as Array).size(), "every map of the world is on a floor")
	_leave()


func test_the_stair_keeper_goes_up_and_down() -> void:
	if not _enter():
		return
	var c := Conn.new(LocalServer.new())
	var listed := c.send(Protocol.hello(WORLD))
	var chars := listed.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.CHARACTERS)
	check(not chars.is_empty() and not (chars[0]["breeds"] as Array).is_empty(), "the world offers classes")
	if chars.is_empty():
		_leave()
		return
	var breed := int((chars[0]["breeds"] as Array)[0])
	c.send(Protocol.create_character("Kirito", breed))
	c.send(Protocol.hello(WORLD, "Kirito"))
	var hubs := keepers()
	var first := c.map
	check(hubs.has(first), "the character starts on the first floor's hub (%d)" % first)
	var up := _reply(c, hubs[first], "Monter")
	check(up >= 0, "the keeper of the first floor offers to go up")
	if up < 0:
		_leave()
		return
	c.send(Protocol.dialog_reply(up))
	check(hubs.has(c.map) and c.map != first, "going up lands on another floor's hub (%d)" % c.map)
	var down := _reply(c, hubs.get(c.map, 0), "Descendre")
	check(down >= 0, "the keeper of the second floor offers to go down")
	if down >= 0:
		c.send(Protocol.dialog_reply(down))
		eq(c.map, first, "going down leads back to the first floor")
	_leave()


func test_monsters_by_floor_and_equipment_only() -> void:
	if not _enter():
		return
	var server := LocalServer.new()
	var sim := server.world(WORLD)
	check(sim.rates.bonus_drops, "the world forces the bonus drops (world.json rates)")
	var hubs: Array = sim.info["phoenixes"] # in floor order
	eq(hubs.size(), FLOORS)
	var with_groups := 0
	var bosses := 0
	for f in hubs.size():
		var hub := int(hubs[f])
		eq(_groups(sim, hub).size(), 0, "no monster on the hub of floor %d" % (f + 1))
		var lo := int(BANDS[f][0])
		var hi := int(BANDS[f][1])
		var first_ring := 999
		var last_ring := 0
		for m: int in floor_of(hub):
			if m == hub:
				continue
			var gs := _groups(sim, m)
			check(not gs.is_empty(), "groups on map %d of floor %d" % [m, f + 1])
			with_groups += 1
			for g: MonsterGroup in gs:
				for mem: Dictionary in g.members:
					var lv := int(mem["level"])
					if sim.spawner.bosses.has(str(int(mem.get("monster", 0)))):
						bosses += 1
					else:
						check(lv >= lo and lv <= hi, "map %d: level %d in %d-%d" % [m, lv, lo, hi])
					check((mem.get("drops", []) as Array).is_empty(), "no normal drop")
			var levels: Array = sim.spawner.subareas[str(sim.get_map(m).data.subarea)]["levels"]
			first_ring = mini(first_ring, int(levels[0]))
			last_ring = maxi(last_ring, int(levels[1]))
		eq(first_ring, lo, "floor %d starts at the bottom of its band" % (f + 1))
		eq(last_ring, hi, "floor %d ends at the top of its band" % (f + 1))
	check(with_groups >= 60, "the floors are full of monsters (%d maps)" % with_groups)
	print("    ascension: %d boss members among the first spawns" % bosses)
	# a won fight: equipment of the bonus drops only
	var c := Conn.new(server)
	c.send(Protocol.hello(WORLD))
	var chars := c.take(Protocol.CHARACTERS)
	c.send(Protocol.create_character("Asuna", int((chars[0]["breeds"] as Array)[0]) if not chars.is_empty() else 1))
	c.send(Protocol.hello(WORLD, "Asuna"))
	var target := -1
	for m: int in floor_of(int(hubs[0])):
		if m != int(hubs[0]):
			target = m
			break
	var data := sim.get_map(target).data
	sim.teleport(sim.players[c.backend.player_id], target, data.nearest_walkable(300))
	_step(server, c)
	var g: MonsterGroup = _groups(sim, target)[0]
	var ids: Array = g.members.map(func(mem: Dictionary) -> int: return int(mem.get("monster", 0)))
	var top: int = g.members.map(func(mem: Dictionary) -> int: return int(mem["level"])).max()
	c.send(Protocol.fight_attack(g.id))
	for i in 20:
		_step(server, c)
	c.send(Protocol.fight_ready())
	for i in 20:
		_step(server, c)
	var fight: Fight = sim.fights.values()[0] if not sim.fights.is_empty() else null
	check(fight != null, "the fight started")
	if fight != null:
		for f: Fighter in fight.fighters.values():
			if f.team == 1:
				f.hp = 0
				f.alive = false
		fight.rates = WorldRates.for_world(fight.rates, {"rates": {"bonus-drop-rate": 100}}) # every monster gives one
		fight._finish("win")
		for i in 200:
			_step(server, c)
			if c.events.any(func(e: Dictionary) -> bool: return e["t"] == Protocol.FIGHT_END):
				break
		var ends := c.events.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.FIGHT_END)
		check(not ends.is_empty(), "fight_end")
		if not ends.is_empty():
			var mine: Dictionary = ends[0]["rewards"][0]
			eq((mine.get("items", []) as Array).size(), 0, "no resource")
			check(not (mine.get("bonus_items", []) as Array).is_empty(), "bonus equipment")
			var pool := BonusDrops.set_items(ids) + BonusDrops.equipment_between(top - 15, top + 15)
			for it: Dictionary in mine.get("bonus_items", []):
				check(pool.has(int(it["id"])), "item %d: from the sets of the monsters or an equipment of their level" % int(it["id"]))
	_leave()


## The server owns the clock (the backend shares it): one 50 ms step of both.
static func _step(server: LocalServer, c: Conn) -> void:
	server.tick(50)
	c.backend.poll(0.05)


static func _groups(sim: WorldSim, map_id: int) -> Array:
	return sim.get_map(map_id).actors.values().filter(func(a: SimActor) -> bool: return a is MonsterGroup)


## Talks to the keeper `npc` of the current map; the id of the reply whose text starts with `word`, or -1.
func _reply(c: Conn, npc: int, word: String) -> int:
	if not c.npcs.has(npc):
		fail("keeper %d not on map %d" % [npc, c.map])
		return -1
	c.send(Protocol.npc_talk(c.npcs[npc]))
	var dlg := c.take(Protocol.DIALOG)
	if dlg.is_empty():
		fail("the keeper does not talk (%s)" % [c.events])
		return -1
	for r: Dictionary in dlg[0]["replies"]:
		if str(r.get("text", "")).begins_with(word):
			return int(r["id"])
	return -1
