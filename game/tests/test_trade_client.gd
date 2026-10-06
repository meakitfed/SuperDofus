## The trade window of the client (P3.11b): TradeModel (no node: invitations, offers, the messages
## built from the last confirmed offer, the texts of the ends), the "Échanger" entry of the player
## menu, and the whole flow with real ClientSessions on LocalBackends (invitation card, offer by
## double-click, double validation, cancel by closing). The same messages over WebSockets are
## test_trade::test_trade_over_websocket plus the NetBackend flow at the end of this file.
extends TestCase

const NetTests := preload("res://tests/test_net.gd")
const LOOK := "{1|120,2195,4072,4941,3963,5716|1=13418918,2=4077879,3=16022817,4=14386944,5=4275500,6=9904435|56|1@0={1420|||90}}"
const ITEM := 683


func _init() -> void:
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()


static func _offer(items: Array, kamas := 0, ready := false) -> Dictionary:
	return {"items": items, "kamas": kamas, "ready": ready}


func _open_model() -> TradeModel:
	var m := TradeModel.new()
	m.apply_open(ProtocolTrade.open("Bob", 7))
	return m


func test_invitations_expire_and_open_clears_them() -> void:
	var m := TradeModel.new()
	m.apply_invited("Alice", 1000)
	m.apply_invited("Alice", 2000)
	m.apply_invited("Carol", 2500)
	eq(m.invites.size(), 2, "the same inviter twice: one card")
	check(not m.expire(2000 + TradeModel.INVITE_MS - 1), "still valid")
	check(m.expire(2000 + TradeModel.INVITE_MS), "Alice's is gone")
	eq(m.invites.size(), 1)
	m.apply_open(ProtocolTrade.open("Carol", 3))
	check(m.invites.is_empty() and m.is_open, "opening drops the other invitations")
	eq([m.with, m.with_id], ["Carol", 3])


func test_the_offer_is_built_from_the_confirmed_one() -> void:
	var m := _open_model()
	eq(m.add(5, 2, 5), ProtocolTrade.set_offer([{"uid": 5, "qty": 2}], 0))
	m.apply_update(ProtocolTrade.update(_offer([{"uid": 5, "id": 683, "qty": 2}], 10), _offer([])))
	eq(m.offered_qty(5), 2)
	eq(m.add(5, 9, 5), ProtocolTrade.set_offer([{"uid": 5, "qty": 5}], 10), "clamped to what the bag holds, kamas kept")
	eq(m.add(5, 1, 2), null, "nothing left of that stack")
	eq(m.add(6, 1, 1), ProtocolTrade.set_offer([{"uid": 5, "qty": 2}, {"uid": 6, "qty": 1}], 10))
	eq(m.remove(5), ProtocolTrade.set_offer([], 10))
	eq(m.remove(99), null, "not offered")
	eq(m.with_kamas(500, 300), ProtocolTrade.set_offer([{"uid": 5, "qty": 2}], 300), "kamas clamped to the purse")
	eq(m.add(5, 0, 5), null, "quantity 0")


func test_the_line_cap_and_the_closed_window() -> void:
	var m := _open_model()
	var items: Array = []
	for uid in TradeRules.MAX_LINES:
		items.append({"uid": uid + 1, "id": 683, "qty": 1})
	m.apply_update(ProtocolTrade.update(_offer(items), _offer([])))
	eq(m.add(100, 1, 1), null, "20 stacks at most")
	m.close()
	eq(m.add(1, 1, 1), null, "closed: nothing to send")
	check(not m.can_ready())


func test_validation_state_and_texts() -> void:
	var m := _open_model()
	check(m.can_ready(), "open, not validated")
	m.apply_update(ProtocolTrade.update(_offer([], 0, true), _offer([], 0, false)))
	check(not m.can_ready(), "already validated")
	eq([m.status_text(m.mine), m.status_text(m.theirs)], ["Validé", "En attente"])
	for r: String in [ProtocolTrade.REASON_DONE, ProtocolTrade.REASON_CANCELLED, ProtocolTrade.REASON_DECLINED, ProtocolTrade.REASON_EXPIRED,
			ProtocolTrade.REASON_MOVED, ProtocolTrade.REASON_FIGHT, ProtocolTrade.REASON_DISCONNECTED, ProtocolTrade.REASON_ACTION, ProtocolTrade.REASON_FAILED]:
		check(TradeModel.end_text(r) != "", "a text for " + r)
	check("trop plein" in TradeModel.end_text(ProtocolTrade.REASON_FAILED, Protocol.E_OVERLOADED))


