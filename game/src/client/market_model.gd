## State of the marketplace window (P2.10b), without any Node so a test can drive it: the rules the
## sim announced (hdv_opened), the last search (hdv_results), my lots (hdv_mine), and the messages
## the window sends. The sim decides everything (tax, kamas, lot ownership, expiry); this only
## keeps what is shown, builds the messages and previews the tax with MarketRules.
class_name MarketModel
extends RefCounted

## [category id, label]. APPROX(P2.10b): itemtypes.categoryId has no name in the client tables, the
## labels follow the order of the client's item category enum (0 equipment, 1 consumables,
## 2 resources, 3 quest, 4 other, 5 cosmetics); the quest objects (3) cannot be sold anyway.
const CATEGORIES := [[-1, "Toutes"], [0, "Équipements"], [1, "Consommables"], [2, "Ressources"], [4, "Divers"], [5, "Apparences"]]

var is_open := false
var tax := MarketRules.TAX_PERCENT
var quantities: Array = MarketRules.QUANTITIES
var max_listings := MarketRules.MAX_LISTINGS
## the last search: [listing view], and where it stands
var listings: Array = []
var page := 0
var pages := 1
var total := 0
## my lots (listing views)
var mine: Array = []
## the last search's filters, kept to ask the next page
var category := MarketRules.ALL_CATEGORIES
var name_filter := ""


func apply_opened(ev: Dictionary) -> void:
	is_open = true
	tax = int(ev["tax"])
	quantities = (ev["quantities"] as Array).map(func(q: Variant) -> int: return int(q))
	max_listings = int(ev["max_listings"])
	mine = ev["mine"]
	listings = []
	page = 0
	pages = 1
	total = 0


func apply_end() -> void:
	is_open = false
	listings = []
	mine = []


func apply_results(ev: Dictionary) -> void:
	listings = ev["listings"]
	page = int(ev["page"])
	pages = maxi(1, int(ev["pages"]))
	total = int(ev["total"])


func apply_mine(ev: Dictionary) -> void:
	mine = ev["mine"]


## The search message for the given filters (a new search starts at page 0).
func search(p_category: int, p_name: String, p_page := 0) -> Dictionary:
	category = p_category
	name_filter = p_name.strip_edges()
	return ProtocolMarket.search(category, name_filter, 0, p_page)


## The message for another page of the same search, null when there is none.
func turn(delta: int) -> Variant:
	var target := page + delta
	if target < 0 or target >= pages:
		return null
	return ProtocolMarket.search(category, name_filter, 0, target)


## Price of one object of a lot (rounded up).
static func unit_price(l: Dictionary) -> int:
	var qty := maxi(1, int(l["qty"]))
	return (int(l["price"]) + qty - 1) / qty


## "+20 %" / "-15 %" against the object's average price, "" without an average.
static func versus_average(l: Dictionary) -> String:
	var avg := int(l.get("avg", 0))
	if avg <= 0:
		return ""
	var pct := int(round((float(unit_price(l)) / avg - 1.0) * 100.0))
	return "%+d %%" % pct


## Lot sizes offered for a stack of `have` objects.
func lot_sizes(have: int) -> Array:
	return quantities.filter(func(q: Variant) -> bool: return int(q) <= have)


## How many lots of `lot` the stack and the free places allow (at least 0).
func max_count(have: int, lot: int) -> int:
	return maxi(0, mini(have / maxi(1, lot), max_listings - mine.size()))


## Tax of putting `count` lots on sale at `price` each.
static func tax_for(price: int, count: int) -> int:
	return MarketRules.tax(price) * count


## "" when the sale looks possible (the sim checks again), else why not (a tooltip).
func sell_problem(have: int, lot: int, count: int, price: int, kamas: int) -> String:
	if lot < 1 or have < lot * count or count < 1:
		return "Pas assez d'exemplaires"
	if mine.size() + count > max_listings:
		return "Trop d'objets en vente (%d au plus)" % max_listings
	if price < 1 or price > MarketRules.MAX_PRICE:
		return "Prix invalide"
	if kamas < tax_for(price, count):
		return "Pas assez de kamas pour la taxe"
	return ""


func sell(uid: int, lot: int, price: int, count: int) -> Dictionary:
	return ProtocolMarket.sell(uid, lot, price, count)


## Status text of one of my lots (the sim gives `left`): "Expiré" or the time left ("3 j 4 h", "5 h", "12 min").
static func status(l: Dictionary) -> String:
	var left := int(l.get("left", 0))
	if bool(l.get("expired", false)) or left <= 0:
		return "Expiré"
	var minutes := left / 60000
	if minutes >= 1440:
		return "%d j %d h" % [minutes / 1440, (minutes % 1440) / 60]
	if minutes >= 60:
		return "%d h" % (minutes / 60)
	return "%d min" % maxi(1, minutes)


## The message text of a sale / purchase (the toast).
static func sold_text(ev: Dictionary) -> String:
	return "Vendu : %d x %s pour %s K" % [int(ev["qty"]), UiTooltips.item_name(int(ev["item"])), UiStyle.thousands(int(ev["price"]))]


static func bought_text(ev: Dictionary) -> String:
	return "Acheté : %d x %s pour %s K" % [int(ev["qty"]), UiTooltips.item_name(int(ev["item"])), UiStyle.thousands(int(ev["price"]))]
