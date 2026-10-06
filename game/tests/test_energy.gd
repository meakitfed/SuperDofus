## Energy, death, ghost, phoenix (roadmap P1.10): a lost fight costs 10 energy
## per level, at 0 the character is a ghost (it walks, cannot fight nor use a
## zaap, groups ignore it) until it reaches the Incarnam phoenix; energy comes
## back while logged out (twice as fast in the Tavern) and with a Michette.
extends TestCase

const START := 154010373
const CEMETERY_WEST := 153881088 # Cimetière (4,-1): the phoenix (links.json)
const TAVERN := 153357316
const ZAAP := 153880064
const MICHETTE := 521 # items effect 139: +30 energy


func _init() -> void:
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()


class Conn:
	var backend := LocalBackend.new()
	var events: Array = []

	func _init() -> void:
		backend.server = LocalServer.new()
		backend.event.connect(func(ev: Dictionary) -> void: events.append(ev))
		backend.send(Protocol.hello("incarnam", "Bob"))
		backend.poll(0.0)

	func player() -> PlayerActor:
		return backend.sim.players[backend.player_id]

	func put(map_id: int, cell: int) -> void:
		events.clear()
		backend.sim.teleport(player(), map_id, cell)
		backend.poll(0.0)

	func send(cmd: Dictionary) -> void:
		events.clear()
		backend.send(cmd)
		backend.poll(0.0)

	func last(type: String) -> Dictionary:
		var l := events.filter(func(e: Dictionary) -> bool: return e["t"] == type)
		return l[-1] if not l.is_empty() else {}

	func infos() -> Array:
		return events.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.INFO).map(
				func(e: Dictionary) -> String: return str(e["code"]))

	func error() -> String:
		return str(last(Protocol.ERROR).get("code", ""))

	## Attacks a group of the start map and passes every turn until the end.
	func lose_a_fight() -> Dictionary:
		put(START, 287)
		var group := -1
		for id: int in backend.sim.get_map(START).actors:
			if backend.sim.get_map(START).actors[id] is MonsterGroup:
				group = id
		send(Protocol.fight_attack(group))
		send(Protocol.fight_ready(true))
		var all: Array = []
		for i in 600:
			backend.send(Protocol.fight_end_turn())
			backend.server.tick(500)
			backend.poll(0.0)
			all.append_array(events)
			if not last(Protocol.FIGHT_END).is_empty():
				events = all
				return last(Protocol.FIGHT_END)
		return {}


func test_defeat_loss_is_ten_per_level() -> void:
	eq(Energy.defeat_loss(1), 10)
	eq(Energy.defeat_loss(150), 1500)
	eq(Energy.defeat_loss(260), 2000, "APPROX: capped at level 200")
	eq(Energy.offline_gain(90 * 60000 + 59999, false), 90, "1 point per whole minute")
	eq(Energy.offline_gain(10 * 60000, true), 20, "twice as fast in a tavern")


func test_a_defeat_costs_energy_and_zero_makes_a_ghost() -> void:
	var c := Conn.new()
	var end := c.lose_a_fight()
	eq(str(end["result"]), "lose")
	eq(int(end["rewards"][0]["energy_lost"]), 10, "level 1: 10 energy")
	eq(c.player().character.energy, Energy.MAX - 10)
	check(c.infos().has(Protocol.I_ENERGY_LOST))
	check(not c.player().character.is_ghost())
	# the last points: a ghost, back at the save point
	c.player().character.energy = 4
	end = c.lose_a_fight()
	eq(int(end["rewards"][0]["energy_lost"]), 4, "what was left")
	eq(c.player().character.energy, 0)
	check(c.player().character.is_ghost())
	eq(c.infos(), [Protocol.I_ENERGY_LOST, Protocol.I_GHOST])
	eq(int(c.last(Protocol.PLAYER_STATS)["stats"]["life"]), Energy.GHOST)
	eq(c.player().map_id, START, "save point (the world's start)")
	eq(int(c.player().to_dict(0)["life"]), Energy.GHOST, "everyone sees a ghost")


