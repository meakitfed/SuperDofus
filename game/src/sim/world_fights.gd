## Fights of a world (WorldSim handler): they start (attack or aggression), the events
## of a fight reach its players, they end with rewards. The fights themselves are
## `Fight` (sim/fight/); WorldSim.fights keeps them.
class_name WorldFights
extends WorldHandler

## fight id -> MonsterGroup being fought
var _groups := {}


func on_fight_attack(p: PlayerActor, map: MapInstance, group_id: int) -> void:
	var g: SimActor = map.actors.get(group_id)
	if not g is MonsterGroup:
		p.outbox.append(Protocol.error(Protocol.E_NO_TARGET, "no monster group %d here" % group_id, Protocol.FIGHT_ATTACK))
		return
	start_fight(p, map, g as MonsterGroup)


## Each tick: the fights advance, the ones that ended are settled.
func tick() -> void:
	for f: Fight in sim.fights.values():
		f.tick(sim.now)
		if f.result != "":
			finish_fight(f)


## A fight against a group: the player attacked it, or it attacked them (aggression).
func start_fight(p: PlayerActor, map: MapInstance, group: MonsterGroup) -> void:
	p.settle(sim.now)
	group.settle(sim.now)
	p.return_cell = p.cell
	map.remove_actor(group)
	map.remove_actor(p)
	var fight_id := sim.alloc_id()
	var fight := Fight.new(fight_id, map.data, hash([sim.seed, sim.now, group.id]), fight_emit.bind(fight_id))
	group.bonus = sim.stars.bonus(group.subarea, map.data.area, sim.clock.now_unix_ms())
	fight.reward_rate = 1.0 + group.bonus / 100.0 # luaformulas 99 rewardRate
	var pf := player_fighter(p)
	_place(fight, map, p, group, pf)
	fight.add_fighter(pf)
	var spots := _placement_spots(fight.placement[1], group.cell, group.members.size())
	for i in spots.size():
		var mf := monster_fighter(group.members[i])
		mf.cell = spots[i]
		mf.dir = MapGeometry.facing(mf.cell, pf.cell) if mf.cell != pf.cell else 1
		fight.add_fighter(mf)
	pf.dir = MapGeometry.facing(pf.cell, spots[0]) if not spots.is_empty() else pf.dir
	sim.fights[fight.id] = fight
	_groups[fight.id] = group
	p.fight_id = fight.id
	sim.trade.cancel_for(p, ProtocolTrade.REASON_FIGHT)
	sim.watch.on_fight_started(fight, map, group.cell)
	fight.prepare()
	fight.start_placement(sim.now)
	p.outbox.append(Protocol.fight_start(fight.id, pf.id, fight.fighters_dicts(), fight.order,
			fight.placement_dict(), fight.placement_end))
	if bool(sim.info.get("challenges", false)): # world.json "challenges": the real worlds (P1.15)
		fight.draw_challenges()
		if not fight.challenges.is_empty():
			p.outbox.append(Protocol.challenge_list(fight.challenges))


## The placement cells of both teams, and the player's starting cell.
## Dofus placement cells when the map has them (players red, monsters blue).
func _place(fight: Fight, map: MapInstance, p: PlayerActor, group: MonsterGroup, pf: Fighter) -> void:
	var red: Array = map.data.placement.get("red", [])
	var blue: Array = map.data.placement.get("blue", [])
	if red.size() >= 1 and blue.size() >= group.members.size():
		fight.placement = {0: red.duplicate(), 1: blue.duplicate()}
		pf.cell = _closest(red, p.cell)
		return
	fight.placement = {0: _fight_spots(map.data, p.cell, {}, 6)}
	pf.cell = fight.placement[0][0] if not fight.placement[0].is_empty() else p.cell
	var taken := {}
	for c: int in fight.placement[0]:
		taken[c] = true
	fight.placement[1] = _fight_spots(map.data, group.cell, taken, maxi(group.members.size(), 1) + 2)


