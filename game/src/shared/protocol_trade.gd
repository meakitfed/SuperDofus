## The trade messages (P3.11), an extension of Protocol (protocol.gd stays under its size
## limit): constants, SCHEMA entries, builders and error codes of the domain. Protocol.validate
## and docs/PROTOCOL.md read this table after Protocol.SCHEMA. Same rules as Protocol.
class_name ProtocolTrade
extends RefCounted

# same strings as Protocol.C2S / S2C (a test checks it): this file does not reference Protocol
const C2S := "client → jeu"
const S2C := "jeu → client"

# client -> game
const INVITE := "trade_invite"
const ACCEPT := "trade_accept"
const DECLINE := "trade_decline"
const SET := "trade_set"
const READY := "trade_ready"
const CANCEL := "trade_cancel"
# game -> client
const INVITED := "trade_invited"
const OPEN := "trade_open"
const UPDATE := "trade_update"
const END := "trade_end"

const E_TRADE_BUSY := "trade_busy"                      # trade_invite / trade_accept: you or the other is in a trade, a fight or another window
const E_NOT_IN_TRADE := "not_in_trade"                  # trade_set / trade_ready / trade_cancel without an open trade
const E_NO_TRADE_INVITATION := "no_trade_invitation"    # trade_accept / trade_decline: nobody invited you (or it expired)
const ERROR_CODES := [E_TRADE_BUSY, E_NOT_IN_TRADE, E_NO_TRADE_INVITATION]

# trade_end.reason
const REASON_DONE := "done"                 # both validated, the exchange was made
const REASON_CANCELLED := "cancelled"       # one side cancelled
const REASON_DECLINED := "declined"         # (no window open) the invited player refused
const REASON_EXPIRED := "expired"           # (no window open) nobody answered in time
const REASON_MOVED := "moved"               # one side changed map
const REASON_FIGHT := "fight"               # one side entered a fight
const REASON_DISCONNECTED := "disconnected" # one side left the game
const REASON_ACTION := "action"             # one side did something else (walk, talk, use an item...)
const REASON_FAILED := "failed"             # the exchange was refused at the end (`code`: e.g. overloaded): nothing moved

## type -> [direction, meaning, {field: type}], same format as Protocol.SCHEMA.
## An offer view = {items: [{uid, id, qty, effects}] (the stacks offered, qty = the offered part,
## uid = the offerer's), kamas, ready (bool)}.
const SCHEMA := {
	INVITE: [C2S, "Échange (P3.11) : inviter le joueur `name` de votre map (hors combat, aucun des deux en échange). Réponse : trade_invited chez lui, ou error (player_offline, no_target, trade_busy, ghost)", {"name": "str"}],
	ACCEPT: [C2S, "Échange : accepter l'invitation de `from` (une minute) : trade_open aux deux, ou error (no_trade_invitation, trade_busy)", {"from": "str"}],
	DECLINE: [C2S, "Échange : refuser l'invitation de `from` : trade_end{declined} chez l'invitant", {"from": "str"}],
	SET: [C2S, "Échange ouvert : poser votre offre, `items` [{uid, qty}] (piles du sac, 20 au plus) et `kamas` ; elle remplace la précédente et annule les deux validations. Réponse : trade_update aux deux, ou error (unknown_item, item_worn, not_enough_kamas, overloaded : le sac de l'autre ne peut pas tout porter)", {"items": "array", "kamas": "int"}],
	READY: [C2S, "Échange ouvert : valider l'offre telle qu'elle est ; à la double validation l'échange est fait (trade_end{done} + item_added / item_removed + player_stats), ou error (overloaded) sans rien changer", {}],
	CANCEL: [C2S, "Échange ouvert : l'annuler : trade_end{cancelled} aux deux", {}],
	INVITED: [S2C, "Échange : `from` vous invite (trade_accept / trade_decline)", {"from": "str"}],
	OPEN: [S2C, "Échange : la fenêtre s'ouvre avec le joueur `with` (id d'acteur `with_id`)", {"with": "str", "with_id": "int"}],
	UPDATE: [S2C, "Échange : les deux offres, `mine` et `theirs` (voir en tête de protocol_trade.gd), envoyées à chaque changement", {"mine": "dict", "theirs": "dict"}],
	END: [S2C, "Échange : fin (la fenêtre se ferme), `reason` = done | cancelled | declined | expired | moved | fight | disconnected | action | failed ; `code` = le refus quand reason = failed", {"reason": "str", "code": "str?"}],
}


static func invite(name: String) -> Dictionary:
	return {"t": INVITE, "name": name}

static func accept(from: String) -> Dictionary:
	return {"t": ACCEPT, "from": from}

static func decline(from: String) -> Dictionary:
	return {"t": DECLINE, "from": from}

## `items`: [{uid, qty}]
static func set_offer(items: Array, kamas: int) -> Dictionary:
	return {"t": SET, "items": items, "kamas": kamas}

static func ready() -> Dictionary:
	return {"t": READY}

static func cancel() -> Dictionary:
	return {"t": CANCEL}

static func invited(from: String) -> Dictionary:
	return {"t": INVITED, "from": from}

static func open(with: String, with_id: int) -> Dictionary:
	return {"t": OPEN, "with": with, "with_id": with_id}

static func update(mine: Dictionary, theirs: Dictionary) -> Dictionary:
	return {"t": UPDATE, "mine": mine, "theirs": theirs}

static func end(reason: String, code := "") -> Dictionary:
	var m := {"t": END, "reason": reason}
	if code != "":
		m["code"] = code
	return m
