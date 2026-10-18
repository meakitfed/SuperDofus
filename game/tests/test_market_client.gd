## P2.10b: the client side of the marketplace and its access. MarketModel (no node), the access rule
## of the sim (an auction house manager of the world, dialog button or direct), the window driven
## through a real ClientSession on a LocalBackend, and the same messages through NetBackends.
extends TestCase

const NetTests := preload("res://tests/test_net.gd")
const MANAGER := 2900     # npcs.id "Gérant de l'hôtel de vente"
const MANAGER_CELL := 330
const ITEM := 683         # items.price 1000, 1 pod
## the real manager's tree is built from the client tables (Dialog.with_market on its first message), absent in tests
const TREE := {"start": "a", "nodes": {"a": {"text": "Bonjour", "replies": [
	{"id": 1, "text": "Consulter l'hôtel de vente", "action": {"type": "market"}}]}}}


func _init() -> void:
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()


static func _source(id: String) -> WorldSource:
	var src := WorldSource.from_dicts({"id": id, "name": id, "start_map": 1, "start_cell": MapGeometry.neighbors(MANAGER_CELL)[0],
			"wander_ms": [600000, 600000]}, [{"id": 1, "coords": [0, 0], "neighbors": {}}])
	src.set_npcs({1: [{"npc": MANAGER, "cell": MANAGER_CELL, "dir": 3, "look": "{11}", "name_id": 749305}]}, {MANAGER: TREE})
	src.set_auctioneers([MANAGER])
	return src


static func _listing(id: int, qty: int, price: int, avg := 0) -> Dictionary:
	return {"id": id, "item": ITEM, "effects": [], "qty": qty, "price": price, "avg": avg, "seller": "X", "expires": 5000000, "expired": false, "left": 5000000}


# -- the model ---------------------------------------------------------------------------------

func test_prices_and_the_average() -> void:
	eq(MarketModel.unit_price(_listing(1, 10, 995)), 100, "rounded up")
	eq(MarketModel.unit_price(_listing(1, 1, 7)), 7)
	eq(MarketModel.versus_average(_listing(1, 10, 1200, 100)), "+20 %")
	eq(MarketModel.versus_average(_listing(1, 10, 850, 100)), "-15 %")
	eq(MarketModel.versus_average(_listing(1, 10, 850, 0)), "", "no sale yet: no comparison")
	eq(MarketModel.tax_for(500, 3), 30, "2 % per lot")
	eq(MarketModel.tax_for(10, 2), 2, "at least 1 per lot")


func test_lot_sizes_counts_and_problems() -> void:
	var m := MarketModel.new()
	eq(m.lot_sizes(0), [])
	eq(m.lot_sizes(12), [1, 10])
	eq(m.lot_sizes(1000), [1, 10, 100, 1000])
	eq(m.max_count(25, 10), 2)
	eq(m.max_count(5, 10), 0)
	m.apply_opened(ProtocolMarket.opened([_listing(1, 1, 1), _listing(2, 1, 1)]))
	eq(m.max_count(1000, 1), 48, "free places: 50 - 2")
	eq(m.sell_problem(12, 10, 1, 500, 100), "")
	check(m.sell_problem(12, 100, 1, 500, 100) != "", "not enough objects")
	check(m.sell_problem(12, 10, 1, 0, 100) != "", "price")
	check(m.sell_problem(12, 10, 1, 5000, 99) != "", "the tax (100) is above the purse")
	eq(m.sell(7, 10, 500, 1), ProtocolMarket.sell(7, 10, 500, 1))


func test_search_and_pages() -> void:
	var m := MarketModel.new()
	m.apply_opened(ProtocolMarket.opened([]))
	check(m.turn(1) == null, "a single page")
	eq(m.search(2, " blé ", 0), ProtocolMarket.search(2, "blé", 0, 0))
	m.apply_results(ProtocolMarket.results([_listing(1, 1, 5)], 0, 3, 41))
	eq(m.turn(1), ProtocolMarket.search(2, "blé", 0, 1), "same filters, next page")
	check(m.turn(-1) == null, "no page before the first")
	m.apply_results(ProtocolMarket.results([], 2, 3, 41))
	check(m.turn(1) == null, "no page after the last")
	m.apply_end()
	check(not m.is_open and m.listings.is_empty())


