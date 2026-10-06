## Joining a fight and watching one (P3.04), an extension of Protocol (protocol.gd stays under its
## size limit): constants, SCHEMA entries, builders and error codes of the domain. Protocol.validate
## and docs/PROTOCOL.md read this table after Protocol.SCHEMA. Same rules as Protocol.
##
## A fight started on a map is an actor of that map (`actor_add{kind: "fight"}`, the swords): its
## dict is {id (= the fight id), kind, name, cell, dir, looks: [], teams: [n0, n1] (fighters per
## team, summons excluded), phase ("placement" | "fight"), options}. It is sent again (actor_add with
## the same id replaces it) whenever the teams, the phase or the options change, and removed
## (actor_remove) when the fight ends. A fight is not a place of the map: nothing in it is private.
class_name ProtocolWatch
extends RefCounted

# same strings as Protocol.C2S / S2C (a test checks it): this file does not reference Protocol
const C2S := "client → jeu"
const S2C := "jeu → client"

# client -> game
const JOIN := "fight_join"
const SPECTATE := "fight_spectate"
# game -> client
const WATCH := "fight_watch"
const JOINED := "fighter_joined"
const LEFT := "fighter_left"

const E_NO_FIGHT := "no_fight"                # fight_join / fight_spectate: no such fight on your map
const E_FIGHT_FULL := "fight_full"            # fight_join: the team has 8 fighters, or no free placement cell
const E_FIGHT_STARTED := "fight_started"      # fight_join: the placement is over
const E_BAD_TEAM := "bad_team"                # fight_join: that team cannot be joined (the monsters')
const E_SPECTATING := "spectating"            # any command but fight_leave / chat / party while watching
const ERROR_CODES := [E_NO_FIGHT, E_FIGHT_FULL, E_FIGHT_STARTED, E_BAD_TEAM, E_SPECTATING]

## fighters per team (Dofus: 8)
const TEAM_MAX := 8

## type -> [direction, meaning, {field: type}], same format as Protocol.SCHEMA.
const SCHEMA := {
	JOIN: [C2S, "Rejoindre le combat `fight` de sa map, dans l'équipe `team` (0 = les joueurs ; pendant le placement seulement, 8 par équipe) : fight_start chez vous (vous êtes un combattant), fighter_joined chez les autres. Erreurs : no_fight, fight_started, fight_full, bad_team, fight_locked, fight_party_only, in_fight", {"fight": "int", "team": "int"}],
	SPECTATE: [C2S, "Regarder le combat `fight` de sa map : fight_watch (l'état du combat) puis tous ses événements, sans pouvoir agir (fight_leave pour sortir). Erreurs : no_fight, fight_secret, in_fight", {"fight": "int"}],
	WATCH: [S2C, "Vous regardez un combat : `fight`, `fighters`, `order`, `phase` (placement | fight), `placement`, `end` (fin du chrono en cours), `turn` (id du combattant qui joue, -1 au placement), `options`, `challenges`", {"fight": "int", "fighters": "array", "order": "array", "phase": "str", "placement": "dict", "end": "int", "turn": "int", "options": "dict", "challenges": "array"}],
	JOINED: [S2C, "Un joueur rejoint le combat pendant le placement : sa fiche de combattant (`fighter`) et le nouvel ordre", {"fighter": "dict", "order": "array"}],
	LEFT: [S2C, "Un joueur quitte le combat (fuite) sans le terminer : `id` ne combat plus ; `order` = le nouvel ordre", {"id": "int", "order": "array"}],
}


static func join(fight: int, team := 0) -> Dictionary:
	return {"t": JOIN, "fight": fight, "team": team}

static func spectate(fight: int) -> Dictionary:
	return {"t": SPECTATE, "fight": fight}

static func watch(fight: int, fighters: Array, order: Array, phase: String, placement: Dictionary, end: int,
		turn: int, options: Dictionary, challenges: Array) -> Dictionary:
	return {"t": WATCH, "fight": fight, "fighters": fighters, "order": order, "phase": phase, "placement": placement,
			"end": end, "turn": turn, "options": options.duplicate(), "challenges": challenges}

static func joined(fighter: Dictionary, order: Array) -> Dictionary:
	return {"t": JOINED, "fighter": fighter, "order": order}

static func left(id: int, order: Array) -> Dictionary:
	return {"t": LEFT, "id": id, "order": order}
