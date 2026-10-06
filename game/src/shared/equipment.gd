## Equipment rules (roadmap P1.06), shared by the sim (equip, fight stats) and
## the client (slots of the equipment window, set tooltips):
##   slots: itemtypes.superTypeId -> itemsupertypes.possiblePositions (Dofus
##   inventory positions: 0 amulet, 1 weapon, 2 / 4 rings, 3 belt, 5 boots,
##   6 hat, 7 cape, 8 pet, 9-14 Dofus and trophies, 15 shield);
##   stats: each effect whose effects.characteristic is a characteristic,
##   signed by effects.bonusType; sets: itemsets.effects[n - 1] for n items worn;
##   the weapon hit: a spell made from the weapon's fields (items.apCost, range,
##   criticalHitProbability / criticalHitBonus…) and its damage effects, in the
##   weapon type's zone (itemtypes.rawZone).
class_name Equipment
extends RefCounted

const AMULET := 0
const WEAPON := 1
const RING_LEFT := 2
const BELT := 3
const RING_RIGHT := 4
const BOOTS := 5
const HAT := 6
const CAPE := 7
const PET := 8
const DOFUS := [9, 10, 11, 12, 13, 14]
const SHIELD := 15
const SLOTS := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]
const SLOT_NAMES := {0: "Amulette", 1: "Arme", 2: "Anneau", 3: "Ceinture", 4: "Anneau", 5: "Bottes", 6: "Coiffe",
		7: "Cape", 8: "Familier", 9: "Dofus / trophée", 10: "Dofus / trophée", 11: "Dofus / trophée",
		12: "Dofus / trophée", 13: "Dofus / trophée", 14: "Dofus / trophée", 15: "Bouclier"}
## castable id of the equipped weapon's hit (a fighter-own spell, see Fighter.own_spells)
const WEAPON_SPELL := 999_999
## characteristics.id -> Fighter / Character stat name
const CHARACTERISTIC_STAT := {1: "ap", 23: "mp", 10: "strength", 11: "vitality", 12: "wisdom", 13: "chance",
		14: "agility", 15: "intelligence", 16: "damage", 18: "crit", 19: "range", 25: "power", 26: "summons",
		27: "ap_dodge", 28: "mp_dodge", 33: "res_earth", 34: "res_fire", 35: "res_water", 36: "res_air",
		37: "res_neutral", 40: "pods", 44: "initiative", 48: "prospecting", 49: "heals", 54: "res_fixed_earth",
		55: "res_fixed_fire", 56: "res_fixed_water", 57: "res_fixed_air", 58: "res_fixed_neutral", 78: "escape",
		79: "tackle", 82: "ap_attack", 83: "mp_attack", 84: "push_damage", 85: "push_res", 86: "crit_damage",
		87: "crit_res", 88: "damage_earth", 89: "damage_fire", 90: "damage_water", 91: "damage_air",
		92: "damage_neutral"}
## weapon hit effects (same ids as spells, see tools/extractor/spells.py)
const WEAPON_DAMAGE := {96: "water", 97: "earth", 98: "air", 99: "fire", 100: "neutral"}
const WEAPON_STEAL := {91: "water", 92: "earth", 93: "air", 94: "fire", 95: "neutral"}
const SHAPES := {"P": "point", "C": "circle", "X": "cross", "G": "square", "Q": "cross_ring", "O": "ring",
		"L": "line", "T": "tline"}


## The slots an item can go in ([] = not equipment).
static func positions(item_id: int) -> Array:
	var type := GameData.row("itemtypes", int(GameData.item(item_id).get("type", 0)))
	var sup := GameData.row("itemsupertypes", int(type.get("superTypeId", 0)))
	return (sup.get("possiblePositions", []) as Array).map(func(p: Variant) -> int: return int(p)) \
			.filter(func(p: int) -> bool: return SLOTS.has(p))


## {stat: value} of item effects ([effects.id, value, …]).
static func stats_of(effects: Array) -> Dictionary:
	var out := {}
	for e: Array in effects:
		var row := GameData.row("effects", int(e[0]))
		var stat: String = CHARACTERISTIC_STAT.get(int(row.get("characteristic", -1)), "")
		var sign := int(row.get("bonusType", 0))
		if stat == "" or sign == 0:
			continue
		out[stat] = int(out.get(stat, 0)) + sign * maxi(int(e[1]), int(e[2]))
	return out


## The set bonus effects of `n` items of set `set_id` worn (itemsets.effects[n - 1]).
static func set_bonus(set_id: int, n: int) -> Array:
	var effects: Array = GameData.item_set(set_id).get("effects", [])
	return effects[n - 1] if n >= 1 and n <= effects.size() else []


## {set id: items of it worn} for the worn item ids (each id counts once).
static func set_counts(item_ids: Array) -> Dictionary:
	var out := {}
	var seen := {}
	for id: int in item_ids:
		var sid := int(GameData.item(id).get("set", 0))
		if sid > 0 and not seen.has(id):
			seen[id] = true
			out[sid] = int(out.get(sid, 0)) + 1
	return out


