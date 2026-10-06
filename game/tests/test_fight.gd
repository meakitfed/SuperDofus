## Fights: shared rules, effects on a bare Fight, then full scenarios through
## LocalBackend (attack -> placement -> turns -> spells -> end -> rewards).
extends TestCase

const LOOK := "{1|120,2195||56}"


func _init() -> void:
	SpellBook.use_file("res://tests/fixtures/spells.json")


static func _member(hp := 30, extra := {}) -> Dictionary:
	var m := {"look": "{4907|||130}", "name": "Tofu", "level": 3, "hp": hp, "ap": 4, "mp": 3}
	m.merge(extra, true)
	return m


static func _world(monster_hp := 30, extra := {}, count := 2) -> WorldSource:
	var members: Array = []
	for i in count:
		members.append(_member(monster_hp, extra))
	return WorldSource.from_dicts(
		{"id": "arena", "name": "Arena", "start_map": 1, "start_cell": 300, "wander_ms": [600000, 600000]},
		[{"id": 1, "coords": [0, 0], "groups": [{"name": "Tofus", "members": members}]},
		{"id": 2, "coords": [1, 0], "groups": []}])


class Client:
	var backend := LocalBackend.new()
	var events: Array = []
	var you := -1

	func _init(source: WorldSource, store: Persistence = null) -> void:
		backend.sources["arena"] = source
		if store != null:
			backend.persistence = store
		backend.event.connect(func(ev: Dictionary) -> void:
			events.append(ev)
			if ev["t"] == Protocol.WELCOME:
				you = int(ev["you"]))
		backend.send(Protocol.hello("arena", "Tester", LOOK))
		run(0.1)

	func run(seconds: float, step := 0.05) -> void:
		for i in int(seconds / step):
			backend.poll(step)

	func send(cmd: Dictionary) -> void:
		backend.send(cmd)
		run(0.05)

	func take(type: String) -> Array:
		var out := events.filter(func(e: Dictionary) -> bool: return e["t"] == type)
		events = events.filter(func(e: Dictionary) -> bool: return e["t"] != type)
		return out

	func group_id() -> int:
		for a: SimActor in backend.sim.maps[1].actors.values():
			if a is MonsterGroup:
				return a.id
		return -1

	## attack the group and skip the placement
	func start_fight() -> void:
		send(Protocol.fight_attack(group_id()))
		send(Protocol.fight_ready())

	func fight() -> Fight:
		return backend.sim.fights.values()[0] if not backend.sim.fights.is_empty() else null

	func me() -> Fighter:
		return fight().fighters[you]

	func monsters() -> Array:
		return fight().fighters.values().filter(func(f: Fighter) -> bool: return f.team == 1)

	func character() -> Character:
		return (backend.sim.players[you] as PlayerActor).character

	## monsters 3 cells from the player (their 3 MP reach it)
	func bring_monsters() -> void:
		var offsets := [Vector2i(3, 0), Vector2i(0, 3), Vector2i(-3, 0)]
		var i := 0
		for m: Fighter in monsters():
			m.cell = MapGeometry.from_iso(MapGeometry.to_iso(me().cell) + offsets[i])
			i += 1


## A bare fight: `me` (team 0, plays first) next to `foe` (team 1) on an empty map.
class Duel:
	var fight: Fight
	var me := Fighter.new()
	var foe := Fighter.new()
	var events: Array = []

	func _init(spells: Array = [], foe_offset := Vector2i(1, 0)) -> void:
		fight = Fight.new(1, MapData.new(), 7, func(ev: Dictionary) -> void: events.append(ev))
		me.id = 1
		me.cell = 300
		me.hp = 100
		me.max_hp = 100
		me.spells = spells
		foe.id = 2
		foe.team = 1
		foe.cell = MapGeometry.from_iso(MapGeometry.to_iso(300) + foe_offset)
		foe.hp = 100
		foe.max_hp = 100
		foe.ai = false
		fight.add_fighter(me)
		fight.add_fighter(foe)
		fight.start_placement(0)
		fight.begin(0)

	func last(type: String) -> Dictionary:
		for i in range(events.size() - 1, -1, -1):
			if events[i]["t"] == type:
				return events[i]
		return {}


static func _with_spell(spell: Dictionary) -> int:
	SpellBook.get_spell(1) # loads the fixture file
	SpellBook._spells[int(spell["id"])] = spell
	return int(spell["id"])


# ── shared rules ───────────────────────────────────────────────────────────────

