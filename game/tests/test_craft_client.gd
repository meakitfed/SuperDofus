## P2.06b: the state behind the workshop window (CraftModel) follows craft_state and builds the messages
## the window sends; driven through a LocalBackend, so the sim answers for real.
extends TestCase

const SKILL := 20
const RING_A := 16512
const RING_B := 303


static func _backend() -> LocalBackend:
	var s := LocalServer.new()
	s.sources["craft"] = WorldSource.from_dicts({"id": "craft", "name": "Craft", "start_map": 1, "start_cell": 301},
		[{"id": 1, "coords": [0, 0], "neighbors": {}}])
	var b := LocalBackend.new()
	b.server = s
	b.send(Protocol.hello("craft", "Eli", "{1}"))
	b.poll(0.0)
	return b


## Sends `cmd` and feeds every craft_state of the answer to the model.
static func _step(b: LocalBackend, m: CraftModel, cmd: Dictionary) -> Array:
	var events: Array = []
	var f := func(ev: Dictionary) -> void: events.append(ev)
	b.event.connect(f)
	b.send(cmd)
	b.poll(0.0)
	b.event.disconnect(f)
	for ev: Dictionary in events:
		if ev["t"] == Protocol.CRAFT_STATE:
			m.apply_state(ev)
	return events


func test_state_follows_the_sim() -> void:
	var b := _backend()
	var m := CraftModel.new()
	check(not m.is_open)
	_step(b, m, Protocol.craft_open(SKILL))
	check(m.is_open)
	eq(m.skill, SKILL)
	check(m.slots >= 2)
	check(not m.book.is_empty(), "the book comes with the first state")
	eq(m.result, 0)
	check(not m.can_craft())
	check(m.make(1) == null, "nothing to make without a recipe")
	# the first book recipe fills the slots; the bag is empty so max stays 0
	var first: Dictionary = m.book[0]
	_step(b, m, m.fill_from(first))
	eq(m.result, int(first["item"]))
	eq(m.ingredients.size(), (first["ingredients"] as Array).size())
	eq(m.max_count, 0)
	check(not m.can_craft())
	_step(b, m, Protocol.craft_set([]))
	eq(m.result, 0)
	check(not m.book.is_empty(), "the book stays for the later states")


func test_adding_and_removing_ingredients() -> void:
	var b := _backend()
	var m := CraftModel.new()
	_step(b, m, Protocol.craft_open(SKILL))
	var msg: Variant = m.add(RING_A, 3)
	check(msg != null)
	_step(b, m, msg)
	eq(m.qty_of(RING_A), 3)
	_step(b, m, m.add(RING_A, 2))
	eq(m.qty_of(RING_A), 5, "the same item stacks in one slot")
	_step(b, m, m.add(RING_B, 3))
	eq(m.ingredients.size(), 2)
	_step(b, m, m.remove(RING_A))
	eq(m.qty_of(RING_A), 0)
	eq(m.ingredients.size(), 1)
	check(m.add(RING_B, 0) == null, "nothing to add")


func test_full_slots_refuse_a_new_item_locally() -> void:
	var b := _backend()
	var m := CraftModel.new()
	_step(b, m, Protocol.craft_open(SKILL))
	var n := m.slots
	for i in n:
		_step(b, m, m.add(100 + i, 1))
	eq(m.ingredients.size(), n)
	check(not m.has_room_for(999))
	check(m.add(999, 1) == null)
	check(m.add(100, 1) != null, "an item already down still takes more")


func test_make_is_clamped_to_what_the_bag_holds() -> void:
	var b := _backend()
	var m := CraftModel.new()
	_step(b, m, Protocol.craft_open(SKILL))
	var sim: WorldSim = b.sim
	var p: PlayerActor = sim.players[b.player_id]
	sim.give_item(p, RING_A, 6)
	sim.give_item(p, RING_B, 6)
	_step(b, m, Protocol.craft_open(SKILL))
	_step(b, m, Protocol.craft_set([{"item": RING_A, "qty": 3}, {"item": RING_B, "qty": 3}]))
	check(m.can_craft())
	eq(m.max_count, 2)
	var cmd: Variant = m.make(50)
	eq(int(cmd["count"]), 2, "clamped to max")
	eq(int(m.make(0)["count"]), 1)
	var events := _step(b, m, cmd)
	check(events.any(func(e: Dictionary) -> bool: return e["t"] == Protocol.CRAFT_DONE))
	eq(m.max_count, 0)
	check(not m.can_craft())
	m.close()
	check(not m.is_open)
	check(m.book.is_empty())
