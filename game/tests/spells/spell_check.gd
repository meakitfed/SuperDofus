## Checks a spell grade: its data (SpellCheck.data_errors), then every effect of its normal and
## critical lists against its kind's contract (EffectContract), each cast alone in a fresh
## SpellArena, with the caster's rolls forced to the min, then to the max. An effect with a
## `delay` or an `on` is checked twice: its wrapper (a delay / trigger buff on its targets), then
## the effect itself cast without it.
class_name SpellCheck
extends RefCounted

const ROLLS := ["min", "max"]
## the slots tried, in order, as the cast cell of an effect aimed at fighters: the first one whose
## cast touches someone (TargetOracle)
const AIM_ORDER := ["foe", "ally_t", "ally", "me", "foe_n", "foe_2", "far"]
## the characteristics the fight reads (Fighter.stat, StatFormulas): a buff of any other does nothing
const READ_STATS := ["strength", "intelligence", "chance", "agility", "wisdom", "vitality", "initiative",
		"power", "damage", "heals", "range", "crit", "summons", "tackle", "escape", "ap_attack", "mp_attack",
		"ap_dodge", "mp_dodge", "push_damage", "push_res", "crit_res", "final_damage", "final_heals", "combo",
		"erosion", "reflect", "roll_min", "roll_max", "res_all", "crit_damage", "dmg_taken", "melee_damage",
		"ranged_damage", "spell_damage", "melee_res", "ranged_res"]
const ELEMENTS := ["earth", "fire", "water", "air", "neutral"]
const MARK_KINDS := ["trap", "glyph_start", "glyph_end", "aura", "rune", "glyph_now", "portal"]

static var _contracts := {}
static var _trigger := BuffContracts.Trigger.new()
static var _delay := BuffContracts.Delay.new()


## kind -> its EffectContract.
static func contracts() -> Dictionary:
	if _contracts.is_empty():
		for family: Variant in [LifeContracts, BuffContracts, RemovalContracts, MoveContracts, EntityContracts]:
			family.register(_contracts)
	return _contracts


## What grade `id` does wrong: its data, then its effects. `untested` collects the effects no
## fighter of the arena could be touched by (conditions the arena cannot meet).
static func grade(id: int, untested: PackedStringArray = []) -> PackedStringArray:
	var spell := SpellBook.get_spell(id)
	var errors := data_errors(spell)
	for list_name: String in ["effects", "crit_effects"]:
		var list: Array = spell.get(list_name, [])
		if list_name == "crit_effects" and list == spell.get("effects", []):
			continue
		for i in list.size():
			var e: Dictionary = list[i]
			var where := "%s%d %s" % ["crit " if list_name == "crit_effects" else "", i, e.get("kind", "?")]
			for msg: String in effect(spell, e, untested):
				if not errors.has(where + ": " + msg):
					errors.append(where + ": " + msg)
	return errors


static func effect(spell: Dictionary, e: Dictionary, untested: PackedStringArray = []) -> PackedStringArray:
	var errors: PackedStringArray = []
	if not contracts().has(str(e.get("kind", ""))):
		errors.append("no contract for kind %s" % e.get("kind"))
		return errors
	for stage: Array in _stages(e):
		for roll: String in ROLLS:
			for msg: String in _run(spell, stage[1], stage[0], roll, untested):
				if not errors.has(msg):
					errors.append(msg)
	return errors


## [contract, effect] pairs to run: the wrappers first, then the bare effect.
static func _stages(e: Dictionary) -> Array:
	if int(e.get("delay", 0)) > 0:
		var bare := e.duplicate()
		bare.erase("delay")
		return [[_delay, e]] + _stages(bare)
	if e.has("on") and str(e.get("kind", "")) not in FightTriggers.PASSIVE:
		var bare := e.duplicate()
		for key: String in ["on", "turns", "now"]:
			bare.erase(key)
		return [[_trigger, e]] + _stages(bare)
	return [[contracts()[str(e["kind"])], e]]


static func _run(spell: Dictionary, e: Dictionary, contract: EffectContract, roll: String, untested: PackedStringArray) -> PackedStringArray:
	var p := EffectProbe.new(spell, e, roll)
	contract.prepare(p)
	_meet_conditions(p)
	p.center = _aim(p, contract)
	p.oracle = TargetOracle.expected(p.arena, spell, e, p.center)
	if p.oracle.fighters.is_empty() and contract.aim() == EffectContract.Aim.TARGET:
		untested.append("%s %s" % [SpellIndex.label(int(spell.get("id", 0))), e.get("kind")])
	p.before = p.arena.snapshot()
	var alone := spell.duplicate()
	alone["effects"] = [e]
	alone["crit_effects"] = []
	p.out = p.arena.cast(alone, p.center)
	if contract.strict(p):
		_untouched(p)
	for t: Fighter in p.oracle.fighters:
		if p.oracle.exact or p.was(t).changed(t):
			contract.check(p, t)
	contract.check_cast(p)
	return p.errors


