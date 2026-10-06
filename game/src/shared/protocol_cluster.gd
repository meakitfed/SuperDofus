## Worlds of a server (roadmap S.04), an extension of Protocol (protocol.gd stays under its size
## limit): messages, SCHEMA entries, builders and the error code of the domain. Protocol.validate
## and docs/PROTOCOL.md read this table after Protocol.SCHEMA. Same rules as Protocol.
##
## `server_list` (after the login on a server) is answered by `servers{worlds}`: the worlds open
## right now, [{id, content, name, module, players, version}] (S.04b: `content` = the world whose data an
## instance reads, its own id for an ordinary world). A world a GM stops sends its players
## `error{code: world_closed}` (they are saved and back at the login state: pick another world).
class_name ProtocolCluster
extends RefCounted

# same strings as Protocol.C2S / S2C (a test checks it): this file does not reference Protocol
const C2S := "client → jeu"
const S2C := "jeu → client"

const SERVER_LIST := "server_list"
const SERVERS := "servers"

const E_WORLD_CLOSED := "world_closed" # the world the player was in has been stopped by an admin
const ERROR_CODES := [E_WORLD_CLOSED]

## type -> [direction, meaning, {field: type}], same format as Protocol.SCHEMA.
const SCHEMA := {
	SERVER_LIST: [C2S, "Serveur : demande la liste des mondes ouverts (réponse : servers)", {}],
	SERVERS: [S2C, "Mondes ouverts du serveur : `worlds` = [{id, content, name, module, players, version}] (content = le monde dont l'instance lit les données, S.04b : l'id lui-même pour un monde ordinaire ; version = celle du paquet de contenu, \"\" s'il n'y en a pas)", {"worlds": "array"}],
}


static func server_list() -> Dictionary:
	return {"t": SERVER_LIST}

static func servers(worlds: Array) -> Dictionary:
	return {"t": SERVERS, "worlds": worlds}
