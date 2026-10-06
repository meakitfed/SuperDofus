## Items, part 1 (roadmap P1.05): instances with uids and effects rolled at
## creation, stacks, pods and overload, consumables (heal, recall, scrolls with
## their items.criterions), destroy. Real item data, through LocalBackend.
extends TestCase


func _init() -> void:
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()


class Conn:
	var backend := LocalBackend.new()
	var events: Array = []

	func _init(server: LocalServer, save := {}) -> void:
		backend.server = server
		backend.event.connect(func(ev: Dictionary) -> void: events.append(ev))
		if not save.is_empty():
			server.persistence.save_character("items", "Bob", save)
		backend.send(Protocol.hello("items", "Bob"))
		backend.poll(0.0)

	func player() -> PlayerActor:
		return backend.sim.players[backend.player_id]

	func send(cmd: Dictionary) -> void:
		backend.send(cmd)
		backend.poll(0.0)

	func give(id: int, qty := 1) -> Dictionary:
		backend.sim.give_item(player(), id, qty)
		backend.poll(0.0)
		return last(Protocol.ITEM_ADDED).get("item", {})

	func last(type: String) -> Dictionary:
		var l := events.filter(func(e: Dictionary) -> bool: return e["t"] == type)
		return l[-1] if not l.is_empty() else {}

	func errors() -> Array:
		var out := events.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.ERROR).map(func(e: Dictionary) -> String: return e["code"])
		events.clear()
		return out


static func _server() -> LocalServer:
	var s := LocalServer.new()
	s.sources["items"] = WorldSource.from_dicts(
		{"id": "items", "name": "Items", "start_map": 1, "start_cell": 300},
		[{"id": 1, "coords": [0, 0], "neighbors": {"right": 2}}, {"id": 2, "coords": [1, 0], "neighbors": {"left": 1}}])
	return s


func test_effects_are_rolled_at_creation_deterministically() -> void:
	var a := RandomNumberGenerator.new()
	a.seed = 7
	var b := RandomNumberGenerator.new()
	b.seed = 7
	var ra := ItemEffects.roll(44, a) # Épée de Boisaille: 8-10 neutral hit, 7-10 Force, 1 earth damage
	eq(ra, ItemEffects.roll(44, b), "same seed, same rolls")
	eq(ra[0], [100, 8, 10, 0], "a weapon hit keeps its dice (effects.bonusType 0)")
	eq(int(ra[1][0]), 118)
	check(int(ra[1][1]) >= 7 and int(ra[1][1]) <= 10 and int(ra[1][2]) == 0, "Force rolled once in 7..10")
	eq(ra[2], [422, 1, 0, 0])
	eq(ItemEffects.roll(468, a), [[110, 12, 0, 0]], "a consumable keeps its usage dice")
	var values := {}
	for i in 60:
		values[int(ItemEffects.roll(44, a)[1][1])] = true
	eq(values.size(), 4, "every value of 7..10 comes out")


func test_uids_and_stacks() -> void:
	var c := Conn.new(_server())
	var bread := c.give(468, 3)
	eq(int(bread["qty"]), 3)
	var again := c.give(468, 2)
	eq(int(again["uid"]), int(bread["uid"]), "identical items stack")
	eq(int(again["qty"]), 5)
	var inv := Inventory.new()
	var n := [100]
	var alloc := func() -> int:
		n[0] += 1
		return n[0]
	var s1 := inv.add(44, 1, [[118, 8, 0, 0]], alloc)
	var s2 := inv.add(44, 1, [[118, 9, 0, 0]], alloc)
	var s3 := inv.add(44, 1, [[118, 8, 0, 0]], alloc)
	check(int(s1["uid"]) != int(s2["uid"]), "different rolls, different stacks")
	eq(int(s3["uid"]), int(s1["uid"]))
	var cape := c.give(2473)
	check(int(cape["uid"]) > int(bread["uid"]), "uids from Persistence.next_uid")
	eq(c.backend.server.persistence.next_uid("item"), int(cape["uid"]) + 1)


