## Mods (src/shared/mods.gd): add-on content merged over the generated data, and
## the Joss mod (res://mods/joss): a monster, his spell (a bin that blows up over a
## 1-cell circle) and his group on map 153879809. Skipped when the mod is off.
extends TestCase

const LOOK := "{1|120,2195||56}"
const JOSS_MAP := 153879809
const BIN := 1900001


func _init() -> void:
	SpellBook.use_file("") # the real spells (+ mods)


func _joss_on() -> bool:
	if not Mods.enabled().has("joss"):
		skip("joss mod disabled in res://mods/mods.json")
		return false
	return true


func test_mod_spells_are_added_not_replacing() -> void:
	if not _joss_on():
		return
	var bin := SpellBook.get_spell(BIN)
	eq(str(bin.get("name", "")), "Poubelle explosive")
	eq(int(bin["fx"]["missile"]), 900002, "flying bin FX bone")
	eq(int(bin["fx"]["target"]), 900003, "blast FX bone")
	eq(str(SpellBook.get_spell(1041048).get("name", "")), "Retour du Bâton", "real spells untouched")
	SpellBook.use_file("res://tests/fixtures/spells.json")
	check(SpellBook.get_spell(BIN).is_empty(), "test fixtures never get mod spells")
	SpellBook.use_file("")


func test_joss_spawns_on_his_map_only() -> void:
	if not _joss_on():
		return
	var sim := WorldSim.new(JsonWorldSource.for_world("incarnam"))
	check(sim.spawner.monsters.has("900001"), "Joss is in the monster db")
	check(not sim.spawner.pool(443).has(900001), "but in no subarea pool (their rolls are unchanged)")
	var joss := _joss_groups(sim.get_map(JOSS_MAP))
	eq(joss.size(), 1, "one Joss group on his map")
	eq(str((joss[0] as MonsterGroup).looks[0]), "{900001|||85}")
	eq(_joss_groups(sim.get_map(int(sim.info["start_map"]))).size(), 0, "not elsewhere")


static func _joss_groups(m: MapInstance) -> Array:
	return m.actors.values().filter(func(a: SimActor) -> bool:
		return a is MonsterGroup and str((a as MonsterGroup).looks[0]).begins_with("{900001"))


## Full scenario through LocalBackend: attack Joss, wait, he throws his bin.
func test_joss_throws_his_bin() -> void:
	if not _joss_on():
		return
	var source := JsonWorldSource.for_world("incarnam")
	source._info["start_map"] = JOSS_MAP
	source._info["start_cell"] = 300
	var backend := LocalBackend.new()
	backend.sources["incarnam"] = source
	var events: Array = []
	var me := {"id": -1}
	backend.event.connect(func(ev: Dictionary) -> void:
		events.append(ev)
		if ev["t"] == Protocol.WELCOME:
			me["id"] = int(ev["you"]))
	backend.send(Protocol.hello("incarnam", "Tester", LOOK))
	_run(backend, 0.1)
	var group := _joss_groups(backend.sim.maps[JOSS_MAP])
	eq(group.size(), 1, "Joss is there")
	if group.is_empty():
		return
	backend.send(Protocol.fight_attack((group[0] as MonsterGroup).id))
	_run(backend, 0.1)
	backend.send(Protocol.fight_ready())
	_run(backend, 0.1)
	var fight: Fight = backend.sim.fights.values()[0]
	var joss: Fighter = fight.fighters.values().filter(func(f: Fighter) -> bool: return f.team == 1)[0]
	var you: Fighter = fight.fighters[int(me["id"])]
	you.hp = 500 # survive a few bins
	you.max_hp = 500
	# 3 cells away: in range (2-5) on this open map
	joss.cell = MapGeometry.from_iso(MapGeometry.to_iso(you.cell) + Vector2i(3, 0))
	eq(str(joss.name), "Joss")
	var cast := {}
	for turn in 6:
		if fight.current() == you:
			backend.send(Protocol.fight_end_turn())
		_run(backend, 4.0)
		for ev: Dictionary in events:
			if ev["t"] == Protocol.SPELL_CAST and int(ev["spell"]) == BIN:
				cast = ev
		if not cast.is_empty():
			break
	check(not cast.is_empty(), "Joss threw his bin")
	if cast.is_empty():
		return
	eq(int(cast["caster"]), joss.id)
	var hit := (cast["effects"] as Array).filter(func(e: Dictionary) -> bool:
		return str(e["kind"]) == "damage" and int(e["target"]) == you.id)
	check(not hit.is_empty(), "the blast hurts the player")


static func _run(backend: LocalBackend, seconds: float, step := 0.05) -> void:
	for i in int(seconds / step):
		backend.poll(step)
