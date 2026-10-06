## Trade between two players (roadmap P3.11): the pure rules of shared/TradeRules, the messages,
## the flow of WorldTrade (invitation, window, double validation, atomic exchange, cancellation
## by moving / fighting / disconnecting, full bag, audit) through two LocalBackends, and the same
## flow over WebSockets (two NetBackends on 127.0.0.1).
extends TestCase

const Players := preload("res://tests/test_players.gd")
const NetTests := preload("res://tests/test_net.gd")

const ITEM := 683
const OTHER_ITEM := 1182


func _init() -> void:
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()


## Alice and Bob in a duo world; Alice has 5 of ITEM and 300 kamas, Bob 2 of OTHER_ITEM and 50 kamas.
func _pair() -> Array:
	var server := Players._server()
	var a := Players.Conn.new(server, "Alice", Players.LOOK, "alice")
	var b := Players.Conn.new(server, "Bob", Players.LOOK, "bob")
	Players._run([a, b], 0.2)
	a.sim().give_item(a.player(), ITEM, 5)
	a.player().character.kamas = 300
	a.sim().give_item(b.player(), OTHER_ITEM, 2)
	b.player().character.kamas = 50
	Players._run([a, b], 0.1)
	for c: Players.Conn in [a, b]:
		c.events.clear()
	return [a, b]


func _open(t: Array) -> void:
	(t[0] as Players.Conn).send(ProtocolTrade.invite("Bob"))
	Players._run(t, 0.1)
	(t[1] as Players.Conn).send(ProtocolTrade.accept("Alice"))
	Players._run(t, 0.1)


static func _uid(c: Players.Conn, id: int) -> int:
	for it: Dictionary in c.player().character.inventory.items.values():
		if int(it["id"]) == id:
			return int(it["uid"])
	return 0


static func _codes(c: Players.Conn) -> Array:
	return c.take(Protocol.ERROR).map(func(e: Dictionary) -> String: return str(e["code"]))


static func _last(c: Players.Conn) -> Dictionary:
	var u := c.take(ProtocolTrade.UPDATE)
	return u[-1] if not u.is_empty() else {}


static func _ends(c: Players.Conn) -> Array:
	return c.take(ProtocolTrade.END).map(func(e: Dictionary) -> String: return str(e["reason"]))


# -- shared/TradeRules: pure ------------------------------------------------------------

func test_normalize_sums_lines_and_refuses_junk() -> void:
	eq(TradeRules.normalize([{"uid": 4, "qty": 2}, {"uid": 4.0, "qty": 3.0}, {"uid": 9, "qty": 1}]), {4: 5, 9: 1})
	eq(TradeRules.normalize([]), {})
	for bad: Array in [[{"uid": 1}], [{"uid": 1, "qty": 0}], [{"uid": 1, "qty": -2}], [{"uid": 1, "qty": 1.5}], [3],
			[{"uid": 1, "qty": TradeRules.MAX_QTY + 1}], [{"uid": "x", "qty": 1}]]:
		eq(TradeRules.normalize(bad).get("err", ""), Protocol.E_BAD_MESSAGE, str(bad))
	var many := []
	for i in TradeRules.MAX_LINES + 1:
		many.append({"uid": i + 1, "qty": 1})
	eq(TradeRules.normalize(many).get("err", ""), Protocol.E_BAD_MESSAGE, "too many lines")


func test_offer_error_checks_stacks_worn_items_and_kamas() -> void:
	var stacks := {1: {"uid": 1, "id": ITEM, "qty": 3, "pos": -1}, 2: {"uid": 2, "id": ITEM, "qty": 1, "pos": 2}}
	eq(TradeRules.offer_error(stacks, 10, {1: 3}, 10), "")
	eq(TradeRules.offer_error(stacks, 10, {1: 4}, 0), Protocol.E_UNKNOWN_ITEM, "more than the stack")
	eq(TradeRules.offer_error(stacks, 10, {7: 1}, 0), Protocol.E_UNKNOWN_ITEM, "no such stack")
	eq(TradeRules.offer_error(stacks, 10, {2: 1}, 0), Protocol.E_ITEM_WORN, "a worn item stays on")
	eq(TradeRules.offer_error(stacks, 10, {}, 11), Protocol.E_NOT_ENOUGH_KAMAS)
	eq(TradeRules.offer_error(stacks, 10, {}, -1), Protocol.E_BAD_MESSAGE)