func test_status_of_a_lot() -> void:
	var l := _listing(1, 1, 1)
	l["left"] = 10 * 60000
	eq(MarketModel.status(l), "10 min")
	l["left"] = 3 * 3600000
	eq(MarketModel.status(l), "3 h")
	l["left"] = (2 * 1440 + 5 * 60) * 60000
	eq(MarketModel.status(l), "2 j 5 h")
	l["left"] = 0
	eq(MarketModel.status(l), "Expiré")
	l["left"] = 60000
	l["expired"] = true
	eq(MarketModel.status(l), "Expiré")
	check("Vendu" in MarketModel.sold_text({"item": ITEM, "qty": 10, "price": 5000}))
	check("Acheté" in MarketModel.bought_text({"item": ITEM, "qty": 10, "price": 5000}))


# -- the access ----------------------------------------------------------------------------------

func _backend(server: LocalServer, world: String, name: String) -> LocalBackend:
	var b := LocalBackend.new()
	b.server = server
	b.account = name.to_lower()
	b.send(Protocol.hello(world, name, "{1}"))
	b.poll(0.0)
	return b


static func _manager_id(b: LocalBackend) -> int:
	for a: SimActor in b.sim.get_map(1).actors.values():
		if a is NpcActor:
			return a.id
	return -1


func test_the_marketplace_is_open_only_beside_a_manager() -> void:
	var server := LocalServer.new()
	server.sources["hdv"] = _source("hdv")
	var b := _backend(server, "hdv", "Eli")
	var events: Array = []
	b.event.connect(func(ev: Dictionary) -> void: events.append(ev))
	var p: PlayerActor = b.sim.players[b.player_id]
	# beside the manager: the direct command works too
	b.send(ProtocolMarket.open())
	b.poll(0.0)
	check(events.any(func(e: Dictionary) -> bool: return e["t"] == ProtocolMarket.OPENED), "beside the manager")
	b.send(ProtocolMarket.close())
	b.poll(0.0)
	check(not p.market_open)
	# far from it: refused
	p.cell = 20
	p.path = []
	events.clear()
	b.send(ProtocolMarket.open())
	b.poll(0.0)
	check(not p.market_open, "far from every manager")
	check(events.any(func(e: Dictionary) -> bool: return e["t"] == Protocol.ERROR and e["code"] == Protocol.E_NOT_AT_NPC))


func test_the_manager_dialog_has_the_market_button() -> void:
	var tree := Dialog.with_market({"start": "0", "nodes": {"0": {"text_id": 1, "replies": [{"id": 4, "text": "x"}]}}})
	var reply: Dictionary = tree["nodes"]["0"]["replies"][1]
	eq([int(reply["id"]), reply["action"]], [5, {"type": "market"}])
	eq(Dialog.with_market({}), {}, "a silent manager opens it directly")


func test_dialog_reply_opens_it_and_a_silent_manager_too() -> void:
	var server := LocalServer.new()
	server.sources["hdv"] = _source("hdv")
	var b := _backend(server, "hdv", "Eli")
	var events: Array = []
	b.event.connect(func(ev: Dictionary) -> void: events.append(ev))
	var npc := _manager_id(b)
	b.send(Protocol.npc_talk(npc))
	b.poll(0.0)
	var dlg: Dictionary = events.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.DIALOG)[-1]
	var reply_id := -1
	for r: Dictionary in dlg["replies"]:
		if str(r.get("text", "")) == MarketRules.OPEN_TEXT:
			reply_id = int(r["id"])
	check(reply_id > 0, "the dialog offers the marketplace")
	events.clear()
	b.send(Protocol.dialog_reply(reply_id))
	b.poll(0.0)
	check(events.any(func(e: Dictionary) -> bool: return e["t"] == ProtocolMarket.OPENED), "opened by the reply")
	check(events.any(func(e: Dictionary) -> bool: return e["t"] == Protocol.DIALOG_END))


func test_a_silent_manager_opens_it_directly() -> void:
	var server := LocalServer.new()
	var src := _source("hdv")
	src.set_npcs({1: [{"npc": MANAGER, "cell": MANAGER_CELL, "dir": 3, "look": "{11}", "name_id": 749305}]}, {})
	server.sources["hdv"] = src
	var b := _backend(server, "hdv", "Eli")
	var events: Array = []
	b.event.connect(func(ev: Dictionary) -> void: events.append(ev))
	b.send(Protocol.npc_talk(_manager_id(b)))
	b.poll(0.0)
	check(events.any(func(e: Dictionary) -> bool: return e["t"] == ProtocolMarket.OPENED), "no dialog: straight to the marketplace")


# -- the window ----------------------------------------------------------------------------------

