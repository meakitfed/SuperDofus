## P2.10: the marketplace. The rules of MarketRules, then the flow of WorldMarket / Marketplace
## (tax, lots of 1 / 10 / 100, buying between two characters, expiry, the kamas of a sale made
## while the seller is offline, persistence) through two LocalBackends, and the same flow over
## WebSockets (two NetBackends on 127.0.0.1).
extends TestCase

const Players := preload("res://tests/test_players.gd")
const NetTests := preload("res://tests/test_net.gd")

const ITEM := 683         # items.price 1000, 1 pod
const OTHER_ITEM := 44    # items.price 700, 1 pod


func _init() -> void:
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()


## Alice has 120 of ITEM and 1000 kamas, Bob 5000 kamas.
func _pair(server: LocalServer = null) -> Array:
	server = server if server != null else Players._server()
	var a := Players.Conn.new(server, "Alice", Players.LOOK, "alice")
	var b := Players.Conn.new(server, "Bob", Players.LOOK, "bob")
	Players._run([a, b], 0.2)
	a.sim().give_item(a.player(), ITEM, 120)
	a.player().character.kamas = 1000
	b.player().character.kamas = 5000
	Players._run([a, b], 0.1)
	for c: Players.Conn in [a, b]:
		c.events.clear()
	return [a, b]


static func _uid(c: Players.Conn, id: int) -> int:
	for it: Dictionary in c.player().character.inventory.items.values():
		if int(it["id"]) == id:
			return int(it["uid"])
	return 0


static func _codes(c: Players.Conn) -> Array:
	return c.take(Protocol.ERROR).map(func(e: Dictionary) -> String: return str(e["code"]))


static func _mine(c: Players.Conn) -> Array:
	var m := c.take(ProtocolMarket.MINE)
	return m[-1]["mine"] if not m.is_empty() else []


func _step(t: Array, cmd_owner: Players.Conn, cmd: Dictionary) -> void:
	cmd_owner.send(cmd)
	Players._run(t, 0.1)


func _open_both(t: Array) -> void:
	for c: Players.Conn in t:
		c.send(ProtocolMarket.open())
	Players._run(t, 0.1)


# -- the rules ---------------------------------------------------------------------------------

func test_the_tax_is_two_percent_and_at_least_one_kama() -> void:
	eq(MarketRules.tax(1000), 20)
	eq(MarketRules.tax(10), 1, "the minimum")
	eq(MarketRules.tax(1), 1)


func test_lot_sizes_and_prices_are_checked() -> void:
	eq(MarketRules.sell_error(1, 1, 5), "")
	eq(MarketRules.sell_error(10, 3, 5), "")
	eq(MarketRules.sell_error(100, 1, MarketRules.MAX_PRICE), "")
	eq(MarketRules.sell_error(7, 1, 5), ProtocolMarket.E_BAD_LOT)
	eq(MarketRules.sell_error(10, 1, 0), ProtocolMarket.E_BAD_PRICE)
	eq(MarketRules.sell_error(10, 1, MarketRules.MAX_PRICE + 1), ProtocolMarket.E_BAD_PRICE)
	eq(MarketRules.sell_error(10, 0, 5), Protocol.E_BAD_MESSAGE)
	eq(MarketRules.sell_error(10, MarketRules.MAX_LISTINGS + 1, 5), Protocol.E_BAD_MESSAGE)


func test_the_category_comes_from_the_item_type() -> void:
	var type := GameData.row("itemtypes", int(GameData.item(ITEM).get("type", 0)))
	eq(MarketRules.category(ITEM), int(type["categoryId"]))
	check(MarketRules.sellable(ITEM))


# -- the flow ------------------------------------------------------------------------------------