func test_rules_reachable_and_path() -> void:
	var m := MapData.new()
	var dist := FightRules.reachable(m, {}, 300, 3)
	eq(dist[300], 0)
	for c: int in dist:
		check(FightRules.distance(300, c) <= 3, "within 3 MP")
	var occupied := {FightRules.neighbors4(300)[0]: true}
	var p := FightRules.path_to(m, occupied, 300, FightRules.neighbors4(300)[0], 3)
	eq(p, [], "cannot walk onto a fighter")
	var far := FightRules.path_to(m, {}, 300, 300 + 28 * 2, 3)
	eq(far, [], "4 steps away needs 4 MP")


func test_rules_area_and_los() -> void:
	var cross := FightRules.area({"area": {"shape": "cross", "size": 1}}, 300)
	eq(cross.size(), 5)
	var m := MapData.new()
	var a := 300
	var mid := MapGeometry.from_iso(MapGeometry.to_iso(a) + Vector2i(2, 0))
	var b := MapGeometry.from_iso(MapGeometry.to_iso(a) + Vector2i(4, 0))
	check(FightRules.has_los(m, {}, a, b), "clear line")
	check(not FightRules.has_los(m, {mid: true}, a, b), "fighter in between blocks")
	m.los_blocked[mid] = true
	check(not FightRules.has_los(m, {}, a, b), "obstacle blocks")
	m.los_blocked.erase(mid)
	m.fight_blocked[mid] = true
	check(FightRules.has_los(m, {}, a, b), "a hole does not block sight")
	var spell := {"ap": 3, "range": [1, 3], "los": true}
	eq(FightRules.cast_error(MapData.new(), {}, spell, a, b, 6), Protocol.E_OUT_OF_RANGE)
	eq(FightRules.cast_error(MapData.new(), {}, spell, a, mid, 2), Protocol.E_NOT_ENOUGH_AP)
	eq(FightRules.cast_error(MapData.new(), {}, spell, a, mid, 6), "")
	spell["range_boost"] = true
	eq(FightRules.cast_error(MapData.new(), {}, spell, a, b, 6, 1), "", "range bonus")


func test_rules_spell_constraints() -> void:
	var m := MapData.new()
	eq(FightRules.area({"area": {"shape": "square", "size": 1}}, 300).size(), 9, "square area")
	eq(FightRules.area({"area": {"shape": "circle", "size": 2}}, 300).size(), 13, "circle = diamond of radius 2")
	eq(FightRules.zone({"shape": "cross_ring", "size": 1}, 300).size(), 4, "cross without centre")
	eq(FightRules.zone({"shape": "ring", "size": 2}, 300).size(), 8, "ring")
	var line := FightRules.zone({"shape": "line", "size": 2}, 300, MapGeometry.from_iso(MapGeometry.to_iso(300) - Vector2i(1, 0)))
	eq(line, [300, MapGeometry.from_iso(MapGeometry.to_iso(300) + Vector2i(1, 0)), MapGeometry.from_iso(MapGeometry.to_iso(300) + Vector2i(2, 0))], "line away from the caster")
	var a := 300
	var diag := MapGeometry.from_iso(MapGeometry.to_iso(a) + Vector2i(2, 1))
	var l3 := MapGeometry.from_iso(MapGeometry.to_iso(a) + Vector2i(3, 0))
	var s := {"ap": 2, "range": [1, 5], "los": false, "in_line": true}
	eq(FightRules.cast_error(m, {}, s, a, diag, 6), Protocol.E_NOT_IN_LINE)
	eq(FightRules.cast_error(m, {}, s, a, l3, 6), "")
	s = {"ap": 2, "range": [1, 5], "los": false, "need_taken_cell": true}
	eq(FightRules.cast_error(m, {}, s, a, l3, 6), Protocol.E_NEEDS_TARGET)
	eq(FightRules.cast_error(m, {l3: true}, s, a, l3, 6), "")
	s = {"ap": 2, "range": [1, 5], "los": false, "need_free_cell": true}
	eq(FightRules.cast_error(m, {l3: true}, s, a, l3, 6), Protocol.E_CELL_NOT_FREE)


func test_rules_criterion() -> void:
	check(FightRules.criterion_ok("", []), "empty")
	check(FightRules.criterion_ok("HS=498", [498]), "has state")
	check(not FightRules.criterion_ok("HS=498", []), "missing state")
	check(FightRules.criterion_ok("HS!8&HS!3536", [498]), "not in states")
	check(FightRules.criterion_ok("HS=3|(HS=3531&HS!534)", [3531]), "or / parentheses")
	check(not FightRules.criterion_ok("HS=3|(HS=3531&HS!534)", [3531, 534]), "and inside parentheses")
	check(FightRules.criterion_ok("PL>50", []), "unknown terms pass")


