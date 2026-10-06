## Summons (roadmap P1.11): the fighters a spell brings into the fight.
##   data:   SpellBook.summon(monster id) = spells.json `summons` (tools/extractor/spells.py:
##           monsters.grades + bonusCharacteristics, monsters.m_flags useSummonSlot / canPlay /
##           canTackle); the summon effect gives the monster and its grade.
##   stats:  HP = grade lifePoints + bonus lifePoints x (summoner level + 10) / 20: measured
##           by the JondoEmu emulator on 18 summons of real fights (Jondo.Unity.Server
##           Managers/Summons.cs VidaDelInvocado: bonus 100 -> 1 050 HP at level 200).
##           Other characteristics (P1.11b) = the grade's + the summoner's same characteristic x
##           bonus / 100 (strength, wisdom, damage_fire...), taken when it arrives.
##           APPROX(P1.11b): not measured; read from the data, where these bonuses are shares:
##           only 50 / 75 / 100, 50 for the Osamodas's first summons, 75 for their evolutions,
##           100 for the third ones, always on the summon's own element (Tofu: agility and air
##           damage, Bouftou: strength and earth damage), 100 on everything for the bombs, the
##           Steamer's turrets, the Fées. Growing them with the level like the HP gave an
##           Explobombe +1 050 fire damage at level 200. The summon's level is its summoner's.
##           monsters.characRatios is not for summons: it goes into the official monster scaling
##           formulas (characteristics.scaleFormulaId -> luaformulas 4 / 5 / 3 / 12), which give
##           2 200 000 HP for the Ocra beacon JondoEmu measured at 1 050.
##   limit:  summons using a slot (useSummonSlot) <= StatFormulas.BASE_SUMMONS + "summons"
##           (characteristic 26 maxSummonedCreaturesBoost, items).
##   turns:  a summon that can play (canPlay) plays right after its summoner (and the
##           summoner's older summons); it dies with its summoner; it gives no XP or drop
##           and does not keep its team in the fight (Fight._check_end).
##   double: APPROX(P1.11): the caster's copy (look, level, HP, characteristics), no spells.
##   bombs:  (P1.13d) effect 1009 "Déclenche une bombe" sets a bomb off (spellbombs, at the
##           bomb's grade, cast by the bomb on its own cell): it casts its chain reaction
##           (chainReactionSpellId: 1009 on the bombs in its circle 2 and, same monster, in
##           line up to 7 cells), then its explosion (explodSpellId: hurts in circle 2, kills
##           the bomb, 141 on the caster). A bomb already dead (Poudre: 1009 on its death,
##           trigger X) casts instantSpellId instead (the same hurt, no kill). A bomb goes off
##           once. APPROX(P1.13d): the data does not say what casts chainReactionSpellId and
##           instantSpellId (server code): read from their effects. Walls: FightMarks.walls.
##   start:  a summon casts its grade's start spell (monsters.grades.startingSpellId) on
##           itself when it arrives: its hooks (trigger buffs: heal at the start of its
##           turn, die when its summoner is hit...), P1.13b.
class_name Summons
extends RefCounted


## Summons of `f` that use a slot, alive.
static func count(fight: Fight, f: Fighter) -> int:
	var n := 0
	for g: Fighter in fight.fighters.values():
		if g.alive and g.summoner == f.id and g.summon_slot:
			n += 1
	return n


static func max_summons(f: Fighter) -> int:
	return StatFormulas.BASE_SUMMONS + f.stat("summons")


## Why `caster` cannot cast `spell` because of its summons ("" = it can).
static func cast_error(fight: Fight, caster: Fighter, spell: Dictionary) -> String:
	for e: Dictionary in spell.get("effects", []):
		var kind := str(e.get("kind", ""))
		var slot := kind == "double" or (kind == "summon" and bool(SpellBook.summon(int(e["monster"])).get("slot", false)))
		if slot and count(fight, caster) >= max_summons(caster):
			return Protocol.E_SUMMON_LIMIT
	return ""


