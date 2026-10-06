## Trade between two players (P3.11): the pure rules, shared by the sim and the client.
## An offer is {uid: qty} (stacks of the offerer's bag) plus kamas. Nothing is Dofus-specific
## beyond the item weights (items.realWeight, through GameData).
##   APPROX(P3.11): the numbers below (60 s invitation, 20 stacks per offer, quantity cap) are
##   ours: the client tables and luaformulas hold no trade rule (the exchange itself is server
##   logic in Dofus). The flow follows the game: invitation, common window, both sides
##   validate, any change cancels the validations, move / fight / disconnection cancels.
class_name TradeRules
extends RefCounted

const INVITE_TTL_MS := 60000
## stacks in one offer
const MAX_LINES := 20
## the largest quantity of one line
const MAX_QTY := 100000

const BAG := -1


## The lines [{uid, qty}] of a trade_set as {uid: qty} (a repeated uid adds up), or
## {"err": code} when a line is malformed or too many.
static func normalize(lines: Array) -> Dictionary:
	var out := {}
	if lines.size() > MAX_LINES:
		return {"err": Protocol.E_BAD_MESSAGE}
	for l: Variant in lines:
		if not l is Dictionary or not (l as Dictionary).has("uid") or not (l as Dictionary).has("qty"):
			return {"err": Protocol.E_BAD_MESSAGE}
		var uid: Variant = l["uid"]
		var qty: Variant = l["qty"]
		if not _whole(uid) or not _whole(qty) or int(qty) < 1 or int(qty) > MAX_QTY:
			return {"err": Protocol.E_BAD_MESSAGE}
		out[int(uid)] = int(out.get(int(uid), 0)) + int(qty)
	return out


static func _whole(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or (typeof(v) == TYPE_FLOAT and v == floorf(v) and is_finite(v))


## "" if the offerer may give `items` ({uid: qty}) and `kamas` out of its bag (`stacks`: uid ->
## instance) and purse (`have`), else the error code: unknown_item, item_worn, not_enough_kamas.
static func offer_error(stacks: Dictionary, have: int, items: Dictionary, kamas: int) -> String:
	if kamas < 0:
		return Protocol.E_BAD_MESSAGE
	if kamas > have:
		return Protocol.E_NOT_ENOUGH_KAMAS
	for uid: int in items:
		var it: Dictionary = stacks.get(uid, {})
		if it.is_empty() or int(items[uid]) > int(it["qty"]) or int(items[uid]) < 1:
			return Protocol.E_UNKNOWN_ITEM
		if int(it.get("pos", BAG)) != BAG:
			return Protocol.E_ITEM_WORN
	return ""


## Pods of an offer ({uid: qty} of `stacks`).
static func weight_of(stacks: Dictionary, items: Dictionary) -> int:
	var w := 0
	for uid: int in items:
		var it: Dictionary = stacks.get(uid, {})
		if not it.is_empty():
			w += int(GameData.item(int(it["id"])).get("weight", 1)) * int(items[uid])
	return w


## "" if a bag that weighs `weight` of at most `max_weight` pods can give away `giving` and
## take `receiving` pods; else overloaded (a full bag fails the trade, nothing is lost).
static func weight_error(weight: int, max_weight: int, giving: int, receiving: int) -> String:
	return Protocol.E_OVERLOADED if weight - giving + receiving > max_weight else ""