func test_a_lot_sold_between_two_characters() -> void:
	var t := _pair()
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	_open_both(t)
	var opened: Dictionary = a.take(ProtocolMarket.OPENED)[0]
	eq([int(opened["tax"]), opened["quantities"].size()], [2, 4])
	_step(t, a, ProtocolMarket.sell(_uid(a, ITEM), 10, 500))
	eq(_codes(a), [])
	eq(a.player().character.inventory.count(ITEM), 110, "the lot left the bag")
	eq(a.player().character.kamas, 1000 - 10, "the tax: 2 % of 500")
	var mine := _mine(a)
	eq([mine.size(), int(mine[0]["qty"]), int(mine[0]["price"])], [1, 10, 500])
	# Bob searches, buys
	_step(t, b, ProtocolMarket.search(MarketRules.ALL_CATEGORIES, "", ITEM))
	var found: Dictionary = b.take(ProtocolMarket.RESULTS)[0]
	eq(int(found["total"]), 1)
	var listing := int(found["listings"][0]["id"])
	_step(t, b, ProtocolMarket.buy(listing))
	eq(_codes(b), [])
	eq(b.player().character.inventory.count(ITEM), 10)
	eq(b.player().character.kamas, 5000 - 500)
	eq(a.player().character.kamas, 990 + 500, "the seller is paid at once, no tax on the sale")
	var sold: Dictionary = a.take(ProtocolMarket.SOLD)[0]
	eq([int(sold["item"]), int(sold["qty"]), int(sold["price"])], [ITEM, 10, 500])
	eq(int(b.take(ProtocolMarket.BOUGHT)[0]["listing"]), listing)
	_step(t, b, ProtocolMarket.buy(listing))
	eq(_codes(b), [ProtocolMarket.E_NO_LISTING], "sold only once")
	_step(t, b, ProtocolMarket.search(MarketRules.ALL_CATEGORIES, "", ITEM))
	eq(int(b.take(ProtocolMarket.RESULTS)[0]["total"]), 0)
	var mk := Marketplace.load_from(a.server.persistence)
	eq(mk.average(ITEM), 50, "the average unit price of the sale")


func test_lots_of_1_10_and_100_and_several_at_once() -> void:
	var t := _pair()
	var a: Players.Conn = t[0]
	_open_both(t)
	_step(t, a, ProtocolMarket.sell(_uid(a, ITEM), 1, 100))
	_step(t, a, ProtocolMarket.sell(_uid(a, ITEM), 100, 9000))
	_step(t, a, ProtocolMarket.sell(_uid(a, ITEM), 7, 100))
	eq(_codes(a), [ProtocolMarket.E_BAD_LOT])
	_step(t, a, ProtocolMarket.sell(_uid(a, ITEM), 10, 100))
	eq(_codes(a), [])
	eq(_mine(a).size(), 3, "1 + 100 + 10")
	eq(a.player().character.inventory.count(ITEM), 120 - 111)
	_step(t, a, ProtocolMarket.sell(_uid(a, ITEM), 10, 100, 1))
	eq(_codes(a), [Protocol.E_UNKNOWN_ITEM], "only 9 left")


func test_not_enough_objects_or_kamas_and_other_refusals() -> void:
	var t := _pair()
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	_step(t, a, ProtocolMarket.sell(1, 1, 1))
	eq(_codes(a), [ProtocolMarket.E_NO_MARKET], "closed")
	_open_both(t)
	var uid := _uid(a, ITEM)
	_step(t, a, ProtocolMarket.sell(uid, 1000, 100))
	eq(_codes(a), [Protocol.E_UNKNOWN_ITEM], "not that many")
	_step(t, a, ProtocolMarket.sell(uid, 10, 0))
	eq(_codes(a), [ProtocolMarket.E_BAD_PRICE])
	a.player().character.kamas = 5
	_step(t, a, ProtocolMarket.sell(uid, 10, 1000))
	eq(_codes(a), [Protocol.E_NOT_ENOUGH_KAMAS], "the tax is 20")
	a.player().character.kamas = 1000
	_step(t, a, ProtocolMarket.sell(424242, 1, 10))
	eq(_codes(a), [Protocol.E_UNKNOWN_ITEM])
	a.player().character.inventory.items[uid]["pos"] = 6
	_step(t, a, ProtocolMarket.sell(uid, 1, 10))
	eq(_codes(a), [Protocol.E_ITEM_WORN])
	a.player().character.inventory.items[uid]["pos"] = Inventory.BAG
	_step(t, a, ProtocolMarket.sell(uid, 1, 1000))
	var id := int(_mine(a)[0]["id"])
	_step(t, a, ProtocolMarket.buy(id))
	eq(_codes(a), [ProtocolMarket.E_OWN_LISTING])
	b.player().character.kamas = 10
	_step(t, b, ProtocolMarket.buy(id))
	eq(_codes(b), [Protocol.E_NOT_ENOUGH_KAMAS])
	b.player().character.kamas = 5000
	_step(t, b, ProtocolMarket.cancel(id))
	eq(_codes(b), [ProtocolMarket.E_NO_LISTING], "not Bob's lot")
	b.player().character.inventory.add(OTHER_ITEM, b.player().character.max_weight(), [], a.sim().items.new_item_uid)
	_step(t, b, ProtocolMarket.buy(id))
	eq(_codes(b), [Protocol.E_OVERLOADED])
	eq(Marketplace.load_from(a.server.persistence).listings.size(), 1, "still on sale")


