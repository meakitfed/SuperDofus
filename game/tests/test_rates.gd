## The server's rates (S.06, WorldRates): XP, drop, kamas and job XP multipliers, and the
## Temporis-like bonus drops (BonusDrops), apart from the normal drops. Standalone
## (LocalBackend.rates_options) and over the network (ServerHost on 127.0.0.1).
extends TestCase

const LOOK := "{1|120,2195||56}"
const STEP := 0.05
const LARVA := 31 # Larve Bleue: tied to the Larva set (33) by its resources


## A fight with players 1.. and monsters 11.., foes all killed, then won.
class Arena extends SpellArena:
	func _init(rates: WorldRates, allies := 1, foes := 2, foe_level := 16) -> void:
		var layout := {}
		for i in allies:
			layout["p%d" % i] = {"at": Vector2i(-i, 0), "team": 0, "id": 1 + i, "level": 20, "hp": 100}
		for i in foes:
			layout["m%d" % i] = {"at": Vector2i(3 + i, 2), "team": 1, "id": 11 + i, "level": foe_level, "hp": 100,
					"monster": LARVA, "ai": false}
		super(0, layout)
		fight.rates = rates
		for f: Fighter in fight.fighters.values():
			if f.team == 0:
				f.player_id = f.id
			else:
				f.loot = {"xp": 1000, "kamas": [50, 50], "drops": [{"item": 362, "pct": 10.0}]}
		for f: Fighter in fight.fighters.values():
			if f.team == 1:
				f.hp = 0
				f.alive = false
		fight._finish("win")


static func _rates(opts: Dictionary) -> WorldRates:
	return WorldRates.from_options(opts)


func test_options() -> void:
	var r := _rates({"xp-rate": "3", "drop-rate": "2.5", "bonus-drops": "1", "bonus-drop-range": "10"})
	near(r.xp, 3.0)
	near(r.drop, 2.5)
	near(r.kamas, 1.0)
	check(r.bonus_drops, "--bonus-drops turns them on")
	eq(r.bonus_range, 10)
	check(not r.is_default())
	check(WorldRates.new().is_default(), "the defaults change nothing")
	check(not _rates({"bonus-drops": "0"}).bonus_drops, "--bonus-drops=0 keeps them off")
	eq(WorldRates.check_options({"xp-rate": "3", "bonus-drops": "1"}), "")
	check(WorldRates.check_options({"xp-rate": "-1"}) != "", "a negative rate is refused")
	check(WorldRates.check_options({"drop-rate": "abc"}) != "", "a rate that is not a number is refused")
	eq(r.to_dict()["bonus_range"], 10)
	check(not WorldRates.new().to_dict().has("bonus_rate"), "no bonus fields while they are off")
	eq(_rates({"job-xp-rate": "2"}).job_xp_of(15), 30)
	eq(WorldRates.new().job_xp_of(15), 15)


func test_rates_multiply_xp_kamas_and_drops() -> void:
	var base: Dictionary = FightRewards.compute(Arena.new(WorldRates.new()).fight)[1]
	check(not base.has("bonus_items"), "no bonus drops by default")
	var boosted: Dictionary = FightRewards.compute(Arena.new(_rates({"xp-rate": "2", "kamas-rate": "3"})).fight)[1]
	eq(int(boosted["xp"]), int(base["xp"]) * 2, "XP x2")
	eq(int(base["kamas"]), 100)
	eq(int(boosted["kamas"]), 300, "kamas x3")
	# drop chance 10 % x 10 = 100 %: both monsters drop
	var drops: Dictionary = FightRewards.compute(Arena.new(_rates({"drop-rate": "10"})).fight)[1]
	eq(int(drops["items"].get(362, 0)), 2, "drop rate x10 on a 10 % drop")


func test_bonus_drops_are_apart() -> void:
	if BonusDrops.sets_of(LARVA).is_empty():
		skip("no data/bonus_drops.json (python tools/extractor/gamedata.py bonus_drops)")
		return
	var plain: Dictionary = FightRewards.compute(Arena.new(WorldRates.new()).fight)[1]
	var r := _rates({"bonus-drops": "1", "bonus-drop-rate": "100"})
	var got: Dictionary = FightRewards.compute(Arena.new(r).fight)[1]
	eq(got["items"], plain["items"], "the normal drops are rolled the same, before the bonus")
	eq(got["xp"], plain["xp"])
	var bonus: Dictionary = got["bonus_items"]
	var n := 0
	var sets := BonusDrops.set_items([LARVA])
	var free := BonusDrops.equipment_between(16 - 15, 16 + 15)
	for item: int in bonus:
		n += int(bonus[item])
		check(sets.has(item) or free.has(item), "item %d is from the Larva sets or an equipment at +-15 levels" % item)
		var lv := int(GameData.item(item).get("level", 0))
		check(sets.has(item) or (lv >= 1 and lv <= 31), "level %d within the range" % lv)
	eq(n, 2, "100 %: one bonus item per monster killed")
	var none: Dictionary = FightRewards.compute(Arena.new(_rates({"bonus-drops": "1", "bonus-drop-rate": "0"})).fight)[1]
	eq((none["bonus_items"] as Dictionary).size(), 0, "0 %: none")


