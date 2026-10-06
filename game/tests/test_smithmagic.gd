## P2.07: forgemagie. Smithmagic (rules, deterministic by seed) and fm_apply through LocalBackend.
## Item 758 = Cape du Justicier (Vitalité 31-40, Puissance 21-30, Soins 4-5), runes: 7436 Rune Pui (+1 Puissance,
## weight 2), 1523 Rune Vi (+5 Vitalité, weight 1), 1519 Rune Fo (+1 Force, weight 1), 1557 Rune Ga Pa (+1 PA, weight 100).
extends TestCase

const CAPE := 758
const PUI := 7436
const VI := 1523
const FO := 1519
const PA := 1557
const BOISAILLE := 44


func _init() -> void:
	SpellBook.use_file("")
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()


class Conn:
	var backend := LocalBackend.new()
	var events: Array = []

	func _init(items: Array) -> void:
		var server := LocalServer.new()
		server.persistence.save_character("incarnam", "Eli", {"level": 20, "items": items})
		backend.server = server
		backend.event.connect(func(ev: Dictionary) -> void: events.append(ev))
		backend.send(Protocol.hello("incarnam", "Eli"))
		backend.poll(0.0)

	func send(cmd: Dictionary) -> Array:
		events = []
		backend.send(cmd)
		backend.poll(0.0)
		return events

	func of(type: String) -> Array:
		return events.filter(func(e: Dictionary) -> bool: return e["t"] == type)

	func code() -> String:
		var errs := of(Protocol.ERROR)
		return "" if errs.is_empty() else str(errs[0]["code"])

	func inv() -> Inventory:
		return backend.sim.players[backend.player_id].character.inventory


static func _cape(uid := 101, qty := 1, pos := -1) -> Dictionary:
	return {"uid": uid, "id": CAPE, "qty": qty, "pos": pos, "effects": [[125, 35, 0, 0], [138, 25, 0, 0], [178, 4, 0, 0]]}


static func _rune(uid: int, id: int, qty: int) -> Dictionary:
	return {"uid": uid, "id": id, "qty": qty, "pos": -1, "effects": []}


func test_runes_are_read_from_the_data() -> void:
	eq(Smithmagic.rune_info(FO), {"effect": 118, "amount": 1, "weight": 100})
	eq(int(Smithmagic.rune_info(VI)["weight"]), 100, "5 Vitalité = 1 weight, like the Rune Vi")
	eq(int(Smithmagic.rune_info(1548)["weight"]), 300, "Rune Pa Vi = 3 weight")
	eq(int(Smithmagic.rune_info(PA)["weight"]), 10000)
	check(Smithmagic.rune_info(CAPE).is_empty(), "an equipment is no rune")
	check(Smithmagic.runes().size() >= 40, "the runes we simulate: %d" % Smithmagic.runes().size())
	check(Smithmagic.forgeable(CAPE))
	check(not Smithmagic.forgeable(6679), "a Touffe de Féca has no characteristic")
	check(not Smithmagic.forgeable(FO), "a rune is not forged")
	eq(Smithmagic.maximum(CAPE, 125), 40)
	eq(Smithmagic.maximum(CAPE, 118), 0)


func test_chance_falls_towards_the_maximum() -> void:
	eq(Smithmagic.chance(10, 40), 83)
	eq(Smithmagic.chance(40, 40), 30)
	check(Smithmagic.chance(30, 30) >= Smithmagic.MIN_CHANCE)


