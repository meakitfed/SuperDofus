## The marketplace's durable state (roadmap P2.10): every lot on sale and the sales statistics,
## in the "market" collection of Persistence under the key "listings" (one marketplace for every
## world sharing the store). Rules: MarketRules (shared with the client).
##
## Always loaded fresh and written in the same Persistence.commit as the characters it touches,
## so that an object is never both in a bag and on sale, nor sold twice.
## The kamas of a sale that nobody online receives wait in the "market" document
## "proceeds/<world>/<seller>" {kamas, sold: [{item, qty, price}]} until the seller is back.
class_name Marketplace
extends RefCounted

const COLLECTION := "market"
const KEY := "listings"

var next := 1
## lots: {id, seller, world, item, effects, reserve?, qty, price, expires}
var listings: Array = []
## str(items.id) -> {qty, sum}: objects sold and kamas paid for them (the average price)
var stats := {}


static func load_from(persistence: Persistence) -> Marketplace:
	var d := persistence.load_doc(COLLECTION, KEY)
	var m := Marketplace.new()
	m.next = int(d.get("next", 1))
	for l: Dictionary in d.get("listings", []):
		m.listings.append(_clean(l))
	for k: String in d.get("stats", {}):
		m.stats[k] = {"qty": int(d["stats"][k]["qty"]), "sum": int(d["stats"][k]["sum"])}
	return m


## The write of the marketplace for Persistence.commit.
func write() -> Dictionary:
	return {"collection": COLLECTION, "key": KEY, "data": {"next": next, "listings": listings.duplicate(true), "stats": stats.duplicate(true)}}


static func proceeds_key(world: String, name: String) -> String:
	return "proceeds/" + world + "/" + name


static func _clean(l: Dictionary) -> Dictionary:
	var out := {"id": int(l["id"]), "seller": str(l["seller"]), "world": str(l["world"]), "item": int(l["item"]),
			"effects": (l.get("effects", []) as Array).map(func(e: Array) -> Array: return e.map(func(x: Variant) -> int: return int(x))),
			"qty": int(l["qty"]), "price": int(l["price"]), "expires": int(l["expires"])}
	if int(l.get("reserve", 0)) != 0:
		out["reserve"] = int(l["reserve"])
	return out


func index_of(id: int) -> int:
	for i in listings.size():
		if int(listings[i]["id"]) == id:
			return i
	return -1


func is_seller(l: Dictionary, world: String, name: String) -> bool:
	return str(l["seller"]) == name and str(l["world"]) == world


func count_of(world: String, name: String) -> int:
	var n := 0
	for l: Dictionary in listings:
		n += 1 if is_seller(l, world, name) else 0
	return n


## Puts a lot on sale: returns it.
func add(world: String, seller: String, item: int, effects: Array, reserve: int, qty: int, price: int, now_ms: int) -> Dictionary:
	var l := {"id": next, "seller": seller, "world": world, "item": item, "effects": effects.duplicate(true), "qty": qty,
			"price": price, "expires": now_ms + MarketRules.DURATION_MS}
	if reserve != 0:
		l["reserve"] = reserve
	next += 1
	listings.append(l)
	return l


## A sale of `qty` objects of `item` for `price` kamas, for the average price.
func record_sale(item: int, qty: int, price: int) -> void:
	var s: Dictionary = stats.get(str(item), {"qty": 0, "sum": 0})
	s["qty"] = int(s["qty"]) + qty
	s["sum"] = int(s["sum"]) + price
	stats[str(item)] = s


## The mean unit price of the sales of an object (0 = never sold).
func average(item: int) -> int:
	var s: Dictionary = stats.get(str(item), {})
	return int(s["sum"]) / int(s["qty"]) if not s.is_empty() and int(s["qty"]) > 0 else 0


func view(l: Dictionary, now_ms: int) -> Dictionary:
	var v := l.duplicate(true)
	v["avg"] = average(int(l["item"]))
	v["expired"] = MarketRules.is_expired(l, now_ms)
	v["left"] = maxi(0, int(l["expires"]) - now_ms) # what the client shows, it does not read the host clock
	return v


## The lots of a seller (expired ones too, to be taken back), oldest first.
func mine(world: String, name: String, now_ms: int) -> Array:
	var out: Array = []
	for l: Dictionary in listings:
		if is_seller(l, world, name):
			out.append(view(l, now_ms))
	return out


## hdv_search: {listings (the page), page, pages, total}; only lots still on sale, cheapest unit price first.
func search(category: int, name: String, item: int, page: int, now_ms: int) -> Dictionary:
	var found: Array = []
	var needle := name.to_lower()
	for l: Dictionary in listings:
		if MarketRules.is_expired(l, now_ms):
			continue
		var id := int(l["item"])
		if item != 0 and id != item:
			continue
		if category != MarketRules.ALL_CATEGORIES and MarketRules.category(id) != category:
			continue
		if needle != "" and str(GameData.item(id).get("name", "")).to_lower().find(needle) < 0:
			continue
		found.append(l)
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ua := float(a["price"]) / float(a["qty"])
		var ub := float(b["price"]) / float(b["qty"])
		return int(a["id"]) < int(b["id"]) if ua == ub else ua < ub)
	var pages := maxi(1, ceili(float(found.size()) / MarketRules.PAGE_SIZE))
	page = clampi(page, 0, pages - 1)
	var out: Array = []
	for l: Dictionary in found.slice(page * MarketRules.PAGE_SIZE, (page + 1) * MarketRules.PAGE_SIZE):
		out.append(view(l, now_ms))
	return {"listings": out, "page": page, "pages": pages, "total": found.size()}
