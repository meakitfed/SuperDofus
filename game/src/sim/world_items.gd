## Items of the players (WorldSim handler): gains, consumables, equipment, destruction.
class_name WorldItems
extends WorldHandler


## Gives `qty` new items (drop, craft, quest…): rolled effects (ItemEffects.roll),
## stacked with identical ones. Gains are never refused for weight (Dofus).
func give_item(p: PlayerActor, item_id: int, qty := 1, quest_event := true) -> void:
	var stack := p.character.inventory.add(item_id, qty, ItemEffects.roll(item_id, sim.rng), new_item_uid)
	p.outbox.append(Protocol.item_added(stack))
	if quest_event:
		sim.quests.event(p, {"kind": "item"}) # P2.03: an objective may ask for it


func new_item_uid() -> int:
	return sim.persistence.next_uid("item")


## use_item: a consumable's effects (items.possibleEffects), one item used.
##   110 heals (dice rolled now, up to max HP) · 600 back to the save point ·
##   606-611 +N additional characteristic. Conditions: items.criterions (Criteria).
func use_item(p: PlayerActor, uid: int) -> String:
	var c := p.character
	var it := c.inventory.get_item(uid)
	if it.is_empty():
		return Protocol.E_UNKNOWN_ITEM
	var data := GameData.item(int(it["id"]))
	var effects := ItemEffects.usable(it["effects"])
	if not bool(data.get("usable", false)) or effects.is_empty() or int(it.get("pos", Inventory.BAG)) != Inventory.BAG:
		return Protocol.E_ITEM_NOT_USABLE
	if not CriteriaEval.ok(str(data.get("criteria", "")), c.criteria_values()):
		return Protocol.E_ITEM_CONDITION
	var recall := false
	var regained := 0
	for e: Array in effects:
		if int(e[0]) == ItemEffects.ENERGY and c.energy >= Energy.MAX:
			return Protocol.E_ENERGY_FULL # "Vos points d'énergie sont déjà au maximum." (i18n 4691)
	for e: Array in effects:
		var eid := int(e[0])
		if eid == ItemEffects.HEAL:
			c.set_hp(c.hp_at(sim.now) + ItemEffects.dice(e, sim.rng), sim.now)
		elif eid == ItemEffects.RECALL:
			recall = true
		elif eid == ItemEffects.ENERGY:
			regained += c.gain_energy(ItemEffects.dice(e, sim.rng))
		elif eid == ItemEffects.JOB_XP:
			var job := int(e[2])
			var gained := int(e[3])
			var levels := c.jobs.gain(job, gained)
			p.outbox.append(Protocol.job_xp(gained, levels, c.jobs.view(job)))
		elif ItemEffects.SCROLLS.has(eid):
			var stat: String = ItemEffects.SCROLLS[eid]
			c.additional[stat] = int(c.additional[stat]) + maxi(1, int(e[1]))
	take_item(p, uid, 1)
	sim.quests.event(p, {"kind": "use", "item": int(it["id"])})
	if regained > 0:
		p.outbox.append(Protocol.info(Protocol.I_ENERGY_REGAINED, [regained]))
	if recall:
		var sp := sim.travel.save_point(c)
		sim.teleport(p, sp[0], sp[1])
	return ""


## After equip / unequip: the item events, then the new stats (saved).
func apply_items(p: PlayerActor, type: String, r: Dictionary) -> void:
	if str(r["err"]) == "":
		for uid: int in r["removed"]:
			p.outbox.append(Protocol.item_removed(uid))
		for it: Dictionary in r["changed"]:
			p.outbox.append(Protocol.item_added(it))
		refresh_look(p)
	sim.character_changed(p, type, str(r["err"]))


## The worn items changed: the new look for everyone on the map (P1.06b).
func refresh_look(p: PlayerActor) -> void:
	var look := p.character.display_look()
	if p.looks.size() == 1 and p.looks[0] == look:
		return
	p.looks = PackedStringArray([look])
	var map := sim.get_map(p.map_id)
	if map != null and map.actors.has(p.id):
		map.broadcast(Protocol.actor_look(p.id, [look]))


## destroy_item: throws away `qty` of a stack (0 = all).
func destroy_item(p: PlayerActor, uid: int, qty: int) -> String:
	var it := p.character.inventory.get_item(uid)
	if it.is_empty() or qty < 0:
		return Protocol.E_UNKNOWN_ITEM
	if int(it.get("pos", Inventory.BAG)) != Inventory.BAG:
		return Protocol.E_ITEM_WORN
	take_item(p, uid, mini(int(it["qty"]), qty) if qty > 0 else int(it["qty"]))
	return ""


func take_item(p: PlayerActor, uid: int, qty: int) -> void:
	var left := p.character.inventory.remove(uid, qty)
	p.outbox.append(Protocol.item_added(left) if not left.is_empty() else Protocol.item_removed(uid))
