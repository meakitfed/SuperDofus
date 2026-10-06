## One participant of a fight (a player, or one monster of a group).
class_name Fighter
extends RefCounted

## characteristics (stats): strength (earth + neutral), intelligence (fire, heals),
## chance (water), agility (air, tackle, escape), wisdom (AP/MP removal and dodge),
## vitality, power (+% damage), damage (fixed), heals, range, crit, ap_dodge,
## mp_dodge, push_res, push_damage, res_<element> (%)
const ELEMENT_STAT := {"earth": "strength", "neutral": "strength", "fire": "intelligence",
		"water": "chance", "air": "agility"}

var id := 0
var team := 0 # 0 = players, 1 = monsters
var name := ""
## localized name id (monsters), resolved by the client; 0 = use `name`
var name_id := 0
## portrait picto (monster gfxId), 0 = render the look
var portrait := 0
var looks: PackedStringArray = []
var level := 1
var cell := 0:
	set(v):
		if v != cell:
			prev_cell = cell
		cell = v
## positions the rollbacks go back to (P1.13q): before the most recent move (1100), at the start of
## its turn (1099) and of the fight (784); -1 = none yet
## AP spent on spells since its turn began (1132, P1.17)
var ap_spent := 0
var prev_cell := -1
var turn_begin_cell := -1
var start_cell := -1
var dir := 1
var hp := 1
var max_hp := 1
var ap := 6
var mp := 3
var max_ap := 6
var max_mp := 3
var alive := true
var spells: Array = []
## spells only this fighter has: Equipment.WEAPON_SPELL -> its weapon's hit
var own_spells := {}
var stats := {} # base characteristics (see above); buffs add on top
var buffs: Array = [] # Buff
var pass_turn := false # 1031 (P1.17b 7): its turn ends once the spell is cast, or is skipped
var cooldowns := {} # spell id -> turns before it can be cast again
## controlled by FightAI instead of a player
var ai := false
## FightAI.profile cache ("" = not computed yet)
var ai_profile := ""
var flee_turns := 0 # turns the AI spent running away (FightAI: it fights back after FLEE_MAX_TURNS)
## PlayerActor id for player fighters, -1 otherwise
var player_id := -1
## placement phase
var ready := false
## a player whose connection dropped (S.02b): since when (sim ms), -1 = present. Fight.tick passes
## its turns, then hands it to the AI (`ai_takeover`) until it comes back
var absent_since := -1
var ai_takeover := false
## a player who fled while others stayed (Fight.leave): out of the fight, no reward (P3.04)
var left := false
## monsters: what beating them gives {xp, kamas: [min, max], drops: [{item, pct}]}
var loot := {}
## summons (P1.11, Summons): the summoner's fighter id (-1 = not a summon), the monster
## (monsters.id), uses a summon slot, has turns (canPlay), tackles (canTackle)
var summoner := -1
var monster := 0
## characters: breeds.id (target masks B / b, P1.13h), 0 otherwise
var breed := 0
var grade := 1
## a bomb that exploded (Summons.detonate, P1.13d): once only, its explosion goes on after it died
var exploded := false
## while it casts a spell projected through portals (P1.13f): the portals' % bonus, else -1
var projecting := -1
var summon_slot := false
var plays := true
var tackles := true
## monsters.canSwitchPos / canSwitchPosOnTarget (m_flags bits 9 / 10, P1.13n FightDisplace.can_swap)
var can_switch := true
var can_switch_on_target := true
## carry (P1.12, Carry): the fighter this one carries / is carried by (-1 = none)
var carrying := -1
var carried_by := -1
## the last fighter that hit this one (P1.13i, FightTriggers K: its killer), -1 = none
var last_hit_by := -1
## that hit was a weapon's (P1.13m: KWW rather than KWS)
var last_hit_weapon := false


## A player character (not a monster, a summon or a double).
func is_character() -> bool:
	return player_id >= 0 or (monster == 0 and summoner == -1 and not ai)


## A spell this fighter can cast: its own (weapon) or SpellBook's.
func spell(id: int) -> Dictionary:
	var s: Dictionary = own_spells[id] if own_spells.has(id) else SpellBook.get_spell(id)
	if s.is_empty() or not buffs.any(func(b: Buff) -> bool: return b.kind == "stat" and b.stat.begins_with(SPELL_MOD)):
		return s
	return _modded(s)


## Stat buffs named "spell_mod:<ap|heal|rmin|rmax>:<spells.id>" change that spell (P1.17b, 285 BoostSpellApCost
## "#1 : -#3 PA", 2935 BoostSpellBaseHeal "#1 : +#3 soins de base"): its AP cost, or the base of its heals.
const SPELL_MOD := "spell_mod:"