# ── effects on a bare fight ────────────────────────────────────────────────────

func test_spell_effects_respect_teams() -> void:
	var d := Duel.new([_with_spell({"id": 900, "ap": 1, "range": [0, 2], "los": false, "per_turn": 9,
			"area": {"shape": "circle", "size": 1},
			"effects": [{"kind": "heal", "min": 10, "max": 10, "target": "allies"},
					{"kind": "damage", "min": 10, "max": 10, "target": "enemies"}]})])
	d.me.hp = 50
	d.foe.hp = 50
	eq(d.fight.cast(d.me, 900, 300, 0), "")
	eq(d.me.hp, 60, "ally healed only")
	eq(d.foe.hp, 40, "enemy damaged only")
	SpellBook._spells.erase(900)


func test_damage_uses_stats_resistances_and_shield() -> void:
	var d := Duel.new([_with_spell({"id": 901, "ap": 1, "range": [1, 1], "los": false, "per_turn": 9,
			"effects": [{"kind": "damage", "element": "earth", "min": 10, "max": 10, "target": "enemies"}]})])
	d.me.stats = {"strength": 100, "damage": 2} # 10 x 200% + 2 = 22
	d.foe.stats = {"res_earth": 50} # -> 11
	eq(d.fight.cast(d.me, 901, d.foe.cell, 0), "")
	eq(d.foe.hp, 89, "stats and resistances")
	var b := Buff.new()
	b.kind = "shield"
	b.value = 5
	b.turns = 2
	d.foe.buffs.append(b)
	d.fight.cast(d.me, 901, d.foe.cell, 0)
	var eff: Dictionary = d.last(Protocol.SPELL_CAST)["effects"][0]
	eq(int(eff["shield"]), 5, "shield absorbs first")
	eq(d.foe.hp, 83)
	eq(d.foe.shield(), 0)
	SpellBook._spells.erase(901)


func test_critical_hit_uses_critical_effects() -> void:
	var d := Duel.new([_with_spell({"id": 902, "ap": 1, "range": [1, 1], "los": false, "per_turn": 9, "crit": 100,
			"effects": [{"kind": "damage", "min": 1, "max": 1, "target": "enemies"}],
			"crit_effects": [{"kind": "damage", "min": 30, "max": 30, "target": "enemies"}]})])
	d.fight.cast(d.me, 902, d.foe.cell, 0)
	check(bool(d.last(Protocol.SPELL_CAST)["crit"]), "critical")
	eq(d.foe.hp, 70)
	SpellBook._spells.erase(902)


func test_push_and_collision_damage() -> void:
	var d := Duel.new([5])
	var behind := MapGeometry.from_iso(MapGeometry.to_iso(d.foe.cell) + Vector2i(1, 0))
	var wall := MapGeometry.from_iso(MapGeometry.to_iso(behind) + Vector2i(1, 0))
	d.fight.map.fight_blocked[wall] = true
	eq(d.fight.cast(d.me, 5, d.foe.cell, 0), "")
	eq(d.foe.cell, behind, "pushed until the wall")
	var effects: Array = d.last(Protocol.SPELL_CAST)["effects"]
	eq(effects[0]["kind"], "move")
	eq(effects[1]["kind"], "damage", "collision")
	eq(int(effects[1]["amount"]), 8, "(level/2 + 32) x 1 cell / 4")


func test_mp_buff_lasts_until_the_casters_next_turn() -> void:
	var d := Duel.new([6])
	eq(d.fight.cast(d.me, 6, d.me.cell, 0), "")
	eq(d.me.mp, 5, "+2 MP now")
	d.fight.end_turn(0) # foe's turn
	d.fight.end_turn(0) # my turn: the buff runs out
	eq(d.me.mp, 3, "back to 3 MP")
	var ends: Array = d.last(Protocol.FIGHT_TURN)["effects"]
	eq(ends.size(), 1)
	eq(ends[0]["kind"], "buff_end")


func test_ap_loss_applies_on_the_targets_turn() -> void:
	var d := Duel.new([8])
	d.fight.cast(d.me, 8, d.foe.cell, 0)
	d.fight.end_turn(0)
	eq(d.foe.ap, 4, "6 - 2 AP for its turn")
	d.fight.end_turn(0)
	d.fight.end_turn(0)
	eq(d.foe.ap, 6, "expired")