func test_weight_rules() -> void:
	var w := int(GameData.item(ITEM).get("weight", 1))
	var stacks := {1: {"uid": 1, "id": ITEM, "qty": 4, "pos": -1}}
	eq(TradeRules.weight_of(stacks, {1: 3}), 3 * w)
	eq(TradeRules.weight_error(100, 100, 0, 0), "")
	eq(TradeRules.weight_error(100, 100, 0, 1), Protocol.E_OVERLOADED)
	eq(TradeRules.weight_error(100, 100, 30, 30), "", "what is given makes room")
	eq(TradeRules.weight_error(100, 100, 30, 31), Protocol.E_OVERLOADED)


func test_trade_session_validations_fall_on_any_change() -> void:
	var s := TradeSession.create("A", "B")
	eq(s.other("A"), "B")
	s.ready["A"] = true
	s.ready["B"] = true
	check(s.both_ready())
	s.set_offer("B", {3: 1}, 5)
	check(not s.ready["A"] and not s.ready["B"], "both validations fall")
	eq([s.items_of("B"), s.kamas_of("B"), s.kamas_of("A")], [{3: 1}, 5, 0])


# -- the messages ----------------------------------------------------------------------

func test_messages_match_the_schema() -> void:
	eq(ProtocolTrade.C2S, Protocol.C2S)
	eq(ProtocolTrade.S2C, Protocol.S2C)
	for m: Dictionary in [ProtocolTrade.invite("Bob"), ProtocolTrade.accept("A"), ProtocolTrade.decline("A"),
			ProtocolTrade.set_offer([{"uid": 3, "qty": 2}], 10), ProtocolTrade.ready(), ProtocolTrade.cancel()]:
		eq(Protocol.validate(Protocol.roundtrip(m), Protocol.C2S), "", str(m))
	for m: Dictionary in [ProtocolTrade.invited("A"), ProtocolTrade.open("A", 3), ProtocolTrade.update({}, {}),
			ProtocolTrade.end("done"), ProtocolTrade.end("failed", "overloaded")]:
		eq(Protocol.validate(Protocol.roundtrip(m), Protocol.S2C), "", str(m))
	check(Protocol.validate({"t": ProtocolTrade.SET, "items": []}, Protocol.C2S).contains("kamas"), "kamas are required")
	check(Protocol.validate(ProtocolTrade.invited("A"), Protocol.C2S) != "", "an event is no command")
	for code: String in ProtocolTrade.ERROR_CODES:
		check(Protocol.ERROR_CODES.has(code) and ErrorTexts.TEXTS.has(code), "%s is listed and has its text" % code)


# -- the flow ---------------------------------------------------------------------------

func test_a_full_trade_swaps_items_and_kamas() -> void:
	var t := _pair()
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	a.send(ProtocolTrade.invite("bob"))
	Players._run(t, 0.1)
	eq(b.take(ProtocolTrade.INVITED)[0]["from"], "Alice", "Bob is invited (any case)")
	b.send(ProtocolTrade.accept("Alice"))
	Players._run(t, 0.1)
	var oa: Dictionary = a.take(ProtocolTrade.OPEN)[0]
	var ob: Dictionary = b.take(ProtocolTrade.OPEN)[0]
	eq([oa["with"], int(oa["with_id"])], ["Bob", b.backend.player_id])
	eq([ob["with"], int(ob["with_id"])], ["Alice", a.backend.player_id])
	var ua := _uid(a, ITEM)
	var ub := _uid(b, OTHER_ITEM)
	a.send(ProtocolTrade.set_offer([{"uid": ua, "qty": 2}], 100))
	b.send(ProtocolTrade.set_offer([{"uid": ub, "qty": 1}], 20))
	Players._run(t, 0.1)
	var view := _last(b)
	eq(int(view["theirs"]["kamas"]), 100, "Bob sees Alice's kamas")
	eq([int(view["theirs"]["items"][0]["id"]), int(view["theirs"]["items"][0]["qty"])], [ITEM, 2], "and her item, the offered part")
	eq(int(view["mine"]["items"][0]["qty"]), 1)
	a.send(ProtocolTrade.ready())
	Players._run(t, 0.1)
	eq(bool(_last(b)["theirs"]["ready"]), true, "Bob sees Alice validate")
	check(a.player().character.inventory.get_item(ua)["qty"] == 5, "nothing moves with one validation")
	b.send(ProtocolTrade.ready())
	Players._run(t, 0.1)
	eq([_ends(a), _ends(b)], [["done"], ["done"]])
	var ca := a.player().character
	var cb := b.player().character
	eq([ca.kamas, cb.kamas], [300 - 100 + 20, 50 + 100 - 20])
	eq([ca.inventory.count(ITEM), ca.inventory.count(OTHER_ITEM)], [3, 1])
	eq([cb.inventory.count(ITEM), cb.inventory.count(OTHER_ITEM)], [2, 1])
	check(not a.sim().trade.in_trade(a.player()) and not b.sim().trade.in_trade(b.player()), "the trade is closed")
	# saved: reloading the characters shows the same bags
	var saved: Dictionary = a.server.persistence.load_character("duo", "Bob")
	eq(int(saved["kamas"]), cb.kamas, "the exchange is persisted")
	# audit
	var log: Array = a.sim().trade.log
	eq(log.size(), 1)
	eq([log[0]["cmd"], log[0]["name"], log[0]["with"], log[0]["ok"], log[0]["account"], log[0]["with_account"]], ["trade", "Alice", "Bob", true, "alice", "bob"])
	eq(int(log[0]["gave"]["Alice"]["kamas"]), 100)
	eq(log[0]["gave"]["Bob"]["items"], [{"id": OTHER_ITEM, "qty": 1}])