## Gives the fighters the states the effect's conditions ask for (its `cond`, its mask's E<n>).
static func _meet_conditions(p: EffectProbe) -> void:
	var wants: Array = [] # [on the caster, state]
	for c: Dictionary in p.effect.get("cond", []):
		if c.has("state") and bool(c["has"]):
			wants.append([str(c.get("who", "")) == "caster", int(c["state"])])
	for tok: String in str(p.effect.get("mask", "")).split(",", false):
		var body := tok.trim_prefix("*")
		if body.length() > 1 and body[0] == "E" and body.substr(1).is_valid_int():
			wants.append([tok.begins_with("*"), int(body.substr(1))])
	for w: Array in wants: # a target's state: on everyone (the caster may be the target)
		for f: Fighter in p.arena.fighters():
			if (f == p.me() or not bool(w[0])) and not f.has_state(int(w[1])):
				p.arena.give_state(f, int(w[1]))


static func _aim(p: EffectProbe, contract: EffectContract) -> int:
	var on_itself := int((p.spell.get("range", [0, 0]) as Array)[1]) == 0
	match contract.aim():
		EffectContract.Aim.FREE:
			return p.arena.free_cell()
		EffectContract.Aim.CELL:
			return p.me().cell if on_itself else p.arena.free_cell()
		EffectContract.Aim.ADJACENT:
			return p.arena.at("ally").cell
	if on_itself:
		return p.me().cell
	if bool(p.spell.get("need_free_cell", false)):
		return p.arena.free_cell()
	for slot: String in AIM_ORDER:
		var cell := p.arena.at(slot).cell
		if not TargetOracle.expected(p.arena, p.spell, p.effect, cell).fighters.is_empty():
			return cell
	return p.arena.foe.cell


## No fighter outside the targets (and the ones the contract allows) changed.
static func _untouched(p: EffectProbe) -> void:
	for f: Fighter in p.arena.fighters():
		if p.before.has(f.id) and not p.is_target(f) and not p.may_change.has(f.id) and p.was(f).changed(f):
			p.fail("%s touched outside the targets: %s" % [p.arena.slot_of(f), p.was(f).describe_change(f)])


## What the data of `spell` says that the fight cannot do: effects not simulated, kinds without a
## contract, sub-spells / marks / summons it names that do not exist, characteristics no rule
## reads.
static func data_errors(spell: Dictionary) -> PackedStringArray:
	var errors: PackedStringArray = []
	if spell.has("partial"):
		errors.append("partial: effects %s not simulated" % [spell["partial"]])
	if (spell.get("effects", []) as Array).is_empty() and not spell.has("noop") and not spell.has("partial"):
		errors.append("no effect") # `noop`: only looks in the game's data
	for e: Dictionary in spell.get("effects", []) + spell.get("crit_effects", []):
		var kind := str(e.get("kind", ""))
		var problem := ""
		if not contracts().has(kind):
			problem = "kind without contract"
		elif kind == "cast" or kind in MARK_KINDS:
			var sub := SpellBook.get_spell(int(e.get("spell", 0)))
			if sub.is_empty():
				problem = "spell %d unknown" % int(e.get("spell", 0))
			elif kind == "cast" and sub.has("noop"):
				problem = "casts spell %d, which does nothing" % int(e.get("spell", 0))
		elif kind in ["summon", "replace"]:
			if SpellBook.summon(int(e.get("monster", 0))).is_empty():
				problem = "monster %d cannot be summoned" % int(e.get("monster", 0))
		elif kind in ["stat", "steal_stat"] and not stat_read(str(e.get("stat", ""))):
			problem = "characteristic %s is read by no rule" % e.get("stat")
		if problem != "" and not errors.has(kind + ": " + problem):
			errors.append(kind + ": " + problem)
	return errors


static func stat_read(stat: String) -> bool:
	if stat in READ_STATS or stat.begins_with(Fighter.SPELL_MOD):
		return true
	for el: String in ELEMENTS:
		if stat in ["damage_" + el, "res_" + el, "res_fixed_" + el]:
			return true
	return false