func _tree() -> SceneTree:
	return Engine.get_meta("test_tree") as SceneTree


func _session(server: LocalServer, name: String) -> ClientSession:
	var s := ClientSession.new()
	s.world_id = "hdv"
	s.player_name = name
	s.persistent = false
	var b := LocalBackend.new()
	b.account = name.to_lower()
	b.server = server
	s.backend = b
	_tree().root.add_child(s)
	return s


func _drop(s: ClientSession) -> void:
	s.backend = null
	_tree().root.remove_child(s)
	s.free()


func _run(server: LocalServer, sessions: Array, seconds: float, until := Callable()) -> bool:
	for i in int(seconds / 0.05):
		server.tick(50)
		for s: ClientSession in sessions:
			s.backend.poll(0.05)
		if until.is_valid() and until.call():
			return true
	return not until.is_valid()


static func _button(root: Node, text: String) -> Button:
	for n: Node in root.find_children("*", "Button", true, false):
		if (n as Button).text == text and not (n as Button).disabled:
			return n
	return null


func test_flow_through_the_window() -> void:
	var server := LocalServer.new()
	server.sources["hdv"] = _source("hdv")
	var alice := _session(server, "Alice")
	var bob := _session(server, "Bob")
	var all := [alice, bob]
	_run(server, all, 1.0)
	check(alice.map != null and bob.map != null, "both are on the map")
	var sim: WorldSim = (alice.backend as LocalBackend).sim
	var pa: PlayerActor = sim.players[(alice.backend as LocalBackend).player_id]
	var pb: PlayerActor = sim.players[(bob.backend as LocalBackend).player_id]
	sim.give_item(pa, ITEM, 25)
	pa.character.kamas = 500
	pb.character.kamas = 20000
	sim.character_changed(pa, "", "")
	sim.character_changed(pb, "", "")
	_run(server, all, 0.5)
	var wa := alice.player_hud.market
	var wb := bob.player_hud.market
	check(not wa.visible, "closed at first")

	# Alice talks to the manager and picks the marketplace
	var npc := -1
	for a: SimActor in sim.get_map(1).actors.values():
		if a is NpcActor:
			npc = a.id
	alice.backend.send(Protocol.npc_talk(npc))
	check(_run(server, all, 2.0, func() -> bool: return alice.player_hud.dialog.visible), "the dialog opens")
	var reply := _button(alice.player_hud.dialog, MarketRules.OPEN_TEXT)
	check(reply != null, "the dialog shows the marketplace reply")
	reply.pressed.emit()
	check(_run(server, all, 2.0, func() -> bool: return wa.visible), "the window opens")
	check(wa.model.is_open and not alice.player_hud.dialog.visible, "the dialog is gone")

	# the Vendre tab: lot of 10 at 400 (the default size is 1, pick the second)
	_run(server, all, 0.3)
	wa._fill_sell()
	var rows := wa._sell_rows.find_children("*", "OptionButton", true, false)
	check(not rows.is_empty(), "the bag item has a lot size box")
	var lot_box: OptionButton = rows[0]
	eq(lot_box.item_count, 2, "25 objects: lots of 1 and 10")
	lot_box.select(1)
	lot_box.item_selected.emit(1)
	var price: QtyStepper = wa._sell_rows.find_children("*", "QtyStepper", true, false)[0]
	price.value = 400
	var go := _button(wa._sell_rows, "Vendre")
	check(go != null, "the sale is possible")
	go.pressed.emit()
	check(_run(server, all, 2.0, func() -> bool: return wa.model.mine.size() == 1), "my lot appears")
	eq(pa.character.kamas, 500 - 8, "the tax: 2 % of 400")
	eq(int(wa.model.mine[0]["qty"]), 10)

	# Bob opens it, searches, buys
	bob.backend.send(Protocol.npc_talk(npc))
	_run(server, all, 0.5)
	_button(bob.player_hud.dialog, MarketRules.OPEN_TEXT).pressed.emit()
	check(_run(server, all, 2.0, func() -> bool: return wb.visible and wb.model.total == 1), "Bob's window lists the lot")
	var buy := _button(wb._results, "Acheter")
	check(buy != null, "a buy button")
	buy.pressed.emit()
	check(_run(server, all, 2.0, func() -> bool: return pb.character.inventory.count(ITEM) == 10), "Bob got the lot")
	eq(pb.character.kamas, 20000 - 400)
	eq(pa.character.kamas, 500 - 8 + 400, "paid at once")
	check(_run(server, all, 2.0, func() -> bool: return wb.model.total == 0), "the page is refreshed")
	check(_run(server, all, 2.0, func() -> bool: return wa.model.mine.is_empty()), "Alice's list is empty again")

	# closing the window closes the marketplace in the sim; walking away does too
	wa.close_window()
	check(_run(server, all, 2.0, func() -> bool: return not pa.market_open), "closing the window closes it")
	pb.cell = 20
	bob.backend.send(Protocol.move(25, false))
	check(_run(server, all, 2.0, func() -> bool: return not wb.visible), "moving closes it")
	_drop(alice)
	_drop(bob)