func test_the_number_of_lots_is_limited() -> void:
	var t := _pair()
	var a: Players.Conn = t[0]
	a.player().character.kamas = 100000
	_open_both(t)
	_step(t, a, ProtocolMarket.sell(_uid(a, ITEM), 1, 10, MarketRules.MAX_LISTINGS))
	eq(_codes(a), [])
	eq(_mine(a).size(), MarketRules.MAX_LISTINGS)
	_step(t, a, ProtocolMarket.sell(_uid(a, ITEM), 1, 10))
	eq(_codes(a), [ProtocolMarket.E_MARKET_FULL])
	# a lot taken back frees a place
	_step(t, a, ProtocolMarket.cancel(int(Marketplace.load_from(a.server.persistence).listings[0]["id"])))
	_step(t, a, ProtocolMarket.sell(_uid(a, ITEM), 1, 10))
	eq(_codes(a), [])


func test_a_lot_expires_and_its_seller_takes_it_back() -> void:
	var t := _pair()
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	_open_both(t)
	_step(t, a, ProtocolMarket.sell(_uid(a, ITEM), 10, 500))
	var id := int(_mine(a)[0]["id"])
	a.server.clock.advance(MarketRules.DURATION_MS + 1)
	_step(t, b, ProtocolMarket.search())
	eq(int(b.take(ProtocolMarket.RESULTS)[0]["total"]), 0, "expired lots are not shown")
	_step(t, b, ProtocolMarket.buy(id))
	eq(_codes(b), [ProtocolMarket.E_NO_LISTING], "nor sold")
	a.take(ProtocolMarket.OPENED)
	_step(t, a, ProtocolMarket.open())
	var mine: Array = a.take(ProtocolMarket.OPENED)[0]["mine"]
	check(bool(mine[0]["expired"]), "the seller sees it expired")
	_step(t, a, ProtocolMarket.cancel(id))
	eq(_codes(a), [])
	eq(a.player().character.inventory.count(ITEM), 120, "the objects are back")
	eq(a.player().character.kamas, 990, "the tax is not refunded")
	eq(_mine(a).size(), 0)


func test_an_active_lot_can_be_taken_back_too() -> void:
	var t := _pair()
	var a: Players.Conn = t[0]
	_open_both(t)
	_step(t, a, ProtocolMarket.sell(_uid(a, ITEM), 100, 9000))
	_step(t, a, ProtocolMarket.cancel(int(_mine(a)[0]["id"])))
	eq(a.player().character.inventory.count(ITEM), 120)
	eq(Marketplace.load_from(a.server.persistence).listings.size(), 0)