## Every characteristic the worn items and their sets give.
static func bonus(worn: Array) -> Dictionary:
	var out := {}
	var ids: Array = []
	for it: Dictionary in worn:
		ids.append(int(it["id"]))
		_add(out, stats_of(it.get("effects", [])))
	var sets := set_counts(ids)
	for sid: int in sets:
		_add(out, stats_of(set_bonus(sid, int(sets[sid]))))
	return out


static func _add(into: Dictionary, more: Dictionary) -> void:
	for k: String in more:
		into[k] = int(into.get(k, 0)) + int(more[k])


## Why `item_id` cannot go in `slot` ("" = it can). `worn`: slot -> item id;
## `values`: CriteriaEval values of the character.
##   level: items.level <= character level; conditions: items.criterions;
##   one of each Dofus / trophy; APPROX(P1.06): the same item of a set only
##   once (rings), known Dofus rule not in the data.
static func equip_error(item_id: int, slot: int, level: int, values: Dictionary, worn: Dictionary) -> String:
	var data := GameData.item(item_id)
	if data.is_empty():
		return Protocol.E_UNKNOWN_ITEM
	if not positions(item_id).has(slot):
		return Protocol.E_BAD_SLOT
	if int(data.get("level", 1)) > level:
		return Protocol.E_ITEM_LEVEL
	if not CriteriaEval.ok(str(data.get("criteria", "")), values):
		return Protocol.E_ITEM_CONDITION
	for s: int in worn:
		if s == slot or int(worn[s]) != item_id:
			continue
		if DOFUS.has(slot) or int(data.get("set", 0)) > 0:
			return Protocol.E_ALREADY_EQUIPPED
	return ""


## The hit of weapon `item_id` as a castable spell (id WEAPON_SPELL); {} if not a weapon.
static func weapon_spell(item_id: int) -> Dictionary:
	var data := GameData.item(item_id)
	var w: Dictionary = data.get("weapon", {})
	if w.is_empty():
		return {}
	var area := zone(str(GameData.row("itemtypes", int(data.get("type", 0))).get("rawZone", "P")))
	var effects: Array = []
	var crit_effects: Array = []
	for e: Array in data.get("effects", []):
		var eid := int(e[0])
		var kind := "damage" if WEAPON_DAMAGE.has(eid) else ("steal" if WEAPON_STEAL.has(eid) else "")
		if kind == "":
			continue
		var lo := int(e[1])
		var hi := maxi(lo, int(e[2]))
		var fx := {"kind": kind, "element": WEAPON_DAMAGE.get(eid, WEAPON_STEAL.get(eid, "neutral")), "target": "all",
				"min": lo, "max": hi, "duration": 0, "delay": 0, "area": area}
		effects.append(fx)
		var crit := fx.duplicate()
		crit["min"] = lo + int(w.get("crit_bonus", 0)) # items.criticalHitBonus: + per damage line
		crit["max"] = hi + int(w.get("crit_bonus", 0))
		crit_effects.append(crit)
	return {"id": WEAPON_SPELL, "weapon": item_id, "name_id": int(data.get("name_id", 0)), "name": str(data.get("name", "")),
			"item_icon": int(data.get("icon", 0)), "level": 1, "ap": int(w.get("ap", 3)),
			"range": [int(w.get("min_range", 1)), int(w.get("range", 1))], "range_boost": false,
			"los": bool(w.get("los", 1)), "in_line": bool(w.get("in_line", 0)), "need_free_cell": false,
			"need_taken_cell": false, "per_turn": maxi(1, int(w.get("per_turn", 1))), "per_target": 99, "cooldown": 0,
			"initial_cooldown": 0, "crit": int(w.get("crit", 0)), "area": area, "effects": effects,
			"crit_effects": crit_effects, "anim": ["AnimAttaque0"], "fx": {}}


## itemtypes.rawZone ("P", "X1,0,10,1", "T1,10,1"…) -> {shape, size, min?}: param1, then
## param2 only when there are four numbers (the minimum distance of C / X / Q / L / T, see
## FightRules.zone), then the damage decrease (step %, times).
static func zone(raw: String) -> Dictionary:
	if raw == "" or not SHAPES.has(raw[0]) or raw[0] == "P":
		return {"shape": "point", "size": 0}
	var params := raw.substr(1).split(",")
	var out := {"shape": SHAPES[raw[0]], "size": int(params[0]) if params[0].is_valid_int() else 1}
	if params.size() >= 4 and params[1].is_valid_int() and int(params[1]) > 0 and raw[0] in "CXQLT":
		out["min"] = int(params[1])
	# the last two numbers: damage decrease step % and times (P1.13j, FightRules.efficiency)
	if params.size() >= 3 and int(params[-2]) > 0 and int(params[-1]) > 0:
		out["step"] = int(params[-2])
		out["steps"] = int(params[-1])
	return out
