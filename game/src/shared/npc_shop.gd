## NPC shops (roadmap P2.02): prices and the checks of a purchase / sale, shared
## by the sim (authority) and the client (greys out what cannot be bought).
##
## A shop is data: {items: [items.id]} per NPC template (worlds/<id>/shops.json).
##
## Sources:
##  - which templates trade: npcs.actions (1 "Acheter/Vendre", 11 "Acheter", 12 "Vendre")
##  - purchase price of an item: items.price (kamas), as in the client's own tables
##  - sale price: APPROX(P2.02) price / 10 (rounded down), the community rule
##    (wiki: "un PNJ rachète un objet 10 fois moins cher qu'il ne le vend"); the real
##    ratio is server data. An item whose items.price is 0 is not bought back.
##  - shop contents: APPROX(P2.02) hand-made, absent from the client.
##  - pods: APPROX(P2.02) a purchase that would push the character over its maximum
##    weight is refused (the roadmap's rule; gains such as drops are never refused).
class_name NpcShop
extends RefCounted

const SELL_DIVISOR := 10
## npcs.actions that open a shop
const TRADE_ACTIONS := [1, 6, 11]
## the largest quantity of one purchase / sale
const MAX_QTY := 1000


## items.price: what the NPC asks for one item.
static func buy_price(item_id: int) -> int:
	return maxi(0, int(GameData.item(item_id).get("price", 0)))


## What the NPC pays for one item (0 = it does not buy it).
static func sell_price(item_id: int) -> int:
	return buy_price(item_id) / SELL_DIVISOR if buy_price(item_id) > 0 else 0


static func sellable(item_id: int) -> bool:
	return buy_price(item_id) > 0


## "" when the purchase is possible, else the error code.
static func check_buy(shop: Dictionary, item_id: int, qty: int, kamas: int, weight: int, max_weight: int) -> String:
	if qty < 1 or qty > MAX_QTY:
		return Protocol.E_BAD_MESSAGE
	# ids come back as floats from the world's JSON: compare as ints (rule 3)
	if not (shop.get("items", []) as Array).any(func(i: Variant) -> bool: return int(i) == item_id) or not GameData.item(item_id).has("id"):
		return Protocol.E_NO_SHOP
	if kamas < buy_price(item_id) * qty:
		return Protocol.E_NOT_ENOUGH_KAMAS
	if weight + int(GameData.item(item_id).get("weight", 1)) * qty > max_weight:
		return Protocol.E_OVERLOADED
	return ""


## The shop as the client shows it: [{item, price}] in the shop's order.
static func offers(shop: Dictionary) -> Array:
	return (shop.get("items", []) as Array).filter(func(i: Variant) -> bool: return GameData.item(int(i)).has("id")) \
			.map(func(i: Variant) -> Dictionary: return {"item": int(i), "price": buy_price(int(i))})
