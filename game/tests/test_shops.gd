## P2.02: NPC shops (NpcShop): buy, sell, not enough kamas, overload, distance, closing.
extends TestCase

const LOOK := "{1|120,2195||56}"
const NPC_CELL := 300
const SWORD := 44        # price 700, 1 pod
const HAT := 10801       # price 100, 1 pod
const BREAD := 468       # price 0: not bought back, 2 pods
const TREE := {"start": "a", "nodes": {"a": {"text": "Bonjour", "replies": [
	{"id": 1, "text": "Ma boutique", "action": {"type": "shop"}}]}}}


class Conn:
	var backend := LocalBackend.new()
	var events: Array = []
	var npc := -1
	var merchant := -1
	var real := -1

	func _init(server: LocalServer) -> void:
		backend.server = server
		backend.event.connect(func(ev: Dictionary) -> void:
			events.append(ev)
			if ev["t"] == Protocol.MAP_ENTER:
				for a: Dictionary in ev["actors"]:
					if a["kind"] == "npc" and int(a["npc"]) == 9001:
						npc = int(a["id"])
					if a["kind"] == "npc" and int(a["npc"]) == 2892:
						real = int(a["id"])
					if a["kind"] == "npc" and int(a["npc"]) == 9002:
						merchant = int(a["id"]))
		backend.send(Protocol.hello("shops", "Eli", LOOK))
		backend.poll(0.0)

	func send(cmd: Dictionary) -> Array:
		events = []
		backend.send(cmd)
		backend.poll(0.0)
		return events

	func last(type: String) -> Dictionary:
		for i in range(events.size() - 1, -1, -1):
			if events[i]["t"] == type:
				return events[i]
		return {}

	func errors() -> Array:
		return events.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.ERROR).map(func(e: Dictionary) -> String: return e["code"])

	func character() -> Character:
		return backend.sim.players[backend.player_id].character

	func kamas() -> int:
		return character().kamas


static func _conn(kamas := 1000) -> Conn:
	var s := LocalServer.new()
	var src := WorldSource.from_dicts({"id": "shops", "name": "Shops", "start_map": 1, "start_cell": 301},
		[{"id": 1, "coords": [0, 0], "neighbors": {}}])
	src.set_npcs({1: [{"npc": 9001, "cell": NPC_CELL, "dir": 3, "look": "{714}", "name_id": 8306},
			{"npc": 9002, "cell": 330, "dir": 1, "look": "{714}", "name_id": 8306},
			{"npc": 2892, "cell": 360, "dir": 1}]}, {9001: TREE})
	src.set_shops({9001: {"items": [SWORD, HAT]}, 9002: {"items": [HAT]}, 2892: {"items": [HAT]}})
	s.sources["shops"] = src
	var c := Conn.new(s)
	c.character().kamas = kamas
	c.send(Protocol.move(MapGeometry.neighbors(NPC_CELL)[0], false))
	return c


static func _open(c: Conn) -> Dictionary:
	c.send(Protocol.npc_talk(c.npc))
	c.send(Protocol.dialog_reply(1))
	return c.last(Protocol.SHOP_OPEN)


func test_prices_come_from_the_item_table() -> void:
	eq(NpcShop.buy_price(SWORD), 700)
	eq(NpcShop.sell_price(SWORD), 70, "price / 10")
	eq(NpcShop.sell_price(BREAD), 0)
	check(not NpcShop.sellable(BREAD), "price 0: not bought back")
	eq(NpcShop.offers({"items": [SWORD, 999999999]}), [{"item": SWORD, "price": 700}], "unknown items are left out")


func test_the_shop_action_of_a_dialog_opens_the_shop() -> void:
	var c := _conn()
	var open := _open(c)
	eq((open["items"] as Array).map(func(o: Dictionary) -> Array: return [int(o["item"]), int(o["price"])]), [[SWORD, 700], [HAT, 100]])
	eq(int(open["sell_divisor"]), NpcShop.SELL_DIVISOR)
	eq(int(open["npc"]), c.npc)


func test_a_merchant_without_dialog_opens_directly() -> void:
	var c := _conn()
	c.send(Protocol.move(MapGeometry.neighbors(330)[0], false))
	c.send(Protocol.npc_talk(c.merchant))
	check(not c.last(Protocol.SHOP_OPEN).is_empty())
	eq(c.last(Protocol.SHOP_OPEN)["items"].size(), 1)


func test_a_real_npc_with_a_shop_gets_the_menu_button() -> void:
	var c := _conn()
	c.send(Protocol.move(MapGeometry.neighbors(360)[0], false))
	c.send(Protocol.npc_talk(c.real))
	var d := c.last(Protocol.DIALOG)
	eq(d["replies"].size(), 1, "its message, and the Acheter/Vendre button")
	eq(int(d["replies"][0]["text_id"]), Dialog.SHOP_TEXT_ID)
	c.send(Protocol.dialog_reply(int(d["replies"][0]["id"])))
	eq(int(c.last(Protocol.SHOP_OPEN)["items"][0]["item"]), HAT)
	eq(Dialog.with_shop({}), {}, "a silent merchant keeps opening its shop directly")


func test_item_ids_read_from_json_floats_are_accepted() -> void:
	eq(NpcShop.check_buy({"items": [44.0]}, 44, 1, 1000, 0, 1000), "")


func test_buy_takes_kamas_and_gives_the_items() -> void:
	var c := _conn()
	_open(c)
	var evs := c.send(Protocol.shop_buy(HAT, 3))
	eq(c.kamas(), 700)
	eq(c.character().inventory.count(HAT), 3)
	eq(int(c.last(Protocol.ITEM_ADDED)["item"]["qty"]), 3)
	eq(int(c.last(Protocol.PLAYER_STATS)["stats"]["kamas"]), 700)
	check(c.errors().is_empty(), str(evs))


