## Jobs: harvesting (P2.05), a WorldSim handler.
class_name WorldJobs
extends WorldHandler

## What stops a harvest: the player does something else.
const CANCELLED_BY := [Protocol.MOVE, Protocol.CHANGE_MAP, Protocol.USE_TRIGGER, Protocol.USE_ZAAP,
		Protocol.ZAAP_TRAVEL, Protocol.NPC_TALK, Protocol.FIGHT_ATTACK, ProtocolWatch.JOIN, ProtocolWatch.SPECTATE, Protocol.ADMIN_CMD, Protocol.INTERACTIVE_USE]


## Each tick: the harvests that end.
func tick() -> void:
	for p: PlayerActor in sim.players.values():
		if not p.harvest.is_empty():
			tick_harvest(p)


## interactive_use: harvest the element beside the player. The element is busy for
## Jobs.HARVEST_MS (counted from the arrival if the player is still walking), then it
## gives its resource (tick_harvest) and stays gone until it grows back (Jobs.RESPAWN_MS).
func on_interactive_use(p: PlayerActor, map: MapInstance, element: int, skill: int) -> void:
	var el := map.interactives.element(element)
	var err := ""
	if el.is_empty() or int(el["skill"]) != skill or not Jobs.is_gathering(skill):
		err = Protocol.E_NO_ELEMENT
	elif not map.data.use_cells(int(el["cell"])).has(p.dest_cell()):
		err = Protocol.E_NOT_AT_ELEMENT
	else:
		err = Jobs.check(skill, p.character.jobs.level(Jobs.job_of(skill)))
		if err == "" and not map.interactives.available(element, p.id):
			err = Protocol.E_ELEMENT_BUSY
	if err != "":
		p.outbox.append(Protocol.error(err, "", Protocol.INTERACTIVE_USE))
		return
	var start := p.t0 + Movement.duration_ms(p.path, p.run) if p.is_moving(sim.now) else sim.now
	p.harvest = {"map": map.data.id, "element": element, "skill": skill, "end": start + Jobs.HARVEST_MS}
	map.interactives.claim(element, p.id)
	map.broadcast(Protocol.interactive_start(p.id, element, skill, int(p.harvest["end"])))


## A harvest ends: the resource, the job XP, the element gone. Cancelled if the player left.
func tick_harvest(p: PlayerActor) -> void:
	var map := sim.get_map(int(p.harvest["map"]))
	if p.fight_id != 0 or p.map_id != int(p.harvest["map"]) or map == null:
		cancel_harvest(p)
		return
	if sim.now < int(p.harvest["end"]):
		return
	var element := int(p.harvest["element"])
	var skill := int(p.harvest["skill"])
	p.harvest = {}
	var job := Jobs.job_of(skill)
	var qty := Jobs.roll_quantity(skill, p.character.jobs.level(job), sim.rng)
	var until := map.interactives.deplete(element, sim.now)
	map.broadcast(Protocol.interactive_end(p.id, element, true))
	map.broadcast(Protocol.interactive_state(element, false, until))
	sim.items.give_item(p, Jobs.item_of(skill), qty)
	var gained := Jobs.xp_gain(skill)
	var levels := p.character.jobs.gain(job, gained)
	p.outbox.append(Protocol.job_xp(gained, levels, p.character.jobs.view(job)))
	sim.character_changed(p, Protocol.INTERACTIVE_USE, "")


func cancel_harvest(p: PlayerActor) -> void:
	if p.harvest.is_empty():
		return
	var element := int(p.harvest["element"])
	var map := sim.get_map(int(p.harvest["map"]))
	p.harvest = {}
	if map != null:
		map.interactives.release(element, p.id)
		map.broadcast(Protocol.interactive_end(p.id, element, false))