func test_a_ghost_walks_and_cannot_fight() -> void:
	var c := Conn.new()
	c.player().character.lose_energy(Energy.MAX)
	c.put(START, 287)
	var group := -1
	for id: int in c.backend.sim.get_map(START).actors:
		if c.backend.sim.get_map(START).actors[id] is MonsterGroup:
			group = id
	c.send(Protocol.fight_attack(group))
	eq(c.error(), Protocol.E_GHOST)
	eq(c.player().fight_id, 0)
	c.put(ZAAP, c.backend.sim.get_map(ZAAP).data.use_cells(c.backend.sim.get_map(ZAAP).data.zaap)[0])
	c.send(Protocol.use_zaap())
	eq(c.error(), Protocol.E_GHOST)
	c.put(START, 287)
	c.send(Protocol.move(300, true))
	eq(bool(c.last(Protocol.ACTOR_MOVE).get("run", true)), false, "a ghost walks")
	var aggro := {"zone": 10, "level_diff": -200, "immunity": ""}
	check(not MapInstance._aggresses({"level": 50}, aggro, c.player()), "groups ignore a ghost")


func test_the_phoenix_resurrects_a_ghost() -> void:
	var c := Conn.new()
	var m := c.backend.sim.get_map(CEMETERY_WEST).data
	check(m.phoenix >= 0, "the Incarnam phoenix is on the Cimetière (4,-1)")
	check(not m.use_cells(m.phoenix).is_empty())
	c.put(CEMETERY_WEST, m.use_cells(m.phoenix)[0])
	c.send(Protocol.use_phoenix())
	eq(c.error(), Protocol.E_NOT_GHOST, "only a ghost")
	c.player().character.lose_energy(Energy.MAX)
	c.put(CEMETERY_WEST, 440)
	c.send(Protocol.use_phoenix())
	eq(c.error(), Protocol.E_NOT_AT_PHOENIX)
	c.put(CEMETERY_WEST, m.use_cells(m.phoenix)[0])
	c.send(Protocol.use_phoenix())
	eq(c.error(), "")
	check(not c.player().character.is_ghost())
	eq(c.player().character.energy, Energy.PHOENIX)
	check(c.infos().has(Protocol.I_RESURRECTED))
	eq(int(c.last(Protocol.PLAYER_STATS)["stats"]["life"]), Energy.ALIVE)
	check(not c.player().to_dict(0).has("life"))
	var phoenixes: Array = c.last(Protocol.PLAYER_STATS)["stats"]["phoenixes"]
	eq(int(phoenixes[0]["map"]), CEMETERY_WEST, "shown on the world map")


func test_energy_comes_back_while_logged_out_twice_in_the_tavern() -> void:
	var clock := Clock.new(1_000_000)
	var sim := WorldSim.new(JsonWorldSource.for_world("incarnam"), 1, Persistence.new(), clock)
	var id := sim.connect_player("Bob", "")
	var p: PlayerActor = sim.players[id]
	p.character.energy = 100
	sim.disconnect_player(id)
	clock.advance(90 * 60000)
	id = sim.connect_player("Bob", "")
	eq((sim.players[id] as PlayerActor).character.energy, 190, "90 minutes: +90")
	var infos := sim.drain(id).filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.INFO)
	eq(infos.map(func(e: Dictionary) -> Array: return [e["code"], e["args"]]), [[Protocol.I_ENERGY_REGAINED, [90]]])
	p = sim.players[id]
	sim.teleport(p, TAVERN, sim.get_map(TAVERN).data.nearest_walkable(300))
	sim.disconnect_player(id)
	clock.advance(10 * 60000)
	id = sim.connect_player("Bob", "")
	eq((sim.players[id] as PlayerActor).character.energy, 210, "10 minutes in the Tavern: +20")
	# a ghost does not come back to life by resting
	p = sim.players[id]
	p.character.lose_energy(Energy.MAX)
	sim.disconnect_player(id)
	clock.advance(60 * 60000)
	id = sim.connect_player("Bob", "")
	eq((sim.players[id] as PlayerActor).character.energy, 0)
	check((sim.players[id] as PlayerActor).character.is_ghost())


func test_a_michette_gives_energy_back() -> void:
	var c := Conn.new()
	c.backend.sim.give_item(c.player(), MICHETTE, 2)
	c.backend.poll(0.0)
	var uid := int(c.player().character.inventory.items.values().filter(
			func(it: Dictionary) -> bool: return int(it["id"]) == MICHETTE).front()["uid"])
	c.send(Protocol.use_item(uid))
	eq(c.error(), Protocol.E_ENERGY_FULL, "already at the maximum")
	c.player().character.energy = 5000
	c.send(Protocol.use_item(uid))
	eq(c.player().character.energy, 5030)
	eq((c.last(Protocol.INFO).get("args", []) as Array).map(func(v: Variant) -> int: return int(v)), [30])
	c.player().character.lose_energy(Energy.MAX)
	c.send(Protocol.use_item(uid))
	eq(c.error(), Protocol.E_GHOST, "a ghost uses no item")