func test_poison_ticks_at_the_targets_turn() -> void:
	var d := Duel.new([7])
	d.fight.cast(d.me, 7, d.foe.cell, 0)
	eq(d.foe.hp, 100, "nothing yet")
	d.fight.end_turn(0)
	eq(d.foe.hp, 95, "ticks when it starts playing")
	var eff: Array = d.last(Protocol.FIGHT_TURN)["effects"]
	eq(eff[0]["kind"], "damage")
	d.fight.end_turn(0)
	d.fight.end_turn(0)
	eq(d.foe.hp, 90)
	d.fight.end_turn(0)
	d.fight.end_turn(0)
	eq(d.foe.hp, 90, "2 turns only")


func test_tackle_costs_mp() -> void:
	var d := Duel.new()
	d.foe.stats = {"agility": 100} # tackle 10 vs escape 0: keeps 2 / 24 of its MP
	var away := MapGeometry.from_iso(MapGeometry.to_iso(300) - Vector2i(1, 0))
	eq(d.fight.move(d.me, away, 0), "")
	var mv := d.last(Protocol.FIGHTER_MOVE)
	eq(int(mv["lost"]["mp"]), 3, "all MP lost")
	eq((mv["path"] as Array).size(), 1, "did not move")
	eq(d.me.cell, 300)
	check(d.me.ap < 6, "AP lost too")


func test_cooldown_per_target_and_criterion() -> void:
	var d := Duel.new([9, 10])
	eq(d.fight.cast(d.me, 9, d.foe.cell, 0), "")
	eq(d.fight.cast(d.me, 9, d.foe.cell, 0), Protocol.E_SPELL_COOLDOWN)
	eq(int(d.me.cooldowns[9]), 2, "available in 2 turns")
	d.fight.end_turn(0)
	d.fight.end_turn(0)
	check(d.fight.cast(d.me, 9, d.foe.cell, 0) != "", "still 1 turn")
	d.fight.end_turn(0)
	d.fight.end_turn(0)
	eq(d.fight.cast(d.me, 9, d.foe.cell, 0), "", "available again")
	eq(d.fight.cast(d.me, 10, d.foe.cell, 0), Protocol.E_SPELL_CONDITION)
	var st := Buff.new()
	st.kind = "state"
	st.state = 77
	st.turns = -1
	d.me.buffs.append(st)
	eq(d.fight.cast(d.me, 10, d.foe.cell, 0), "", "state 77 allows it")


func test_state_effects_and_conditions() -> void:
	var d := Duel.new([_with_spell({"id": 903, "ap": 1, "range": [1, 1], "los": false, "per_turn": 9,
			"effects": [{"kind": "damage", "min": 10, "max": 10, "target": "enemies", "cond": [{"who": "caster", "state": 5, "has": false}]},
					{"kind": "state", "state": 5, "target": "caster", "duration": -1},
					{"kind": "damage", "min": 30, "max": 30, "target": "enemies", "cond": [{"who": "caster", "state": 5, "has": true}]}]})])
	d.fight.cast(d.me, 903, d.foe.cell, 0)
	eq(d.foe.hp, 90, "sober variant only: conditions are read at cast time")
	check(d.me.has_state(5), "state set")
	d.fight.cast(d.me, 903, d.foe.cell, 0)
	eq(d.foe.hp, 60, "state variant")
	SpellBook._spells.erase(903)


func test_initiative_decides_who_starts() -> void:
	var d := Duel.new()
	eq(int(d.fight.order[0]), 1, "tie: players first")
	d.foe.stats = {"agility": 200}
	d.fight.prepare()
	eq(int(d.fight.order[0]), 2, "the faster team starts")


# ── scenarios ──────────────────────────────────────────────────────────────────

