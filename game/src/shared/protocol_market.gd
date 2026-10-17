## The marketplace messages (P2.10), an extension of Protocol: constants, SCHEMA entries,
## builders and error codes of the domain. Same rules as Protocol.
## A listing view = {id, item (items.id), effects, reserve?, qty (the lot), price (of the lot),
## avg (mean unit price of the object's sales, 0 = none yet), seller, expires (unix ms),
## expired (bool)}.
class_name ProtocolMarket
extends RefCounted

const C2S := "client → jeu"
const S2C := "jeu → client"

# client -> game
const OPEN := "hdv_open"
const SEARCH := "hdv_search"
const SELL := "hdv_sell"
const BUY := "hdv_buy"
const CANCEL := "hdv_cancel"
const CLOSE := "hdv_close"
# game -> client
const OPENED := "hdv_opened"
const RESULTS := "hdv_results"
const MINE := "hdv_mine"
const BOUGHT := "hdv_bought"
const SOLD := "hdv_sold"
const END := "hdv_end"

const E_NO_MARKET := "no_market"          # an hdv_* command without the marketplace open
const E_MARKET_BUSY := "market_busy"      # hdv_open: a ghost cannot, nor a player at a workshop or harvesting
const E_BAD_LOT := "bad_lot"              # hdv_sell: the lot size is not an allowed quantity
const E_BAD_PRICE := "bad_price"          # hdv_sell: the price is below 1 or above the limit
const E_MARKET_FULL := "market_full"      # hdv_sell: too many lots on sale already
const E_NO_LISTING := "no_listing"        # hdv_buy / hdv_cancel: the lot is gone (sold, taken back, not yours)
const E_OWN_LISTING := "own_listing"      # hdv_buy: you cannot buy your own lot
const ERROR_CODES := [E_NO_MARKET, E_MARKET_BUSY, E_BAD_LOT, E_BAD_PRICE, E_MARKET_FULL, E_NO_LISTING, E_OWN_LISTING]

const SCHEMA := {
	OPEN: [C2S, "Hôtel de vente (P2.10) : ouvrir la fenêtre (hors combat, ni fantôme). Réponse : hdv_opened ; les kamas des ventes faites hors ligne sont versés (hdv_sold + player_stats). Toute autre commande hors hdv_* ferme l'hôtel de vente", {}],
	SEARCH: [C2S, "Hôtel de vente ouvert : chercher des lots en vente (non expirés), filtres facultatifs `category` (itemtypes.categoryId, -1 = toutes), `name` (partie du nom), `item` (items.id), `page` (depuis 0, 20 lots par page). Réponse : hdv_results trié par prix unitaire", {"category": "int?", "name": "str?", "item": "int?", "page": "int?"}],
	SELL: [C2S, "Hôtel de vente ouvert : mettre en vente `count` lots (1 par défaut) de `lot` exemplaires (1, 10, 100 ou 1000) de la pile du sac `uid` au prix `price` le lot ; la taxe de mise en vente est payée. Réponse : hdv_mine + item_added / item_removed + player_stats, ou error (bad_lot, bad_price, market_full, unknown_item, item_worn, not_sellable, not_enough_kamas)", {"uid": "int", "lot": "int", "price": "int", "count": "int?"}],
	BUY: [C2S, "Hôtel de vente ouvert : acheter le lot `listing` au prix affiché. Réponse : hdv_bought + item_added + player_stats, ou error (no_listing, own_listing, not_enough_kamas, overloaded)", {"listing": "int"}],
	CANCEL: [C2S, "Hôtel de vente ouvert : reprendre un de vos lots (en vente ou expiré), la taxe n'est pas rendue. Réponse : hdv_mine + item_added, ou error (no_listing)", {"listing": "int"}],
	CLOSE: [C2S, "Fermer l'hôtel de vente", {}],
	OPENED: [S2C, "L'hôtel de vente s'ouvre : `tax` (% du prix du lot), `quantities` (tailles de lot), `max_listings`, `duration_ms`, `mine` (vos lots, vues d'un lot en tête de protocol_market.gd)", {"tax": "int", "quantities": "array", "max_listings": "int", "duration_ms": "int", "mine": "array"}],
	RESULTS: [S2C, "Résultat d'une recherche : `listings` (vues), `page`, `pages`, `total`", {"listings": "array", "page": "int", "pages": "int", "total": "int"}],
	MINE: [S2C, "Vos lots ont changé (mise en vente, reprise, vente, achat) : la liste complète", {"mine": "array"}],
	BOUGHT: [S2C, "Achat fait : le lot `listing` (`item` x `qty`) pour `price` kamas", {"listing": "int", "item": "int", "qty": "int", "price": "int"}],
	SOLD: [S2C, "Un de vos lots est vendu : `item` x `qty` pour `price` kamas, déjà versés (aussi après une vente hors ligne, à la connexion)", {"item": "int", "qty": "int", "price": "int"}],
	END: [S2C, "L'hôtel de vente est fermé (fermeture ou autre commande)", {}],
}


static func open() -> Dictionary:
	return {"t": OPEN}

static func search(category := MarketRules.ALL_CATEGORIES, name := "", item := 0, page := 0) -> Dictionary:
	var m := {"t": SEARCH, "page": page}
	if category != MarketRules.ALL_CATEGORIES:
		m["category"] = category
	if name != "":
		m["name"] = name
	if item != 0:
		m["item"] = item
	return m

static func sell(uid: int, lot: int, price: int, count := 1) -> Dictionary:
	return {"t": SELL, "uid": uid, "lot": lot, "price": price, "count": count}

static func buy(listing: int) -> Dictionary:
	return {"t": BUY, "listing": listing}

static func cancel(listing: int) -> Dictionary:
	return {"t": CANCEL, "listing": listing}

static func close() -> Dictionary:
	return {"t": CLOSE}

static func opened(mine: Array) -> Dictionary:
	return {"t": OPENED, "tax": MarketRules.TAX_PERCENT, "quantities": MarketRules.QUANTITIES, "max_listings": MarketRules.MAX_LISTINGS,
			"duration_ms": MarketRules.DURATION_MS, "mine": mine}

static func results(listings: Array, page: int, pages: int, total: int) -> Dictionary:
	return {"t": RESULTS, "listings": listings, "page": page, "pages": pages, "total": total}

static func mine(list: Array) -> Dictionary:
	return {"t": MINE, "mine": list}

static func bought(listing: int, item: int, qty: int, price: int) -> Dictionary:
	return {"t": BOUGHT, "listing": listing, "item": item, "qty": qty, "price": price}

static func sold(item: int, qty: int, price: int) -> Dictionary:
	return {"t": SOLD, "item": item, "qty": qty, "price": price}

static func end() -> Dictionary:
	return {"t": END}
