## The marketplace (P2.10): opening, search, putting lots on sale (with the tax), buying,
## taking a lot back, and the kamas of a sale that reach the seller even offline. The rules
## are in shared/MarketRules, the state in Marketplace (via Persistence), the messages in
## shared/ProtocolMarket. Every change is one Persistence.commit holding the marketplace and
## the characters it touches, so an object is never in two places.
class_name WorldMarket
extends WorldHandler


## One of the hdv_* commands of a player (already validated against the schema).
func on_command(p: PlayerActor, type: String, cmd: Dictionary) -> void:
	var err := ""
	if type == ProtocolMarket.OPEN:
		err = open_at(p, null)
	elif type == ProtocolMarket.CLOSE:
		close_for(p)
	elif not p.market_open:
		err = ProtocolMarket.E_NO_MARKET
	else:
		match type:
			ProtocolMarket.SEARCH:
				_search(p, cmd)
			ProtocolMarket.SELL:
				err = _sell(p, int(cmd["uid"]), int(cmd["lot"]), int(cmd["price"]), int(cmd.get("count", 1)))
			ProtocolMarket.BUY:
				err = _buy(p, int(cmd["listing"]))
			ProtocolMarket.CANCEL:
				err = _cancel(p, int(cmd["listing"]))
	if err != "":
		p.outbox.append(Protocol.error(err, "", type))


func close_for(p: PlayerActor) -> void:
	if p.market_open:
		p.market_open = false
		p.outbox.append(ProtocolMarket.end())


## Opens the marketplace for `p`, beside the manager `npc` (null: any manager beside the player).
## A world with managers (market.json) refuses it anywhere else; one without keeps it open
## everywhere. Returns the error code, "" when opened (the error of a dialog reply is sent here).
func open_at(p: PlayerActor, npc: NpcActor) -> String:
	var err := _open(p, npc)
	if err != "" and npc != null:
		p.outbox.append(Protocol.error(err, "", Protocol.DIALOG_REPLY))
		return ""
	return err


func _beside_manager(p: PlayerActor, npc: NpcActor) -> bool:
	if not sim.source.has_auctioneers():
		return true
	var map := sim.get_map(p.map_id)
	var candidates: Array = [npc] if npc != null else map.actors.values()
	for a: Variant in candidates:
		if a is NpcActor and sim.source.is_auctioneer((a as NpcActor).npc_id) 				and MapGeometry.distance(p.dest_cell(), (a as NpcActor).cell) <= 1:
			return true
	return false


func _open(p: PlayerActor, npc: NpcActor) -> String:
	if p.character.is_ghost():
		return Protocol.E_GHOST
	if not p.craft.is_empty() or not p.harvest.is_empty():
		return ProtocolMarket.E_MARKET_BUSY
	if not _beside_manager(p, npc):
		return Protocol.E_NOT_AT_NPC
	collect(p)
	p.market_open = true
	p.outbox.append(ProtocolMarket.opened(_mine(p)))
	return ""


func _market() -> Marketplace:
	return Marketplace.load_from(sim.persistence)


func _mine(p: PlayerActor, m: Marketplace = null) -> Array:
	return (m if m != null else _market()).mine(sim.world_id(), p.name, sim.clock.now_unix_ms())


func _search(p: PlayerActor, cmd: Dictionary) -> void:
	var r := _market().search(int(cmd.get("category", MarketRules.ALL_CATEGORIES)), str(cmd.get("name", "")),
			int(cmd.get("item", 0)), int(cmd.get("page", 0)), sim.clock.now_unix_ms())
	p.outbox.append(ProtocolMarket.results(r["listings"], int(r["page"]), int(r["pages"]), int(r["total"])))


## hdv_sell: `count` lots of `lot` objects of a bag stack, each at `price`; the tax is paid per lot.
func _sell(p: PlayerActor, uid: int, lot: int, price: int, count: int) -> String:
	var err := MarketRules.sell_error(lot, count, price)
	if err != "":
		return err
	var c := p.character
	var it := c.inventory.get_item(uid)
	if it.is_empty() or int(it["qty"]) < lot * count:
		return Protocol.E_UNKNOWN_ITEM
	if int(it.get("pos", Inventory.BAG)) != Inventory.BAG:
		return Protocol.E_ITEM_WORN
	var id := int(it["id"])
	if not MarketRules.sellable(id):
		return Protocol.E_NOT_SELLABLE
	var m := _market()
	if m.count_of(sim.world_id(), p.name) + count > MarketRules.MAX_LISTINGS:
		return ProtocolMarket.E_MARKET_FULL
	var tax := MarketRules.tax(price) * count
	if c.kamas < tax:
		return Protocol.E_NOT_ENOUGH_KAMAS
	var effects: Array = it["effects"]
	var reserve := int(it.get("reserve", 0)) # the forgemagie puits follows the item
	var left := c.inventory.remove(uid, lot * count)
	p.outbox.append(Protocol.item_added(left) if not left.is_empty() else Protocol.item_removed(uid))
	c.kamas -= tax
	for i in count:
		m.add(sim.world_id(), p.name, id, effects, reserve, lot, price, sim.clock.now_unix_ms())
	sim.persistence.commit([sim.character_write(p), m.write()])
	p.outbox.append(Protocol.player_stats(c.public_dict(sim.now)))
	p.outbox.append(ProtocolMarket.mine(_mine(p, m)))
	return ""


