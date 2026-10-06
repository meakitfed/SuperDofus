## State of the trade window (P3.11b), without any Node so a test can drive it: the invitations
## received, the two offers as the sim last sent them (trade_update) and the messages the window
## sends. The sim decides everything (bag, kamas, weight, double validation); this only keeps what
## is shown and builds the next offer from the last confirmed one.
class_name TradeModel
extends RefCounted

const INVITE_MS := 60000 # same as the sim (TradeRules.INVITE_TTL_MS)

var is_open := false
var with := ""
var with_id := -1
## an offer view: {items: [{uid, id, qty, effects}], kamas, ready}
var mine := {"items": [], "kamas": 0, "ready": false}
var theirs := {"items": [], "kamas": 0, "ready": false}
## [{from, at (ms)}], oldest first
var invites: Array = []


func apply_invited(from: String, now: int) -> void:
	invites = invites.filter(func(i: Dictionary) -> bool: return i["from"] != from)
	invites.append({"from": from, "at": now})


## Drops the invitations unanswered for a minute; true if one went.
func expire(now: int) -> bool:
	var kept := invites.filter(func(i: Dictionary) -> bool: return now - int(i["at"]) < INVITE_MS)
	var changed := kept.size() != invites.size()
	invites = kept
	return changed


func forget_invite(from: String) -> void:
	invites = invites.filter(func(i: Dictionary) -> bool: return i["from"] != from)


## trade_open: a fresh window, empty offers. The other invitations are moot.
func apply_open(ev: Dictionary) -> void:
	is_open = true
	with = str(ev["with"])
	with_id = int(ev["with_id"])
	mine = {"items": [], "kamas": 0, "ready": false}
	theirs = {"items": [], "kamas": 0, "ready": false}
	invites.clear()


func apply_update(ev: Dictionary) -> void:
	mine = ev["mine"]
	theirs = ev["theirs"]


func close() -> void:
	is_open = false
	with = ""
	with_id = -1
	mine = {"items": [], "kamas": 0, "ready": false}
	theirs = {"items": [], "kamas": 0, "ready": false}


func offered_qty(uid: int) -> int:
	for it: Dictionary in mine["items"]:
		if int(it["uid"]) == uid:
			return int(it["qty"])
	return 0


func my_kamas() -> int:
	return int(mine["kamas"])


func _lines() -> Array:
	var out: Array = []
	for it: Dictionary in mine["items"]:
		out.append({"uid": int(it["uid"]), "qty": int(it["qty"])})
	return out


## Message that puts `qty` more of the stack `uid` down, `available` = what the bag holds of it
## (null when nothing can be added: closed, no more of it, or all the lines are used).
func add(uid: int, qty: int, available: int) -> Variant:
	var room := available - offered_qty(uid)
	if not is_open or qty < 1 or room < 1:
		return null
	var lines := _lines()
	var found := false
	for l: Dictionary in lines:
		if int(l["uid"]) == uid:
			l["qty"] = int(l["qty"]) + mini(qty, room)
			found = true
	if not found:
		if lines.size() >= TradeRules.MAX_LINES:
			return null
		lines.append({"uid": uid, "qty": mini(qty, room)})
	return ProtocolTrade.set_offer(lines, my_kamas())


## Message that takes the stack `uid` back (all of it).
func remove(uid: int) -> Variant:
	if not is_open or offered_qty(uid) == 0:
		return null
	return ProtocolTrade.set_offer(_lines().filter(func(l: Dictionary) -> bool: return int(l["uid"]) != uid), my_kamas())


## Message that sets the kamas of the offer (clamped to the purse).
func with_kamas(kamas: int, purse: int) -> Variant:
	if not is_open:
		return null
	return ProtocolTrade.set_offer(_lines(), clampi(kamas, 0, purse))


## Validation only means something once the other side did not just change its offer, so the
## button is open as long as we did not validate this exact offer.
func can_ready() -> bool:
	return is_open and not bool(mine["ready"])


func status_text(side: Dictionary) -> String:
	return "Validé" if bool(side["ready"]) else "En attente"


## What the end of a trade says (toast). "" = nothing to say (done is shown by the bag itself).
static func end_text(reason: String, code := "") -> String:
	match reason:
		ProtocolTrade.REASON_DONE:
			return "Échange terminé"
		ProtocolTrade.REASON_CANCELLED:
			return "Échange annulé"
		ProtocolTrade.REASON_DECLINED:
			return "Votre invitation à échanger a été refusée"
		ProtocolTrade.REASON_EXPIRED:
			return "L'invitation à échanger a expiré"
		ProtocolTrade.REASON_MOVED:
			return "Échange annulé : un des joueurs a changé de carte"
		ProtocolTrade.REASON_FIGHT:
			return "Échange annulé : un combat commence"
		ProtocolTrade.REASON_DISCONNECTED:
			return "Échange annulé : l'autre joueur s'est déconnecté"
		ProtocolTrade.REASON_ACTION:
			return "Échange annulé"
		ProtocolTrade.REASON_FAILED:
			return "Échange impossible : %s" % ("un des sacs est trop plein" if code == Protocol.E_OVERLOADED else "vérifiez vos offres")
	return ""