func test_buy_refused_without_enough_kamas() -> void:
	var c := _conn(650)
	_open(c)
	c.send(Protocol.shop_buy(SWORD, 1))
	eq(c.errors(), [Protocol.E_NOT_ENOUGH_KAMAS])
	eq(c.kamas(), 650)
	eq(c.character().inventory.count(SWORD), 0)
	c.send(Protocol.shop_buy(HAT, 7))
	eq(c.errors(), [Protocol.E_NOT_ENOUGH_KAMAS], "the total counts: 7 x 100 > 650")


func test_buy_refused_when_it_would_overload() -> void:
	var c := _conn(1000000)
	_open(c)
	var p: PlayerActor = c.backend.sim.players[c.backend.player_id]
	c.backend.sim.give_item(p, BREAD, (c.character().max_weight() - c.character().weight() - 1) / 2) # 1 or 2 pods left
	var room := c.character().max_weight() - c.character().weight()
	check(room >= 1 and room <= 2)
	c.send(Protocol.shop_buy(HAT, room + 1))
	eq(c.errors(), [Protocol.E_OVERLOADED])
	eq(c.kamas(), 1000000)
	c.send(Protocol.shop_buy(HAT, room))
	check(c.errors().is_empty(), "exactly the free pods is fine")
	eq(c.character().weight(), c.character().max_weight())


func test_buy_refuses_an_item_the_shop_does_not_sell_or_a_bad_quantity() -> void:
	var c := _conn()
	_open(c)
	c.send(Protocol.shop_buy(BREAD, 1))
	eq(c.errors(), [Protocol.E_NO_SHOP])
	c.send(Protocol.shop_buy(HAT, 0))
	eq(c.errors(), [Protocol.E_BAD_MESSAGE])
	c.send(Protocol.shop_buy(HAT, -2))
	eq(c.errors(), [Protocol.E_BAD_MESSAGE])


func test_sell_pays_a_tenth_and_removes_the_items() -> void:
	var c := _conn(0)
	c.backend.sim.give_item(c.backend.sim.players[c.backend.player_id], SWORD, 3)
	var uid := int(c.character().inventory.to_array()[0]["uid"])
	_open(c)
	c.send(Protocol.shop_sell(uid, 2))
	eq(c.kamas(), 140)
	eq(c.character().inventory.count(SWORD), 1)
	eq(int(c.last(Protocol.ITEM_ADDED)["item"]["qty"]), 1)
	c.send(Protocol.shop_sell(uid, 1))
	eq(c.kamas(), 210)
	eq(int(c.last(Protocol.ITEM_REMOVED)["uid"]), uid)


func test_sell_refusals() -> void:
	var c := _conn(0)
	var p: PlayerActor = c.backend.sim.players[c.backend.player_id]
	c.backend.sim.give_item(p, BREAD, 1)
	c.backend.sim.give_item(p, SWORD, 1)
	var bread := 0
	var sword := 0
	for it: Dictionary in c.character().inventory.to_array():
		if int(it["id"]) == BREAD:
			bread = int(it["uid"])
		else:
			sword = int(it["uid"])
	_open(c)
	c.send(Protocol.shop_sell(bread, 1))
	eq(c.errors(), [Protocol.E_NOT_SELLABLE])
	c.send(Protocol.shop_sell(sword, 2))
	eq(c.errors(), [Protocol.E_UNKNOWN_ITEM], "more than the stack")
	c.send(Protocol.shop_sell(424242, 1))
	eq(c.errors(), [Protocol.E_UNKNOWN_ITEM])
	c.character().inventory.items[sword]["pos"] = 1
	c.send(Protocol.shop_sell(sword, 1))
	eq(c.errors(), [Protocol.E_ITEM_WORN], "worn items are not sold")
	eq(c.kamas(), 0)


func test_no_shop_open_no_trade() -> void:
	var c := _conn()
	c.send(Protocol.shop_buy(HAT, 1))
	eq(c.errors(), [Protocol.E_NO_SHOP])
	_open(c)
	c.send(Protocol.shop_close())
	check(not c.last(Protocol.SHOP_END).is_empty())
	c.send(Protocol.shop_buy(HAT, 1))
	eq(c.errors(), [Protocol.E_NO_SHOP], "closed")


func test_walking_away_closes_the_shop() -> void:
	var c := _conn()
	_open(c)
	var evs := c.send(Protocol.move(NPC_CELL + 40, false))
	check(not evs.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.SHOP_END).is_empty())
	c.send(Protocol.shop_buy(HAT, 1))
	eq(c.errors(), [Protocol.E_NO_SHOP])
	eq(c.kamas(), 1000)


func test_a_ghost_cannot_trade() -> void:
	var c := _conn()
	_open(c)
	c.character().energy = 0
	c.character().life = Energy.GHOST
	c.send(Protocol.shop_buy(HAT, 1))
	eq(c.errors(), [Protocol.E_GHOST])


func test_the_real_worlds_ship_their_merchants() -> void:
	var dofus := JsonWorldSource.new("worlds/dofus")
	var shop := dofus.get_shop(5510)
	check(not (shop.get("items", []) as Array).is_empty(), "NPC 5510 sells items (JondoEmu npc_shops)")
	var known := 0
	for i: Variant in shop["items"]:
		known += 1 if GameData.item(int(i)).has("price") else 0
	eq(known, (shop["items"] as Array).size(), "every offer has its item data and price")
	check(not JsonWorldSource.new("worlds/incarnam").get_shop(2892).is_empty(), "Incarnam: the hand-made APPROX shop")
