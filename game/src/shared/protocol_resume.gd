## Reconnection (S.02b), an extension of Protocol (protocol.gd stays under its size limit): the
## messages, SCHEMA entries, builders and error code of the domain. Protocol.validate and
## docs/PROTOCOL.md read this table after Protocol.SCHEMA. Same rules as Protocol.
##
## After a cut (no logout), the server keeps the session for a while and its token stays valid.
## `resume{token}` on a new connection takes the session over: the answer is `resume_ok` then the
## events that rebuild the client (welcome, player_stats, inventory, quest_list, then either
## fight_start / fight_options / fight_begin / fight_turn when the character is still in a fight, or
## the map as for a fresh connection, or the character list when none had been chosen). A bad,
## expired or unknown token is refused with `login_error{code: bad_token, cmd: "resume"}`; a token
## whose connection is still alive and active with `already_connected`.
class_name ProtocolResume
extends RefCounted

# same strings as Protocol.C2S / S2C (a test checks it): this file does not reference Protocol
const C2S := "client → jeu"
const S2C := "jeu → client"

const RESUME := "resume"
const RESUME_OK := "resume_ok"
const NET_RECONNECTING := "net_reconnecting"

const E_BAD_TOKEN := "bad_token"  # resume: the token is unknown, expired or already given up
const ERROR_CODES := [E_BAD_TOKEN]

## type -> [direction, meaning, {field: type}], same format as Protocol.SCHEMA.
const SCHEMA := {
	RESUME: [C2S, "Compte (serveur seulement) : reprendre la session du `token` après une coupure (réponse : resume_ok puis les événements de l'état courant, ou login_error{bad_token | already_connected})", {"token": "str"}],
	NET_RECONNECTING: [S2C, "Transport (fait par le backend réseau, jamais par le serveur) : la connexion est coupée, nouvel essai n°`attempt` dans `delay_ms` (1, 2, 4, 8 s puis toutes les 8 s) ; `resume_ok` y met fin, une erreur login_error{bad_token} l'abandonne", {"attempt": "int", "delay_ms": "int", "reason": "str"}],
	RESUME_OK: [S2C, "Session reprise : `token`, `role`, `login` comme login_ok, et `state` {world, name, playing, in_fight} ; suivent les événements qui reconstruisent le client (combat en cours, sinon la map)", {"token": "str", "role": "str", "login": "str", "state": "dict"}],
}


static func resume(token: String) -> Dictionary:
	return {"t": RESUME, "token": token}

static func resume_ok(token: String, role: String, login_name: String, state: Dictionary) -> Dictionary:
	return {"t": RESUME_OK, "token": token, "role": role, "login": login_name, "state": state}