func _tree() -> SceneTree:
	return Engine.get_meta("test_tree") as SceneTree


func _drop(s: ClientSession) -> void:
	s.backend = null
	_tree().root.remove_child(s)
	s.free()


func _session(server: LocalServer, name: String) -> ClientSession:
	var b := LocalBackend.new()
	b.account = name.to_lower()
	b.server = server
	var s := ClientSession.new()
	s.world_id = "duo"
	s.player_name = name
	s.persistent = false
	s.backend = b
	_tree().root.add_child(s)
	return s


func _run(server: LocalServer, sessions: Array, seconds: float, until := Callable()) -> bool:
	for i in int(seconds / 0.05):
		server.tick(50)
		for s: ClientSession in sessions:
			s.backend.poll(0.05)
		if until.is_valid() and until.call():
			return true
	return not until.is_valid()


func _world() -> LocalServer:
	var s := LocalServer.new()
	s.sources["duo"] = WorldSource.from_dicts(
		{"id": "duo", "name": "Duo", "start_map": 1, "start_cell": 300, "wander_ms": [600000, 600000]},
		[{"id": 1, "coords": [0, 0]}])
	return s


func _player(s: ClientSession) -> PlayerActor:
	return (s.backend as LocalBackend).sim.players[(s.backend as LocalBackend).player_id]


## The stack of the bag grid of a trade window holding `item`.
func _bag_slot(w: TradeWindow, item: int) -> ItemSlot:
	for c: Node in w._bag_grid.get_children():
		if c is ItemSlot and (c as ItemSlot).item_id == item:
			return c
	return null


func test_flow_through_the_client_windows() -> void:
	var server := _world()
	var alice := _session(server, "Alice")
	var bob := _session(server, "Bob")
	var all := [alice, bob]
	_run(server, all, 1.0)
	check(alice.map != null and bob.map != null, "both are on the map")
	var sim: WorldSim = (alice.backend as LocalBackend).sim
	sim.give_item(_player(alice), ITEM, 5)
	_player(alice).character.kamas = 300
	_run(server, all, 0.5)
	alice.player_hud.trade.set_stats({"kamas": 300}) # the sim changed the purse behind the client's back: show it
	var ta := alice.player_hud.trade
	var tb := bob.player_hud.trade

	# the entry of the player menu invites
	check(_run(server, all, 2.0, func() -> bool: return alice.views.has(bob.you)), "Alice sees Bob")
	alice._others.menu(bob.you, Vector2(20, 20))
	var menus := alice.get_children().filter(func(n: Node) -> bool: return n is PopupMenu)
	var menu: PopupMenu = menus[-1]
	var index := -1
	for i in menu.item_count:
		if menu.get_item_text(i) == "Échanger":
			index = i
			check(not menu.is_item_disabled(i), "the entry is live")
	check(index >= 0, "there is an Échanger entry")
	menu.id_pressed.emit(menu.get_item_id(index))
	check(_run(server, all, 2.0, func() -> bool: return not tb.model.invites.is_empty()), "Bob gets the invitation")
	eq(bob.player_hud.trade_invites.get_child_count(), 1, "one card")
	bob.player_hud.trade_invites.accept("Alice")
	check(_run(server, all, 2.0, func() -> bool: return ta.visible and tb.visible), "both windows open")
	eq([ta.model.with, tb.model.with], ["Bob", "Alice"])
	eq(bob.player_hud.trade_invites.get_child_count(), 0, "the card is gone")

	# Alice double-clicks her stack, puts kamas down
	var slot := _bag_slot(ta, ITEM)
	check(slot != null, "the item is in the bag grid")
	ta._qty.value = 2
	slot.activated.emit(slot)
	check(_run(server, all, 2.0, func() -> bool: return ta.model.offered_qty(int(slot.instance["uid"])) == 2 and tb.model.theirs["items"].size() == 1), "the offer reaches both windows")
	eq(_bag_slot(ta, ITEM).qty, 3, "the bag grid shows what is left")
	ta._kamas.value = 120
	ta._send(ta.model.with_kamas(int(ta._kamas.value), 300))
	check(_run(server, all, 2.0, func() -> bool: return int(tb.model.theirs["kamas"]) == 120), "kamas shown on the other side")

	# double validation
	ta._ready_button.pressed.emit()
	check(_run(server, all, 2.0, func() -> bool: return bool(tb.model.theirs["ready"])), "Bob sees Alice validated")
	check(ta._ready_button.disabled, "her button is closed")
	tb._ready_button.pressed.emit()
	check(_run(server, all, 3.0, func() -> bool: return not ta.visible and not tb.visible), "both windows close when done")
	eq(bob.player_hud.inventory.item_count(ITEM), 2, "Bob got the items")
	eq(alice.player_hud.inventory.item_count(ITEM), 3, "Alice kept the rest")
	check(_player(bob).character.kamas >= 120, "and the kamas")

	# closing the window cancels
	alice.player_hud.trade.on_event(ProtocolTrade.INVITED, ProtocolTrade.invited("Bob"), null) # a stale card is harmless
	ta.model.forget_invite("Bob")
	alice.backend.send(ProtocolTrade.invite("Bob"))
	check(_run(server, all, 2.0, func() -> bool: return not tb.model.invites.is_empty()), "second invitation")
	bob.player_hud.trade_invites.accept("Alice")
	check(_run(server, all, 2.0, func() -> bool: return ta.visible and tb.visible), "open again")
	ta.close_window()
	check(_run(server, all, 2.0, func() -> bool: return not tb.visible), "Alice closing the window cancels Bob's")
	check(not tb.model.is_open and not ta.model.is_open, "both models are closed")
	_drop(alice)
	_drop(bob)


