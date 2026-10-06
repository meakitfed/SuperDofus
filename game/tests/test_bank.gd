## P2.08: the account chest (BankRules, Bank): access cost, deposit / withdraw of objects and
## kamas, shared by the characters of an account, atomic with the character save.
extends TestCase

const LOOK := "{1|120,2195||56}"
const NPC_CELL := 300
const SWORD := 44        # 1 pod
const HAT := 10801       # 1 pod
const TREE := {"start": "a", "nodes": {"a": {"text": "Bonjour", "replies": [
	{"id": 1, "text": "Mon coffre", "action": {"type": "bank"}}]}}}


class Conn:
	var backend := LocalBackend.new()
	var events: Array = []
	var banker := -1
	var silent := -1

	func _init(server: LocalServer, name: String, account := "acc1") -> void:
		backend.server = server
		backend.account = account
		backend.event.connect(func(ev: Dictionary) -> void:
			events.append(ev)
			if ev["t"] == Protocol.MAP_ENTER:
				for a: Dictionary in ev["actors"]:
					if a["kind"] == "npc" and int(a["npc"]) == 9001:
						banker = int(a["id"])
					if a["kind"] == "npc" and int(a["npc"]) == 9002:
						silent = int(a["id"]))
		backend.send(Protocol.hello("bank", name, LOOK))
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

	## Walks next to the banker, talks, picks the chest reply.
	func open() -> Dictionary:
		send(Protocol.move(MapGeometry.neighbors(NPC_CELL)[0], false))
		send(Protocol.npc_talk(banker))
		send(Protocol.dialog_reply(1))
		return last(Protocol.BANK_OPEN)

	func give(id: int, qty: int, effects := []) -> int:
		return int(character().inventory.add(id, qty, effects, func() -> int: return backend.server.persistence.next_uid("item"))["uid"])


static func _server() -> LocalServer:
	var s := LocalServer.new()
	var src := WorldSource.from_dicts({"id": "bank", "name": "Bank", "start_map": 1, "start_cell": 301},
		[{"id": 1, "coords": [0, 0], "neighbors": {}}])
	src.set_npcs({1: [{"npc": 9001, "cell": NPC_CELL, "dir": 3, "look": "{714}", "name_id": 8306},
			{"npc": 9002, "cell": 330, "dir": 1, "look": "{714}", "name_id": 8306}]}, {9001: TREE})
	src.set_bankers([9001, 9002])
	s.sources["bank"] = src
	return s


func test_the_cost_is_one_kama_per_stack() -> void:
	eq(BankRules.access_cost(0), 0)
	eq(BankRules.access_cost(7), 7)


func test_a_banker_dialog_gets_the_chest_button() -> void:
	var tree := {"start": "0", "nodes": {"0": {"text_id": 1, "replies": []}}}
	var with := Dialog.with_bank(tree)
	eq(int(with["nodes"]["0"]["replies"][0]["text_id"]), BankRules.OPEN_TEXT_ID)
	eq(with["nodes"]["0"]["replies"][0]["action"], {"type": "bank"})
	eq(Dialog.with_bank({}), {}, "a silent banker opens the chest directly")
	var row: Dictionary = GameData.row("npcs", 6394)
	eq(int(row["dialogReplies"][0]["values"][1]), BankRules.OPEN_TEXT_ID, "the real banker's own reply text")


func test_an_empty_chest_opens_free() -> void:
	var c := Conn.new(_server(), "Eli")
	var o := c.open()
	check(not o.is_empty(), "opened")
	eq(int(o["cost"]), 0)
	eq((o["items"] as Array).size(), 0)
	eq(int(o["kamas"]), 0)


func test_deposit_and_withdraw_an_object_keeps_its_effects() -> void:
	var c := Conn.new(_server(), "Eli")
	var uid := c.give(SWORD, 3, [[110, 5, 0]])
	c.open()
	c.send(Protocol.bank_move(uid, 2, BankRules.IN))
	check(c.errors().is_empty(), str(c.events))
	eq(c.character().inventory.count(SWORD), 1)
	var upd := c.last(Protocol.BANK_UPDATE)
	eq(int(upd["items"][0]["qty"]), 2)
	eq(int(upd["items"][0]["effects"][0][1]), 5, "rolled effects kept")
	var bank_uid := int(upd["items"][0]["uid"])
	c.send(Protocol.bank_move(bank_uid, 2, BankRules.OUT))
	check(c.errors().is_empty(), str(c.events))
	eq(c.character().inventory.count(SWORD), 3, "back in the bag, same stack")
	eq(int(c.last(Protocol.BANK_UPDATE)["items"][0]["qty"]), 0, "the chest stack is gone")
	eq(Bank.load_for(c.backend.server.persistence, "acc1").inventory.items.size(), 0)


func test_an_object_deposited_by_one_character_is_seen_by_another_of_the_account() -> void:
	var s := _server()
	var a := Conn.new(s, "Alice")
	var uid := a.give(HAT, 4)
	a.open()
	a.send(Protocol.bank_move(uid, 4, BankRules.IN))
	a.send(Protocol.bank_close())
	var b := Conn.new(s, "Bob")
	b.character().kamas = 5
	var o := b.open()
	eq(o["items"].size(), 1, "the other character sees it")
	eq(int(o["items"][0]["id"]), HAT)
	eq(int(o["items"][0]["qty"]), 4)
	eq(int(o["cost"]), 1, "1 stack stored: 1 kama")
	var other := Conn.new(s, "Mallory", "acc2")
	eq(other.open()["items"].size(), 0, "another account has its own chest")


