## Items, part 2 (roadmap P1.06): slots, conditions (CriteriaEval), set
## bonuses, equipment in the characteristics and in fight, the weapon hit.
## Real item data, through LocalBackend.
extends TestCase

const CAPE := 2473 # Cape de l'Aventurier (Panoplie du Jeune Aventurier), level 8
const SWORD := 44 # Épée de Boisaille, level 7: 8-10 neutral, 3 AP, crit 30 +5
const RING := 852 # Petit Anneau Magique, no set
const DOFAWA := 7113


func _init() -> void:
	SpellBook.use_file("")
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()


class Conn:
	var backend := LocalBackend.new()
	var events: Array = []

	func _init(server: LocalServer, save := {}, name := "Bob") -> void:
		backend.server = server
		backend.event.connect(func(ev: Dictionary) -> void: events.append(ev))
		var d := {"name": name, "level": 20}
		d.merge(save, true)
		server.persistence.save_character("eq", name, d)
		backend.send(Protocol.hello("eq", name))
		backend.poll(0.0)

	func character() -> Character:
		return (backend.sim.players[backend.player_id] as PlayerActor).character

	func give(id: int, qty := 1) -> int:
		backend.sim.give_item(backend.sim.players[backend.player_id], id, qty)
		backend.poll(0.0)
		return int(last(Protocol.ITEM_ADDED)["item"]["uid"])

	func send(cmd: Dictionary) -> void:
		events.clear()
		backend.send(cmd)
		backend.poll(0.0)

	func last(type: String) -> Dictionary:
		var l := events.filter(func(e: Dictionary) -> bool: return e["t"] == type)
		return l[-1] if not l.is_empty() else {}

	func error() -> String:
		return str(last(Protocol.ERROR).get("code", ""))


static func _server() -> LocalServer:
	var s := LocalServer.new()
	s.sources["eq"] = WorldSource.from_dicts({"id": "eq", "name": "Eq", "start_map": 1, "start_cell": 300},
			[{"id": 1, "coords": [0, 0], "neighbors": {}}])
	return s


func test_slots_come_from_the_item_super_types() -> void:
	eq(Equipment.positions(CAPE), [Equipment.CAPE], "itemsupertypes 11")
	eq(Equipment.positions(RING), [2, 4])
	eq(Equipment.positions(DOFAWA), Equipment.DOFUS)
	eq(Equipment.positions(SWORD), [Equipment.WEAPON])
	eq(Equipment.positions(468), [], "bread is not equipment")


func test_conditions_level_and_uniqueness() -> void:
	var c := Conn.new(_server(), {"level": 5})
	c.send(Protocol.equip(c.give(CAPE), Equipment.CAPE))
	eq(c.error(), Protocol.E_ITEM_LEVEL, "items.level 8 > 5")
	c.character().level = 60
	c.send(Protocol.equip(c.give(758), Equipment.CAPE)) # Cape du Justicier (level 30): Ps=1&Pa>20
	eq(c.error(), Protocol.E_ITEM_CONDITION, "no alignment yet")
	c.send(Protocol.equip(c.give(468), Equipment.CAPE))
	eq(c.error(), Protocol.E_BAD_SLOT)
	var two := c.give(DOFAWA, 2)
	c.send(Protocol.equip(two, 9))
	eq(c.error(), "")
	c.send(Protocol.equip(two, 10))
	eq(c.error(), Protocol.E_ALREADY_EQUIPPED, "one of each Dofus")
	var rings := c.give(RING, 2)
	c.send(Protocol.equip(rings, 2))
	c.send(Protocol.equip(rings, 4))
	eq(c.error(), "", "the same ring twice when it has no set")
	eq(c.character().inventory.worn().size(), 3)
	check(CriteriaEval.ok("PG=1", {"breed": 1}) and not CriteriaEval.ok("BI=1", {}) and CriteriaEval.ok("PO=468", {"items": [468]}))
	eq(CriteriaEval.unknown_keys("PL>2&Qa=5|PJ>2,40|Pk=1"), PackedStringArray(["Pk"]))  # Qa is read since P2.03, PJ since P2.05b


