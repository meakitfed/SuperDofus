## GM console (A1.01), an extension of Protocol (protocol.gd stays under its size limit): the
## messages, SCHEMA entries, builders and error codes of the domain. Protocol.validate and
## docs/PROTOCOL.md read this table after Protocol.SCHEMA. Same rules as Protocol.
##
## The commands themselves travel in `admin_cmd{cmd, args}` (Protocol); a refused one answers with
## `error` (not_gm, unknown_command, bad_message, unknown_map, unknown_item, player_offline…), a
## done one with `admin_result{cmd, args}`. Nothing here is specific to a game.
class_name ProtocolAdmin
extends RefCounted

# same strings as Protocol.C2S / S2C (a test checks it): this file does not reference Protocol
const C2S := "client → jeu"
const S2C := "jeu → client"

const ADMIN_RESULT := "admin_result"
const ANNOUNCE := "announce"

const E_BANNED := "banned"  # login / hello: the account is banned (also login_error.code)
const E_MUTED := "muted"    # chat_send: the account is muted (msg = seconds left)
const E_KICKED := "kicked"  # error before the connection ends: a GM threw the player out
const ERROR_CODES := [E_BANNED, E_MUTED, E_KICKED]

## The commands of `admin_cmd` (WorldAdmin): name -> usage, shown by the client's help.
const USAGE := {
	"tp": "/tp <map id> [cellule]  ·  /tp <x> <y> [world map]",
	"give": "/give <objet> [quantité] [joueur]",
	"kamas": "/kamas <montant> [joueur]",
	"level": "/level <niveau> [joueur]",
	"heal": "/heal [joueur]",
	"say": "/say <message>",
	"who": "/who",
	"kick": "/kick <joueur>",
	"ban": "/ban <joueur> [raison]",
	"unban": "/unban <joueur ou compte>",
	"mute": "/mute <joueur> [minutes]",
	"unmute": "/unmute <joueur>",
	"reload": "/reload",
}

## type -> [direction, meaning, {field: type}], same format as Protocol.SCHEMA.
const SCHEMA := {
	ADMIN_RESULT: [S2C, "Une commande GM (admin_cmd) a été exécutée : `cmd` et `args` (valeurs utiles : joueur visé, quantité, liste des joueurs pour `who`…)", {"cmd": "str", "args": "array"}],
	ANNOUNCE: [S2C, "Message d'un GM à tous les joueurs du monde (/say) : `from` (nom du GM) et `text`", {"from": "str", "text": "str"}],
}


static func admin_result(cmd: String, args := []) -> Dictionary:
	return {"t": ADMIN_RESULT, "cmd": cmd, "args": args}

static func announce(from_name: String, text: String) -> Dictionary:
	return {"t": ANNOUNCE, "from": from_name, "text": text}
