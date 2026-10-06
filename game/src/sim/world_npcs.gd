## NPCs (WorldSim handler): dialogs (P2.01), shops (P2.02) and the bank (P2.08).
class_name WorldNpcs
extends WorldHandler


## The tree of an NPC template: the world's hand-written one, else its first message.
func dialog_for(npc_id: int) -> Dictionary:
	var tree := sim.source.get_dialog(npc_id)
	if not tree.is_empty():
		return tree # hand-written: it carries its own shop reply when it needs one
	tree = Dialog.default_for(GameData.row("npcs", npc_id))
	if sim.source.is_banker(npc_id):
		tree = Dialog.with_bank(tree)
	return Dialog.with_shop(tree) if not sim.source.get_shop(npc_id).is_empty() else tree


## Any other action than the NPC's own walks away from the open dialog / shop / bank.
func walk_away(p: PlayerActor, type: String) -> void:
	if p.dialog_npc != 0 and not type in [Protocol.DIALOG_REPLY, Protocol.DIALOG_CLOSE]:
		end_dialog(p) # any other action walks away from the NPC
	if p.shop_npc != 0 and not type in [Protocol.SHOP_BUY, Protocol.SHOP_SELL, Protocol.SHOP_CLOSE]:
		end_shop(p)
	if p.bank_npc != 0 and not type in [Protocol.BANK_MOVE, Protocol.BANK_KAMAS, Protocol.BANK_CLOSE]:
		end_bank(p)


# ── dialogs ────────────────────────────────────────────────────────────────────

## APPROX(P2.01): talking needs the player on a cell beside the NPC (like the zaap), the
## client's rule for NPCs (interaction distance) is not read.
func on_npc_talk(p: PlayerActor, map: MapInstance, npc_actor: int) -> void:
	var npc: SimActor = map.actors.get(npc_actor)
	if not npc is NpcActor:
		p.outbox.append(Protocol.error(Protocol.E_NO_TARGET, "no NPC %d here" % npc_actor, Protocol.NPC_TALK))
		return
	var n := npc as NpcActor
	if MapGeometry.distance(p.dest_cell(), n.cell) > 1:
		p.outbox.append(Protocol.error(Protocol.E_NOT_AT_NPC, "", Protocol.NPC_TALK))
		return
	var progressed := sim.quests.event(p, {"kind": "talk", "npc": n.npc_id}) # P2.03: objectives done by talking
	var quests := sim.source.get_quests()
	var tree := n.dialog
	if not quests.is_empty():
		tree = QuestEngine.with_offers(tree, quests, QuestEngine.offers(quests, p.character.quests, n.npc_id, p.character.criteria_values(), sim.quests.day()))
	if tree.is_empty():
		if not sim.source.get_shop(n.npc_id).is_empty(): # a merchant without small talk: the shop opens directly
			open_shop(p, n)
		elif sim.source.is_banker(n.npc_id): # a banker without small talk: the chest opens directly
			open_bank(p, n)
		elif not progressed:
			p.outbox.append(Protocol.error(Protocol.E_NO_DIALOG, "", Protocol.NPC_TALK))
	else:
		p.dialog_npc = n.id
		p.dialog_tree = tree
		show_dialog(p, n, str(tree["start"]))


func show_dialog(p: PlayerActor, npc: NpcActor, node: String, action := {}) -> void:
	var view := Dialog.view(p.dialog_tree, node, p.character.criteria_values())
	if view.is_empty():
		end_dialog(p, action)
		return
	p.dialog_node = node
	p.outbox.append(Protocol.dialog(npc.id, view, action))


func on_dialog_reply(p: PlayerActor, map: MapInstance, reply_id: int) -> void:
	var npc: SimActor = map.actors.get(p.dialog_npc)
	if not npc is NpcActor or MapGeometry.distance(p.dest_cell(), npc.cell) > 1:
		end_dialog(p)
		p.outbox.append(Protocol.error(Protocol.E_NO_REPLY, "", Protocol.DIALOG_REPLY))
		return
	var n := npc as NpcActor
	var reply := Dialog.find_reply(p.dialog_tree, p.dialog_node, reply_id, p.character.criteria_values())
	if reply.is_empty():
		p.outbox.append(Protocol.error(Protocol.E_NO_REPLY, "", Protocol.DIALOG_REPLY))
		return
	var action: Dictionary = reply.get("action", {})
	var next := str(reply.get("next", ""))
	if do_dialog_action(p, action) or next == "": # leaving the map ends the dialog (teleport: already ended)
		end_dialog(p, action)
	else:
		show_dialog(p, n, next, action)