func test_the_kamas_of_a_sale_reach_a_seller_who_is_offline() -> void:
	var server := Players._server()
	var t := _pair(server)
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	_open_both(t)
	_step(t, a, ProtocolMarket.sell(_uid(a, ITEM), 10, 700))
	a.sim().disconnect_player(a.backend.player_id)
	Players._run([b], 0.1)
	var id := int(Marketplace.load_from(server.persistence).listings[0]["id"])
	_step([b], b, ProtocolMarket.buy(id))
	eq(_codes(b), [])
	eq(b.player().character.kamas, 5000 - 700)
	# Alice's saved character does not hold the kamas yet: they wait for her
	eq(int(server.persistence.load_character("duo", "Alice")["kamas"]), 986)
	eq(int(server.persistence.load_doc(Marketplace.COLLECTION, Marketplace.proceeds_key("duo", "Alice"))["kamas"]), 700)
	var a2 := Players.Conn.new(server, "Alice", Players.LOOK, "alice")
	Players._run([a2, b], 0.2)
	eq(a2.player().character.kamas, 986 + 700, "paid at login")
	var sold := a2.take(ProtocolMarket.SOLD)
	eq(sold.size(), 1)
	eq([int(sold[0]["qty"]), int(sold[0]["price"])], [10, 700])
	eq(server.persistence.load_doc(Marketplace.COLLECTION, Marketplace.proceeds_key("duo", "Alice")), {}, "the proceeds are consumed")
	eq(int(server.persistence.load_character("duo", "Alice")["kamas"]), 1686, "and saved with the character")
	a2.sim().disconnect_player(a2.backend.player_id)
	var a3 := Players.Conn.new(server, "Alice", Players.LOOK, "alice")
	Players._run([a3, b], 0.2)
	eq(a3.player().character.kamas, 1686, "paid only once")
	eq(a3.take(ProtocolMarket.SOLD).size(), 0)


func test_the_marketplace_survives_a_restart_of_the_server() -> void:
	var s := Players._server()
	var t := _pair(s)
	var a: Players.Conn = t[0]
	_open_both(t)
	_step(t, a, ProtocolMarket.sell(_uid(a, ITEM), 10, 500))
	var s2 := Players._server()
	s2.persistence = s.persistence
	var t2 := _pair(s2)
	var b: Players.Conn = t2[1]
	_open_both(t2)
	_step(t2, b, ProtocolMarket.search())
	eq(int(b.take(ProtocolMarket.RESULTS)[0]["total"]), 1)


func test_search_filters_and_sorting() -> void:
	var t := _pair()
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	a.sim().give_item(a.player(), OTHER_ITEM, 3)
	a.player().character.kamas = 10000
	_open_both(t)
	_step(t, a, ProtocolMarket.sell(_uid(a, ITEM), 10, 900))   # 90 each
	_step(t, a, ProtocolMarket.sell(_uid(a, ITEM), 10, 500))   # 50 each
	_step(t, a, ProtocolMarket.sell(_uid(a, OTHER_ITEM), 1, 300))
	_step(t, b, ProtocolMarket.search())
	var all: Array = b.take(ProtocolMarket.RESULTS)[0]["listings"]
	eq(all.map(func(l: Dictionary) -> int: return int(l["price"])), [500, 900, 300], "cheapest unit price first")
	_step(t, b, ProtocolMarket.search(MarketRules.ALL_CATEGORIES, "", OTHER_ITEM))
	eq(int(b.take(ProtocolMarket.RESULTS)[0]["total"]), 1)
	_step(t, b, ProtocolMarket.search(MarketRules.ALL_CATEGORIES, str(GameData.item(OTHER_ITEM)["name"]).substr(0, 4)))
	check(int(b.take(ProtocolMarket.RESULTS)[0]["total"]) >= 1, "by part of the name")
	_step(t, b, ProtocolMarket.search(MarketRules.category(ITEM), "", ITEM))
	eq(int(b.take(ProtocolMarket.RESULTS)[0]["total"]), 2, "by category")
	_step(t, b, ProtocolMarket.search(9999))
	eq(int(b.take(ProtocolMarket.RESULTS)[0]["total"]), 0)


func test_closing_and_other_commands_close_the_marketplace() -> void:
	var t := _pair()
	var a: Players.Conn = t[0]
	_open_both(t)
	_step(t, a, ProtocolMarket.close())
	eq(a.take(ProtocolMarket.END).size(), 1)
	_step(t, a, ProtocolMarket.search())
	eq(_codes(a), [ProtocolMarket.E_NO_MARKET])
	_step(t, a, ProtocolMarket.open())
	a.take(ProtocolMarket.OPENED)
	_step(t, a, Protocol.move(MapGeometry.neighbors(300)[0], false))
	eq(a.take(ProtocolMarket.END).size(), 1, "walking closes it")
	_step(t, a, ProtocolMarket.search())
	eq(_codes(a), [ProtocolMarket.E_NO_MARKET])


