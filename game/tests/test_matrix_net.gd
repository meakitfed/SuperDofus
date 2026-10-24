## Local / network parity of the matrix (H.06, tests/parity/parity_rig.gd): a sample of the matrix is played
## twice, by a LocalBackend and through a real ServerHost + NetBackend on 127.0.0.1 (WebSocket, JSON), and the
## rule-bearing events must be identical. Sample: one monster per AI family (golden of the monster matrix) and
## one spell per class (golden of the class spells). TEST_CASE=<key or class> runs only some.
class_name TestMatrixNet
extends TestCase

const PLAYER_LEVEL := 100
## A level-1 Tofu-like fixture is not needed: the monsters are the data's own grades.


func _init() -> void:
	SpellBook.use_file("")


## One monster per family (not the bombs): the first, in key order, whose spells are present.
static func monster_sample() -> Array:
	var golden := MonsterMatrix.read_golden()
	var seen := {}
	var out := []
	for e: Dictionary in MonsterMatrix.entries():
		var row: Dictionary = golden.get(e["key"], {})
		var fam := str(row.get("family", ""))
		if fam == "" or fam == MonsterFamily.BOMB or seen.has(fam):
			continue
		if int(row.get("spells_absent", 0)) > 0 and fam != MonsterFamily.PASSIVE:
			continue
		seen[fam] = true
		out.append(e)
	return out


## One spell per class: the first spell the level-100 character knows (SpellBook.known_ids) that has effects.
static func spell_sample() -> Dictionary:
	var out := {}
	for breed: int in SpellGolden.breeds():
		if breed == 0:
			continue
		for id: int in SpellBook.known_ids(breed, PLAYER_LEVEL):
			if not (SpellBook.get_spell(id).get("effects", []) as Array).is_empty():
				out[breed] = id
				break
	return out


func _compare(label: String, source: WorldSource, breed: int, spell: int, level := PLAYER_LEVEL, variants := []) -> Array:
	var s := ParityRig.scenario(breed, level, variants)
	var local := ParityRig.digest(ParityRig.play_local(source, s, spell))
	var net := ParityRig.play_net(source, ParityRig.scenario(breed, level, variants), spell)
	eq((net["schema_errors"] as Array).size(), 0, label + ": the network events follow the schema")
	var remote := ParityRig.digest(net["events"])
	check(local.size() > 4, "%s: the fight really happened (%d rule events)" % [label, local.size()])
	var n := mini(local.size(), remote.size())
	for i in n:
		if local[i] != remote[i]:
			fail("%s: event %d differs, local %s, network %s" % [label, i, local[i], remote[i]])
			break
	# the network clock trails the local one by a few steps: the last events of the run may not have arrived
	check(local.size() - remote.size() <= 6 and remote.size() - local.size() <= 6, "%s: %d rule events locally, %d through the network" % [label, local.size(), remote.size()])
	return local


func test_a_monster_per_family_plays_the_same_on_both_backends() -> void:
	var sample := monster_sample()
	check(sample.size() >= 4, "the sample covers several families (%d)" % sample.size())
	var any_cast := false
	for e: Dictionary in sample:
		var label := MonsterMatrix.label(e)
		if not sub(label):
			continue
		var grade := MonsterMatrix.played_grade(e)
		var local := _compare(label, ParityRig.world([grade]), 5, 0)
		any_cast = any_cast or local.any(func(d: String) -> bool: return d.contains("spell_cast") and not d.contains("\"caster\":1"))
	sub("")
	if _case_filter == "":
		check(any_cast, "at least one sampled monster cast a spell")


## H.04d: the start spell (states, hooks) is cast where the sim adds the monster to the fight, on both sides: Boufton
## (the Mûrissement states its spells need), a Kitsou (states + hooks) and 4737 (a kill on a state) play the same locally and through the network.
func test_monsters_with_a_start_spell_play_the_same_on_both_backends() -> void:
	for key: String in ["dofus:76", "dofus:896", "dofus:4737"]:
		if not sub(key):
			continue
		for e: Dictionary in MonsterMatrix.entries():
			if e["key"] == key:
				var local := _compare(MonsterMatrix.label(e), ParityRig.world([MonsterMatrix.played_grade(e)]), 5, 0)
				check(local.any(func(d: String) -> bool: return d.contains("spell_cast") and not d.contains("\"caster\":1")), "%s: the monster cast a spell" % key)
	sub("")


func test_a_spell_per_class_plays_the_same_on_both_backends() -> void:
	var sample := spell_sample()
	check(sample.size() >= 12, "the sample covers the classes (%d)" % sample.size())
	var grade := {"monster": 31, "grade": 1, "name": "Cible", "level": 20, "hp": 400, "ap": 0, "mp": 0, "xp": 10, "look": "{4907|||130}",
			"res": {}, "stats": {}, "kamas": [1, 2], "drops": [], "spells": []}
	var casts := 0
	for breed: int in sample:
		if not sub("classe %d" % breed):
			continue
		var local := _compare("classe %d" % breed, ParityRig.world([grade]), breed, int(sample[breed]))
		if local.any(func(d: String) -> bool: return d.contains("spell_cast")):
			casts += 1
	sub("")
	if _case_filter == "":
		check(casts >= 6, "the spells were really cast through the network (%d classes)" % casts)


## P1.18d: the rules fixed there (a sub-spell replacing the effects of its caller, a zone summon, a delayed
## kill of every creature a cast summoned) play the same through the network.
func test_the_p118d_spells_play_the_same_on_both_backends() -> void:
	var grade := {"monster": 31, "grade": 1, "name": "Cible", "level": 20, "hp": 400, "ap": 0, "mp": 0, "xp": 10, "look": "{4907|||130}",
			"res": {}, "stats": {}, "kamas": [1, 2], "drops": [], "spells": []}
	for c: Array in [["Pavois", 1, 1041129], ["Mot Deprimant", 7, 1065568], ["Mot Stimulant", 7, 1065555]]: # Balise Tactique is left out: it needs a free target cell, and the rig casts at the enemy (local spell tests cover it)
		if not sub(str(c[0])):
			continue
		var local := _compare(str(c[0]), ParityRig.world([grade]), int(c[1]), SpellBook.grade_for(int(SpellBook.get_spell(int(c[2])).get("spell", 0)), 200), 200, [int(SpellBook.get_spell(int(c[2])).get("spell", 0))]) # the variant is chosen; # the grade a level-200 character holds
		check(local.any(func(d: String) -> bool: return d.contains("spell_cast")), "%s was cast" % c[0])
	sub("")


## H.04c: the monsters whose spells were declared gaps (Noyade, Macro-Ondes, Drako, Embaumement: AP / MP
## removals that dodge, a steal that repeats, a reflect) play the same through the network.
func test_the_h04c_monsters_play_the_same_on_both_backends() -> void:
	for key: String in ["dofus:3153", "dofus:3670", "dofus:3392", "dofus:831"]:
		if not sub(key):
			continue
		for e: Dictionary in MonsterMatrix.entries():
			if e["key"] == key:
				var local := _compare(key, ParityRig.world([MonsterMatrix.played_grade(e)]), 5, 0)
				check(local.any(func(d: String) -> bool: return d.contains("spell_cast")), "%s: a spell was cast" % key)
	sub("")
