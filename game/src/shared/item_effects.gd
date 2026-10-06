## Item effects (roadmap P1.05): what an item instance carries and what using
## it does. Item data (GameData.item) lists `effects` = items.possibleEffects as
## [effects.id, diceNum, diceSide, value]; an instance keeps the same format.
## At creation (drop, craft), an effect that is a characteristic bonus or malus
## (effects.useDice and effects.bonusType != 0: Force, PA, Soins…) is rolled once
## between diceNum and diceSide and stored as [id, value, 0, v]; the others
## (weapon hits, "Rend #1 PV"…) keep their dice and are rolled when used.
class_name ItemEffects
extends RefCounted

const HEAL := 110           # "Rend #1{~1~2 à }#2 points de vie"
const ENERGY := 139         # "Rend #1{~1~2 à }#2 points d'énergie"
## [614, 0, jobs.id, xp]: job XP. APPROX(P2.05b): read from the scrolls (items 695 "Parchemin de Bucheron" = [614, 0, 2, 100]),
## the effect text (effects 614, descriptionId 1104136) was not checked: the 4th value is taken as XP.
const JOB_XP := 614
const RECALL := 600         # "Téléporte au point de sauvegarde"
## "+#1 <stat> additionnelle" (effects.characteristic 12 / 10 / 13 / 14 / 11 / 15)
const SCROLLS := {606: "wisdom", 607: "strength", 608: "chance", 609: "agility", 610: "vitality", 611: "intelligence"}


## True if `effect_id` is rolled once when the item is created.
static func rolled_at_creation(effect_id: int) -> bool:
	var e := GameData.row("effects", effect_id)
	return int(e.get("useDice", 0)) == 1 and int(e.get("bonusType", 0)) != 0


## The effects of a new instance of `item_id`, rolled with `rng` (the sim's, seeded).
static func roll(item_id: int, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for e: Array in GameData.item(item_id).get("effects", []):
		var eid := int(e[0])
		var lo := int(e[1])
		var hi := maxi(lo, int(e[2]))
		if rolled_at_creation(eid):
			out.append([eid, rng.randi_range(lo, hi), 0, int(e[3])])
		else:
			out.append([eid, lo, int(e[2]), int(e[3])])
	return out


## One value of a dice effect [id, diceNum, diceSide, value] (fixed when diceSide < diceNum).
static func dice(e: Array, rng: RandomNumberGenerator) -> int:
	var lo := int(e[1])
	return rng.randi_range(lo, maxi(lo, int(e[2])))


## The effects `use_item` applies (the others, emotes, spells…, wait for their lots).
static func usable(effects: Array) -> Array:
	return effects.filter(func(e: Array) -> bool:
		var eid := int(e[0])
		return eid == HEAL or eid == ENERGY or eid == RECALL or eid == JOB_XP or SCROLLS.has(eid))
