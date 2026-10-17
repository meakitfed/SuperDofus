## The guild messages (P3.06a), an extension of Protocol (protocol.gd stays under its size
## limit): constants, SCHEMA entries, builders and error codes of the domain. Same rules as
## Protocol: JSON-safe dictionaries, int() on read.
class_name ProtocolGuild
extends RefCounted

# same strings as Protocol.C2S / S2C (a test checks it): this file does not reference Protocol
const C2S := "client → jeu"
const S2C := "jeu → client"

# client -> game
const GET := "guild_get"
const CREATE := "guild_create"
const INVITE := "guild_invite"
const ACCEPT := "guild_accept"
const DECLINE := "guild_decline"
const LEAVE := "guild_leave"
const KICK := "guild_kick"
const RANK := "guild_rank"
const RIGHTS := "guild_rights"
const LEADER := "guild_leader"
const DISBAND := "guild_disband"
# game -> client
const INFO := "guild_info"
const INVITED := "guild_invited"
const LEFT := "guild_left"
const DECLINED := "guild_declined"

const E_ALREADY_IN_GUILD := "already_in_guild"      # guild_create / guild_accept: you (or the invited player) are in a guild
const E_NOT_IN_GUILD := "not_in_guild"              # a guild command without a guild, or a target who is not a member
const E_BAD_GUILD_NAME := "bad_guild_name"          # guild_create: the name breaks the naming rule
const E_GUILD_NAME_TAKEN := "guild_name_taken"      # guild_create: another guild of the world has it (any case)
const E_BAD_EMBLEM := "bad_emblem"                  # guild_create: symbol / background unknown, colour out of range
const E_GUILD_NO_RIGHT := "guild_no_right"          # the command needs a right or a rank you do not have
const E_GUILD_FULL := "guild_full"                  # guild_invite / guild_accept: 200 members
const E_BAD_RANK := "bad_rank"                      # guild_rank: not a rank of guildranks, or the leader's
const E_BAD_RIGHT := "bad_right"                    # guild_rights: not a right the sim enforces
const E_GUILD_LEADER := "guild_leader"              # guild_leave / guild_kick: the leader must hand over or disband first
const E_NO_GUILD_INVITATION := "no_guild_invitation" # guild_accept / guild_decline: nobody invited you (or it expired)
const ERROR_CODES := [E_ALREADY_IN_GUILD, E_NOT_IN_GUILD, E_BAD_GUILD_NAME, E_GUILD_NAME_TAKEN, E_BAD_EMBLEM, E_GUILD_NO_RIGHT,
		E_GUILD_FULL, E_BAD_RANK, E_BAD_RIGHT, E_GUILD_LEADER, E_NO_GUILD_INVITATION]

const REASON_LEFT := "left"           # you left
const REASON_KICKED := "kicked"       # a member with the right excluded you
const REASON_DISBANDED := "disbanded" # the leader dissolved the guild

## type -> [direction, meaning, {field: type}], same format as Protocol.SCHEMA.
## guild_info.guild = {} when the player has no guild, else {id, name, emblem {symbol, symbol_color,
## bg, bg_color}, members: [{name, rank, rights [int], online (bool), level, breed}] (the leader first),
## you: {rank, rights}}. Sent at connection, in answer to guild_get and whenever the guild changes
## (a member joins, leaves, changes rank or rights, connects or disconnects) to every member online.
const SCHEMA := {
	GET: [C2S, "Guilde (P3.06) : demander la sienne. Réponse : guild_info", {}],
	CREATE: [C2S, "Guilde : fonder la guilde `name` avec l'emblème `emblem` {symbol, symbol_color, bg, bg_color} (hors guilde) ; vous en êtes le maître. Réponse : guild_info, ou error (already_in_guild, bad_guild_name, guild_name_taken, bad_emblem)", {"name": "str", "emblem": "dict"}],
	INVITE: [C2S, "Guilde : inviter le joueur connecté `name` (droit 6) : guild_invited chez lui, ou error (guild_no_right, not_in_guild, player_offline, already_in_guild, guild_full)", {"name": "str"}],
	ACCEPT: [C2S, "Guilde : accepter l'invitation de `from` (une minute) : guild_info à tous les membres, ou error (no_guild_invitation, already_in_guild, guild_full)", {"from": "str"}],
	DECLINE: [C2S, "Guilde : refuser l'invitation de `from` : guild_declined chez l'invitant", {"from": "str"}],
	LEAVE: [C2S, "Guilde : la quitter (le maître ne le peut pas tant qu'elle compte d'autres membres) : guild_left chez vous, guild_info aux autres", {}],
	KICK: [C2S, "Guilde : exclure le membre `name` (droit 13, et un rang plus haut que le sien) : guild_left{kicked} chez lui", {"name": "str"}],
	RANK: [C2S, "Guilde : donner à `name` le rang `rank` (guildranks.id 2 à 4 ; droit 26, rang plus haut que le sien des deux côtés) ; il prend les droits par défaut du rang", {"name": "str", "rank": "int"}],
	RIGHTS: [C2S, "Guilde : fixer la liste des droits (`rights`, guildrights.id) de `name` (droit 1, rang plus haut que le sien, et seulement des droits que l'on a)", {"name": "str", "rights": "array"}],
	LEADER: [C2S, "Guilde : passer la guilde au membre `name` (le maître seul) ; il devient officier", {"name": "str"}],
	DISBAND: [C2S, "Guilde : la dissoudre (le maître seul) : guild_left{disbanded} chez tous les membres", {}],
	INFO: [S2C, "Guilde : la guilde du joueur (voir en tête de protocol_guild.gd), `guild` vide s'il n'en a pas", {"guild": "dict"}],
	INVITED: [S2C, "Guilde : `from` vous invite dans la guilde `guild` (guild_accept / guild_decline)", {"from": "str", "guild": "str"}],
	LEFT: [S2C, "Guilde : vous n'en faites plus partie, `reason` = left | kicked | disbanded", {"reason": "str"}],
	DECLINED: [S2C, "Guilde : `name` a refusé votre invitation", {"name": "str"}],
}


static func get_guild() -> Dictionary:
	return {"t": GET}

static func create(name: String, emblem: Dictionary) -> Dictionary:
	return {"t": CREATE, "name": name, "emblem": emblem}

static func invite(name: String) -> Dictionary:
	return {"t": INVITE, "name": name}

static func accept(from: String) -> Dictionary:
	return {"t": ACCEPT, "from": from}

static func decline(from: String) -> Dictionary:
	return {"t": DECLINE, "from": from}

static func leave() -> Dictionary:
	return {"t": LEAVE}

static func kick(name: String) -> Dictionary:
	return {"t": KICK, "name": name}

static func rank(name: String, rank_id: int) -> Dictionary:
	return {"t": RANK, "name": name, "rank": rank_id}

static func rights(name: String, list: Array) -> Dictionary:
	return {"t": RIGHTS, "name": name, "rights": list}

static func leader(name: String) -> Dictionary:
	return {"t": LEADER, "name": name}

static func disband() -> Dictionary:
	return {"t": DISBAND}

static func info(guild: Dictionary) -> Dictionary:
	return {"t": INFO, "guild": guild}

static func invited(from: String, guild: String) -> Dictionary:
	return {"t": INVITED, "from": from, "guild": guild}

static func left(reason: String) -> Dictionary:
	return {"t": LEFT, "reason": reason}

static func declined(name: String) -> Dictionary:
	return {"t": DECLINED, "name": name}
