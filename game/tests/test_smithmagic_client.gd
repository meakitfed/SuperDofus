## P2.07b: the state behind the smithmagic window (SmithmagicModel) filters the bag, previews with the
## shared rules and builds fm_apply; driven through a LocalBackend, so the sim answers for real.
## Cape du Justicier 758 (Vitalité 31-40, Puissance 21-30, Soins 4-5), runes 1523 Rune Vi, 7436 Rune Pui,
## 1557 Rune Ga Pa (+1 PA: over the maximum, needs the puits), 44 Boisaille (a sword: another workshop).
extends TestCase

const CAPE := 758
const VI := 1523
const PUI := 7436
const PA := 1557


func _init() -> void:
	SpellBook.use_file("")
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()


static func _backend(items: Array) -> LocalBackend:
	var server := LocalServer.new()
	server.persistence.save_character("incarnam", "Eli", {"level": 20, "items": items})
	var b := LocalBackend.new()
	b.server = server
	b.send(Protocol.hello("incarnam", "Eli"))
	b.poll(0.0)
	return b


static func _bag(b: LocalBackend) -> Array:
	var inv: Inventory = b.sim.players[b.player_id].character.inventory
	var out := inv.items.values().filter(func(it: Dictionary) -> bool: return int(it.get("pos", -1)) < 0)
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["uid"]) < int(y["uid"]))
	return out


static func _items() -> Array:
	return [{"uid": 101, "id": CAPE, "qty": 1, "pos": -1, "effects": [[125, 35, 0, 0], [138, 25, 0, 0], [178, 4, 0, 0]]},
		{"uid": 102, "id": 44, "qty": 3, "pos": -1, "effects": []},
		{"uid": 103, "id": VI, "qty": 2, "pos": -1, "effects": []},
		{"uid": 104, "id": PA, "qty": 1, "pos": -1, "effects": []},
		{"uid": 105, "id": 7436, "qty": 1, "pos": -1, "effects": []}]


static func _send(b: LocalBackend, m: SmithmagicModel, cmd: Dictionary) -> Array:
	var events: Array = []
	var f := func(ev: Dictionary) -> void: events.append(ev)
	b.event.connect(f)
	b.send(cmd)
	b.poll(0.0)
	b.event.disconnect(f)
	for ev: Dictionary in events:
		if ev["t"] == Protocol.FM_RESULT:
			m.on_result(ev)
	return events


func test_workshops_come_from_the_skills_table() -> void:
	var w := Smithmagic.workshops()
	check(w.size() >= 6, "the six forgemagus workshops")
	check(w.has(118) and w.has(113))
	check(not w.has(20), "a craft skill is no forgemagus workshop")
	var m := SmithmagicModel.new()
	eq(m.skill, int(w[0]))


func test_the_bag_is_filtered_by_workshop_and_rune() -> void:
	var b := _backend(_items())
	var bag := _bag(b)
	var m := SmithmagicModel.new()
	var capes := Smithmagic.workshops().filter(func(s: int) -> bool: return Smithmagic.accepts(s, CAPE))
	eq(capes.size(), 1, "one workshop forges capes")
	m.set_skill(int(capes[0]))
	eq(m.forgeable(bag).size(), 1)
	eq(int(m.forgeable(bag)[0]["uid"]), 101)
	var other := Smithmagic.workshops().filter(func(s: int) -> bool: return not Smithmagic.accepts(s, CAPE))
	m.set_skill(int(other[0]))
	eq(m.forgeable(bag).size(), 1, "the sword workshop sees the Boisaille, not the cape")
	eq(int(m.forgeable(bag)[0]["uid"]), 102)
	eq(SmithmagicModel.runes_in(bag).size(), 3, "Boisaille is no rune")


func test_preview_and_apply_message() -> void:
	var b := _backend(_items())
	var bag := _bag(b)
	var m := SmithmagicModel.new()
	check(m.preview(bag).is_empty(), "nothing picked")
	check(m.apply(bag) == null)
	m.item_uid = 101
	m.rune = VI
	var pv := m.preview(bag)
	eq(str(pv["kind"]), "roll")
	eq(int(pv["chance"]), Smithmagic.chance(40, 40), "35 + 5 reaches the maximum 40")
	check(m.can_apply(bag))
	eq(m.apply(bag), Protocol.fm_apply(101, VI))
	m.rune = PA
	pv = m.preview(bag)
	eq(str(pv["kind"]), "overmax")
	eq(str(pv["refused"]), Protocol.E_FM_RESERVE, "no puits: refused")
	check(m.apply(bag) == null)
	m.rune = 44
	check(m.can_apply(bag) == false, "not a rune")
	m.item_uid = 999
	check(m.picked(bag).is_empty())
	eq(m.item_uid, 0, "a vanished item leaves the pick")


func test_results_fill_the_history_and_follow_the_item() -> void:
	var b := _backend(_items())
	var m := SmithmagicModel.new()
	m.item_uid = 101
	m.rune = VI
	var events := _send(b, m, m.apply(_bag(b)))
	check(events.any(func(e: Dictionary) -> bool: return e["t"] == Protocol.FM_RESULT))
	eq(m.history.size(), 1)
	eq(m.item_uid, int(m.history[0]["uid"]))
	check(SmithmagicModel.result_text(m.history[0]).contains(UiTooltips.item_name(VI)))
	check(not SmithmagicModel.effect_name(125).contains("0"), "the effect name has no number: %s" % SmithmagicModel.effect_name(125))
	# the rune stack lost one; a second try works, a third has no rune left
	_send(b, m, m.apply(_bag(b)))
	eq(m.history.size(), 2)
	check(m.apply(_bag(b)) == null, "no rune left in the bag")
	for i in 40:
		m.on_result({"uid": 1, "rune": VI, "outcome": "fail", "lost": [[138, 2]], "item": {}})
	eq(m.history.size(), SmithmagicModel.MAX_HISTORY)
	check(SmithmagicModel.result_text(m.history[0]).contains("-2"))