func test_a_trader_or_a_ghost_cannot_open_it() -> void:
	var t := _pair()
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	_step(t, a, ProtocolMarket.open())
	a.take(ProtocolMarket.OPENED)
	_step(t, b, ProtocolTrade.invite("Alice"))
	eq(_codes(b), [ProtocolTrade.E_TRADE_BUSY], "no trade with someone at the marketplace")


# -- the same over WebSockets -----------------------------------------------------------------------

func test_the_marketplace_over_websocket() -> void:
	var rig := NetTests.Rig.new()
	var a := rig.client("tiny", "Alice")
	rig.run(2.0, func() -> bool: return a.has(Protocol.MAP_ENTER))
	var b := rig.client("tiny", "Bob")
	rig.run(2.0, func() -> bool: return b.has(Protocol.MAP_ENTER))
	var sim := rig.sim()
	sim.give_item(sim.players[a.you], ITEM, 30)
	sim.players[a.you].character.kamas = 100
	sim.players[b.you].character.kamas = 2000
	rig.run(0.3)
	var ua := 0
	for it: Dictionary in sim.players[a.you].character.inventory.items.values():
		ua = int(it["uid"])
	a.backend.send(ProtocolMarket.open())
	check(rig.run(2.0, func() -> bool: return a.has(ProtocolMarket.OPENED)), "the marketplace opens through the server")
	a.backend.send(ProtocolMarket.sell(ua, 10, 600, 2))
	check(rig.run(2.0, func() -> bool: return a.has(ProtocolMarket.MINE)), "the lots are on sale")
	var mine: Array = a.take(ProtocolMarket.MINE)[-1]["mine"]
	eq(mine.size(), 2)
	eq(sim.players[a.you].character.kamas, 100 - 2 * 12, "the tax over the network")
	b.backend.send(ProtocolMarket.open())
	rig.run(0.3)
	b.backend.send(ProtocolMarket.search(MarketRules.ALL_CATEGORIES, "", ITEM))
	check(rig.run(2.0, func() -> bool: return b.has(ProtocolMarket.RESULTS)), "Bob searches")
	var found: Dictionary = b.take(ProtocolMarket.RESULTS)[0]
	eq(int(found["total"]), 2)
	var listing := int(found["listings"][0]["id"])
	b.backend.send(ProtocolMarket.buy(listing))
	check(rig.run(2.0, func() -> bool: return b.has(ProtocolMarket.BOUGHT) and a.has(ProtocolMarket.SOLD)), "bought, and the seller is told")
	eq(int(b.take(ProtocolMarket.BOUGHT)[0]["listing"]), listing, "ids survive the JSON round trip as ints")
	eq([sim.players[a.you].character.kamas, sim.players[b.you].character.kamas], [76 + 600, 2000 - 600])
	eq(sim.players[b.you].character.inventory.count(ITEM), 10)
	# the seller leaves, the second lot is bought offline
	var key_before := Marketplace.proceeds_key(sim.world_id(), "Alice")
	a.backend.close()
	rig.run(0.5, func() -> bool: return sim.chat.find_player("Alice") == null)
	b.backend.send(ProtocolMarket.buy(int(found["listings"][1]["id"])))
	check(rig.run(2.0, func() -> bool: return b.has(ProtocolMarket.BOUGHT)), "bought while the seller is away")
	eq(int(sim.persistence.load_doc(Marketplace.COLLECTION, key_before)["kamas"]), 600)
	var a2 := rig.client("tiny", "Alice")
	check(rig.run(2.0, func() -> bool: return a2.has(ProtocolMarket.SOLD)), "told at login")
	rig.run(0.3)
	eq(sim.players[a2.you].character.kamas, 76 + 600 + 600, "paid at login")
	eq(a.backend.schema_errors.size() + b.backend.schema_errors.size() + a2.backend.schema_errors.size(), 0, "every event matches the schema")
	rig.host.shutdown()