func test_stacks_split_and_merge() -> void:
	var c := Conn.new(_server())
	var rings := c.give(RING, 3)
	c.send(Protocol.equip(rings, 2))
	var changed := c.events.filter(func(e: Dictionary) -> bool: return e["t"] == Protocol.ITEM_ADDED)
	eq(changed.size(), 2, "the bag stack (2 left) and the worn one")
	var worn: Dictionary = changed[1]["item"]
	eq([int(worn["qty"]), int(worn["pos"])], [1, 2])
	check(int(worn["uid"]) != rings)
	c.send(Protocol.unequip(2))
	eq(int(c.last(Protocol.ITEM_REMOVED)["uid"]), int(worn["uid"]), "back in the bag, merged")
	eq(int(c.last(Protocol.ITEM_ADDED)["item"]["qty"]), 3)
	c.send(Protocol.destroy_item(rings))
	eq(c.error(), "")
	c.send(Protocol.unequip(2))
	eq(c.error(), Protocol.E_BAD_SLOT, "nothing worn there")


func test_set_bonus_and_stats_in_and_out_of_fight() -> void:
	var c := Conn.new(_server())
	var ch := c.character()
	var before := ch.stat("strength")
	c.send(Protocol.equip(c.give(CAPE), Equipment.CAPE))
	eq(ch.stat("strength"), before + 5, "the cape's +5 Force")
	var other := 2474
	c.send(Protocol.equip(c.give(other), Equipment.positions(other)[0]))
	var items := Equipment.stats_of(GameData.item(CAPE)["effects"])
	for k: String in Equipment.stats_of(GameData.item(other)["effects"]):
		items[k] = int(items.get(k, 0)) + int(Equipment.stats_of(GameData.item(other)["effects"])[k])
	var set2 := Equipment.stats_of(Equipment.set_bonus(5, 2)) # itemsets 5: +5 in each element for 2 items
	eq(int(set2["strength"]), 5)
	eq(ch.stat("strength"), before + int(items.get("strength", 0)) + 5, "items + set bonus")
	var st: Dictionary = c.last(Protocol.PLAYER_STATS)["stats"]
	eq(int(st["bonus"]["strength"]), int(items.get("strength", 0)) + 5)
	var f: Fighter = c.backend.sim._player_fighter(c.backend.sim.players[c.backend.player_id])
	eq(f.stat("strength"), ch.stat("strength"), "the fighter gets the same characteristics")
	eq(f.initiative(), int(ch.derived_stats(c.backend.sim.now)["initiative"]))
	eq(f.max_ap, ch.max_ap())


func test_weapon_hit() -> void:
	var c := Conn.new(_server())
	var sim := c.backend.sim
	var bare: Fighter = sim._player_fighter(sim.players[c.backend.player_id])
	check(bare.spells.has(SpellBook.grade_for(0, 20)), "Coup de poing bare-handed (spells 0)")
	c.send(Protocol.equip(c.give(SWORD), Equipment.WEAPON))
	eq(c.error(), "")
	var f: Fighter = sim._player_fighter(sim.players[c.backend.player_id])
	check(f.spells.has(Equipment.WEAPON_SPELL))
	var hit := f.spell(Equipment.WEAPON_SPELL)
	eq(Protocol.validate(Protocol.fight_start(1, 1, [f.to_dict()], [1], {"0": [], "1": []}, 0), Protocol.S2C), "", "JSON-safe fighter with a weapon")
	eq([int(hit["ap"]), int(hit["crit"])], [3, 30], "items.apCost, criticalHitProbability")
	eq([int(hit["effects"][0]["min"]), int(hit["effects"][0]["max"])], [8, 10])
	eq([int(hit["crit_effects"][0]["min"]), int(hit["crit_effects"][0]["max"])], [13, 15], "criticalHitBonus +5")
	# cast it in a bare fight
	var fight := Fight.new(1, MapData.new(), 7, func(_ev: Dictionary) -> void: pass)
	f.id = 1
	f.cell = 300
	f.stats = {}
	var foe := Fighter.new()
	foe.id = 2
	foe.team = 1
	foe.cell = MapGeometry.from_iso(MapGeometry.to_iso(300) + Vector2i(1, 0))
	foe.hp = 100
	foe.max_hp = 100
	fight.add_fighter(f)
	fight.add_fighter(foe)
	fight.start_placement(0)
	fight.begin(0)
	if fight.current() != f:
		fight.end_turn(0)
	eq(fight.cast(f, Equipment.WEAPON_SPELL, foe.cell, 0), "")
	check(foe.hp <= 92 and foe.hp >= 85, "8-10 damage, 13-15 on a critical hit (hp %d)" % foe.hp)
	eq(fight.cast(f, Equipment.WEAPON_SPELL, foe.cell, 0), Protocol.E_CAST_LIMIT, "items.maxCastPerTurn 1")