func player_fighter(p: PlayerActor) -> Fighter:
	var c := p.character
	var f := Fighter.new()
	f.id = p.id
	f.player_id = p.id
	f.breed = c.breed
	f.team = 0
	f.name = p.name
	f.looks = p.looks
	f.level = c.level
	f.max_hp = c.max_hp()
	f.hp = maxi(1, c.hp_at(sim.now))
	f.max_ap = c.max_ap()
	f.max_mp = c.max_mp()
	f.ap = f.max_ap
	f.mp = f.max_mp
	f.stats = c.fight_stats()
	f.spells = c.known_spells()
	# the weapon hit (Equipment.weapon_spell), or "Coup de poing" (spells 0) bare-handed
	var weapon: Dictionary = c.inventory.worn().get(Equipment.WEAPON, {})
	var hit := Equipment.weapon_spell(int(weapon["id"])) if not weapon.is_empty() else {}
	if not hit.is_empty():
		f.own_spells[Equipment.WEAPON_SPELL] = hit
		f.spells.append(Equipment.WEAPON_SPELL)
	elif not SpellBook.grade_ids(0).is_empty():
		f.spells.append(SpellBook.grade_for(0, c.level))
	var states: Array = SpellBook.start_states(c.breed).duplicate()
	for sid: int in f.spells: # the chosen variant's states (Eliotrope Portail / Errance, P1.13f)
		for st: Variant in f.spell(sid).get("start_states", []):
			if not states.has(int(st)):
				states.append(int(st))
	for st: int in states:
		var b := Buff.new()
		b.kind = "state"
		b.state = st
		b.turns = -1
		b.caster = f.id
		f.buffs.append(b)
	return f


## A monster of a group (world data member: stats, res, spells, xp, kamas, drops are optional).
func monster_fighter(m: Dictionary) -> Fighter:
	var f := Fighter.new()
	f.id = sim.alloc_id()
	f.team = 1
	f.ai = true
	f.name = str(m.get("name", "Monstre"))
	f.name_id = int(m.get("name_id", 0))
	f.monster = int(m.get("monster", 0)) # target masks F / f (P1.13d)
	f.can_switch = bool(m.get("switch", true)) # P1.13n, monsters.m_flags bits 9 / 10 (maps.py)
	f.can_switch_on_target = bool(m.get("switch_on_target", true))
	f.grade = int(m.get("grade", 1))
	f.portrait = int(m.get("portrait", 0))
	f.looks = PackedStringArray([str(m.get("look", ""))])
	f.level = int(m.get("level", 1))
	f.max_hp = int(m.get("hp", 40))
	f.hp = f.max_hp
	f.max_ap = maxi(0, int(m.get("ap", 5)))
	f.max_mp = maxi(0, int(m.get("mp", 3)))
	f.ap = f.max_ap
	f.mp = f.max_mp
	var st: Dictionary = m.get("stats", {})
	for k: String in st:
		f.stats[k] = int(st[k])
	var res: Dictionary = m.get("res", {})
	for k: String in res:
		f.stats["res_" + k] = int(res[k])
	f.spells = (m.get("spells", []) as Array).map(func(s: Variant) -> int: return int(s)) \
			.filter(func(s: int) -> bool: return not SpellBook.get_spell(s).is_empty())
	# official monster XP formula (luaformulas 2) when the data has none (hand-made worlds)
	f.loot = {"xp": int(m.get("xp", FightXp.monster_xp(f.level))),
			"kamas": m.get("kamas", [f.level, f.level * 3]), "drops": m.get("drops", [])}
	return f


static func _closest(cells: Array, to: int) -> int:
	var best: int = cells[0]
	for c: int in cells:
		if MapGeometry.distance(c, to) < MapGeometry.distance(best, to):
			best = c
	return best


static func _placement_spots(cells: Array, near: int, count: int) -> Array[int]:
	var sorted := cells.duplicate()
	sorted.sort_custom(func(a: int, b: int) -> bool: return MapGeometry.distance(a, near) < MapGeometry.distance(b, near))
	var out: Array[int] = []
	for c: int in sorted.slice(0, count):
		out.append(c)
	return out


## Free cells for the monster team, closest to the group first.
func _fight_spots(data: MapData, center: int, taken: Dictionary, count: int) -> Array[int]:
	var dist := FightRules.reachable(data, taken, center if not taken.has(center) else data.nearest_walkable(center), 8)
	var cells := dist.keys().filter(func(c: int) -> bool: return not taken.has(c) and data.is_fight_walkable(c))
	cells.sort_custom(func(a: int, b: int) -> bool: return dist[a] < dist[b] or (dist[a] == dist[b] and a < b))
	var out: Array[int] = []
	for c: int in cells.slice(0, count):
		out.append(c)
	return out


