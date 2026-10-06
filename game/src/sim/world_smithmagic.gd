## Forgemagie (P2.07), a WorldSim handler: fm_apply. The rules are Smithmagic (shared); the dice come from the
## sim's seeded rng. The item must be in the bag (a worn one would change the stats under the fight rules'
## feet), the rune is spent only when the rune works (a refused rune stays in the bag).
class_name WorldSmithmagic
extends WorldHandler


func on_fm_apply(p: PlayerActor, uid: int, rune_id: int) -> void:
	var inv := p.character.inventory
	var it := inv.get_item(uid)
	if it.is_empty():
		_error(p, Protocol.E_UNKNOWN_ITEM)
		return
	if int(it.get("pos", Inventory.BAG)) != Inventory.BAG:
		_error(p, Protocol.E_ITEM_WORN)
		return
	if inv.bag_count(rune_id) < 1 or Smithmagic.rune_info(rune_id).is_empty():
		_error(p, Protocol.E_FM_RUNE)
		return
	var r := Smithmagic.apply(int(it["id"]), it["effects"], int(it.get("reserve", 0)), rune_id, sim.rng)
	if str(r["err"]) != "":
		_error(p, str(r["err"]))
		return
	# the rune is spent
	for t: Dictionary in inv.take(rune_id, 1):
		var left: Dictionary = t["left"]
		p.outbox.append(Protocol.item_added(left) if not left.is_empty() else Protocol.item_removed(int(t["uid"])))
	# one item at a time: a stack gives one away
	var target := it
	if int(it["qty"]) > 1:
		var rest := inv.remove(uid, 1)
		p.outbox.append(Protocol.item_added(rest))
		var new_uid := sim.items.new_item_uid()
		target = {"uid": new_uid, "id": int(it["id"]), "qty": 1, "effects": [], "pos": Inventory.BAG}
		inv.items[new_uid] = target
	target["effects"] = r["effects"]
	if int(r["reserve"]) != 0:
		target["reserve"] = int(r["reserve"])
	else:
		target.erase("reserve")
	p.outbox.append(Protocol.item_added(target))
	p.outbox.append(Protocol.fm_result(int(target["uid"]), rune_id, str(r["outcome"]), target, r["lost"]))
	sim.character_changed(p, Protocol.FM_APPLY, "")


func _error(p: PlayerActor, code: String) -> void:
	p.outbox.append(Protocol.error(code, "", Protocol.FM_APPLY))