func test_overmax_needs_the_puits() -> void:
	var fx := _cape()["effects"] as Array
	eq(Smithmagic.preview(CAPE, fx, 0, FO)["refused"], Smithmagic.ERR_RESERVE, "Force is not on the cape: exotic")
	eq(Smithmagic.preview(CAPE, fx, 99, FO)["refused"], Smithmagic.ERR_RESERVE, "puits below the weight of the rune")
	eq(Smithmagic.preview(CAPE, fx, 100, FO)["refused"], "")
	eq(Smithmagic.preview(CAPE, fx, 1_000_000, PA)["refused"], "", "PA: +1 over a maximum of 0 is allowed")
	var r := Smithmagic.apply(CAPE, fx, 250, FO, RandomNumberGenerator.new())
	eq(r["outcome"], Smithmagic.OVERMAX)
	eq(int(r["reserve"]), 150, "the puits pays the rune")
	eq(Smithmagic.value_of(r["effects"], 118), 1, "the exotic characteristic appears")
	eq(Smithmagic.value_of(r["effects"], 125), 35, "the others are untouched")
	eq(Smithmagic.preview(CAPE, r["effects"], 1_000_000, PA)["refused"], "")
	var two := Smithmagic.apply(CAPE, r["effects"], 1_000_000, PA, RandomNumberGenerator.new())
	eq(Smithmagic.preview(CAPE, two["effects"], 1_000_000, PA)["refused"], Smithmagic.ERR_RESERVE, "PA, PM and Portée: one over, no more")
	eq(Smithmagic.preview(CAPE, fx, 0, 1)["refused"], Smithmagic.ERR_RUNE, "not a rune")
	eq(Smithmagic.preview(6679, fx, 0, FO)["refused"], Smithmagic.ERR_ITEM)


func test_distribution_is_deterministic_and_balanced() -> void:
	# Puissance 25 -> 26 of 30: chance 100 - 70 * 26 / 30 = 40, crit 4: crit 4 %, success 36 %, neutral 30 %, fail 30 %
	var runs := func(seed_value: int) -> Dictionary:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var counts := {Smithmagic.CRIT: 0, Smithmagic.SUCCESS: 0, Smithmagic.NEUTRAL: 0, Smithmagic.FAIL: 0}
		for i in 4000:
			var r := Smithmagic.apply(CAPE, _cape()["effects"], 0, PUI, rng)
			counts[r["outcome"]] += 1
		return counts
	var a: Dictionary = runs.call(7)
	eq(a, runs.call(7), "same seed, same distribution")
	check(a != runs.call(8), "another seed")
	check(absi(int(a[Smithmagic.CRIT]) - 160) < 60, "crit about 4 %%: %d" % a[Smithmagic.CRIT])
	check(absi(int(a[Smithmagic.SUCCESS]) - 1440) < 150, "success about 36 %%: %d" % a[Smithmagic.SUCCESS])
	check(absi(int(a[Smithmagic.NEUTRAL]) - 1200) < 150, "neutral about 30 %%: %d" % a[Smithmagic.NEUTRAL])
	check(absi(int(a[Smithmagic.FAIL]) - 1200) < 150, "fail about 30 %%: %d" % a[Smithmagic.FAIL])


func test_each_outcome_moves_the_weight() -> void:
	var rng := RandomNumberGenerator.new()
	var seen := {}
	for i in 400:
		rng.seed = i
		var before := _cape()["effects"] as Array
		var r := Smithmagic.apply(CAPE, before, 0, PUI, rng)
		var o: String = r["outcome"]
		seen[o] = true
		var pui := Smithmagic.value_of(r["effects"], 138) - 25
		var gained_weight := pui * 200
		var lost_weight := 0
		for l: Array in r["lost"]:
			lost_weight += int(l[1]) * int(Smithmagic.WEIGHTS[int(l[0])])
		match o:
			Smithmagic.CRIT:
				eq(pui, 1)
				eq(r["lost"], [], "a critical costs nothing")
				eq(int(r["reserve"]), 0)
			Smithmagic.SUCCESS:
				eq(pui, 1)
				check(lost_weight >= 200, "the other characteristics pay the rune: %d" % lost_weight)
				eq(int(r["reserve"]), 0)
			Smithmagic.NEUTRAL:
				eq(r["effects"], before)
				eq(int(r["reserve"]), 0)
			Smithmagic.FAIL:
				eq(pui, 0)
				eq(int(r["reserve"]), lost_weight, "what a failure takes fills the puits")
				check(lost_weight >= 200, "lost %d" % lost_weight)
		eq(gained_weight == 0 or o == Smithmagic.CRIT or o == Smithmagic.SUCCESS, true)
	eq(seen.size(), 4, "the four outcomes show up")