## The effect of a summon / double / replace effect cast on `cell`.
static func apply(fight: Fight, caster: Fighter, e: Dictionary, cell: int) -> Array:
	var out: Array = []
	var kind := str(e.get("kind", "summon"))
	if kind == "replace": # kills its own summon standing there, the new one takes its place
		var old := fight.fighter_at(cell)
		if old == null or old.summoner != caster.id or (e.has("replaces") and old.monster != int(e["replaces"])) \
				or not FightEffects.cond_ok(e, caster, old):
			return []
		out.append(FightEffects.kill(old))
		out.append_array(fight.handle_deaths())
	if not fight.map.is_fight_walkable(cell) or fight.fighter_at(cell) != null:
		return out
	var f := double(fight, caster) if kind == "double" else create(fight, caster, int(e["monster"]), int(e.get("grade", 1)))
	if f == null:
		return out
	f.cell = cell
	f.dir = caster.dir
	fight.add_summon(f, caster)
	fight.log_cast(f, "summoned") # a summon event haa (TargetMask U)
	out.append({"kind": "summon", "target": f.id, "summoner": caster.id, "fighter": f.to_dict(), "order": fight.order.duplicate()})
	if kind != "double":
		var start := SpellBook.get_spell(start_spell(int(e["monster"]), int(e.get("grade", 1))))
		if not start.is_empty():
			out.append_array(FightEffects.apply_spell(fight, f, start, f.cell, false))
	return out


## Bomb `t` explodes (effect 1009): it casts its explosion (see the header).
static func detonate(fight: Fight, t: Fighter) -> Array:
	var data := SpellBook.summon(t.monster)
	if not data.has("explode") or t.exploded:
		return []
	t.exploded = true
	var out: Array = [{"kind": "explode", "target": t.id}]
	for key: String in (["chain", "explode"] if t.alive else ["instant"]):
		var spells: Array = data.get(key, [])
		if not spells.is_empty():
			var spell := SpellBook.get_spell(int(spells[clampi(t.grade, 1, spells.size()) - 1]))
			out.append_array(FightEffects.apply_spell(fight, t, spell, t.cell, false))
	return out


## The castable a summon of `monster_id` at `grade` casts when it arrives (0 = none).
static func start_spell(monster_id: int, grade: int) -> int:
	var grades: Array = SpellBook.summon(monster_id).get("grades", [])
	if grades.is_empty():
		return 0
	return int((grades[clampi(grade, 1, grades.size()) - 1] as Dictionary).get("start", 0))


## A fighter for monster `monster_id` at `grade`, summoned by `caster` (null if unknown).
static func create(fight: Fight, caster: Fighter, monster_id: int, grade: int) -> Fighter:
	var data := SpellBook.summon(monster_id)
	var grades: Array = data.get("grades", [])
	if grades.is_empty():
		return null
	var g: Dictionary = grades[clampi(grade, 1, grades.size()) - 1]
	var f := Fighter.new()
	f.id = fight.next_summon_id()
	f.team = caster.team
	f.ai = true
	f.summoner = caster.id
	f.monster = monster_id
	f.grade = grade
	f.summon_slot = bool(data.get("slot", false))
	f.plays = bool(data.get("plays", true))
	f.tackles = bool(data.get("tackles", true))
	f.can_switch = bool(data.get("switch", true)) # P1.13n
	f.can_switch_on_target = bool(data.get("switch_on_target", true))
	f.name_id = int(data.get("name_id", 0))
	f.portrait = int(data.get("portrait", 0))
	f.looks = PackedStringArray([str(data.get("look", ""))])
	f.level = caster.level
	var bonus: Dictionary = g.get("bonus", {})
	f.max_hp = maxi(1, int(g.get("hp", 0)) + scaled(int(bonus.get("hp", 0)), caster.level))
	f.hp = f.max_hp
	f.max_ap = maxi(0, int(g.get("ap", 0)))
	f.max_mp = maxi(0, int(g.get("mp", 0)))
	f.ap = f.max_ap
	f.mp = f.max_mp
	var st: Dictionary = g.get("stats", {})
	for k: String in st:
		f.stats[k] = int(st[k])
	for k: String in bonus:
		if k != "hp":
			f.stats[k] = int(f.stats.get(k, 0)) + caster.stat(k) * int(bonus[k]) / 100
	var res: Dictionary = g.get("res", {})
	for k: String in res:
		f.stats["res_" + k] = int(res[k])
	f.spells = (g.get("spells", []) as Array).map(func(s: Variant) -> int: return int(s)) \
			.filter(func(s: int) -> bool: return not SpellBook.get_spell(s).is_empty())
	return f


## The HP bonus at the summoner's level (see the header).
static func scaled(bonus: int, summoner_level: int) -> int:
	return bonus * (maxi(1, summoner_level) + 10) / 20


static func double(fight: Fight, caster: Fighter) -> Fighter:
	var f := Fighter.new()
	f.id = fight.next_summon_id()
	f.team = caster.team
	f.ai = true
	f.summoner = caster.id
	f.summon_slot = true
	f.name = caster.name
	f.looks = caster.looks
	f.level = caster.level
	f.max_hp = caster.max_hp
	f.hp = caster.hp
	f.max_ap = caster.max_ap
	f.max_mp = caster.max_mp
	f.ap = f.max_ap
	f.mp = f.max_mp
	f.stats = caster.stats.duplicate()
	return f