## The same messages through two NetBackends (127.0.0.1), the models fed with the events the
## WebSocket delivers (no ClientSession on a NetBackend: it crashes the headless engine at exit).
func test_trade_flow_over_websocket() -> void:
	var rig := NetTests.Rig.new()
	var a := rig.client("tiny", "Alice")
	rig.run(2.0, func() -> bool: return a.has(Protocol.MAP_ENTER))
	var b := rig.client("tiny", "Bob")
	rig.run(2.0, func() -> bool: return b.has(Protocol.MAP_ENTER))
	var sim := rig.sim()
	var pa: PlayerActor = sim.players[a.you]
	sim.give_item(pa, ITEM, 4)
	pa.character.kamas = 100
	var ma := TradeModel.new()
	var mb := TradeModel.new()
	var pump := func() -> void:
		for pair: Array in [[a, ma], [b, mb]]:
			for ev: Dictionary in pair[0].events:
				match str(ev["t"]):
					ProtocolTrade.INVITED:
						pair[1].apply_invited(str(ev["from"]), 0)
					ProtocolTrade.OPEN:
						pair[1].apply_open(ev)
					ProtocolTrade.UPDATE:
						pair[1].apply_update(ev)
					ProtocolTrade.END:
						pair[1].close()
			pair[0].events = pair[0].events.filter(func(e: Dictionary) -> bool: return not str(e["t"]).begins_with("trade_"))
	a.backend.send(ProtocolTrade.invite("Bob")) # what the menu entry sends
	rig.run(2.0, func() -> bool: return b.has(ProtocolTrade.INVITED))
	pump.call()
	eq(mb.invites.size(), 1)
	b.backend.send(ProtocolTrade.accept(str(mb.invites[0]["from"])))
	rig.run(2.0, func() -> bool: return a.has(ProtocolTrade.OPEN) and b.has(ProtocolTrade.OPEN))
	pump.call()
	check(ma.is_open and mb.is_open, "both models open")
	var uid := int((pa.character.inventory.to_array().filter(func(it: Dictionary) -> bool: return int(it["id"]) == ITEM)[0] as Dictionary)["uid"])
	a.backend.send(ma.add(uid, 3, 4))
	rig.run(2.0, func() -> bool: return a.has(ProtocolTrade.UPDATE) and b.has(ProtocolTrade.UPDATE) and \
			a.events.any(func(e: Dictionary) -> bool: return e["t"] == ProtocolTrade.UPDATE and (e["mine"]["items"] as Array).size() == 1))
	pump.call()
	eq(mb.theirs["items"].size(), 1, "Bob's model shows the offer")
	eq(ma.offered_qty(uid), 3)
	a.backend.send(ProtocolTrade.cancel())
	rig.run(2.0, func() -> bool: return b.has(ProtocolTrade.END))
	pump.call()
	check(not mb.is_open, "cancelled")
	eq(a.backend.schema_errors.size() + b.backend.schema_errors.size(), 0, "every event matches the schema")
	rig.host.shutdown()