# ── worn look (P1.06b) ─────────────────────────────────────────────────────────

const HAT := 10801 # Chapeau de l'intrépide: skin 460 (measured, JondoEmu)
const INTREPID_CAPE := 10800 # skin 461 (measured)
const SHIELD := 10798 # Bouclier de l'intrépide: skin 462 (measured)
const LOOK := {"look": "{1|120,2188|1=15047528|56}"}


func test_worn_items_add_their_skin_to_the_look() -> void:
	eq(LookBuilder.with_equipment("{1|120,2188|1=5|56}", [460, 461]), "{1|120,2188,460,461|1=5|56}")
	eq(LookBuilder.with_equipment("{1|120,2188|1=5|56}", []), "{1|120,2188|1=5|56}")
	eq(LookBuilder.with_equipment("{1|120,460||56}", [460]), "{1|120,460||56}", "no skin twice")
	eq(int(GameData.item(HAT).get("skin", 0)), 460, "items.json skin (gamedata.py, JondoEmu)")
	eq(int(GameData.item(RING).get("skin", 0)), 0, "a ring shows nothing")


func test_equipping_changes_the_look_for_everyone() -> void:
	var server := _server()
	var bob := Conn.new(server, LOOK)
	var ann := Conn.new(server, LOOK, "Ann")
	var base := bob.character().look
	var hat := bob.give(HAT)
	var shield := bob.give(SHIELD)
	var ring := bob.give(RING)
	ann.events.clear()
	bob.send(Protocol.equip(hat, Equipment.HAT))
	var mine := LookBuilder.parse(str(bob.last(Protocol.PLAYER_STATS)["stats"]["look"]))
	check((mine["skins"] as Array).has(460), "player_stats look wears the hat")
	ann.backend.poll(0.0)
	var seen := ann.last(Protocol.ACTOR_LOOK)
	eq(int(seen.get("id", -1)), bob.backend.player_id, "the other player sees it")
	check((LookBuilder.parse(str(seen["looks"][0]))["skins"] as Array).has(460))
	bob.send(Protocol.equip(shield, Equipment.SHIELD))
	eq(LookBuilder.parse(bob.character().display_look())["skins"].slice(-2), [460, 462], "slot order: hat, shield")
	ann.backend.poll(0.0)
	ann.events.clear()
	bob.send(Protocol.equip(ring, Equipment.RING_LEFT))
	ann.backend.poll(0.0)
	eq(ann.last(Protocol.ACTOR_LOOK), {}, "a ring does not change the look")
	bob.send(Protocol.unequip(Equipment.HAT))
	bob.send(Protocol.unequip(Equipment.SHIELD))
	eq(bob.character().display_look(), base, "back to the bare look")
	eq(str((bob.backend.sim.players[bob.backend.player_id] as PlayerActor).looks[0]), base)


func test_the_look_is_worn_in_fight_and_in_the_character_list() -> void:
	var server := _server()
	var bob := Conn.new(server, LOOK)
	bob.send(Protocol.equip(bob.give(INTREPID_CAPE), Equipment.CAPE))
	eq(bob.error(), "")
	var p: PlayerActor = bob.backend.sim.players[bob.backend.player_id]
	check(str(bob.backend.sim._player_fighter(p).looks[0]).contains("461"), "the fighter wears the cape")
	bob.backend.sim.save_player(p)
	var list := CharacterRoster.summaries(bob.backend.sim, p.character.account)
	check(str(list[0]["look"]).contains("461"), "character selection shows it dressed")