# -- over the network ----------------------------------------------------------------------------

func test_the_marketplace_access_and_models_over_websocket() -> void:
	var rig := NetTests.Rig.new()
	rig.host.server.sources["tiny"] = _source("tiny")
	var a := rig.client("tiny", "Alice")
	rig.run(2.0, func() -> bool: return a.has(Protocol.MAP_ENTER))
	var b := rig.client("tiny", "Bob")
	rig.run(2.0, func() -> bool: return b.has(Protocol.MAP_ENTER))
	var sim := rig.sim()
	var pa: PlayerActor = sim.players[a.you]
	var pb: PlayerActor = sim.players[b.you]
	sim.give_item(pa, ITEM, 12)
	pa.character.kamas = 200
	pb.character.kamas = 5000
	var ma := MarketModel.new()
	var mb := MarketModel.new()
	var pump := func() -> void:
		for pair: Array in [[a, ma], [b, mb]]:
			for ev: Dictionary in pair[0].events:
				match str(ev["t"]):
					ProtocolMarket.OPENED:
						pair[1].apply_opened(ev)
					ProtocolMarket.RESULTS:
						pair[1].apply_results(ev)
					ProtocolMarket.MINE:
						pair[1].apply_mine(ev)
					ProtocolMarket.END:
						pair[1].apply_end()
			pair[0].events = pair[0].events.filter(func(e: Dictionary) -> bool: return not str(e["t"]).begins_with("hdv_"))
	var npc := -1
	for act: SimActor in sim.get_map(1).actors.values():
		if act is NpcActor:
			npc = act.id
	# far from the manager: refused
	pb.cell = 20
	b.backend.send(ProtocolMarket.open())
	rig.run(1.0, func() -> bool: return b.has(Protocol.ERROR))
	check(not pb.market_open, "not beside the manager")
	pb.cell = MapGeometry.neighbors(MANAGER_CELL)[0]
	# the dialog route
	for c in [a, b]:
		c.backend.send(Protocol.npc_talk(npc))
	rig.run(2.0, func() -> bool: return a.has(Protocol.DIALOG) and b.has(Protocol.DIALOG))
	for c in [a, b]:
		var dlg: Dictionary = c.events.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.DIALOG)[-1]
		for r: Dictionary in dlg["replies"]:
			if str(r.get("text", "")) == MarketRules.OPEN_TEXT:
				c.backend.send(Protocol.dialog_reply(int(r["id"])))
	rig.run(2.0, func() -> bool: return a.has(ProtocolMarket.OPENED) and b.has(ProtocolMarket.OPENED))
	pump.call()
	check(ma.is_open and mb.is_open, "both models open")
	var uid := int((pa.character.inventory.to_array().filter(func(it: Dictionary) -> bool: return int(it["id"]) == ITEM)[0] as Dictionary)["uid"])
	a.backend.send(ma.sell(uid, 10, 300, 1))
	rig.run(2.0, func() -> bool: return a.has(ProtocolMarket.MINE))
	pump.call()
	eq(ma.mine.size(), 1)
	eq(pa.character.kamas, 200 - 6, "the tax")
	b.backend.send(mb.search(MarketRules.ALL_CATEGORIES, ""))
	rig.run(2.0, func() -> bool: return b.has(ProtocolMarket.RESULTS))
	pump.call()
	eq(mb.total, 1)
	b.backend.send(ProtocolMarket.buy(int(mb.listings[0]["id"])))
	rig.run(2.0, func() -> bool: return b.has(ProtocolMarket.BOUGHT) and a.has(ProtocolMarket.SOLD))
	eq(pb.character.inventory.count(ITEM), 10)
	eq(pa.character.kamas, 200 - 6 + 300)
	eq(a.backend.schema_errors.size() + b.backend.schema_errors.size(), 0, "every event matches the schema")
	rig.host.shutdown()
