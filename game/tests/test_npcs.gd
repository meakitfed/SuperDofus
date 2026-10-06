## P2.01: NPCs on the map and their dialogs (Dialog trees, replies hidden by criteria, actions).
extends TestCase

const LOOK := "{1|120,2195||56}"
const NPC_CELL := 300
const TREE := {"start": "a", "nodes": {
	"a": {"text": "Bonjour", "replies": [
		{"id": 1, "text": "Qui es-tu ?", "next": "b"},
		{"id": 2, "text": "Réservé aux vétérans", "criteria": "PL>50", "next": "b"},
		{"id": 3, "text": "Emmène-moi", "action": {"type": "teleport", "map": 2, "cell": 310}},
		{"id": 4, "text": "Un cadeau ?", "action": {"type": "give_kamas", "amount": 25}},
		{"id": 5, "text": "Ma boutique", "action": {"type": "shop"}}]},
	"b": {"text_id": 428977, "replies": []}}}


class Conn:
	var backend := LocalBackend.new()
	var events: Array = []
	var you := -1
	var npc := -1
	var entered: Array = [] # the events of the connection

	func _init(server: LocalServer) -> void:
		backend.server = server
		backend.event.connect(func(ev: Dictionary) -> void:
			events.append(ev)
			if ev["t"] == Protocol.WELCOME:
				you = int(ev["you"])
			if ev["t"] == Protocol.MAP_ENTER:
				for a: Dictionary in ev["actors"]:
					if a["kind"] == "npc" and int(a["npc"]) == 9001:
						npc = int(a["id"]))
		backend.send(Protocol.hello("npcs", "Eli", LOOK))
		backend.poll(0.0)
		entered = events.duplicate()

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


static func _conn() -> Conn:
	var s := LocalServer.new()
	var src := WorldSource.from_dicts({"id": "npcs", "name": "Npcs", "start_map": 1, "start_cell": 301},
		[{"id": 1, "coords": [0, 0], "neighbors": {}}, {"id": 2, "coords": [1, 0], "neighbors": {}}])
	src.set_npcs({1: [{"npc": 9001, "cell": NPC_CELL, "dir": 3, "look": "{714}", "name_id": 8306},
			{"npc": 925, "cell": 330, "dir": 1}]}, {9001: TREE})
	s.sources["npcs"] = src
	var c := Conn.new(s)
	c.send(Protocol.move(MapGeometry.neighbors(NPC_CELL)[0], false)) # beside the NPC (the sim checks the destination)
	return c


func test_the_npc_is_an_actor_of_the_map() -> void:
	var c := _conn()
	check(c.npc >= 0, "the map_enter lists the NPC")
	var enter: Dictionary = c.entered.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.MAP_ENTER)[0]
	var npcs: Array = (enter["actors"] as Array).filter(func(a: Dictionary) -> bool: return a["kind"] == "npc")
	eq(npcs.size(), 2)
	var a: Dictionary = npcs.filter(func(n: Dictionary) -> bool: return int(n["npc"]) == 9001)[0]
	eq(int(a["cell"]), NPC_CELL)
	eq(int(a["dir"]), 3)
	eq(int(a["name_id"]), 8306)
	eq(a["looks"], ["{714}"])
	check(bool(a["talk"]))


func test_talk_needs_to_stand_beside_the_npc() -> void:
	var c := _conn()
	c.send(Protocol.move(NPC_CELL + 40, false))
	var err := c.send(Protocol.npc_talk(c.npc)).filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.ERROR)
	eq(err[0]["code"], Protocol.E_NOT_AT_NPC)


func test_dialog_hides_replies_whose_criteria_fail() -> void:
	var c := _conn() # beside the NPC
	c.send(Protocol.npc_talk(c.npc))
	var d := c.last(Protocol.DIALOG)
	eq(d["text"], "Bonjour")
	var ids := (d["replies"] as Array).map(func(r: Dictionary) -> int: return int(r["id"]))
	eq(ids, [1, 3, 4, 5], "reply 2 needs level 50")
	var hidden := c.send(Protocol.dialog_reply(2)).filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.ERROR)
	eq(hidden[0]["code"], Protocol.E_NO_REPLY, "a hidden reply cannot be chosen")


func test_reply_leads_to_the_next_node_then_ends() -> void:
	var c := _conn()
	c.send(Protocol.npc_talk(c.npc))
	c.send(Protocol.dialog_reply(1))
	var d := c.last(Protocol.DIALOG)
	eq(int(d["text_id"]), 428977)
	eq((d["replies"] as Array).size(), 0)
	c.send(Protocol.dialog_close())
	check(not c.last(Protocol.DIALOG_END).is_empty())
	check(not c.send(Protocol.dialog_reply(1)).filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.ERROR).is_empty(), "no dialog open")


func test_actions_teleport_kamas_and_passthrough() -> void:
	var c := _conn()
	c.send(Protocol.npc_talk(c.npc))
	var evs := c.send(Protocol.dialog_reply(4))
	var stats := evs.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.PLAYER_STATS)
	eq(int(stats[0]["stats"]["kamas"]), 25)
	eq(c.last(Protocol.DIALOG_END)["action"]["type"], "give_kamas")
	c.send(Protocol.npc_talk(c.npc))
	eq(c.send(Protocol.dialog_reply(5)).filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.DIALOG_END)[0]["action"]["type"], "shop")
	c.send(Protocol.npc_talk(c.npc))
	var moved := c.send(Protocol.dialog_reply(3))
	check(not moved.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.MAP_ENTER and int(e["map"]["id"]) == 2).is_empty(), "teleported to map 2")


func test_any_other_action_closes_the_dialog() -> void:
	var c := _conn()
	c.send(Protocol.npc_talk(c.npc))
	var evs := c.send(Protocol.move(NPC_CELL + 40, false))
	check(not evs.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.DIALOG_END).is_empty())


func test_a_template_without_tree_says_its_first_message() -> void:
	# npcs 925 (Capitaine Kradoc): the real table, first of dialogMessages, nothing to answer
	var c := _conn()
	var kradoc := -1
	for e: Dictionary in c.entered:
		if e["t"] == Protocol.MAP_ENTER:
			for a: Dictionary in e["actors"]:
				if a["kind"] == "npc" and int(a["npc"]) == 925:
					kradoc = int(a["id"])
	check(kradoc >= 0)
	c.send(Protocol.move(330 - 14, false)) # beside it (cells are 14 wide)
	for i in 3:
		c.backend.poll(1.0)
	c.send(Protocol.npc_talk(kradoc))
	var d := c.last(Protocol.DIALOG)
	eq(int(d["text_id"]), 579953)
	eq((d["replies"] as Array).size(), 0)


func test_default_dialog_reads_json_floats() -> void:
	# a JSON table gives actions [3.0] (3 in [3.0] is false in GDScript): Incarnam NPCs were mute
	var row := {"actions": [3.0], "dialogMessages": [{"values": [21114.0, 552243.0]}]}
	eq(int(Dialog.default_for(row)["nodes"]["0"]["text_id"]), 552243)
	eq(Dialog.default_for({"actions": [1.0], "dialogMessages": row["dialogMessages"]}), {}, "no talk action: silent")
	eq(Dialog.default_for({"actions": [3.0], "dialogMessages": []}), {}, "no message: silent")