func test_bonus_drops_data() -> void:
	if BonusDrops.sets_of(LARVA).is_empty():
		skip("no data/bonus_drops.json")
		return
	check(BonusDrops.sets_of(LARVA).has(33), "Larve Bleue -> the Larva set (Larvamulette)")
	check(BonusDrops.sets_of(101).has(1), "Bouftou -> the Bouftou set (Coiffe du Bouftou)")
	for item: int in BonusDrops.equipment_between(50, 60):
		var it := GameData.item(item)
		check(not it.has("set"), "equipment without a set")
		check(int(it["level"]) >= 50 and int(it["level"]) <= 60, "level in range")


## A world with one group of Larves (S.06 scenario), played in standalone or on a server.
static func _arena_world() -> WorldSource:
	var member := {"look": "{4907|||130}", "name": "Larve", "monster": LARVA, "level": 16, "hp": 100, "ap": 4, "mp": 3,
			"xp": 500, "kamas": [10, 10]}
	return WorldSource.from_dicts(
		{"id": "arena", "name": "Arena", "start_map": 1, "start_cell": 300, "wander_ms": [600000, 600000]},
		[{"id": 1, "coords": [0, 0], "groups": [{"name": "Larves", "members": [member, member, member]}]}])


## Attacks the group, kills it and returns fight_end (events: the client's list).
func _win(events: Array, send: Callable, pump: Callable, fights: Callable) -> Dictionary:
	var first := func(t: String) -> Dictionary:
		for e: Dictionary in events:
			if e["t"] == t:
				return e
		return {}
	pump.call(func() -> bool: return not first.call(Protocol.MAP_ENTER).is_empty())
	var group := -1
	for a: Dictionary in first.call(Protocol.MAP_ENTER).get("actors", []):
		if a["kind"] == "monster_group":
			group = int(a["id"])
	check(group >= 0, "a group on the map")
	send.call(Protocol.fight_attack(group))
	pump.call(func() -> bool: return not first.call(Protocol.FIGHT_START).is_empty())
	send.call(Protocol.fight_ready())
	pump.call(func() -> bool: return not first.call(Protocol.FIGHT_BEGIN).is_empty())
	var list: Array = fights.call()
	if list.is_empty():
		fail("no fight")
		return {}
	var fight: Fight = list[0]
	for f: Fighter in fight.fighters.values():
		if f.team == 1:
			f.hp = 0
			f.alive = false
	fight._finish("win")
	pump.call(func() -> bool: return not first.call(Protocol.FIGHT_END).is_empty())
	return first.call(Protocol.FIGHT_END)


func _check_fight_end(end: Dictionary, events: Array, what: String) -> void:
	var welcome: Dictionary = events.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.WELCOME)[0]
	var rates: Dictionary = welcome["world"].get("rates", {})
	near(float(rates.get("xp", 0)), 2.0, 0.0005, what + " welcome.world.rates")
	check(bool(rates.get("bonus_drops", false)), what + " bonus drops announced")
	check(not end.is_empty(), what + " fight_end")
	if end.is_empty():
		return
	var mine: Dictionary = end["rewards"][0]
	var n := 0
	for it: Dictionary in mine.get("bonus_items", []):
		n += int(it["qty"])
	eq(n, 3, what + " one bonus item per Larve")
	eq(int(mine["kamas"]), 60, what + " kamas x2")


func test_standalone_rates() -> void:
	if BonusDrops.sets_of(LARVA).is_empty():
		skip("no data/bonus_drops.json")
		return
	var backend := LocalBackend.new()
	backend.sources["arena"] = _arena_world()
	backend.rates_options = {"xp-rate": "2", "kamas-rate": "2", "bonus-drops": "1", "bonus-drop-rate": "100"}
	var events: Array = []
	backend.event.connect(func(ev: Dictionary) -> void: events.append(ev))
	backend.send(Protocol.hello("arena", "Tester", LOOK))
	var pump := func(until: Callable) -> void:
		for i in 200:
			backend.poll(STEP)
			if until.call():
				return
	var end := _win(events, backend.send, pump, func() -> Array: return backend.sim.fights.values())
	_check_fight_end(end, events, "standalone:")
	eq(LocalBackend.schema_errors.size(), 0, "every event matches Protocol.SCHEMA")
	backend.close()


func test_server_rates_over_the_network() -> void:
	if BonusDrops.sets_of(LARVA).is_empty():
		skip("no data/bonus_drops.json")
		return
	var host := ServerHost.new()
	host.server.sources["arena"] = _arena_world()
	host.server.rates = WorldRates.from_options({"xp-rate": "2", "kamas-rate": "2", "bonus-drops": "1", "bonus-drop-rate": "100"})
	host.listen(0, "127.0.0.1")
	var net := NetBackend.new()
	net.validate_events = true
	var clock := {"ms": 0}
	net.ticks = func() -> int: return clock["ms"]
	var events: Array = []
	net.event.connect(func(ev: Dictionary) -> void: events.append(ev))
	net.connect_to("127.0.0.1:%d" % host.local_port())
	net.send(Protocol.hello("arena", "Tester", LOOK))
	var pump := func(until: Callable) -> void:
		for i in 400:
			clock["ms"] += int(STEP * 1000.0)
			host.poll(STEP)
			net.poll(STEP)
			if until.call():
				return
	var end := _win(events, net.send, pump, func() -> Array: return host.server.worlds["arena"].fights.values())
	_check_fight_end(end, events, "server:")
	eq(net.schema_errors.size(), 0, "every event matches Protocol.SCHEMA: %s" % [net.schema_errors])
	net.close()
	host.shutdown()