## Runs the sim-side part of a reply's action; true when the player left the map.
func do_dialog_action(p: PlayerActor, action: Dictionary) -> bool:
	match str(action.get("type", "")):
		"teleport":
			var map := sim.get_map(int(action["map"]))
			if map != null:
				end_dialog(p)
				sim.teleport(p, map.data.id, int(action["cell"]) if action.has("cell") else map.random_free_cell())
				return true
		"give_kamas":
			p.character.kamas += int(action["amount"])
			p.outbox.append(Protocol.player_stats(p.character.public_dict(sim.now)))
		"give_item":
			sim.items.give_item(p, int(action["item"]), int(action.get("qty", 1)))
		"quest_start":
			sim.quests.start_quest(p, int(action["quest"]))
		"shop":
			var npc: SimActor = sim.get_map(p.map_id).actors.get(p.dialog_npc)
			if npc is NpcActor and not sim.source.get_shop((npc as NpcActor).npc_id).is_empty():
				open_shop(p, npc as NpcActor)
		"bank":
			var banker: SimActor = sim.get_map(p.map_id).actors.get(p.dialog_npc)
			if banker is NpcActor and sim.source.is_banker((banker as NpcActor).npc_id):
				open_bank(p, banker as NpcActor)
	return false


func end_dialog(p: PlayerActor, action := {}) -> void:
	if p.dialog_npc == 0:
		return
	p.dialog_npc = 0
	p.dialog_node = ""
	p.dialog_tree = {}
	p.outbox.append(Protocol.dialog_end(action))


# ── shops ──────────────────────────────────────────────────────────────────────

func open_shop(p: PlayerActor, npc: NpcActor) -> void:
	p.shop_npc = npc.id
	p.outbox.append(Protocol.shop_open(npc.id, NpcShop.offers(sim.source.get_shop(npc.npc_id)), NpcShop.SELL_DIVISOR))


func end_shop(p: PlayerActor) -> void:
	if p.shop_npc != 0:
		p.shop_npc = 0
		p.outbox.append(Protocol.shop_end())


## The shop the player has open and stands beside, {} (+ the error sent) otherwise.
func shop_of(p: PlayerActor, map: MapInstance, type: String) -> Dictionary:
	var npc: SimActor = map.actors.get(p.shop_npc)
	if not npc is NpcActor:
		p.shop_npc = 0
		p.outbox.append(Protocol.error(Protocol.E_NO_SHOP, "", type))
		return {}
	if MapGeometry.distance(p.dest_cell(), npc.cell) > 1:
		end_shop(p)
		p.outbox.append(Protocol.error(Protocol.E_NOT_AT_NPC, "", type))
		return {}
	return sim.source.get_shop((npc as NpcActor).npc_id)


## shop_buy: `qty` of an item the shop sells, at items.price (NpcShop.check_buy: kamas, pods).
func on_shop_buy(p: PlayerActor, map: MapInstance, item_id: int, qty: int) -> void:
	var shop := shop_of(p, map, Protocol.SHOP_BUY)
	if shop.is_empty():
		return
	var c := p.character
	var err := NpcShop.check_buy(shop, item_id, qty, c.kamas, c.weight(), c.max_weight())
	if err != "":
		p.outbox.append(Protocol.error(err, "", Protocol.SHOP_BUY))
		return
	c.kamas -= NpcShop.buy_price(item_id) * qty
	sim.items.give_item(p, item_id, qty)
	sim.character_changed(p, Protocol.SHOP_BUY, "")


## shop_sell: `qty` of a bag stack, bought back at NpcShop.sell_price.
func on_shop_sell(p: PlayerActor, map: MapInstance, uid: int, qty: int) -> void:
	if shop_of(p, map, Protocol.SHOP_SELL).is_empty():
		return
	var it := p.character.inventory.get_item(uid)
	var err := ""
	if it.is_empty() or qty < 1:
		err = Protocol.E_UNKNOWN_ITEM
	elif int(it.get("pos", Inventory.BAG)) != Inventory.BAG:
		err = Protocol.E_ITEM_WORN
	elif qty > int(it["qty"]):
		err = Protocol.E_UNKNOWN_ITEM
	elif not NpcShop.sellable(int(it["id"])):
		err = Protocol.E_NOT_SELLABLE
	if err != "":
		p.outbox.append(Protocol.error(err, "", Protocol.SHOP_SELL))
		return
	p.character.kamas += NpcShop.sell_price(int(it["id"])) * qty
	sim.items.take_item(p, uid, qty)
	sim.character_changed(p, Protocol.SHOP_SELL, "")


# ── bank ───────────────────────────────────────────────────────────────────────

