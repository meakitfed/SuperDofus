## The marketplace (hotel de vente, roadmap P2.10): the pure rules, shared by the sim and the
## client. A player puts lots of identical objects on sale for a price; the lot goes to the
## first buyer, the kamas to the seller, even when it is offline.
##
## Sources:
##  - allowed lot sizes 1 / 10 / 100 / 1000: auctionhouses.allowedQuantities (the 7 houses of
##    the client all hold [1, 10, 100, 1000]).
##  - what can be sold: APPROX(P2.10) any object whose items.price is above 0 (the tradability
##    flags of items are not read yet, like the bank and the shops).
##  - the category filter: itemtypes.categoryId of the object's type (items.type).
##  - tax: APPROX(P2.10) 2 % of the lot price (at least 1 kama) paid when the lot is put on sale and
##    never refunded, as the community describes it; the real rate is server data (not in the
##    client tables, not in luaformulas).
##  - duration: APPROX(P2.10) 14 days, then the lot is expired: it cannot be bought any more
##    and its seller takes it back (hdv_cancel), with no new tax.
##  - at most MAX_LISTINGS lots per character: APPROX(P2.10), the real limit is server data.
##  - average price: the mean unit price of the sales of the object (mean of price / quantity
##    weighted by quantity), kept by Marketplace.
class_name MarketRules
extends RefCounted

## auctionhouses.allowedQuantities
const QUANTITIES := [1, 10, 100, 1000]
const TAX_PERCENT := 2
const DURATION_MS := 14 * 24 * 3600 * 1000
const MAX_LISTINGS := 50
## kamas fit in 32 bits in the client
const MAX_PRICE := 2000000000
const PAGE_SIZE := 20
const ALL_CATEGORIES := -1


## The tax of one lot put on sale at `price`.
static func tax(price: int) -> int:
	return maxi(1, price * TAX_PERCENT / 100)


static func sellable(item_id: int) -> bool:
	return NpcShop.sellable(item_id)


## itemtypes.categoryId of an object (-1 if unknown).
static func category(item_id: int) -> int:
	var type := GameData.row("itemtypes", int(GameData.item(item_id).get("type", 0)))
	return int(type.get("categoryId", -1))


## "" when a sale of `count` lots of `lot` objects at `price` each is well formed, else the error code.
static func sell_error(lot: int, count: int, price: int) -> String:
	if not lot in QUANTITIES:
		return ProtocolMarket.E_BAD_LOT
	if count < 1 or count > MAX_LISTINGS:
		return Protocol.E_BAD_MESSAGE
	if price < 1 or price > MAX_PRICE:
		return ProtocolMarket.E_BAD_PRICE
	return ""


static func is_expired(listing: Dictionary, now_ms: int) -> bool:
	return int(listing["expires"]) <= now_ms
