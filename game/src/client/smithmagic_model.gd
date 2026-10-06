## State of the smithmagic window (P2.07b), without any Node so a test can drive it: the workshop (a
## forgemagus skill), the item and the rune picked in the bag, the preview and the history of fm_result.
## The sim decides everything (Smithmagic rules, the dice): this only filters the bag, asks the shared
## preview and builds the message.
class_name SmithmagicModel
extends RefCounted

const OUTCOME_TEXTS := {
	Smithmagic.CRIT: "Réussite critique",
	Smithmagic.SUCCESS: "Réussite",
	Smithmagic.NEUTRAL: "Neutre",
	Smithmagic.FAIL: "Échec",
	Smithmagic.OVERMAX: "Dépassement (puits)",
}
const MAX_HISTORY := 30

var skill := 0
## uid of the picked item (0 = none) and id of the picked rune (0 = none)
var item_uid := 0
var rune := 0
## [{uid, rune, outcome, lost, item}] newest first
var history: Array = []


func _init() -> void:
	var w := Smithmagic.workshops()
	skill = int(w[0]) if not w.is_empty() else 0


func set_skill(s: int) -> void:
	skill = s
	item_uid = 0


## The bag stacks the workshop can forge (equipment with characteristics of its item types), uid order.
func forgeable(bag: Array) -> Array:
	return bag.filter(func(it: Dictionary) -> bool:
		return Smithmagic.forgeable(int(it["id"])) and Smithmagic.accepts(skill, int(it["id"])))


## The rune stacks of the bag (runes we simulate only).
static func runes_in(bag: Array) -> Array:
	return bag.filter(func(it: Dictionary) -> bool: return not Smithmagic.rune_info(int(it["id"])).is_empty())


## The picked item in the bag ({} if gone: it is dropped from the pick).
func picked(bag: Array) -> Dictionary:
	for it: Dictionary in bag:
		if int(it["uid"]) == item_uid:
			return it
	item_uid = 0
	return {}


## Shared preview of the pick ({} until an item and a rune are picked): {kind, chance, crit, refused}.
func preview(bag: Array) -> Dictionary:
	var it := picked(bag)
	if it.is_empty() or rune == 0:
		return {}
	return Smithmagic.preview(int(it["id"]), it["effects"], int(it.get("reserve", 0)), rune)


## True if the rune is in the bag and the sim would not refuse the pick.
func can_apply(bag: Array) -> bool:
	var pv := preview(bag)
	if pv.is_empty() or str(pv["refused"]) != "":
		return false
	return bag.any(func(it: Dictionary) -> bool: return int(it["id"]) == rune)


## Message that puts the rune on the item (null when the pick cannot work).
func apply(bag: Array) -> Variant:
	return Protocol.fm_apply(item_uid, rune) if can_apply(bag) else null


## fm_result event: the history, and the pick follows the item (a stack gives one away: new uid).
func on_result(ev: Dictionary) -> void:
	history.push_front({"uid": int(ev["uid"]), "rune": int(ev["rune"]), "outcome": str(ev["outcome"]), "lost": ev["lost"], "item": ev["item"]})
	if history.size() > MAX_HISTORY:
		history.resize(MAX_HISTORY)
	item_uid = int(ev["uid"])


## One line of the history: "Réussite : Rune Fo, -3 Vitalité".
static func result_text(h: Dictionary) -> String:
	var text := "%s : %s" % [OUTCOME_TEXTS.get(h["outcome"], str(h["outcome"])), UiTooltips.item_name(int(h["rune"]))]
	for l: Array in h["lost"]:
		text += ", -%d %s" % [int(l[1]), effect_name(int(l[0]))]
	return text


## "Vitalité" from an effect id (the description template without its numbers).
static func effect_name(effect_id: int) -> String:
	var t := UiTooltips.item_effect_text([effect_id, 0, 0, 0])
	return RegEx.create_from_string("^[-+]?[0-9]+[ ]*").sub(t, "").strip_edges() if t != "" else "Effet %d" % effect_id


## Why the preview refuses, in words (the same texts as the sim's errors).
static func refused_text(code: String) -> String:
	return ErrorTexts.text({"code": code})
