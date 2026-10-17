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


func _compare(label: String, source: WorldSource, breed: int, spell: int) -> Array:
	var s := ParityRig.scenario(breed, PLAYER_LEVEL)
	var local := ParityRig.digest(ParityRig.play_local(source, s, spell))
	var net := ParityRig.play_net(source, ParityRig.scenario(breed, PLAYER_LEVEL), spell)
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
