## The start spell of a monster (H.04d): monsters.grades.startingSpellId, cast on itself when it joins the fight.
## It sets the states other spells of the monster need (spell criterion HS=...: Boufton's Mûrissement cycle),
## and hooks that run on its own turns. Also the AI choices that H.04d fixed for the monsters of the matrix:
## a blast on its own cell, a cone aimed along a line, a kill.
extends TestCase

const BOUFTON := "dofus:76" # start 43608: Timide / Audacieux / Intrépide, its Entartrage grades need HS=1360 / 1361 / 1362
const SPELL_START := 1043608


func _init() -> void:
	SpellBook.use_file("")


static func _entry(key: String) -> Dictionary:
	for e: Dictionary in MonsterMatrix.entries():
		if e["key"] == key:
			return e
	return {}


func test_the_data_names_the_start_spell_of_each_grade() -> void:
	var e := _entry(BOUFTON)
	check(not e.is_empty(), "the monster is in the dofus world")
	var last: int = (e["grades"] as Array).size()
	eq(SpellBook.monster_start(76, 1), SPELL_START, "grade 1")
	eq(SpellBook.monster_start(76, last), SPELL_START, "last grade")
	eq(SpellBook.monster_start(76, 99), SPELL_START, "a grade past the list reads the last one")
	eq(SpellBook.monster_start(1074, 1), 0, "a monster without start spell")
	check(not SpellBook.get_spell(SPELL_START).is_empty(), "the start spell is in the spell data")
	eq(MonsterGame.monster(MonsterMatrix.played_grade(e)).start_spell, SPELL_START, "the fighter carries it")


func test_a_monster_joining_a_fight_casts_its_start_spell() -> void:
	var e := _entry(BOUFTON)
	var st := MonsterGame.setup(MonsterMatrix.played_grade(e))
	var mon: Fighter = st["mon"]
	check(mon.has_state(1361), "state 1361 (Audacieux) is set before the first turn: %s" % [mon.state_ids()])
	# the buffs are part of the fighter's description, so a client or the network sees them at fight start
	var states: Array = (mon.to_dict()["buffs"] as Array).filter(func(b: Dictionary) -> bool: return str(b.get("kind", "")) == "state")
	check(states.any(func(b: Dictionary) -> bool: return int(b.get("state", 0)) == 1361), "the state is in to_dict")
	# the one-turn hook (TB) lives through the countdown of the first turn
	var hook := mon.buffs.filter(func(b: Buff) -> bool: return b.kind == "trigger")
	check(not hook.is_empty() and (hook[0] as Buff).turns >= 1, "the TB hook is on the monster")
	# ... and still there when its first turn starts: the hook casts Audacieux (state 1361) for the next cycle step
	var fight0: Fight = st["fight"]
	fight0.begin(0)
	check(mon.has_state(1361) or mon.has_state(1362), "the cycle of states goes on at its first turn")
	var fight: Fight = st["fight"]
	var cast_ok := false
	for sid: int in mon.spells:
		if str(mon.spell(sid).get("criterion", "")) == "HS=1361":
			cast_ok = fight.spell_block(mon, sid) == ""
	check(cast_ok, "the spell that needs HS=1361 can be cast")


func test_the_dummy_is_hurt_by_a_monster_whose_spells_need_its_start_states() -> void:
	for key: String in ["dofus:76", "dofus:87", "dofus:896", "dofus:4737"]:
		if not sub(key):
			continue
		var r := MonsterGame.play(MonsterMatrix.played_grade(_entry(key)))
		check(int(r["dummy_lost"]) > 0, "%s hurt the dummy" % key)
	sub("")


func test_the_blast_around_itself_the_cone_and_the_kill_are_cast() -> void:
	for key: String in ["dofus:3848", "dofus:2921", "dofus:4362", "dofus:4074"]: # cone, blast on its cell, kill x2
		if not sub(key):
			continue
		var r := MonsterGame.play(MonsterMatrix.played_grade(_entry(key)))
		check(int(r["casts"]) > 0 and int(r["dummy_lost"]) > 0, "%s cast and hurt the dummy (%d casts, %d lost)" % [key, r["casts"], r["dummy_lost"]])
	sub("")


func test_a_fighter_with_a_summoner_is_left_to_summons() -> void:
	# a summon casts its own start spell in Summons.apply; Fight.add_fighter is for the monsters of the group
	var st := MonsterGame.setup(MonsterMatrix.played_grade(_entry(BOUFTON)))
	var fight: Fight = st["fight"]
	var other := MonsterGame.monster(MonsterMatrix.played_grade(_entry(BOUFTON)))
	other.id = 77
	other.cell = MonsterGame.cell_at(MonsterGame.GAP + 2, 2)
	other.summoner = 2
	fight.add_fighter(other)
	eq(other.buffs.size(), 0, "no start spell for a fighter with a summoner")