func test_a_whole_stack_goes_and_stacks_with_the_receivers() -> void:
	var t := _pair()
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	b.sim().give_item(b.player(), ITEM, 1)
	_open(t)
	a.send(ProtocolTrade.set_offer([{"uid": _uid(a, ITEM), "qty": 5}], 0))
	Players._run(t, 0.1)
	a.send(ProtocolTrade.ready())
	b.send(ProtocolTrade.ready())
	Players._run(t, 0.1)
	eq(a.player().character.inventory.count(ITEM), 0, "the stack left Alice's bag")
	eq(b.player().character.inventory.count(ITEM), 6, "and joins Bob's own")
	var stacks := b.player().character.inventory.items.values().filter(func(it: Dictionary) -> bool: return int(it["id"]) == ITEM)
	eq(stacks.size(), 1, "one stack")


func test_any_change_cancels_the_validations() -> void:
	var t := _pair()
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	_open(t)
	a.send(ProtocolTrade.set_offer([], 10))
	a.send(ProtocolTrade.ready())
	Players._run(t, 0.1)
	eq(bool(_last(b)["theirs"]["ready"]), true)
	b.send(ProtocolTrade.set_offer([], 5))
	Players._run(t, 0.1)
	var view := _last(a)
	eq([bool(view["mine"]["ready"]), bool(view["theirs"]["ready"])], [false, false], "Bob's change cancels Alice's validation")
	b.send(ProtocolTrade.ready())
	Players._run(t, 0.1)
	eq(a.player().character.kamas, 300, "one validation is not enough after a change")
	a.send(ProtocolTrade.ready())
	Players._run(t, 0.1)
	eq([a.player().character.kamas, b.player().character.kamas], [300 - 10 + 5, 50 + 10 - 5])


func test_either_side_can_cancel() -> void:
	var t := _pair()
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	_open(t)
	a.send(ProtocolTrade.set_offer([{"uid": _uid(a, ITEM), "qty": 1}], 10))
	b.send(ProtocolTrade.cancel())
	Players._run(t, 0.1)
	eq([_ends(a), _ends(b)], [["cancelled"], ["cancelled"]])
	eq([a.player().character.kamas, a.player().character.inventory.count(ITEM)], [300, 5], "nothing was lost")
	a.send(ProtocolTrade.cancel())
	a.send(ProtocolTrade.set_offer([], 0))
	a.send(ProtocolTrade.ready())
	Players._run(t, 0.1)
	eq(_codes(a), [ProtocolTrade.E_NOT_IN_TRADE, ProtocolTrade.E_NOT_IN_TRADE, ProtocolTrade.E_NOT_IN_TRADE])
	eq(a.sim().trade.log.size(), 1, "a cancelled trade is audited too")
	eq([a.sim().trade.log[0]["ok"], a.sim().trade.log[0]["code"]], [false, "cancelled"])