func test_attack_starts_placement_then_fight() -> void:
	var c := Client.new(_world())
	c.take(Protocol.MAP_ENTER)
	c.send(Protocol.fight_attack(c.group_id()))
	var start := c.take(Protocol.FIGHT_START)
	eq(start.size(), 1, "fight_start")
	eq(int(start[0]["you"]), c.you)
	eq((start[0]["fighters"] as Array).size(), 3, "player + 2 monsters")
	eq(start[0]["phase"], "placement")
	var mine: Array = start[0]["placement"]["0"]
	check(mine.size() >= 2, "placement cells")
	eq(c.take(Protocol.FIGHT_TURN).size(), 0, "no turn during placement")
	var other := int(mine[1]) if int(mine[0]) == c.me().cell else int(mine[0])
	c.send(Protocol.fight_place(other))
	eq(c.take(Protocol.FIGHTER_PLACED).size(), 1)
	eq(c.me().cell, other)
	c.send(Protocol.fight_move(310))
	eq(c.take(Protocol.ERROR).size(), 1, "no moves before the fight starts")
	c.send(Protocol.fight_ready())
	eq(c.take(Protocol.FIGHT_BEGIN).size(), 1)
	var turn := c.take(Protocol.FIGHT_TURN)
	eq(int(turn[0]["id"]), c.you, "player plays first")
	eq(int(turn[0]["ap"]), 6)
	c.send(Protocol.move(310))
	eq(c.take(Protocol.ERROR).size(), 1, "no roleplay moves in fight")


func test_placement_times_out() -> void:
	var c := Client.new(_world())
	c.send(Protocol.fight_attack(c.group_id()))
	c.run(Fight.PLACEMENT_MS / 1000.0 + 0.5, 0.25)
	eq(c.take(Protocol.FIGHT_BEGIN).size(), 1, "starts without ready")


func test_move_costs_mp() -> void:
	var c := Client.new(_world())
	c.start_fight()
	var me := c.me()
	for m: Fighter in c.monsters(): # far from the player: no tackle
		m.cell = MapGeometry.from_iso(MapGeometry.to_iso(me.cell) + Vector2i(6, 6))
	var dist := FightRules.reachable(c.fight().map, c.fight().occupied(me.id), me.cell, 3)
	var target := -1
	for cell: int in dist:
		if dist[cell] == 2:
			target = cell
			break
	c.send(Protocol.fight_move(target))
	var mv := c.take(Protocol.FIGHTER_MOVE)
	eq(mv.size(), 1)
	eq(int(mv[0]["mp"]), 1)
	eq(me.cell, target)
	c.send(Protocol.fight_move(me.cell + 28 * 3))
	eq(c.take(Protocol.ERROR).size(), 1, "not enough MP")


func test_monsters_walk_and_attack() -> void:
	var c := Client.new(_world(30, {"spells": [1]}))
	c.start_fight()
	c.bring_monsters()
	c.take(Protocol.FIGHT_TURN)
	c.send(Protocol.fight_end_turn())
	c.run(12.0, 0.1)
	var casts := c.take(Protocol.SPELL_CAST).filter(func(e: Dictionary) -> bool: return int(e["caster"]) != c.you)
	check(not casts.is_empty(), "a monster punched the player")
	check(c.me().hp < c.me().max_hp, "player hurt")
	var turns := c.take(Protocol.FIGHT_TURN).map(func(e: Dictionary) -> int: return int(e["id"]))
	check(turns.size() >= 3 and turns[2] == c.you, "monster, monster, player again: %s" % [turns])


func test_defeat_sends_back_to_start_with_1_hp() -> void:
	var c := Client.new(_world(500, {"spells": [1], "ap": 9}))
	c.backend.sim.players[c.you].character.set_hp(20, c.backend.time_ms())
	c.backend.sim.info["start_map"] = 2 # respawn point elsewhere
	c.start_fight()
	c.bring_monsters()
	for i in 30:
		if not c.take(Protocol.FIGHT_END).is_empty():
			break
		c.send(Protocol.fight_end_turn())
		c.run(6.0, 0.1)
	var ch := c.character()
	eq(c.backend.sim.players[c.you].fight_id, 0, "fight over")
	eq(c.backend.sim.players[c.you].map_id, 2, "at the world's start map")
	check(ch.hp_at(c.backend.time_ms()) <= 20, "back with 1 HP (+ regen)")
	check(not c.take(Protocol.PLAYER_STATS).is_empty(), "stats sent")