func test_overloaded_characters_cannot_move() -> void:
	var c := Conn.new(_server())
	eq(int(c.last(Protocol.PLAYER_STATS)["stats"]["max_weight"]), 1000, "StatFormulas.pods")
	var pile := c.give(468, 501) # 2 pods each: 1002 > 1000
	c.errors()
	c.send(Protocol.move(301, false))
	eq(c.errors(), [Protocol.E_OVERLOADED])
	c.send(Protocol.destroy_item(int(pile["uid"]), 1))
	eq(int(c.last(Protocol.ITEM_ADDED)["item"]["qty"]), 500)
	c.send(Protocol.move(301, false))
	eq(c.errors(), [], "1000 pods: not overloaded")
	c.send(Protocol.destroy_item(int(pile["uid"])))
	eq(int(c.last(Protocol.ITEM_REMOVED)["uid"]), int(pile["uid"]), "destroy the whole stack")
	eq(int(c.player().character.weight()), 0)


func test_healing_potion() -> void:
	var c := Conn.new(_server())
	var ch := c.player().character
	ch.set_hp(10, c.backend.sim.now)
	var potion := c.give(1182, 2) # Potion de Mini Soin: Rend 11 PV
	c.send(Protocol.use_item(int(potion["uid"])))
	eq(int(c.last(Protocol.PLAYER_STATS)["stats"]["hp"]), 21)
	eq(int(c.last(Protocol.ITEM_ADDED)["item"]["qty"]), 1, "one potion used")
	c.send(Protocol.use_item(int(potion["uid"])))
	eq(int(c.last(Protocol.ITEM_REMOVED)["uid"]), int(potion["uid"]))
	c.send(Protocol.use_item(int(potion["uid"])))
	eq(c.errors(), [Protocol.E_UNKNOWN_ITEM])
	var dust := c.give(519)
	c.send(Protocol.use_item(int(dust["uid"])))
	eq(c.errors(), [Protocol.E_ITEM_NOT_USABLE])


func test_recall_potion_goes_to_the_save_point() -> void:
	var c := Conn.new(_server(), {"name": "Bob", "map": 2, "cell": 250, "level": 5})
	eq(c.player().map_id, 2)
	var recall := c.give(548)
	c.events.clear()
	c.send(Protocol.use_item(int(recall["uid"])))
	eq(int(c.last(Protocol.MAP_ENTER)["map"]["id"]), 1, "the world's start (no zaap yet)")
	eq(c.player().map_id, 1)


func test_scrolls_follow_their_criteria() -> void:
	var c := Conn.new(_server())
	var scroll := c.give(683, 2) # Petit Parchemin de Force: +1 additional Force, cs<25
	c.send(Protocol.use_item(int(scroll["uid"])))
	var st: Dictionary = c.last(Protocol.PLAYER_STATS)["stats"]
	eq(int(st["additional"]["strength"]), 1)
	eq(int(st["derived"]["pods"]), 1005, "additional points count (5 pods per Force)")
	c.player().character.additional["strength"] = 25
	c.send(Protocol.use_item(int(scroll["uid"])))
	eq(c.errors(), [Protocol.E_ITEM_CONDITION], "cs<25")
	check(CriteriaEval.ok("cs<25", {"strength_additional": 24}))
	check(not CriteriaEval.ok("PL>10&cs<25", {"level": 5, "strength_additional": 0}))
	check(CriteriaEval.ok("PL>10|CW>2", {"level": 5, "wisdom": 3}))
	check(not CriteriaEval.ok("Qx=3", {}), "unknown keys never pass")


func test_old_saves_get_uids() -> void:
	var c := Conn.new(_server(), {"name": "Bob", "inventory": {"519": 2, "16512": 1}})
	var items: Array = c.last(Protocol.INVENTORY)["items"]
	eq(items.size(), 2)
	for it: Dictionary in items:
		check(int(it["uid"]) > 0)
	eq(c.player().character.inventory.count(519), 2)
