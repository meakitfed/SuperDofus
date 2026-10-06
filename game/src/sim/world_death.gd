## Death and ghosts (P1.10), a WorldSim handler.
class_name WorldDeath
extends WorldHandler

## What a ghost cannot do. APPROX(P1.10): Dofus 2 behaviour (a ghost only
## walks to a phoenix), the Dofus 3 list is server-side
const GHOST_FORBIDDEN := [Protocol.FIGHT_ATTACK, ProtocolWatch.JOIN, Protocol.INTERACTIVE_USE, Protocol.CRAFT_OPEN, Protocol.USE_ZAAP, Protocol.ZAAP_TRAVEL, Protocol.SET_SAVE_POINT,
		Protocol.USE_ITEM, Protocol.EQUIP, Protocol.UNEQUIP, Protocol.SHOP_BUY, Protocol.SHOP_SELL]


## use_phoenix: a ghost next to the phoenix of the map comes back to life with
## Energy.PHOENIX energy (shown to everyone: it re-enters the map).
func on_use_phoenix(p: PlayerActor, map: MapInstance) -> void:
	var err := ""
	if not p.character.is_ghost():
		err = Protocol.E_NOT_GHOST
	elif map.data.phoenix < 0 or not map.data.use_cells(map.data.phoenix).has(p.dest_cell()):
		err = Protocol.E_NOT_AT_PHOENIX
	if err != "":
		p.outbox.append(Protocol.error(err, "", Protocol.USE_PHOENIX))
		return
	p.character.life = Energy.ALIVE
	p.character.energy = maxi(p.character.energy, Energy.PHOENIX)
	p.settle(sim.now)
	sim.teleport(p, map.data.id, p.cell)
	p.outbox.append(Protocol.info(Protocol.I_RESURRECTED))
	p.outbox.append(Protocol.player_stats(p.character.public_dict(sim.now)))


## After a lost fight: back to the save point (1 HP and the energy loss are already
## applied by the fight's end), then the messages that go with it (a ghost at 0: Energy).
func after_defeat(p: PlayerActor, energy_lost: int) -> void:
	var sp := sim.travel.save_point(p.character)
	sim.enter_map(p, sim.get_map(sp[0]), sp[1])
	p.outbox.append(Protocol.info(Protocol.I_ENERGY_LOST, [energy_lost]))
	if p.character.is_ghost():
		p.outbox.append(Protocol.info(Protocol.I_GHOST))
	elif p.character.energy < Energy.LOW:
		p.outbox.append(Protocol.info(Protocol.I_ENERGY_LOW, [p.character.energy]))
