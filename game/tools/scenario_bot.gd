## A scripted player used to record scenarios (sim_cli --bot). It plays like
## a client: it only reads protocol events and sends protocol commands, with
## the shared rules (FightRules, SpellBook) to choose. Placement: ready at
## once. Its turn: summon once per fight (a spell with a summon effect, on a free
## cell next to it), cast its spells on the nearest enemy while it can, else
## walk towards it, then end the turn. Carrying someone (P1.12, Karcham), it
## throws it with its first throw spell on the free cell nearest to the enemy.
## A trap spell (P1.13a) is laid once per fight, on the way of the nearest enemy
## (the free cell nearest to it, at least 2 cells from the bot). A spell with a
## triggered effect (P1.13b, `on`) is cast first, once per fight, on the nearest enemy.
## A spell that makes invisible (P1.13c) is cast on itself once per fight, before anything.
## Bombs (P1.13d): a bomb is summoned on the free cell nearest the enemy (at least 3 cells
## from the bot) whenever it has none, and a spell that sets bombs off is then cast on its own bomb.
## Portals (P1.13f): with no portal, one on the free cell nearest to it; with one, a spell
## that places a portal under its target and sends it through (Exil) on the enemy; then, an
## enemy standing on one of its portals, an attack on another portal of its (projected).
## mode "fight": plays; "pass": always ends its turn (to record a defeat); "fight:<spells.id>"
## (P1.13e): plays, that spell first on the nearest enemy whenever it can, walking to it if needed.
class_name ScenarioBot
extends RefCounted

const WAIT_AFTER_MOVE_MS := 1500

var mode := "fight"
var you := -1 # fighter id in the current fight
var map: MapData
var fighters := {} # id -> {team, cell, alive, ap, mp, spells}
var my_turn := false
var waiting := false
var wait_until := 0
var ready_sent := false
var summoned := false
var carrying := false
var trapped := false
var triggered := false
var hidden := false
var portals := {} # my portals: mark id -> cell
var prefer := 0 # spells.id cast first ("fight:<id>")
var _seen := 0


func _init(p_mode := "fight") -> void:
	mode = p_mode.get_slice(":", 0)
	if p_mode.contains(":"):
		prefer = int(p_mode.get_slice(":", 1))


## Scenario driver: (backend, events so far, commands to send).
func drive(backend: GameBackend, events: Array, out: Array) -> void:
	while _seen < events.size():
		_on_event(events[_seen]["ev"], backend.time_ms())
		_seen += 1
	if you < 0:
		return
	if not ready_sent:
		ready_sent = true
		out.append(Protocol.fight_ready(true))
		return
	if not my_turn or waiting or backend.time_ms() < wait_until:
		return
	out.append(_decide())
	waiting = true


func _on_event(ev: Dictionary, now: int) -> void:
	match str(ev["t"]):
		Protocol.MAP_ENTER:
			map = MapData.from_dict(ev["map"])
		Protocol.FIGHT_START:
			you = int(ev["you"])
			ready_sent = false
			summoned = false
			carrying = false
			trapped = false
			triggered = false
			hidden = false
			portals.clear()
			fighters.clear()
			for f: Dictionary in ev["fighters"]:
				fighters[int(f["id"])] = {"team": int(f["team"]), "cell": int(f["cell"]), "alive": bool(f["alive"]),
						"ap": int(f["ap"]), "mp": int(f["mp"]), "spells": (f["spells"] as Array).map(func(s: Variant) -> int: return int(s))}
		Protocol.FIGHTER_PLACED:
			if fighters.has(int(ev["id"])):
				fighters[int(ev["id"])]["cell"] = int(ev["cell"])
		Protocol.FIGHT_TURN:
			my_turn = int(ev["id"]) == you
			waiting = false
			if my_turn:
				fighters[you]["ap"] = int(ev["ap"])
				fighters[you]["mp"] = int(ev["mp"])
			_apply_effects(ev.get("effects", []))
		Protocol.FIGHTER_MOVE:
			var id := int(ev["id"])
			var path: Array = ev["path"]
			if fighters.has(id) and not path.is_empty():
				fighters[id]["cell"] = int(path[-1])
				fighters[id]["mp"] = int(ev["mp"])
			if id == you:
				waiting = false
				wait_until = now + WAIT_AFTER_MOVE_MS
		Protocol.SPELL_CAST:
			if int(ev["caster"]) == you:
				fighters[you]["ap"] = int(ev["ap"])
				waiting = false
			_apply_effects(ev["effects"])
		Protocol.ERROR:
			if my_turn: # refused: stop trying this turn
				waiting = false
				fighters[you]["ap"] = 0
				fighters[you]["mp"] = 0
		Protocol.FIGHT_END:
			you = -1
			my_turn = false


