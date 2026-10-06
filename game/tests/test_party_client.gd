## The group frame of the client (P3.03b): what PartyFrame shows of the party events, the answers
## it sends back, the markers over the members' sprites, and the whole flow between two
## NetBackends on 127.0.0.1 (invite from the menu action, accept, leave).
extends TestCase

const NetTests := preload("res://tests/test_net.gd")


func _init() -> void:
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()


static func _member(id: int, name: String, map := 1, hp := 40, fight := false) -> Dictionary:
	return {"id": id, "name": name, "level": 12, "breed": 8, "hp": hp, "max_hp": 60, "map": map, "coords": [3, -2], "cell": 300, "fight": fight}


static func _party(members: Array, follow := "") -> Dictionary:
	return {"id": 1, "leader": str(members[0]["name"]), "follow": follow, "members": members}


## A frame fed by hand, with a sink for what it sends.
class Sink:
	extends GameBackend
	var sent: Array = []

	func send(msg: Dictionary) -> void:
		sent.append(msg)


func _frame(sink: GameBackend) -> PartyFrame:
	var f := PartyFrame.new()
	f.setup(sink)
	return f


func test_events_fill_and_empty_the_frame() -> void:
	var sink := Sink.new()
	var f := _frame(sink)
	var toast: Toast = null
	var ev := ProtocolParty.update(_party([_member(1, "Alice"), _member(2, "Bob", 2, 10)]))
	f.on_event(ProtocolParty.UPDATE, ev, toast, {}, 2)
	eq(f.members().size(), 2)
	check(not f.is_leader(), "Bob (id 2) is not the leader")
	eq(f.party_map(), 2, "our own entry gives our map")
	f.on_event(ProtocolParty.UPDATE, ProtocolParty.update(_party([_member(2, "Bob"), _member(1, "Alice")])), toast, {}, 2)
	check(f.is_leader(), "the first member is the leader")
	f.on_event(ProtocolParty.LEFT, ProtocolParty.left("kicked"), toast, {}, 2)
	check(f.party.is_empty(), "left: no group")
	eq(PartyFrame.left_text("kicked"), "Vous avez été exclu du groupe")
	eq(PartyFrame.left_text("dissolved"), "Le groupe est dissous")
	f.free()


func test_location_text() -> void:
	eq(PartyFrame.location_text(_member(1, "A", 1), 1), "", "same map: nothing")
	eq(PartyFrame.location_text(_member(1, "A", 2), 1), "[3, -2]", "elsewhere: coordinates")
	eq(PartyFrame.location_text(_member(1, "A", 1, 40, true), 1), "en combat")


func test_invitations_are_answered_and_expire() -> void:
	var sink := Sink.new()
	var f := _frame(sink)
	var toast: Toast = null
	f.on_event(ProtocolParty.INVITED, ProtocolParty.invited("Alice"), toast, {}, 2)
	f.on_event(ProtocolParty.INVITED, ProtocolParty.invited("Alice"), toast, {}, 2)
	eq(f.invites.size(), 1, "the same inviter twice: one invitation")
	f.on_event(ProtocolParty.INVITED, ProtocolParty.invited("Carol"), toast, {}, 2)
	f.decline("Carol")
	eq(sink.sent.back(), ProtocolParty.decline("Carol"))
	f.accept("Alice")
	eq(sink.sent.back(), ProtocolParty.accept("Alice"))
	check(f.invites.is_empty(), "answered")
	f.on_event(ProtocolParty.INVITED, ProtocolParty.invited("Dave"), toast, {}, 2)
	f.invites[0]["at"] = Time.get_ticks_msec() - PartyFrame.INVITE_MS - 1
	f._process(0.0)
	check(f.invites.is_empty(), "a minute later it is gone")
	f.invite("Eve")
	eq(sink.sent.back(), ProtocolParty.invite("Eve"))
	f.free()


func test_markers_follow_the_members_on_the_map() -> void:
	var f := _frame(Sink.new())
	var toast: Toast = null
	var views := {1: Node2D.new(), 2: Node2D.new(), 3: Node2D.new()}
	f.on_event(ProtocolParty.UPDATE, ProtocolParty.update(_party([_member(1, "Alice"), _member(2, "Bob")])), toast, views, 2)
	check(views[1].has_node(PartyFrame.MARK), "the leader has a marker")
	check(not views[2].has_node(PartyFrame.MARK), "not on ourselves")
	check(not views[3].has_node(PartyFrame.MARK), "nor on a stranger")
	check(views[1].get_node(PartyFrame.MARK).get_meta("leader"), "gold for the leader")
	f.on_event(ProtocolParty.UPDATE, ProtocolParty.update(_party([_member(3, "Carol"), _member(2, "Bob")])), toast, views, 2)
	check(not views[1].has_node(PartyFrame.MARK), "Alice left: marker gone")
	check(views[3].has_node(PartyFrame.MARK))
	f.on_event(ProtocolParty.LEFT, ProtocolParty.left("left"), toast, views, 2)
	check(not views[3].has_node(PartyFrame.MARK), "no group: no marker")
	for v: Node in views.values():
		v.free()
	f.free()


func test_party_flow_over_websocket() -> void:
	var rig := NetTests.Rig.new()
	var a := rig.client("tiny", "Alice")
	rig.run(2.0, func() -> bool: return a.has(Protocol.MAP_ENTER))
	var b := rig.client("tiny", "Bob")
	rig.run(2.0, func() -> bool: return b.has(Protocol.MAP_ENTER))
	var fa := _frame(a.backend)
	var fb := _frame(b.backend)
	var toast: Toast = null
	var pump := func() -> void:
		for pair: Array in [[a, fa], [b, fb]]:
			for ev: Dictionary in pair[0].events:
				if str(ev["t"]).begins_with("party_"):
					pair[1].on_event(str(ev["t"]), ev, toast, {}, pair[0].you)
			pair[0].events = pair[0].events.filter(func(e: Dictionary) -> bool: return not str(e["t"]).begins_with("party_"))
	fa.invite("Bob") # what the player menu entry does
	rig.run(2.0, func() -> bool: return b.has(ProtocolParty.INVITED))
	pump.call()
	eq(fb.invites.size(), 1, "Bob's frame shows the invitation")
	fb.accept("Alice")
	rig.run(2.0, func() -> bool: return a.has(ProtocolParty.UPDATE) and b.has(ProtocolParty.UPDATE))
	pump.call()
	eq([fa.members().size(), fb.members().size()], [2, 2], "both frames list two members")
	check(fa.is_leader() and not fb.is_leader(), "Alice leads")
	fb.backend.send(ProtocolParty.leave())
	rig.run(2.0, func() -> bool: return b.has(ProtocolParty.LEFT))
	pump.call()
	check(fb.party.is_empty(), "Bob's frame is empty after leaving")
	eq(a.backend.schema_errors.size() + b.backend.schema_errors.size(), 0, "every event matches the schema")
	fa.free()
	fb.free()
	rig.host.shutdown()