func fight_emit(ev: Dictionary, fight_id: int) -> void:
	var fight: Fight = sim.fights.get(fight_id)
	if fight == null:
		return
	for f: Fighter in fight.fighters.values(): # each one its team's view (FightVisibility)
		if f.player_id >= 0 and sim.players.has(f.player_id):
			(sim.players[f.player_id] as PlayerActor).outbox.append(FightVisibility.view(ev, fight, f.team))
	for pid: int in fight.spectators: # no seat: they see what neither team hides (P3.04)
		if sim.players.has(pid):
			(sim.players[pid] as PlayerActor).outbox.append(FightVisibility.view(ev, fight, -1))


## Rewards, then players go back where they were (a defeat sends them to the
## world's start with 1 HP); a beaten group respawns later, otherwise it is back.
func finish_fight(fight: Fight) -> void:
	if not sim.fights.has(fight.id):
		return
	sim.fights.erase(fight.id)
	var group: MonsterGroup = _groups.get(fight.id)
	_groups.erase(fight.id)
	var map := sim.get_map(group.map_id)
	sim.watch.on_fight_finished(fight, map)
	if fight.result == "win":
		map.schedule_respawn(group, sim.now)
		sim.stars.on_defeat(group.subarea, map.data.area, sim.clock.now_unix_ms())
	else:
		group.next_think = sim.now + map.wander_ms.x
		map.add_actor(group, sim.now)
	var rewards: Array = []
	var fought := _reward_players(fight, rewards)
	for p: PlayerActor in fought:
		p.fight_id = 0
		p.outbox.append(Protocol.fight_end(fight.result, sim.now - fight.started_at, rewards))
		if fight.result == "lose": # back to the save point, 1 HP, energy lost (a ghost at 0: Energy)
			var r: Dictionary = rewards.filter(func(x: Dictionary) -> bool: return int(x["id"]) == p.id).front()
			sim.death.after_defeat(p, int(r["energy_lost"]))
		else:
			sim.enter_map(p, sim.get_map(p.map_id), map.data.nearest_walkable(p.return_cell))
		sim.quests.event(p, {"kind": "fight", "win": fight.result == "win", "map": map.data.id,
				"monsters": group.members.map(func(m: Dictionary) -> int: return int(m.get("monster", 0)))})
		p.outbox.append(Protocol.player_stats(p.character.public_dict(sim.now)))
		sim.save_player(p)


## Gives the gains (FightRewards) to the players of a fight, fills `rewards` with the
## fight_end entries and returns the players who fought.
func _reward_players(fight: Fight, rewards: Array) -> Array:
	var gains := FightRewards.compute(fight)
	var fought: Array = []
	for f: Fighter in fight.fighters.values():
		var p: PlayerActor = sim.players.get(f.player_id)
		if p == null or f.left: # a fighter who fled earlier is already back on the map (P3.04)
			continue
		fought.append(p)
		var c := p.character
		var g: Dictionary = gains.get(f.id, {"xp": 0, "kamas": 0, "items": {}})
		c.set_hp(1 if fight.result == "lose" else maxi(1, f.hp), sim.now)
		var energy_lost := c.lose_energy(Energy.defeat_loss(c.level)) if fight.result == "lose" else 0
		var ups := c.gain_xp(int(g["xp"]), sim.now)
		c.kamas += int(g["kamas"])
		var items: Array = []
		for item: int in g["items"]:
			sim.items.give_item(p, item, int(g["items"][item]))
			items.append({"id": item, "qty": int(g["items"][item])})
		rewards.append({"id": f.id, "name": f.name, "level": c.level, "level_up": ups, "xp_gained": int(g["xp"]),
				"xp": c.xp, "xp_floor": GameData.xp_floor(c.level), "xp_next": GameData.xp_next(c.level),
				"kamas": int(g["kamas"]), "items": items, "hp": c.hp_at(sim.now), "max_hp": c.max_hp(),
				"energy": c.energy, "energy_lost": energy_lost,
				"challenge_bonus": roundi((FightChallenges.coefficient(fight) - 1.0) * 100.0) if fight.result == "win" else 0})
	return fought
