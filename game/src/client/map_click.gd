## Roleplay clicks on the map inside a ClientSession (split out of client_session.gd): what is
## under the mouse (a fight's swords, a monster group, an NPC, an element, a door, the zaap, the
## phoenix, a cell) and the action that waits until the player stands beside it (PendingAction).
##   click: walk · double click (or shift): run, like Dofus
class_name MapClick
extends RefCounted

## a second click this soon (ms) and this close (cells) to the first one turns the walk into a run
const DOUBLE_MS := 350
const DOUBLE_CELLS := 1

var _s: ClientSession
var _last_ms := -100000
var _last_cell := -1


func _init(session: ClientSession) -> void:
	_s = session


## A left click on the map (roleplay); `run` = shift held.
func press(p: Vector2, run: bool) -> void:
	var now := Time.get_ticks_msec()
	var cell := MapGeometry.screen_to_cell(p)
	var double := now - _last_ms <= DOUBLE_MS and cell >= 0 and _last_cell >= 0 and MapGeometry.distance(cell, _last_cell) <= DOUBLE_CELLS
	_last_ms = -100000 if double else now # a third click starts over
	_last_cell = cell
	click(p, run or double)


func click(p: Vector2, run: bool) -> void:
	var pending := _s._pending
	var views := _s.views
	var map := _s.map
	if pending.kind == PendingAction.Kind.INTERACTIVE:
		pending.clear()
	var swords := swords_at(p)
	if swords != null: # a fight on the map: join or watch
		swords.menu(_s, _s.get_viewport().get_mouse_position())
		return
	var group := group_at(p)
	if group >= 0:
		_s.backend.send(Protocol.fight_attack(group))
		return
	var npc := npc_at(p)
	if npc >= 0: # walk beside it (the closest cell), then talk
		var me_cell: int = views[_s.you].dest_cell() if views.has(_s.you) else 0
		var spot := _npc_spot(npc, me_cell)
		pending.set_to(PendingAction.Kind.NPC, npc)
		if spot == me_cell:
			try_pending(_s.backend.time_ms())
		elif spot >= 0:
			_s.backend.send(Protocol.move(spot, run))
		return
	if pending.kind == PendingAction.Kind.NPC:
		pending.clear()
	var cell := MapGeometry.screen_to_cell(p)
	var element := map.interactive_near(cell) if cell >= 0 else {}
	if not element.is_empty(): # a resource: walk beside it (the closest cell), then harvest it
		_walk_beside(int(element["cell"]), cell, PendingAction.Kind.INTERACTIVE, int(element["e"]), run)
		return
	var phoenix := cell >= 0 and _s._map_view.is_phoenix(cell)
	var door := map.door_near(cell) if cell >= 0 else -1
	if door >= 0:
		_walk_beside(door, cell, PendingAction.Kind.TRIGGER, door, run)
		return
	if cell >= 0 and (_s._map_view.is_zaap(cell) or phoenix): # walk beside it (the closest cell), then use it
		_walk_beside(map.phoenix if phoenix else map.zaap, cell, PendingAction.Kind.PHOENIX if phoenix else PendingAction.Kind.ZAAP, -1, run)
		return
	if cell < 0 or not map.is_walkable(cell):
		return
	pending.set_exit(PendingAction.exit_for(map, cell, p))
	var me: ActorView = views[_s.you] if views.has(_s.you) else null
	if me != null and me.dest_cell() == cell and not me.is_moving(_s.backend.time_ms()):
		try_pending(_s.backend.time_ms())
		return
	_s.backend.send(Protocol.move(cell, run))


## Walks to the cell beside `target` closest to the player, then does `kind`.
func _walk_beside(target: int, clicked: int, kind: PendingAction.Kind, arg: int, run: bool) -> void:
	var views := _s.views
	var me_cell: int = views[_s.you].dest_cell() if views.has(_s.you) else clicked
	var near := _s.map.use_cells(target)
	near.sort_custom(func(a: int, b: int) -> bool: return MapGeometry.distance(a, me_cell) < MapGeometry.distance(b, me_cell))
	if near.is_empty():
		return
	_s._pending.set_to(kind, arg)
	if near[0] == me_cell:
		try_pending(_s.backend.time_ms())
	else:
		_s.backend.send(Protocol.move(near[0], run))


## Monster group under the mouse (sprite box around each member), -1 if none.
func group_at(p: Vector2) -> int:
	for id: int in _s.views:
		if _s.views[id] is GroupView:
			for m: ActorView in (_s.views[id] as GroupView).members:
				if Rect2(m.position + Vector2(-35, -110), Vector2(70, 120)).has_point(p):
					return id
	return -1


## The swords of a fight under the mouse, null if none.
func swords_at(p: Vector2) -> FightSwords:
	for v: Node in _s.views.values():
		if v is FightSwords and (v as FightSwords).contains(p):
			return v
	return null


## NPC under the mouse (sprite box), -1 if none.
func npc_at(p: Vector2) -> int:
	for id: int in _s.views:
		if _s.views[id].has_meta("npc") and Rect2(_s.views[id].position + Vector2(-35, -110), Vector2(70, 120)).has_point(p):
			return id
	return -1


## The cell to talk to an NPC from: standing beside it (its own cell excluded), the closest to `from`.
func _npc_spot(npc: int, from: int) -> int:
	var at: int = _s.views[npc].cell
	var near := _s.map.use_cells(at).filter(func(c: int) -> bool: return c != at)
	if near.is_empty():
		return -1
	near.sort_custom(func(a: int, b: int) -> bool: return MapGeometry.distance(a, from) < MapGeometry.distance(b, from))
	return near[0]


## Like the Dofus client: the map change (or the door, the zaap, the NPC, the
## element) is requested once the player has arrived beside its target.
func try_pending(now: int) -> void:
	var pending := _s._pending
	var map := _s.map
	if not pending.is_set() or not _s.views.has(_s.you):
		return
	var me: ActorView = _s.views[_s.you]
	if me.is_moving(now):
		return
	var at := me.dest_cell()
	var t := pending.target
	match pending.kind:
		PendingAction.Kind.NPC:
			if not _s.views.has(t) or MapGeometry.distance(at, _s.views[t].cell) > 1 or at == _s.views[t].cell:
				return
			_s.backend.send(Protocol.npc_talk(t))
		PendingAction.Kind.ZAAP:
			if not map.use_cells(map.zaap).has(at):
				return
			_s.backend.send(Protocol.use_zaap())
		PendingAction.Kind.PHOENIX:
			if not map.use_cells(map.phoenix).has(at):
				return
			_s.backend.send(Protocol.use_phoenix())
		PendingAction.Kind.TRIGGER:
			if not map.use_cells(t).has(at):
				return
			_s.backend.send(Protocol.use_trigger(t))
		PendingAction.Kind.INTERACTIVE:
			var el := map.interactive(t)
			if el.is_empty() or not map.use_cells(int(el["cell"])).has(at):
				return
			_s.backend.send(Protocol.craft_open(int(el["skill"])) if Crafting.is_craft_skill(int(el["skill"])) else Protocol.interactive_use(int(el["e"]), int(el["skill"])))
		PendingAction.Kind.EXIT:
			if not map.can_exit(at, pending.exit):
				return # not there yet (the move may not have started)
			_s.backend.send(Protocol.change_map(pending.exit))
	pending.clear()