func test_kamas_in_and_out() -> void:
	var c := Conn.new(_server(), "Eli")
	c.character().kamas = 1000
	c.open()
	c.send(Protocol.bank_kamas(400, BankRules.IN))
	eq(c.character().kamas, 600)
	eq(int(c.last(Protocol.BANK_UPDATE)["kamas"]), 400)
	eq(int(c.last(Protocol.PLAYER_STATS)["stats"]["kamas"]), 600)
	c.send(Protocol.bank_kamas(700, BankRules.IN))
	eq(c.errors(), [Protocol.E_NOT_ENOUGH_KAMAS], "cannot deposit more than carried")
	c.send(Protocol.bank_kamas(500, BankRules.OUT))
	eq(c.errors(), [Protocol.E_NOT_ENOUGH_KAMAS], "cannot withdraw more than stored")
	c.send(Protocol.bank_kamas(100, BankRules.OUT))
	eq(c.character().kamas, 700)
	eq(Bank.load_for(c.backend.server.persistence, "acc1").kamas, 300)


func test_access_is_paid_and_refused_without_kamas() -> void:
	var s := _server()
	var a := Conn.new(s, "Alice")
	var uids := [a.give(HAT, 1), a.give(SWORD, 1), a.give(683, 1)]
	a.open()
	for uid: int in uids:
		a.send(Protocol.bank_move(uid, 1, BankRules.IN))
	a.send(Protocol.bank_close())
	var b := Conn.new(s, "Bob")
	b.character().kamas = 2
	b.open()
	check(b.last(Protocol.BANK_OPEN).is_empty(), "3 stacks cost 3 kamas: refused with 2")
	check(b.errors().has(Protocol.E_NOT_ENOUGH_KAMAS), str(b.events))
	eq(b.character().kamas, 2)
	b.character().kamas = 10
	b.send(Protocol.npc_talk(b.banker))
	b.send(Protocol.dialog_reply(1))
	eq(int(b.last(Protocol.BANK_OPEN)["cost"]), 3)
	eq(b.character().kamas, 7)


func test_refusals() -> void:
	var c := Conn.new(_server(), "Eli")
	c.send(Protocol.bank_move(1, 1, BankRules.IN))
	eq(c.errors(), [Protocol.E_NO_BANK], "no chest open")
	var uid := c.give(HAT, 1)
	c.open()
	c.send(Protocol.bank_move(uid, 5, BankRules.IN))
	eq(c.errors(), [Protocol.E_UNKNOWN_ITEM], "not that many")
	c.send(Protocol.bank_move(uid, 1, "sideways"))
	eq(c.errors(), [Protocol.E_BAD_MESSAGE])
	c.send(Protocol.bank_move(424242, 1, BankRules.OUT))
	eq(c.errors(), [Protocol.E_UNKNOWN_ITEM], "no such stack in the chest")
	c.character().inventory.items[uid]["pos"] = 6 # worn items stay on the character
	c.send(Protocol.bank_move(uid, 1, BankRules.IN))
	eq(c.errors(), [Protocol.E_ITEM_WORN])


func test_withdrawing_more_than_the_pods_allow_is_refused() -> void:
	var c := Conn.new(_server(), "Eli")
	var uid := c.give(SWORD, 1)
	c.open()
	c.send(Protocol.bank_move(uid, 1, BankRules.IN))
	var bank_uid := int(c.last(Protocol.BANK_UPDATE)["items"][0]["uid"])
	var room := c.character().max_weight() - c.character().weight()
	c.give(HAT, room / int(GameData.item(HAT).get("weight", 1)))
	c.send(Protocol.bank_move(bank_uid, 1, BankRules.OUT))
	eq(c.errors(), [Protocol.E_OVERLOADED])
	eq(c.character().inventory.count(SWORD), 0, "still in the chest")


func test_walking_away_closes_the_chest() -> void:
	var c := Conn.new(_server(), "Eli")
	c.open()
	var evs := c.send(Protocol.move(MapGeometry.neighbors(NPC_CELL)[3], false))
	check(not c.last(Protocol.BANK_END).is_empty(), str(evs))
	c.send(Protocol.bank_kamas(1, BankRules.IN))
	eq(c.errors(), [Protocol.E_NO_BANK])


func test_a_silent_banker_opens_the_chest_directly() -> void:
	var c := Conn.new(_server(), "Eli")
	c.send(Protocol.move(MapGeometry.neighbors(330)[0], false))
	c.send(Protocol.npc_talk(c.silent))
	check(not c.last(Protocol.BANK_OPEN).is_empty())


func test_the_chest_survives_a_restart_of_the_server() -> void:
	var s := _server()
	var a := Conn.new(s, "Alice")
	a.character().kamas = 50
	a.open()
	a.send(Protocol.bank_kamas(50, BankRules.IN))
	var s2 := _server()
	s2.persistence = s.persistence
	var b := Conn.new(s2, "Alice")
	eq(int(b.open()["kamas"]), 50)


func test_the_incarnam_banker_is_in_the_world_data() -> void:
	var src := JsonWorldSource.for_world("incarnam")
	check(src.is_banker(6415), "Ruth Banke is a banker of Incarnam")
	var placed := 0
	for m: Variant in src.get_info().get("maps", []):
		for n: Dictionary in src.get_npcs(int(m)):
			placed += 1 if src.is_banker(int(n["npc"])) else 0
	check(placed >= 1, "a banker stands in Incarnam")