func _apply_effects(effects: Array) -> void:
	for e: Dictionary in effects:
		var t := int(e.get("target", -1))
		if str(e.get("kind", "")) == "summon":
			var f: Dictionary = e["fighter"]
			fighters[t] = {"team": int(f["team"]), "cell": int(f["cell"]), "alive": true, "ap": int(f["ap"]),
					"mp": int(f["mp"]), "spells": [], "mine": int(e.get("summoner", -1)) == you}
		if not fighters.has(t):
			continue
		if str(e.get("kind", "")) == "mark_add" and e["mark"]["kind"] == "portal" and int(e["mark"]["caster"]) == you:
			portals[int(e["mark"]["id"])] = int(e["mark"]["cell"])
		elif str(e.get("kind", "")) == "mark_remove":
			portals.erase(int(e["mark"]))
		match str(e.get("kind", "")):
			"carry":
				fighters[t]["carried"] = true
				carrying = carrying or int(e["carrier"]) == you
			"throw", "drop":
				fighters[t]["carried"] = false
				fighters[t]["cell"] = int(e.get("to", e.get("cell", fighters[t]["cell"])))
				carrying = carrying and int(e["carrier"]) != you
		if e.get("died", false):
			fighters[t]["alive"] = false
		if e.has("path") and not (e["path"] as Array).is_empty():
			fighters[t]["cell"] = int(e["path"][-1])


func _occupied(except: int) -> Dictionary:
	var occ := {}
	for id: int in fighters:
		if id != except and fighters[id]["alive"]:
			occ[int(fighters[id]["cell"])] = true
	return occ


