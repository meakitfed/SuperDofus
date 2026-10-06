## Crafting (P2.06), a WorldSim handler: craft_open / craft_set / craft_do / craft_close.
## The workshop is a state of the player (PlayerActor.craft = {skill, ingredients}); the rules are Crafting.
## APPROX(P2.06): no workshop element is needed (the workshops of the maps are server data absent from the
## client and from the JondoEmu dumps): craft_open works anywhere, out of a fight.
class_name WorldCrafting
extends WorldHandler

## the most one craft_do makes (a bag cannot hold more ingredients than that in a session)
const MAX_COUNT := 1000


func on_craft_open(p: PlayerActor, skill: int) -> void:
	if not Crafting.is_craft_skill(skill):
		_error(p, Protocol.E_NO_CRAFT, Protocol.CRAFT_OPEN)
		return
	p.craft = {"skill": skill, "ingredients": []}
	_send_state(p, true)


func on_craft_set(p: PlayerActor, given: Array) -> void:
	if p.craft.is_empty():
		_error(p, Protocol.E_NO_CRAFT, Protocol.CRAFT_SET)
		return
	var merged := {}
	for g: Variant in given:
		if not (g is Dictionary) or not g.has("item") or not g.has("qty"):
			_error(p, Protocol.E_BAD_MESSAGE, Protocol.CRAFT_SET)
			return
		var qty := int(g["qty"])
		if qty > 0:
			merged[int(g["item"])] = int(merged.get(int(g["item"]), 0)) + qty
	var list := []
	var ids := merged.keys()
	ids.sort()
	for id: int in ids:
		list.append({"item": id, "qty": int(merged[id])})
	if list.size() > _slots(p):
		_error(p, Protocol.E_CRAFT_SLOTS, Protocol.CRAFT_SET)
		return
	p.craft["ingredients"] = list
	_send_state(p, false)


## Makes `count` items: the ingredients leave the bag, the items arrive one by one (each with its own
## rolled effects: they stack only when equal), the job gains XP.
func on_craft_do(p: PlayerActor, count: int) -> void:
	if p.craft.is_empty():
		_error(p, Protocol.E_NO_CRAFT, Protocol.CRAFT_DO)
		return
	var skill := int(p.craft["skill"])
	var r := Crafting.match_recipe(skill, p.craft["ingredients"])
	if r.is_empty() or count < 1 or count > MAX_COUNT:
		_error(p, Protocol.E_NO_RECIPE, Protocol.CRAFT_DO)
		return
	var inv := p.character.inventory
	if Crafting.times_available(r, inv.bag_count) < count:
		_error(p, Protocol.E_MISSING_INGREDIENTS, Protocol.CRAFT_DO)
		return
	for ing: Dictionary in Crafting.ingredients(r):
		for t: Dictionary in inv.take(int(ing["item"]), int(ing["qty"]) * count):
			var left: Dictionary = t["left"]
			p.outbox.append(Protocol.item_added(left) if not left.is_empty() else Protocol.item_removed(int(t["uid"])))
	var item := int(r["resultId"])
	for i in count:
		sim.items.give_item(p, item, 1, false)
	sim.quests.event(p, {"kind": "item"})
	var job := Jobs.job_of(skill)
	var before := slots_of(p, skill)
	var gained := Crafting.xp_gain(r, count)
	var levels := p.character.jobs.gain(job, gained)
	p.outbox.append(Protocol.craft_done(item, count))
	p.outbox.append(Protocol.job_xp(gained, levels, p.character.jobs.view(job)))
	_send_state(p, slots_of(p, skill) != before)
	sim.character_changed(p, Protocol.CRAFT_DO, "")


func on_craft_close(p: PlayerActor) -> void:
	p.craft = {}


func slots_of(p: PlayerActor, skill: int) -> int:
	return Crafting.slots_for_level(p.character.jobs.level(Jobs.job_of(skill)))


func _slots(p: PlayerActor) -> int:
	return slots_of(p, int(p.craft["skill"]))


func _send_state(p: PlayerActor, with_book: bool) -> void:
	var skill := int(p.craft["skill"])
	var r := Crafting.match_recipe(skill, p.craft["ingredients"])
	var result := 0
	var max_count := 0
	if not r.is_empty():
		result = int(r["resultId"])
		max_count = Crafting.times_available(r, p.character.inventory.bag_count)
	var slots := slots_of(p, skill)
	p.outbox.append(Protocol.craft_state(skill, slots, p.character.jobs.view(Jobs.job_of(skill)), p.craft["ingredients"],
			result, max_count, Crafting.book(skill, slots) if with_book else []))


func _error(p: PlayerActor, code: String, cmd: String) -> void:
	p.outbox.append(Protocol.error(code, "", cmd))