func _modded(s: Dictionary) -> Dictionary:
	var origin := int(s.get("origin", s.get("id", 0)))
	var ap := 0
	var heal := 0
	var rmin := -1
	var rmax := -1
	var extra := {} # P1.17b (6): perturn / rminadd / crit add up, nolos / freecell are flags
	for b: Buff in buffs:
		if b.kind != "stat" or not b.stat.begins_with(SPELL_MOD):
			continue
		var p := b.stat.split(":")
		if p.size() != 3 or int(p[2]) != origin:
			continue
		if p[1] == "ap":
			ap += b.value
		elif p[1] == "rmax": # 2905 / 2906: the range is fixed (P1.17b)
			rmax = b.value
		elif p[1] == "rmin":
			rmin = b.value
		elif p[1] == "heal":
			heal += b.value
		else:
			extra[p[1]] = int(extra.get(p[1], 0)) + b.value
	if ap == 0 and heal == 0 and rmin < 0 and rmax < 0 and extra.is_empty():
		return s
	var out := s.duplicate()
	# 290 "+#3 lancer(s) par tour", 287 "+#3% Critique", 280 "+#3 Portée minimale", 289 "ligne de vue désactivée",
	# 299 "case libre nécessaire activée" (effects.descriptionId texts). APPROX(P1.17b): 280 adds to the minimum
	if extra.has("perturn"):
		out["per_turn"] = int(s.get("per_turn", 99)) + int(extra["perturn"])
	if extra.has("crit"):
		out["crit"] = int(s.get("crit", 0)) + int(extra["crit"])
	if extra.has("nolos"):
		out["los"] = false
	if extra.has("freecell"):
		out["need_free_cell"] = true
	# P1.17b (9): 291 "+#3 lancer(s) par cible", 297 / 314 "case occupee necessaire desactivee / activee",
	# 798 "cible visible necessaire activee" (texts only)
	if extra.has("pertarget"):
		out["per_target"] = int(s.get("per_target", 99)) + int(extra["pertarget"])
	if extra.has("notaken"):
		out["need_taken_cell"] = false
	if extra.has("taken"):
		out["need_taken_cell"] = true
	if extra.has("visible"):
		out["need_visible_target"] = true
	if extra.has("rminadd"):
		var r0: Array = (out.get("range", s.get("range", [0, 0])) as Array).duplicate()
		r0[0] = maxi(0, int(r0[0]) + int(extra["rminadd"]))
		out["range"] = r0
	if rmin >= 0 or rmax >= 0:
		var r: Array = (s.get("range", [0, 0]) as Array).duplicate()
		r[0] = rmin if rmin >= 0 else r[0]
		r[1] = rmax if rmax >= 0 else r[1]
		out["range"] = r
	out["ap"] = maxi(0, int(s.get("ap", 0)) + ap)
	if heal != 0:
		for key: String in ["effects", "crit_effects"]:
			var list: Array = []
			for e: Dictionary in s.get(key, []):
				if str(e.get("kind", "")) == "heal":
					e = e.duplicate()
					e["min"] = int(e.get("min", 0)) + heal
					e["max"] = int(e.get("max", 0)) + heal
				list.append(e)
			if s.has(key):
				out[key] = list
	return out


## Characteristic with buffs.
func stat(name: String) -> int:
	var v := int(stats.get(name, 0))
	var all := name.begins_with("res_") and not name.begins_with("res_fixed_")
	for b: Buff in buffs:
		if b.kind == "stat" and (b.stat == name or (all and b.stat == "res_all")):
			v += b.value
	return v


func cur_max_ap() -> int:
	return maxi(0, max_ap + _sum("ap"))


func cur_max_mp() -> int:
	return maxi(0, max_mp + _sum("mp"))


func has_state(state: int) -> bool:
	return buffs.any(func(b: Buff) -> bool: return b.kind == "state" and b.state == state)


func state_ids() -> Array:
	return buffs.filter(func(b: Buff) -> bool: return b.kind == "state").map(func(b: Buff) -> int: return b.state)


## A state flag (cant_be_pushed, invulnerable, no_cast...) from any current state.
func has_flag(flag: String) -> bool:
	return buffs.any(func(b: Buff) -> bool: return b.kind == "state" and b.flags.has(flag))


## `spell` is blocked by a no_cast state (spellstates.preventsSpellCast), unless it
## needs that state (the throws of a Porteur: FightRules.needs_state).
func cast_forbidden(spell: Dictionary) -> bool:
	return buffs.any(func(b: Buff) -> bool:
		return b.kind == "state" and b.flags.has("no_cast") and not FightRules.needs_state(spell, b.state))


func shield() -> int:
	return _sum("shield")


## Derived characteristics: the same StatFormulas as the character sheet, on
## the characteristics with buffs.
func initiative() -> int:
	return StatFormulas.initiative(stat, hp, max_hp)


func tackle() -> int:
	return StatFormulas.tackle(stat)


func escape() -> int:
	return StatFormulas.escape(stat)


func start_turn() -> void:
	ap_spent = 0
	ap = cur_max_ap()
	mp = cur_max_mp()


func _sum(kind: String) -> int:
	var v := 0
	for b: Buff in buffs:
		if b.kind == kind:
			v += b.value
	return v


func to_dict() -> Dictionary:
	return {"id": id, "team": team, "name": name, "name_id": name_id, "portrait": portrait, "looks": Array(looks), "cell": cell, "dir": dir,
			"level": level, "hp": hp, "max_hp": max_hp, "ap": ap, "mp": mp, "max_ap": max_ap,
			"max_mp": max_mp, "alive": alive, "spells": spells, "summoner": summoner, "monster": monster, "carrying": carrying, "carried_by": carried_by, "own_spells": _own_spells_dict(), "ready": ready, "shield": shield(),
			"buffs": buffs.map(func(b: Buff) -> Dictionary: return b.to_dict())}


## own_spells with string keys (JSON objects have string keys).
func _own_spells_dict() -> Dictionary:
	var out := {}
	for id: int in own_spells:
		out[str(id)] = own_spells[id]
	return out