func _decide() -> Dictionary:
	var me: Dictionary = fighters[you]
	if mode == "pass":
		return Protocol.fight_end_turn()
	var target := -1
	var best := 1 << 30
	for id: int in fighters:
		var f: Dictionary = fighters[id]
		if f["alive"] and int(f["team"]) != int(me["team"]) and not f.get("carried", false):
			var d := FightRules.distance(int(me["cell"]), int(f["cell"]))
			if d < best:
				best = d
				target = int(f["cell"])
	var occ := _occupied(you)
	if carrying:
		return _throw(me, occ, target if target >= 0 else int(me["cell"]))
	if target < 0:
		return Protocol.fight_end_turn()
	if not hidden:
		for sid: int in me["spells"]:
			var spell := SpellBook.get_spell(sid)
			if (spell.get("effects", []) as Array).any(func(e: Dictionary) -> bool: return (e.get("flags", []) as Array).has("invisible")) 					and FightRules.cast_error(map, occ, spell, int(me["cell"]), int(me["cell"]), int(me["ap"])) == "":
				hidden = true
				return Protocol.fight_cast(sid, int(me["cell"]))
	if not trapped:
		for sid: int in me["spells"]:
			var spell := SpellBook.get_spell(sid)
			if not (spell.get("effects", []) as Array).any(func(e: Dictionary) -> bool: return str(e.get("kind", "")) == "trap"):
				continue
			var cells := FightRules.targetable(map, occ, spell, int(me["cell"])).filter(
					func(c: int) -> bool: return FightRules.distance(c, int(me["cell"])) >= 2)
			cells.sort_custom(func(a: int, b: int) -> bool:
				return FightRules.distance(a, target) < FightRules.distance(b, target) or (FightRules.distance(a, target) == FightRules.distance(b, target) and a < b))
			if not cells.is_empty() and int(spell.get("ap", 0)) <= int(me["ap"]):
				trapped = true
				return Protocol.fight_cast(sid, cells[0])
	var has_bomb := fighters.values().any(func(f: Dictionary) -> bool: return f.get("mine", false) and f["alive"])
	if not summoned or not has_bomb:
		for sid: int in me["spells"]:
			var spell := SpellBook.get_spell(sid)
			if not (spell.get("effects", []) as Array).any(func(e: Dictionary) -> bool: return str(e.get("kind", "")) == "summon") 					or (summoned and not _bomb(spell)):
				continue
			var cells: Array = FightRules.reachable(map, occ, int(me["cell"]), 2).keys()
			cells.sort_custom(func(a: int, b: int) -> bool: return FightRules.distance(a, int(me["cell"])) < FightRules.distance(b, int(me["cell"])))
			if _bomb(spell): # near the enemy, out of its explosion
				cells = FightRules.targetable(map, occ, spell, int(me["cell"])).filter(
						func(c: int) -> bool: return not occ.has(c) and FightRules.distance(c, int(me["cell"])) >= 3)
				cells.sort_custom(func(a: int, b: int) -> bool:
					return FightRules.distance(a, target) < FightRules.distance(b, target) or (FightRules.distance(a, target) == FightRules.distance(b, target) and a < b))
			for c: int in cells:
				if not occ.has(c) and FightRules.cast_error(map, occ, spell, int(me["cell"]), c, int(me["ap"])) == "":
					summoned = true
					return Protocol.fight_cast(sid, c)
	for sid: int in me["spells"]: # sets its own bomb off
		var spell := SpellBook.get_spell(sid)
		if not (spell.get("effects", []) as Array).any(func(e: Dictionary) -> bool: return str(e.get("kind", "")) == "detonate"):
			continue
		for id: int in fighters:
			var f: Dictionary = fighters[id]
			if f.get("mine", false) and f["alive"] \
					and FightRules.cast_error(map, occ, spell, int(me["cell"]), int(f["cell"]), int(me["ap"])) == "":
				return Protocol.fight_cast(sid, int(f["cell"]))
	if prefer > 0:
		for sid: int in me["spells"]:
			var spell := SpellBook.get_spell(sid)
			if int(spell.get("spell", spell.get("origin", 0))) != prefer:
				continue
			if FightRules.cast_error(map, occ, spell, int(me["cell"]), target, int(me["ap"])) == "":
				return Protocol.fight_cast(sid, target)
			if int(me["mp"]) > 0 and int(spell.get("ap", 99)) <= int(me["ap"]):
				var goal := int(me["cell"])
				for c: int in FightRules.reachable(map, occ, int(me["cell"]), int(me["mp"])):
					if FightRules.distance(c, target) < FightRules.distance(goal, target):
						goal = c
				if goal != int(me["cell"]):
					me["mp"] = 0
					return Protocol.fight_move(goal)
	var portal := _portals(me, occ, target)
	if not portal.is_empty():
		return portal
	var spells: Array = me["spells"].duplicate()
	if not triggered: # the spells with a triggered effect first
		spells.sort_custom(func(a: int, b: int) -> bool: return _triggers(a) and not _triggers(b))
	for sid: int in spells:
		var spell := SpellBook.get_spell(sid)
		if spell.is_empty() or not (spell.get("bar", true)) or (spell.get("effects", []) as Array).is_empty() or _bomb(spell) 				or (spell["effects"] as Array).any(func(e: Dictionary) -> bool: return str(e.get("kind", "")) in ["detonate", "portal", "unportal", "teleportal"]):
			continue
		if FightRules.cast_error(map, occ, spell, int(me["cell"]), target, int(me["ap"])) == "":
			triggered = triggered or _triggers(sid)
			return Protocol.fight_cast(sid, target)
	if int(me["mp"]) > 0:
		var cells := FightRules.reachable(map, occ, int(me["cell"]), int(me["mp"]))
		var goal := int(me["cell"])
		for c: int in cells:
			if FightRules.distance(c, target) < FightRules.distance(goal, target):
				goal = c
		if goal != int(me["cell"]):
			me["mp"] = 0 # one move per turn is enough for this bot
			return Protocol.fight_move(goal)
	return Protocol.fight_end_turn()