func test_victory_rewards_xp_kamas_drops() -> void:
	var extra := {"xp": 1000, "kamas": [10, 10], "drops": [{"item": 519, "pct": 100}]}
	var c := Client.new(_world(5, extra))
	var group := c.group_id()
	var start_cell: int = c.backend.sim.players[c.you].cell
	c.take(Protocol.MAP_ENTER)
	c.start_fight()
	var me := c.me()
	var mons := c.monsters()
	var around := FightRules.neighbors4(me.cell).filter(func(x: int) -> bool: return c.fight().map.is_fight_walkable(x))
	for i in mons.size():
		mons[i].cell = around[i]
	c.send(Protocol.fight_cast(1, mons[0].cell))
	var casts := c.take(Protocol.SPELL_CAST)
	eq(casts.size(), 1, "spell cast")
	check(bool(casts[0]["effects"][0]["died"]), "5 hp monster dies")
	c.send(Protocol.fight_cast(1, mons[1].cell))
	c.run(0.1)
	var end := c.take(Protocol.FIGHT_END)
	eq(end.size(), 1)
	eq(end[0]["result"], "win")
	var r: Dictionary = end[0]["rewards"][0]
	eq(int(r["xp_gained"]), 2000, "2 x 1000 XP, level coefficient 1, solo bonus 1")
	eq(int(r["level"]), 4, "2000 XP = level 4")
	eq(int(r["level_up"]), 3)
	eq(int(r["kamas"]), 20)
	eq((r["items"] as Array).map(func(i: Dictionary) -> Array: return [int(i["id"]), int(i["qty"])]), [[519, 2]], "100% drops")
	var ch := c.character()
	eq(ch.level, 4)
	eq(ch.capital, 15)
	eq(ch.inventory.count(519), 2)
	eq(ch.hp_at(c.backend.time_ms()), ch.max_hp(), "level up heals")
	var enter := c.take(Protocol.MAP_ENTER)
	eq(enter.size(), 1, "back on the map")
	eq(c.backend.sim.players[c.you].cell, start_cell, "where the fight started")
	var ids := (enter[0]["actors"] as Array).map(func(a: Dictionary) -> int: return int(a["id"]))
	check(not ids.has(group), "beaten group is gone")
	var stats := c.take(Protocol.PLAYER_STATS)
	eq(int(stats[-1]["stats"]["level"]), 4)
	c.run(21.0, 0.25)
	eq(c.take(Protocol.ACTOR_ADD).size(), 1, "group respawns")


func test_character_is_saved_and_boosts() -> void:
	var store := Persistence.new()
	var extra := {"xp": 1000}
	var c := Client.new(_world(5, extra), store)
	c.start_fight()
	for m: Fighter in c.monsters():
		m.hp = 0
		m.alive = false
	c.fight()._check_end()
	c.run(0.1)
	eq(c.character().level, 4)
	c.send(Protocol.boost_stat("vitality"))
	eq(int(c.character().stats["vitality"]), 1)
	eq(c.character().capital, 14)
	c.send(Protocol.boost_stat("wisdom"))
	eq(c.character().capital, 11, "wisdom costs 3")
	c.backend.close()
	var again := Client.new(_world(), store)
	var st := again.take(Protocol.PLAYER_STATS)
	eq(int(st[0]["stats"]["level"]), 4, "level kept")
	eq(int(st[0]["stats"]["stats"]["vitality"]), 1)
	eq(int(st[0]["stats"]["capital"]), 11)


func test_hp_regenerates_out_of_fight() -> void:
	var ch := Character.new()
	eq(ch.max_hp(), 55, "50 + 5 x level")
	ch.set_hp(10, 1000)
	eq(ch.hp_at(1000), 10)
	eq(ch.hp_at(6000), 15, "1 HP / s")
	eq(ch.hp_at(999999), 55, "capped")


func test_cast_rules_enforced() -> void:
	var c := Client.new(_world())
	c.start_fight()
	var me := c.me()
	c.send(Protocol.fight_cast(1, me.cell)) # range 1 spell on own cell: out of range
	eq(c.take(Protocol.ERROR).size(), 1)
	c.send(Protocol.fight_cast(99, me.cell))
	eq(c.take(Protocol.ERROR).size(), 1, "unknown spell")
	c.send(Protocol.fight_cast(4, me.cell)) # heal self: allowed (range 0)
	eq(c.take(Protocol.SPELL_CAST).size(), 1)
	c.send(Protocol.fight_cast(4, me.cell))
	eq(c.take(Protocol.ERROR).size(), 1, "once per turn")


func test_abandon_puts_group_back() -> void:
	var c := Client.new(_world())
	var group := c.group_id()
	c.take(Protocol.MAP_ENTER)
	c.send(Protocol.fight_attack(group))
	c.send(Protocol.fight_leave())
	c.run(0.1)
	var end := c.take(Protocol.FIGHT_END)
	eq(end[0]["result"], "abandon")
	eq(end[0]["rewards"][0]["xp_gained"], 0.0, "nothing for an abandon")
	var enter := c.take(Protocol.MAP_ENTER)
	var ids := (enter[0]["actors"] as Array).map(func(a: Dictionary) -> int: return int(a["id"]))
	check(ids.has(group), "group back on the map")