## Opens the account chest: the access is paid first (BankRules.access_cost), refused
## when the character cannot pay.
func open_bank(p: PlayerActor, npc: NpcActor) -> void:
	var bank := Bank.load_for(sim.persistence, p.character.account)
	var cost := bank.access_cost()
	if p.character.kamas < cost:
		p.outbox.append(Protocol.error(Protocol.E_NOT_ENOUGH_KAMAS, "", Protocol.DIALOG_REPLY))
		return
	if cost > 0:
		p.character.kamas -= cost
		sim.character_changed(p, Protocol.DIALOG_REPLY, "")
	p.bank_npc = npc.id
	p.outbox.append(Protocol.bank_open(npc.id, cost, bank.kamas, bank.inventory.to_array()))


func end_bank(p: PlayerActor) -> void:
	if p.bank_npc != 0:
		p.bank_npc = 0
		p.outbox.append(Protocol.bank_end())


## The chest the player has open and stands beside (false + the error sent otherwise).
func bank_ok(p: PlayerActor, map: MapInstance, type: String) -> bool:
	var npc: SimActor = map.actors.get(p.bank_npc)
	if not npc is NpcActor:
		p.bank_npc = 0
		p.outbox.append(Protocol.error(Protocol.E_NO_BANK, "", type))
		return false
	if MapGeometry.distance(p.dest_cell(), npc.cell) > 1:
		end_bank(p)
		p.outbox.append(Protocol.error(Protocol.E_NOT_AT_NPC, "", type))
		return false
	return true


## Saves the character and the chest together, then tells the client the chest changed.
func commit_bank(p: PlayerActor, bank: Bank, changed: Array) -> void:
	sim.persistence.commit([sim.character_write(p), bank.write_for(sim.persistence, p.character.account)])
	p.outbox.append(Protocol.player_stats(p.character.public_dict(sim.now)))
	p.outbox.append(Protocol.bank_update(bank.kamas, changed))


## bank_move: a bag stack goes into the chest ("in"), or a chest stack into the bag ("out"),
## `qty` objects with their effects (no new roll).
func on_bank_move(p: PlayerActor, map: MapInstance, uid: int, qty: int, dir: String) -> void:
	if not bank_ok(p, map, Protocol.BANK_MOVE):
		return
	var c := p.character
	var bank := Bank.load_for(sim.persistence, c.account)
	var err := ""
	var from := c.inventory if dir == BankRules.IN else bank.inventory
	var it := from.get_item(uid)
	if not dir in [BankRules.IN, BankRules.OUT] or qty < 1 or qty > BankRules.MAX_QTY:
		err = Protocol.E_BAD_MESSAGE
	elif it.is_empty() or qty > int(it["qty"]):
		err = Protocol.E_UNKNOWN_ITEM
	elif dir == BankRules.IN and int(it.get("pos", Inventory.BAG)) != Inventory.BAG:
		err = Protocol.E_ITEM_WORN
	elif dir == BankRules.OUT and c.weight() + int(GameData.item(int(it["id"])).get("weight", 1)) * qty > c.max_weight():
		err = Protocol.E_OVERLOADED
	if err != "":
		p.outbox.append(Protocol.error(err, "", Protocol.BANK_MOVE))
		return
	var id := int(it["id"])
	var effects: Array = it["effects"]
	var reserve := int(it.get("reserve", 0)) # P2.07: the forgemagie puits follows the item
	var left := from.remove(uid, qty)
	var changed: Array = []
	if dir == BankRules.IN:
		p.outbox.append(Protocol.item_added(left) if not left.is_empty() else Protocol.item_removed(uid))
		changed.append(bank.inventory.add(id, qty, effects, sim.items.new_item_uid, reserve).duplicate(true))
	else:
		changed.append(left if not left.is_empty() else {"uid": uid, "id": id, "qty": 0, "effects": effects, "pos": Inventory.BAG})
		p.outbox.append(Protocol.item_added(c.inventory.add(id, qty, effects, sim.items.new_item_uid, reserve)))
	commit_bank(p, bank, changed)
	if dir == BankRules.OUT:
		sim.quests.event(p, {"kind": "item"})


## bank_kamas: kamas into the chest ("in") or out of it ("out").
func on_bank_kamas(p: PlayerActor, map: MapInstance, amount: int, dir: String) -> void:
	if not bank_ok(p, map, Protocol.BANK_KAMAS):
		return
	var c := p.character
	var bank := Bank.load_for(sim.persistence, c.account)
	var err := ""
	if not dir in [BankRules.IN, BankRules.OUT] or amount < 1:
		err = Protocol.E_BAD_MESSAGE
	elif amount > (c.kamas if dir == BankRules.IN else bank.kamas):
		err = Protocol.E_NOT_ENOUGH_KAMAS
	if err != "":
		p.outbox.append(Protocol.error(err, "", Protocol.BANK_KAMAS))
		return
	var sign := 1 if dir == BankRules.IN else -1
	c.kamas -= sign * amount
	bank.kamas += sign * amount
	commit_bank(p, bank, [])