func test_invitations_decline_expire_and_refuse() -> void:
	var t := _pair()
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	a.send(ProtocolTrade.invite("Nobody"))
	a.send(ProtocolTrade.invite("Alice"))
	b.send(ProtocolTrade.accept("Alice"))
	b.send(ProtocolTrade.decline("Alice"))
	Players._run(t, 0.1)
	eq(_codes(a), [Protocol.E_PLAYER_OFFLINE, Protocol.E_PLAYER_OFFLINE])
	eq(_codes(b), [ProtocolTrade.E_NO_TRADE_INVITATION, ProtocolTrade.E_NO_TRADE_INVITATION])
	a.send(ProtocolTrade.invite("Bob"))
	Players._run(t, 0.1)
	b.send(ProtocolTrade.decline("Alice"))
	Players._run(t, 0.1)
	eq(_ends(a), ["declined"], "the inviter is told")
	b.send(ProtocolTrade.accept("Alice"))
	Players._run(t, 0.1)
	eq(_codes(b), [ProtocolTrade.E_NO_TRADE_INVITATION], "a declined invitation is gone")
	a.send(ProtocolTrade.invite("Bob"))
	Players._run(t, TradeRules.INVITE_TTL_MS / 1000.0 + 2.0)
	eq(_ends(a), ["expired"], "unanswered, it expires")
	b.send(ProtocolTrade.accept("Alice"))
	Players._run(t, 0.1)
	eq(_codes(b), [ProtocolTrade.E_NO_TRADE_INVITATION])
	check(b.take(ProtocolTrade.OPEN).is_empty())


func test_one_trade_at_a_time_and_only_on_the_same_map() -> void:
	var t := _pair()
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	var c := Players.Conn.new(a.server, "Carl", Players.LOOK, "carl")
	t.append(c)
	Players._run(t, 0.2)
	c.events.clear()
	_open([a, b])
	c.send(ProtocolTrade.invite("Alice"))
	a.send(ProtocolTrade.invite("Carl"))
	Players._run(t, 0.1)
	eq(_codes(c), [ProtocolTrade.E_TRADE_BUSY], "Carl cannot trade with someone who trades")
	eq(_codes(a), [ProtocolTrade.E_TRADE_BUSY], "nor can Alice start a second one")
	a.send(ProtocolTrade.cancel())
	Players._run(t, 0.1)
	a.events.clear()
	# on another map: no trade
	c.sim().teleport(c.player(), 2, 300)
	Players._run(t, 0.1)
	c.events.clear()
	c.send(ProtocolTrade.invite("Alice"))
	Players._run(t, 0.1)
	eq(_codes(c), [Protocol.E_NO_TARGET], "not on the same map")
	# a window open (dialog / shop / bank / workshop) refuses it too
	b.player().shop_npc = 99
	a.send(ProtocolTrade.invite("Bob"))
	Players._run(t, 0.1)
	eq(_codes(a), [ProtocolTrade.E_TRADE_BUSY], "Bob has a shop open")
	b.player().shop_npc = 0
	# a ghost cannot trade
	a.player().character.life = Energy.GHOST
	a.send(ProtocolTrade.invite("Bob"))
	Players._run(t, 0.1)
	eq(_codes(a), [Protocol.E_GHOST])


func test_a_bad_offer_is_refused_and_changes_nothing() -> void:
	var t := _pair()
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	_open(t)
	a.take(ProtocolTrade.UPDATE)
	a.send(ProtocolTrade.set_offer([{"uid": 987654, "qty": 1}], 0))
	a.send(ProtocolTrade.set_offer([{"uid": _uid(a, ITEM), "qty": 6}], 0))
	a.send(ProtocolTrade.set_offer([], 301))
	a.send(ProtocolTrade.set_offer([], -1))
	a.send(ProtocolTrade.set_offer([{"uid": 1}], 0))
	Players._run(t, 0.1)
	eq(_codes(a), [Protocol.E_UNKNOWN_ITEM, Protocol.E_UNKNOWN_ITEM, Protocol.E_NOT_ENOUGH_KAMAS, Protocol.E_BAD_MESSAGE, Protocol.E_BAD_MESSAGE])
	check(_last(a).is_empty(), "no trade_update for a refused offer")
	# a worn item
	var cb := b.player().character
	b.sim().give_item(b.player(), 2473, 1)
	var uid := _uid(b, 2473)
	if uid != 0:
		cb.inventory.items[uid]["pos"] = 1
		b.send(ProtocolTrade.set_offer([{"uid": uid, "qty": 1}], 0))
		Players._run(t, 0.1)
		eq(_codes(b), [Protocol.E_ITEM_WORN], "a worn item cannot be offered")