## hdv_buy: the lot goes to the buyer, its price to the seller (online: now, else kept for the
## seller's return), in one commit.
func _buy(p: PlayerActor, id: int) -> String:
	var m := _market()
	var i := m.index_of(id)
	if i < 0 or MarketRules.is_expired(m.listings[i], sim.clock.now_unix_ms()):
		return ProtocolMarket.E_NO_LISTING
	var l: Dictionary = m.listings[i]
	if m.is_seller(l, sim.world_id(), p.name):
		return ProtocolMarket.E_OWN_LISTING
	var c := p.character
	var price := int(l["price"])
	var qty := int(l["qty"])
	var item := int(l["item"])
	if c.kamas < price:
		return Protocol.E_NOT_ENOUGH_KAMAS
	if c.weight() + int(GameData.item(item).get("weight", 1)) * qty > c.max_weight():
		return Protocol.E_OVERLOADED
	m.listings.remove_at(i)
	m.record_sale(item, qty, price)
	c.kamas -= price
	var stack := c.inventory.add(item, qty, l["effects"], sim.items.new_item_uid, int(l.get("reserve", 0)))
	var writes: Array = [sim.character_write(p), m.write()]
	var seller := sim.chat.find_player(str(l["seller"])) if str(l["world"]) == sim.world_id() else null
	if seller != null:
		seller.character.kamas += price
		writes.append(sim.character_write(seller))
	else:
		writes.append(_add_proceeds(str(l["world"]), str(l["seller"]), price, {"item": item, "qty": qty, "price": price}))
	sim.persistence.commit(writes)
	p.outbox.append(Protocol.item_added(stack))
	p.outbox.append(Protocol.player_stats(c.public_dict(sim.now)))
	p.outbox.append(ProtocolMarket.bought(id, item, qty, price))
	if seller != null:
		seller.outbox.append(ProtocolMarket.sold(item, qty, price))
		seller.outbox.append(Protocol.player_stats(seller.character.public_dict(sim.now)))
		if seller.market_open:
			seller.outbox.append(ProtocolMarket.mine(_mine(seller, m)))
	sim.quests.event(p, {"kind": "item"})
	return ""


## hdv_cancel: the seller takes a lot back (on sale or expired); the tax is not refunded.
## The objects come back to the bag even above the pods (a gain, like a drop).
func _cancel(p: PlayerActor, id: int) -> String:
	var m := _market()
	var i := m.index_of(id)
	if i < 0 or not m.is_seller(m.listings[i], sim.world_id(), p.name):
		return ProtocolMarket.E_NO_LISTING
	var l: Dictionary = m.listings[i]
	m.listings.remove_at(i)
	var stack := p.character.inventory.add(int(l["item"]), int(l["qty"]), l["effects"], sim.items.new_item_uid, int(l.get("reserve", 0)))
	sim.persistence.commit([sim.character_write(p), m.write()])
	p.outbox.append(Protocol.item_added(stack))
	p.outbox.append(ProtocolMarket.mine(_mine(p, m)))
	sim.quests.event(p, {"kind": "item"})
	return ""


## The write that adds a sale to the proceeds waiting for a seller who is not here.
func _add_proceeds(world: String, seller: String, kamas: int, sale: Dictionary) -> Dictionary:
	var key := Marketplace.proceeds_key(world, seller)
	var doc := sim.persistence.load_doc(Marketplace.COLLECTION, key)
	doc["kamas"] = int(doc.get("kamas", 0)) + kamas
	var sold: Array = doc.get("sold", [])
	sold.append(sale)
	doc["sold"] = sold
	return {"collection": Marketplace.COLLECTION, "key": key, "data": doc}


## The kamas of the sales made while `p` was away are paid now (login, opening the marketplace).
func collect(p: PlayerActor) -> void:
	var key := Marketplace.proceeds_key(sim.world_id(), p.name)
	var doc := sim.persistence.load_doc(Marketplace.COLLECTION, key)
	if doc.is_empty():
		return
	p.character.kamas += int(doc.get("kamas", 0))
	sim.persistence.commit([sim.character_write(p), {"collection": Marketplace.COLLECTION, "key": key, "data": null}])
	for s: Dictionary in doc.get("sold", []):
		p.outbox.append(ProtocolMarket.sold(int(s["item"]), int(s["qty"]), int(s["price"])))
	p.outbox.append(Protocol.player_stats(p.character.public_dict(sim.now)))
