## Forgemagie (P2.07): a rune changes the rolled effects of an equipment item. Pure rules, shared by the
## sim (WorldSmithmagic) and the client (rune tooltips, the window's preview).
##
## Data: the runes are the items of type 78 (items.json, `gamedata.py items`): effects[0] = [effects.id of the
## characteristic, amount]. The same effect ids are on the equipment ([id, rolled, 0, value]), whose maximum is
## the dice of the item data (diceSide, or diceNum when it is fixed).
##
## SOURCES: the client holds no forgemagie formula (luaformulas has none, nor any table of weights, checked
## in P2.07), the rules live on the server. Everything below the rune data is therefore APPROX(P2.07), the
## Dofus 2 community model simplified:
##  - weight of one unit of a characteristic (WEIGHTS, in hundredths: Vitalité 0.2, Force 1, Sagesse 3, PA 100…);
##    the runes agree (Rune Vi gives 5, Rune Pa Vi 15, Rune Ra Vi 50: 1, 3, 10 weight);
##  - the "puits" (reserve, in hundredths of weight) of an item starts at 0 and is filled by failures;
##  - below the maximum of the characteristic: chance = 100 - 70 * new value / maximum, at least 30 %.
##    Roll d100: <= chance / 10 critical (the characteristic rises, nothing is lost), <= chance success (it rises,
##    the other characteristics lose the weight of the rune), then half of the rest is neutral (nothing happens)
##    and half a failure (the other characteristics lose the weight, the puits gains it);
##  - above the maximum (or a characteristic the item does not have): sure success but the puits must hold the
##    weight of the rune (it pays it); PA / PM / Portée never go more than one above the maximum.
class_name Smithmagic
extends RefCounted

const RUNE_TYPE := 78 # itemtypes.id "Rune de forgemagie"
const CRIT := "crit"
const SUCCESS := "success"
const NEUTRAL := "neutral"
const FAIL := "fail"
const OVERMAX := "overmax"
## errors (Protocol.E_*)
const ERR_ITEM := "fm_item"
const ERR_RUNE := "fm_rune"
const ERR_RESERVE := "fm_reserve"

const MIN_CHANCE := 30
## APPROX(P2.07): weight of one unit, in hundredths (effects.id -> weight x 100)
const WEIGHTS := {
	118: 100, 119: 100, 123: 100, 126: 100, # Force, Agilité, Chance, Intelligence
	124: 300, 125: 20, # Sagesse, Vitalité
	111: 10000, 128: 9000, 117: 5100, # PA, PM, Portée
	115: 1000, 112: 2000, 178: 2000, 182: 3000, # Coups critiques, Dommages, Soins, Invocations
	138: 200, 176: 300, 158: 25, 174: 10, # Puissance, Prospection, Pods, Initiative
	220: 500, 225: 500, 226: 600, 414: 500, 418: 500,
	240: 600, 241: 600, 242: 600, 243: 600, 244: 600, # résistances %
	210: 600, 211: 600, 212: 600, 213: 600, 214: 600,
}
## characteristics that can pass their maximum by one only
const HARD_LIMIT := [111, 128, 117]


## What a rune does: {effect, amount, weight} (weight in hundredths), {} if the item is no rune we simulate.
static func rune_info(rune_id: int) -> Dictionary:
	var it := GameData.item(rune_id)
	if it.is_empty() or int(it.get("type", 0)) != RUNE_TYPE:
		return {}
	var effects: Array = it.get("effects", [])
	if effects.is_empty():
		return {}
	var eid := int((effects[0] as Array)[0])
	var amount := int((effects[0] as Array)[1])
	if amount < 1 or not WEIGHTS.has(eid):
		return {}
	return {"effect": eid, "amount": amount, "weight": amount * int(WEIGHTS[eid])}


## Every rune we simulate, sorted by id.
static func runes() -> Array:
	var out := []
	for id: int in GameData.item_ids():
		if not rune_info(id).is_empty():
			out.append(id)
	return out


## True if the item can be forged: an equipment with at least one rolled characteristic.
static func forgeable(item_id: int) -> bool:
	if Equipment.positions(item_id).is_empty():
		return false
	for e: Array in GameData.item(item_id).get("effects", []):
		if WEIGHTS.has(int(e[0])) and ItemEffects.rolled_at_creation(int(e[0])):
			return true
	return false


## The forgemagus workshops (skills.isForgemagus), sorted by id.
static func workshops() -> Array:
	var out := []
	for k: Variant in GameData.table("skills"):
		if int(GameData.row("skills", int(k)).get("isForgemagus", 0)) == 1:
			out.append(int(k))
	out.sort()
	return out