func test_a_full_bag_cannot_receive_and_nothing_is_lost() -> void:
	var t := _pair()
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	_open(t)
	var w := maxi(1, int(GameData.item(ITEM).get("weight", 1)))
	var many: int = b.player().character.max_weight() / w + 10
	a.sim().give_item(a.player(), ITEM, many) # gains are never refused: Alice is overloaded herself
	Players._run(t, 0.1)
	a.events.clear()
	b.events.clear()
	var uid := _uid(a, ITEM)
	a.send(ProtocolTrade.set_offer([{"uid": uid, "qty": many}], 0))
	Players._run(t, 0.1)
	eq(_codes(a), [Protocol.E_OVERLOADED], "Bob's bag cannot carry it: the offer is refused")
	check(_last(b).is_empty(), "Bob sees nothing")
	# an offer that fits when set, then Bob fills his bag: his validation is refused, nothing moves
	a.send(ProtocolTrade.set_offer([{"uid": uid, "qty": 3}], 10))
	Players._run(t, 0.1)
	a.send(ProtocolTrade.ready())
	b.sim().give_item(b.player(), ITEM, many)
	Players._run(t, 0.1)
	b.events.clear()
	b.send(ProtocolTrade.ready())
	Players._run(t, 0.1)
	eq(_codes(b), [Protocol.E_OVERLOADED], "Bob's validation is refused")
	eq([a.player().character.kamas, b.player().character.kamas], [300, 50], "no kama moved")
	eq(a.player().character.inventory.count(ITEM), 5 + many, "no item moved")
	check(a.sim().trade.in_trade(a.player()), "the trade stays open")
	# the exchange itself checks again: an offer that is no longer there fails, all or nothing
	var s: TradeSession = a.sim().trade.sessions["Alice"]
	a.player().character.inventory.remove(uid, int(a.player().character.inventory.get_item(uid)["qty"]))
	a.sim().trade._commit(s)
	Players._run(t, 0.1)
	eq([_ends(a), _ends(b)], [["failed"], ["failed"]])
	eq([a.player().character.kamas, b.player().character.kamas], [300, 50], "all or nothing")
	eq(a.sim().trade.log[-1]["code"], Protocol.E_UNKNOWN_ITEM)


func test_moving_fighting_acting_or_leaving_cancels() -> void:
	# a map change
	var t := _pair()
	var a: Players.Conn = t[0]
	var b: Players.Conn = t[1]
	_open(t)
	b.sim().teleport(b.player(), 2, 300)
	Players._run(t, 0.1)
	eq([_ends(a), _ends(b)], [["moved"], ["moved"]], "a teleport cancels")
	# another action (a walk)
	t = _pair()
	a = t[0]
	b = t[1]
	_open(t)
	a.send(Protocol.move(320))
	Players._run(t, 0.1)
	eq([_ends(a), _ends(b)], [["action"], ["action"]], "walking cancels")
	# a fight started by a monster group (the fixture spells only for this one: they must not leak to other suites)
	SpellBook.use_file("res://tests/fixtures/spells.json")
	t = _pair()
	a = t[0]
	b = t[1]
	_open(t)
	var map := a.sim().get_map(1)
	var group: SimActor = map.actors.values().filter(func(x: SimActor) -> bool: return x is MonsterGroup)[0]
	a.sim().combat.start_fight(a.player(), map, group)
	Players._run(t, 0.1)
	check(a.player().fight_id != 0, "Alice fights")
	eq([_ends(a), _ends(b)], [["fight"], ["fight"]], "a fight cancels")
	a.send(ProtocolTrade.invite("Bob"))
	Players._run(t, 0.1)
	eq(_codes(a), [Protocol.E_IN_FIGHT], "no trade in a fight")
	SpellBook.use_file("")
	# a disconnection
	t = _pair()
	a = t[0]
	b = t[1]
	_open(t)
	a.sim().disconnect_player(a.backend.player_id)
	Players._run(t, 0.1)
	eq(_ends(b), ["disconnected"], "Bob is told")
	eq(b.player().character.kamas, 50, "nothing moved")
	check(not b.sim().trade.in_trade(b.player()), "and he is free")
	# an invitation of someone who left is void
	t = _pair()
	a = t[0]
	b = t[1]
	a.send(ProtocolTrade.invite("Bob"))
	Players._run(t, 0.1)
	a.sim().disconnect_player(a.backend.player_id)
	b.send(ProtocolTrade.accept("Alice"))
	Players._run(t, 0.1)
	eq(_codes(b), [ProtocolTrade.E_NO_TRADE_INVITATION])


