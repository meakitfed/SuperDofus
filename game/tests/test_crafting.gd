## P2.06: crafting (craft_open / craft_set / craft_do), recipe book, slots by job level, craft XP.
## Skill 20 = Forger (Forgeron job 11): recipe 44 = 3 x item 16512 + 3 x item 303 (2 slots), recipe 55 = 4 x 364 + 4 x 300 + 4 x 2659 (3 slots).
extends TestCase

const SKILL := 20
const RING := 44
const RING_A := 16512
const RING_B := 303
const BIG := 55


class Conn:
	var backend := LocalBackend.new()
	var events: Array = []
	var you := -1

	func _init(p_server: LocalServer) -> void:
		backend.server = p_server
		backend.event.connect(func(ev: Dictionary) -> void:
			events.append(ev)
			if ev["t"] == Protocol.WELCOME:
				you = int(ev["you"]))
		backend.send(Protocol.hello("craft", "Eli", "{1}"))
		backend.poll(0.0)

	func send(cmd: Dictionary) -> Array:
		events = []
		backend.send(cmd)
		backend.poll(0.0)
		return events

	func of(type: String) -> Array:
		return events.filter(func(e: Dictionary) -> bool: return e["t"] == type)

	func code() -> String:
		var errs := of(Protocol.ERROR)
		return "" if errs.is_empty() else str(errs[0]["code"])

	func player() -> PlayerActor:
		return backend.sim.players[you]


static func _conn() -> Conn:
	var s := LocalServer.new()
	s.sources["craft"] = WorldSource.from_dicts({"id": "craft", "name": "Craft", "start_map": 1, "start_cell": 301},
		[{"id": 1, "coords": [0, 0], "neighbors": {}}])
	return Conn.new(s)


static func _ring_ingredients(times := 1) -> Array:
	return [{"item": RING_A, "qty": 3 * times}, {"item": RING_B, "qty": 3 * times}]


func test_recipes_are_indexed_by_skill_and_ingredients() -> void:
	check(Crafting.is_craft_skill(SKILL))
	check(not Crafting.is_craft_skill(6), "a harvest skill crafts nothing")
	eq(int(Crafting.match_recipe(SKILL, _ring_ingredients())["resultId"]), RING)
	eq(int(Crafting.match_recipe(SKILL, [{"item": RING_B, "qty": 3}, {"item": RING_A, "qty": 3}])["resultId"]), RING, "any order")
	check(Crafting.match_recipe(SKILL, [{"item": RING_A, "qty": 3}, {"item": RING_B, "qty": 2}]).is_empty(), "quantities as written")
	check(Crafting.match_recipe(63, _ring_ingredients()).is_empty(), "another skill")
	eq(Crafting.slots_for_level(1), 2)
	eq(Crafting.slots_for_level(40), 4)
	eq(Crafting.slots_for_level(200), 8)


func test_opening_a_workshop_gives_the_state_and_the_book() -> void:
	var c := _conn()
	var st: Dictionary = c.send(Protocol.craft_open(SKILL))[0]
	eq(st["t"], Protocol.CRAFT_STATE)
	eq(int(st["slots"]), 2)
	eq(int(st["view"]["job"]), 11)
	eq(int(st["result"]), 0)
	var items := (st["book"] as Array).map(func(b: Dictionary) -> int: return int(b["item"]))
	check(items.has(RING), "the recipe of a 2-slot item is in the book")
	check(not items.has(BIG), "a 3-slot recipe is not shown at level 1")


func test_a_bad_skill_or_no_workshop_is_refused() -> void:
	var c := _conn()
	c.send(Protocol.craft_open(6))
	eq(c.code(), Protocol.E_NO_CRAFT)
	c.send(Protocol.craft_set(_ring_ingredients()))
	eq(c.code(), Protocol.E_NO_CRAFT)
	c.send(Protocol.craft_do(1))
	eq(c.code(), Protocol.E_NO_CRAFT)
	c.send(Protocol.craft_open(SKILL))
	c.send(Protocol.craft_close())
	c.send(Protocol.craft_do(1))
	eq(c.code(), Protocol.E_NO_CRAFT, "closed")