func test_fm_apply_through_the_backend() -> void:
	var c := Conn.new([_cape(101, 1), _rune(102, PUI, 5), _rune(103, FO, 1), {"uid": 104, "id": 6679, "qty": 1, "pos": -1, "effects": []}])
	check(c.inv().bag_count(PUI) == 5)
	c.send(Protocol.fm_apply(101, PUI))
	eq(c.code(), "")
	var res := c.of(Protocol.FM_RESULT)
	eq(res.size(), 1)
	check(res[0]["outcome"] in [Smithmagic.CRIT, Smithmagic.SUCCESS, Smithmagic.NEUTRAL, Smithmagic.FAIL])
	eq(c.inv().bag_count(PUI), 4, "the rune is spent")
	eq(JSON.stringify(Protocol.roundtrip({"e": c.inv().get_item(101)["effects"]})), JSON.stringify({"e": res[0]["item"]["effects"]}))
	# exotic rune with an empty puits: refused, the rune stays
	var fresh := Conn.new([_cape(101, 1), _rune(102, PUI, 60), _rune(103, FO, 1)])
	fresh.send(Protocol.fm_apply(101, FO))
	eq(fresh.code(), Protocol.E_FM_RESERVE)
	eq(fresh.inv().bag_count(FO), 1, "a refused rune is not spent")
	# a puits filled by failures pays an overmax
	var guard := 0
	while int(fresh.inv().get_item(101).get("reserve", 0)) < 100 and guard < 55:
		fresh.send(Protocol.fm_apply(101, PUI))
		guard += 1
	check(int(fresh.inv().get_item(101).get("reserve", 0)) >= 100, "failures fill the puits")
	fresh.send(Protocol.fm_apply(101, FO))
	eq(fresh.code(), "")
	eq(fresh.of(Protocol.FM_RESULT)[0]["outcome"], Smithmagic.OVERMAX)
	eq(Smithmagic.value_of(fresh.inv().get_item(101)["effects"], 118), 1)
	c.send(Protocol.fm_apply(104, PUI))
	eq(c.code(), Protocol.E_FM_ITEM, "no characteristic to forge")
	c.send(Protocol.fm_apply(101, CAPE))
	eq(c.code(), Protocol.E_FM_RUNE, "the cape is no rune")
	c.send(Protocol.fm_apply(999, PUI))
	eq(c.code(), Protocol.E_UNKNOWN_ITEM)


func test_a_stack_gives_one_item_and_the_puits_follows() -> void:
	var c := Conn.new([_cape(101, 3), _rune(102, PUI, 30)])
	var seen_reserve := false
	for i in 20:
		c.send(Protocol.fm_apply(101, PUI))
		var forged := c.of(Protocol.FM_RESULT)[0]["item"] as Dictionary
		eq(int(forged["qty"]), 1)
		eq(int(c.inv().get_item(101)["qty"]) + (1 if forged["uid"] != 101 else 0) >= 1, true)
		if int(forged.get("reserve", 0)) > 0:
			seen_reserve = true
			var inv := c.inv()
			check(inv.find_stack(CAPE, forged["effects"], 0) != int(forged["uid"]), "an item with a puits never joins a stack without")
			break
	check(seen_reserve, "a failure showed up")
	eq(c.inv().count(CAPE), 3, "no item lost or created")


func test_worn_item_is_refused() -> void:
	var c := Conn.new([_cape(101, 1, 6), _rune(102, PUI, 1)])
	c.send(Protocol.fm_apply(101, PUI))
	eq(c.code(), Protocol.E_ITEM_WORN)
	eq(c.inv().bag_count(PUI), 1)


func test_boisaille_weapon_is_forgeable() -> void:
	check(Smithmagic.forgeable(BOISAILLE), "Épée de Boisaille: Force 7-10")
	var r := Smithmagic.apply(BOISAILLE, [[100, 8, 10, 0], [118, 10, 0, 0]], 0, FO, RandomNumberGenerator.new())
	eq(r["err"], Smithmagic.ERR_RESERVE, "Force 10 + 1 goes over the maximum 10 and the puits is empty")
	r = Smithmagic.apply(BOISAILLE, [[100, 8, 10, 0], [118, 7, 0, 0]], 0, FO, RandomNumberGenerator.new())
	eq(r["err"], "")