## True if the workshop (a skill) works on that kind of item (skills.modifiableItemTypeIds = itemtypes.id).
static func accepts(skill_id: int, item_id: int) -> bool:
	var type := int(GameData.item(item_id).get("type", 0))
	return (GameData.row("skills", skill_id).get("modifiableItemTypeIds", []) as Array).any(func(t: Variant) -> bool: return int(t) == type) # JSON numbers are floats


## The maximum of a characteristic on an item (0 = the item does not have it).
static func maximum(item_id: int, effect_id: int) -> int:
	for e: Array in GameData.item(item_id).get("effects", []):
		if int(e[0]) == effect_id:
			return maxi(int(e[1]), int(e[2]))
	return 0


## Chance (%) of a plain success when the characteristic goes from `value` to `value + amount` (<= the maximum).
static func chance(new_value: int, max_value: int) -> int:
	if max_value <= 0:
		return MIN_CHANCE
	return clampi(100 - 70 * new_value / max_value, MIN_CHANCE, 100)


## The preview the window shows: {kind: "overmax" / "roll", chance, crit, refused: err code or ""}.
static func preview(item_id: int, effects: Array, reserve: int, rune_id: int) -> Dictionary:
	var rune := rune_info(rune_id)
	if rune.is_empty():
		return {"refused": ERR_RUNE}
	if not forgeable(item_id):
		return {"refused": ERR_ITEM}
	var eid := int(rune["effect"])
	var max_value := maximum(item_id, eid)
	var new_value := value_of(effects, eid) + int(rune["amount"])
	if new_value > max_value:
		var hard := HARD_LIMIT.has(eid) and new_value > max_value + 1
		var refused := ERR_RESERVE if hard or reserve < int(rune["weight"]) else ""
		return {"kind": OVERMAX, "chance": 100, "crit": 0, "refused": refused}
	var c := chance(new_value, max_value)
	return {"kind": "roll", "chance": c, "crit": c / 10, "refused": ""}


## The value of a characteristic on an instance's effects.
static func value_of(effects: Array, effect_id: int) -> int:
	for e: Array in effects:
		if int(e[0]) == effect_id:
			return int(e[1])
	return 0


## Applies a rune. `effects` / `reserve`: the instance's. Returns {err, outcome, effects, reserve, lost}
## (err "" when it works; the rune is spent only then), outcome in CRIT / SUCCESS / NEUTRAL / FAIL / OVERMAX.
## `lost` = [[effect id, units lost]]. Deterministic for a seeded `rng`.
static func apply(item_id: int, effects: Array, reserve: int, rune_id: int, rng: RandomNumberGenerator) -> Dictionary:
	var pv := preview(item_id, effects, reserve, rune_id)
	if str(pv["refused"]) != "":
		return {"err": str(pv["refused"])}
	var rune := rune_info(rune_id)
	var eid := int(rune["effect"])
	var out_effects: Array = effects.duplicate(true)
	var lost := []
	var outcome := ""
	if str(pv["kind"]) == OVERMAX:
		reserve -= int(rune["weight"])
		outcome = OVERMAX
		_add(out_effects, item_id, eid, int(rune["amount"]))
	else:
		var roll := rng.randi_range(1, 100)
		var c := int(pv["chance"])
		if roll <= int(pv["crit"]):
			outcome = CRIT
		elif roll <= c:
			outcome = SUCCESS
		elif roll <= c + (100 - c) / 2:
			outcome = NEUTRAL
		else:
			outcome = FAIL
		if outcome == CRIT or outcome == SUCCESS:
			_add(out_effects, item_id, eid, int(rune["amount"]))
		if outcome == SUCCESS or outcome == FAIL:
			var freed := _lose(out_effects, eid, int(rune["weight"]), rng, lost)
			if outcome == FAIL:
				reserve += freed
	return {"err": "", "outcome": outcome, "effects": out_effects, "reserve": reserve, "lost": lost}


static func _add(effects: Array, item_id: int, eid: int, amount: int) -> void:
	for e: Array in effects:
		if int(e[0]) == eid:
			e[1] = int(e[1]) + amount
			return
	effects.append([eid, amount, 0, 0])


## Takes `weight` (hundredths) off the other characteristics, one at random after the other. Returns the weight taken.
static func _lose(effects: Array, keep: int, weight: int, rng: RandomNumberGenerator, lost: Array) -> int:
	var taken := 0
	while taken < weight:
		var from := []
		for i in effects.size():
			var e: Array = effects[i]
			if int(e[0]) != keep and int(e[1]) > 0 and WEIGHTS.has(int(e[0])) and ItemEffects.rolled_at_creation(int(e[0])):
				from.append(i)
		if from.is_empty():
			break
		var e: Array = effects[from[rng.randi_range(0, from.size() - 1)]]
		var w := int(WEIGHTS[int(e[0])])
		var units := mini(int(e[1]), ceili(float(weight - taken) / w))
		e[1] = int(e[1]) - units
		taken += units * w
		lost.append([int(e[0]), units])
	return taken
