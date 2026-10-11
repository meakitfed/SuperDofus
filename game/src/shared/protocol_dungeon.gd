## The dungeon messages (P4.01), an extension of Protocol (protocol.gd stays under its size
## limit): constants, SCHEMA entries, builders and error codes of the domain. Protocol.validate
## and docs/PROTOCOL.md read this table after Protocol.SCHEMA. Same rules as Protocol.
class_name ProtocolDungeon
extends RefCounted

# same strings as Protocol.C2S / S2C: this file does not reference Protocol
const C2S := "client → jeu"
const S2C := "jeu → client"

# client -> game
const ENTER := "dungeon_enter"
const LEAVE := "dungeon_leave"
# game -> client
const ROOM := "dungeon_room"
const END := "dungeon_end"

const E_DUNGEON_UNKNOWN := "dungeon_unknown"                    # dungeon_enter: no such dungeon
const E_DUNGEON_LEVEL := "dungeon_level"                        # dungeon_enter: level too low
const E_DUNGEON_KEY := "dungeon_key"                            # dungeon_enter: the key is missing
const E_DUNGEON_NOT_AT_ENTRANCE := "dungeon_not_at_entrance"    # dungeon_enter: not on the entrance map
const E_DUNGEON_NOT_IN := "dungeon_not_in"                      # dungeon_leave: not in a dungeon
const ERROR_CODES := [E_DUNGEON_UNKNOWN, E_DUNGEON_LEVEL, E_DUNGEON_KEY, E_DUNGEON_NOT_AT_ENTRANCE, E_DUNGEON_NOT_IN]

const REASON_WON := "won"             # the last room is cleared
const REASON_LEFT := "left"           # you left
const REASON_DEFEAT := "defeat"       # you lost a fight in the dungeon
const REASON_DISBANDED := "disbanded" # the group is gone
const REASONS := [REASON_WON, REASON_LEFT, REASON_DEFEAT, REASON_DISBANDED]

## type -> [direction, meaning, {field: type}], same format as Protocol.SCHEMA.
const SCHEMA := {
	ENTER: [C2S, "Donjon (P4.01) : entrer dans le donjon `dungeon` depuis sa map d'entrée (le groupe y entre avec vous). Réponse : dungeon_room, ou error (dungeon_unknown, dungeon_level, dungeon_key, dungeon_not_at_entrance)", {"dungeon": "int"}],
	LEAVE: [C2S, "Donjon : en sortir : dungeon_end{left}, ou error (dungeon_not_in)", {}],
	ROOM: [S2C, "Donjon : la salle courante (`room` à partir de 0, sur `total`), `boss` si c'est la dernière, `name` son nom", {"dungeon": "int", "room": "int", "total": "int", "boss": "bool", "name": "str"}],
	END: [S2C, "Donjon : fin de l'exploration, `reason` = won | left | defeat | disbanded", {"dungeon": "int", "reason": "str"}],
}


static func enter(dungeon: int) -> Dictionary:
	return {"t": ENTER, "dungeon": dungeon}

static func leave() -> Dictionary:
	return {"t": LEAVE}

static func room(dungeon: int, room_index: int, total: int, boss: bool, name: String) -> Dictionary:
	return {"t": ROOM, "dungeon": dungeon, "room": room_index, "total": total, "boss": boss, "name": name}

static func end(dungeon: int, reason: String) -> Dictionary:
	return {"t": END, "dungeon": dungeon, "reason": reason}