func _triggers(sid: int) -> bool:
	return (SpellBook.get_spell(sid).get("effects", []) as Array).any(func(e: Dictionary) -> bool: return e.has("on"))


## Throws the carried fighter on the free cell nearest to `target`.
func _throw(me: Dictionary, occ: Dictionary, target: int) -> Dictionary:
	var states := [FightRules.CARRIER_STATE]
	for sid: int in me["spells"]:
		var spell := SpellBook.get_spell(sid)
		if not (spell.get("effects", []) as Array).any(func(e: Dictionary) -> bool: return str(e.get("kind", "")) == "throw") 				or not FightRules.criterion_ok(str(spell.get("criterion", "")), states) or int(spell.get("ap", 0)) > int(me["ap"]):
			continue
		var cells := FightRules.targetable(map, occ, FightRules.for_caster(spell, states), int(me["cell"]))
		if cells.is_empty():
			continue
		cells.sort_custom(func(a: int, b: int) -> bool:
			return FightRules.distance(a, target) < FightRules.distance(b, target) or (FightRules.distance(a, target) == FightRules.distance(b, target) and a < b))
		return Protocol.fight_cast(sid, cells[0])
	return Protocol.fight_end_turn()


## Portals (see the header): the command, {} if none.
func _portals(me: Dictionary, occ: Dictionary, target: int) -> Dictionary:
	var kinds := func(sid: int) -> Array:
		return (SpellBook.get_spell(sid).get("effects", []) as Array).map(func(e: Dictionary) -> String: return str(e.get("kind", "")))
	for sid: int in me["spells"]:
		var k: Array = kinds.call(sid)
		var spell := SpellBook.get_spell(sid)
		if portals.is_empty() and k.has("portal") and not k.has("teleportal") and not k.has("damage"): # Portail: next to me
			var cells := FightRules.targetable(map, occ, spell, int(me["cell"]))
			cells.sort_custom(func(a: int, b: int) -> bool:
				return FightRules.distance(a, int(me["cell"])) < FightRules.distance(b, int(me["cell"])) \
						or (FightRules.distance(a, int(me["cell"])) == FightRules.distance(b, int(me["cell"])) and a < b))
			if not cells.is_empty():
				return Protocol.fight_cast(sid, cells[0])
		if portals.size() == 1 and k.has("portal") and k.has("teleportal") \
				and FightRules.cast_error(map, occ, spell, int(me["cell"]), target, int(me["ap"])) == "":
			return Protocol.fight_cast(sid, target) # Exil: under the enemy, which comes out of my portal
	if portals.size() < 2 or not portals.values().has(target):
		return {}
	for sid: int in me["spells"]: # an attack projected onto the enemy
		var k: Array = kinds.call(sid)
		if not k.has("damage") or k.has("portal") or k.has("teleportal") or k.has("unportal"):
			continue
		for cell: int in portals.values():
			var through := occ.duplicate()
			through[cell] = true # the sim lets a spell needing a fighter target a portal
			if cell != target and not occ.has(cell) \
					and FightRules.cast_error(map, through, SpellBook.get_spell(sid), int(me["cell"]), cell, int(me["ap"])) == "":
				return Protocol.fight_cast(sid, cell)
	return {}


## `spell` summons a bomb (SpellBook.summon: it has an explosion).
func _bomb(spell: Dictionary) -> bool:
	return (spell.get("effects", []) as Array).any(func(e: Dictionary) -> bool:
		return str(e.get("kind", "")) == "summon" and SpellBook.summon(int(e.get("monster", 0))).has("explode"))