func test_the_audit_sink_gets_every_opened_trade() -> void:
	var t := _pair()
	var a: Players.Conn = t[0]
	var got: Array = []
	a.server.audit_sink = func(e: Dictionary) -> void: got.append(e)
	_open(t)
	a.send(ProtocolTrade.cancel())
	Players._run(t, 0.1)
	eq(got.size(), 1)
	eq([got[0]["cmd"], got[0]["ok"], got[0]["code"]], ["trade", false, "cancelled"])
	check(Protocol.is_json_safe(got[0]), "an audit entry is JSON-safe")


# -- the same over WebSockets ----------------------------------------------------------------

func test_trade_over_websocket() -> void:
	var rig := NetTests.Rig.new()
	var a := rig.client("tiny", "Alice")
	rig.run(2.0, func() -> bool: return a.has(Protocol.MAP_ENTER))
	var b := rig.client("tiny", "Bob")
	rig.run(2.0, func() -> bool: return b.has(Protocol.MAP_ENTER))
	var sim := rig.sim()
	sim.give_item(sim.players[a.you], ITEM, 4)
	sim.players[a.you].character.kamas = 500
	sim.players[b.you].character.kamas = 10
	rig.run(0.3)
	var ua := 0
	for it: Dictionary in sim.players[a.you].character.inventory.items.values():
		ua = int(it["uid"])
	a.backend.send(ProtocolTrade.invite("Bob"))
	check(rig.run(2.0, func() -> bool: return b.has(ProtocolTrade.INVITED)), "Bob is invited through the server")
	b.backend.send(ProtocolTrade.accept("Alice"))
	check(rig.run(2.0, func() -> bool: return a.has(ProtocolTrade.OPEN) and b.has(ProtocolTrade.OPEN)), "both windows open")
	eq(int(b.take(ProtocolTrade.OPEN)[0]["with_id"]), a.you, "ids survive the JSON round trip as ints")
	a.backend.send(ProtocolTrade.set_offer([{"uid": ua, "qty": 3}], 200))
	check(rig.run(2.0, func() -> bool: return b.events.any(func(e: Dictionary) -> bool: return e["t"] == ProtocolTrade.UPDATE and int(e["theirs"]["kamas"]) == 200)), "Bob sees the offer")
	var view: Dictionary = b.take(ProtocolTrade.UPDATE)[-1]
	eq([int(view["theirs"]["kamas"]), int(view["theirs"]["items"][0]["qty"])], [200, 3])
	b.backend.send(ProtocolTrade.set_offer([], 5))
	rig.run(0.3)
	a.backend.send(ProtocolTrade.ready())
	rig.run(0.3)
	b.backend.send(ProtocolTrade.ready())
	check(rig.run(2.0, func() -> bool: return a.has(ProtocolTrade.END) and b.has(ProtocolTrade.END)), "the trade ends for both")
	eq([a.take(ProtocolTrade.END)[0]["reason"], b.take(ProtocolTrade.END)[0]["reason"]], ["done", "done"])
	eq([sim.players[a.you].character.kamas, sim.players[b.you].character.kamas], [500 - 200 + 5, 10 + 200 - 5])
	eq(sim.players[b.you].character.inventory.count(ITEM), 3, "Bob got the items")
	eq(sim.players[a.you].character.inventory.count(ITEM), 1)
	# a cancelled one, and an error coming back with its ref
	a.backend.send(ProtocolTrade.cancel())
	check(rig.run(2.0, func() -> bool: return a.has(Protocol.ERROR)), "an error comes back")
	var err: Dictionary = a.take(Protocol.ERROR)[0]
	eq([str(err["code"]), err.has("ref")], [ProtocolTrade.E_NOT_IN_TRADE, true])
	a.backend.send(ProtocolTrade.invite("Bob"))
	rig.run(0.5)
	b.backend.send(ProtocolTrade.accept("Alice"))
	rig.run(0.5)
	b.backend.send(ProtocolTrade.cancel())
	check(rig.run(2.0, func() -> bool: return a.has(ProtocolTrade.END)), "Bob cancels")
	eq(sim.trade.log.size(), 2, "both opened trades are audited")
	eq(a.backend.schema_errors.size() + b.backend.schema_errors.size(), 0, "every event matches the schema")
	rig.host.shutdown()
