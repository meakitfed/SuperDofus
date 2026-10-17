## The duel messages (P3.10), an extension of Protocol (protocol.gd stays under its size limit):
## constants, SCHEMA entries, builders and error codes of the domain. Same rules as Protocol.
## A duel is a fight between two players of one map (Fight.kind "duel"): the fight itself uses the
## ordinary fight_* messages, this domain only carries the challenge and its answer.
class_name ProtocolDuel
extends RefCounted

const C2S := "client → jeu"
const S2C := "jeu → client"

## APPROX(P3.10): a challenge waits one minute (same as the trade invitation, no source in the client tables)
const INVITE_TTL_MS := 60000

# client -> game
const REQUEST := "duel_request"
const ACCEPT := "duel_accept"
const DECLINE := "duel_decline"
# game -> client
const REQUESTED := "duel_requested"
const END := "duel_end"

const E_DUEL_BUSY := "duel_busy"                    # duel_request / duel_accept: you or the other is in a fight, a trade or another window
const E_NO_DUEL_REQUEST := "no_duel_request"        # duel_accept / duel_decline: nobody challenged you (or it expired)
const ERROR_CODES := [E_DUEL_BUSY, E_NO_DUEL_REQUEST]

# duel_end.reason (the challenge ends without a fight)
const REASON_DECLINED := "declined" # the challenged player refused
const REASON_EXPIRED := "expired"   # nobody answered in time

const SCHEMA := {
	REQUEST: [C2S, "Défi (P3.10) : défier le joueur `name` de votre map (hors combat, aucun des deux occupé). Réponse : duel_requested chez lui, ou error (player_offline, no_target, duel_busy, ghost)", {"name": "str"}],
	ACCEPT: [C2S, "Défi : accepter le défi de `from` (une minute) : les deux entrent en combat (fight_start, pas de gain ni de perte), ou error (no_duel_request, duel_busy)", {"from": "str"}],
	DECLINE: [C2S, "Défi : refuser le défi de `from` : duel_end{declined} chez le provocateur", {"from": "str"}],
	REQUESTED: [S2C, "Défi : `from` vous défie (duel_accept / duel_decline)", {"from": "str"}],
	END: [S2C, "Défi : fin sans combat, `reason` = declined | expired", {"reason": "str"}],
}


static func request(name: String) -> Dictionary:
	return {"t": REQUEST, "name": name}

static func accept(from: String) -> Dictionary:
	return {"t": ACCEPT, "from": from}

static func decline(from: String) -> Dictionary:
	return {"t": DECLINE, "from": from}

static func requested(from: String) -> Dictionary:
	return {"t": REQUESTED, "from": from}

static func end(reason: String) -> Dictionary:
	return {"t": END, "reason": reason}
