## The group messages (P3.03), an extension of Protocol (protocol.gd stays under its size
## limit): constants, SCHEMA entries, builders and error codes of the domain. Protocol.validate
## and docs/PROTOCOL.md read this table after Protocol.SCHEMA. Same rules as Protocol.
class_name ProtocolParty
extends RefCounted

# same strings as Protocol.C2S / S2C (a test checks it): this file does not reference Protocol
const C2S := "client → jeu"
const S2C := "jeu → client"

# client -> game
const INVITE := "party_invite"
const ACCEPT := "party_accept"
const DECLINE := "party_decline"
const LEAVE := "party_leave"
const KICK := "party_kick"
const LEADER := "party_leader"
const FOLLOW := "party_follow"
# game -> client
const INVITED := "party_invited"
const UPDATE := "party_update"
const LEFT := "party_left"
const DECLINED := "party_declined"

const E_PARTY_FULL := "party_full"                    # party_invite / party_accept: 8 members already
const E_ALREADY_IN_PARTY := "already_in_party"        # the invited player (or you, accepting) is in a group
const E_NOT_IN_PARTY := "not_in_party"                # leave / kick / leader / follow without a group
const E_NOT_PARTY_LEADER := "not_party_leader"        # invite (as a member), kick, leader: only the leader
const E_NO_INVITATION := "no_invitation"              # party_accept / party_decline: nobody invited you (or it expired)
const ERROR_CODES := [E_PARTY_FULL, E_ALREADY_IN_PARTY, E_NOT_IN_PARTY, E_NOT_PARTY_LEADER, E_NO_INVITATION]

const REASON_LEFT := "left"           # you left
const REASON_KICKED := "kicked"       # the leader excluded you
const REASON_DISSOLVED := "dissolved" # you were the last but one: the group is gone

## type -> [direction, meaning, {field: type}], same format as Protocol.SCHEMA.
## party_update.party = {id, leader (name), follow (the member the recipient follows, "" = none),
##   members: [{id (actor id), name, level, breed, hp, max_hp, map, coords [x, y], cell, fight (bool)}]},
##   the leader first; sent whenever it changes (a member joins, leaves, moves to another map,
##   enters or leaves a fight, loses life), at most once a second.
const SCHEMA := {
	INVITE: [C2S, "Groupe (P3.03) : inviter le joueur connecté `name` (le chef seul, ou n'importe qui hors d'un groupe : cela en crée un). Réponse : party_invited chez lui, ou error (player_offline, already_in_party, party_full, not_party_leader)", {"name": "str"}],
	ACCEPT: [C2S, "Groupe : accepter l'invitation de `from` (une minute) : party_update à tous les membres, ou error (no_invitation, already_in_party, party_full)", {"from": "str"}],
	DECLINE: [C2S, "Groupe : refuser l'invitation de `from` : party_declined chez l'invitant", {"from": "str"}],
	LEAVE: [C2S, "Groupe : le quitter (le suivant devient chef ; à un seul membre il se dissout) : party_left puis party_update aux autres", {}],
	KICK: [C2S, "Groupe : exclure le membre `name` (le chef seul) : party_left{kicked} chez lui", {"name": "str"}],
	LEADER: [C2S, "Groupe : passer le commandement au membre `name` (le chef seul) : party_update", {"name": "str"}],
	FOLLOW: [C2S, "Groupe : suivre le membre `name` (\"\" = ne plus suivre) : quand il change de carte hors combat, vous l'y rejoignez", {"name": "str"}],
	INVITED: [S2C, "Groupe : `from` vous invite (party_accept / party_decline)", {"from": "str"}],
	UPDATE: [S2C, "Groupe : sa composition et la position de ses membres (voir en tête de protocol_party.gd)", {"party": "dict"}],
	LEFT: [S2C, "Groupe : vous n'en faites plus partie, `reason` = left | kicked | dissolved", {"reason": "str"}],
	DECLINED: [S2C, "Groupe : `name` a refusé votre invitation", {"name": "str"}],
}


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

static func leader(name: String) -> Dictionary:
	return {"t": LEADER, "name": name}

static func follow(name: String) -> Dictionary:
	return {"t": FOLLOW, "name": name}

static func invited(from: String) -> Dictionary:
	return {"t": INVITED, "from": from}

static func update(party: Dictionary) -> Dictionary:
	return {"t": UPDATE, "party": party}

static func left(reason: String) -> Dictionary:
	return {"t": LEFT, "reason": reason}

static func declined(name: String) -> Dictionary:
	return {"t": DECLINED, "name": name}