func test_set_finds_the_recipe_and_how_many_the_bag_allows() -> void:
	var c := _conn()
	c.backend.sim.give_item(c.player(), RING_A, 7)
	c.backend.sim.give_item(c.player(), RING_B, 10)
	c.send(Protocol.craft_open(SKILL))
	var st: Dictionary = c.send(Protocol.craft_set(_ring_ingredients()))[0]
	eq(int(st["result"]), RING)
	eq(int(st["max"]), 2, "7 / 3")
	eq((st["book"] as Array).size(), 0, "the book is only sent on opening")
	st = c.send(Protocol.craft_set([{"item": RING_A, "qty": 1}]))[0]
	eq(int(st["result"]), 0, "no recipe")


func test_too_many_ingredients_for_the_job_level_are_refused() -> void:
	var c := _conn()
	c.send(Protocol.craft_open(SKILL))
	c.send(Protocol.craft_set([{"item": 364, "qty": 4}, {"item": 300, "qty": 4}, {"item": 2659, "qty": 4}]))
	eq(c.code(), Protocol.E_CRAFT_SLOTS)
	c.player().character.jobs.gain(11, GameData.xp_floor(20))
	var st: Dictionary = c.send(Protocol.craft_open(SKILL))[0]
	eq(int(st["slots"]), 3)
	check((st["book"] as Array).any(func(b: Dictionary) -> bool: return int(b["item"]) == BIG), "the 3-slot recipe appears")
	st = c.send(Protocol.craft_set([{"item": 364, "qty": 4}, {"item": 300, "qty": 4}, {"item": 2659, "qty": 4}]))[0]
	eq(int(st["result"]), BIG)


func test_crafting_a_series_takes_the_ingredients_and_gives_items_and_xp() -> void:
	var c := _conn()
	var p := c.player()
	c.backend.sim.give_item(p, RING_A, 10)
	c.backend.sim.give_item(p, RING_B, 9)
	c.send(Protocol.craft_open(SKILL))
	c.send(Protocol.craft_set(_ring_ingredients()))
	var ev := c.send(Protocol.craft_do(3))
	eq(c.code(), "")
	var done: Dictionary = c.of(Protocol.CRAFT_DONE)[0]
	eq(int(done["item"]), RING)
	eq(int(done["count"]), 3)
	eq(p.character.inventory.bag_count(RING), 3)
	eq(p.character.inventory.bag_count(RING_A), 1, "10 - 9")
	eq(p.character.inventory.bag_count(RING_B), 0)
	var xp: Dictionary = c.of(Protocol.JOB_XP)[0]
	eq(int(xp["gained"]), (Crafting.XP_BASE + 7) * 3)
	eq(p.character.jobs.xp_of(11), (Crafting.XP_BASE + 7) * 3)
	var st: Dictionary = c.of(Protocol.CRAFT_STATE)[0]
	eq(int(st["max"]), 0, "nothing left for another")
	check(ev.any(func(e: Dictionary) -> bool: return e["t"] == Protocol.ITEM_REMOVED), "the empty stack is removed")
	# the items rolled their effects: each instance has the effects of the item
	for it: Dictionary in p.character.inventory.to_array():
		if int(it["id"]) == RING:
			check(not (it["effects"] as Array).is_empty(), "rolled effects")


func test_missing_ingredients_and_unknown_recipes_are_refused() -> void:
	var c := _conn()
	var p := c.player()
	c.backend.sim.give_item(p, RING_A, 3)
	c.backend.sim.give_item(p, RING_B, 3)
	c.send(Protocol.craft_open(SKILL))
	c.send(Protocol.craft_do(1))
	eq(c.code(), Protocol.E_NO_RECIPE, "nothing set")
	c.send(Protocol.craft_set(_ring_ingredients()))
	c.send(Protocol.craft_do(2))
	eq(c.code(), Protocol.E_MISSING_INGREDIENTS)
	c.send(Protocol.craft_do(0))
	eq(c.code(), Protocol.E_NO_RECIPE, "count 0")
	eq(p.character.inventory.bag_count(RING_A), 3, "nothing was taken")
	c.send(Protocol.craft_do(1))
	eq(c.code(), "")
	eq(p.character.inventory.bag_count(RING), 1)


func test_a_malformed_craft_set_is_refused() -> void:
	var c := _conn()
	c.send(Protocol.craft_open(SKILL))
	c.send({"t": Protocol.CRAFT_SET, "ingredients": [{"item": 1}]})
	eq(c.code(), Protocol.E_BAD_MESSAGE)
	c.send({"t": Protocol.CRAFT_SET})
	eq(c.code(), Protocol.E_BAD_MESSAGE)
