## What the client knows of dungeons (P4.01), without any node: the dungeons offered by the
## entrance map (`dungeons` of the map_enter dict) and, once inside, the current room (dungeon_room)
## until the end (dungeon_end). The sim decides everything; this only keeps the last words.
class_name DungeonModel
extends RefCounted

var entrances: Array = []   # [{id, name, min_level}] of the current map, [] = no dungeon here
var inside := false
var dungeon := -1
var room := 0               # from 0
var total := 0
var boss := false
var room_name := ""
var last_reason := ""       # reason of the last dungeon_end
var _names := {}            # dungeon id -> name, kept from the entrances seen


## A map_enter: the dungeons of the map (the room maps of a dungeon carry none).
func on_map(map: Dictionary) -> void:
	entrances = map.get("dungeons", [])
	for d: Dictionary in entrances:
		_names[int(d["id"])] = str(d["name"])


## The dungeon events; the text to show in a toast ("" = nothing).
func on_event(t: String, ev: Dictionary) -> String:
	match t:
		ProtocolDungeon.ROOM:
			inside = true
			dungeon = int(ev["dungeon"])
			room = int(ev["room"])
			total = int(ev["total"])
			boss = bool(ev["boss"])
			room_name = str(ev["name"])
			last_reason = ""
			return ""
		ProtocolDungeon.END:
			inside = false
			last_reason = str(ev["reason"])
			dungeon = int(ev["dungeon"])
			return end_text(last_reason)
	return ""


func dungeon_name() -> String:
	return str(_names.get(dungeon, "Donjon"))


## "Salle 2/5" or "Salle du boss" (room counted from 0 by the sim).
func room_text() -> String:
	if boss:
		return "Salle du boss"
	return "Salle %d/%d" % [room + 1, total]


static func end_text(reason: String) -> String:
	match reason:
		ProtocolDungeon.REASON_WON:
			return "Donjon terminé : victoire !"
		ProtocolDungeon.REASON_DEFEAT:
			return "Vous avez été vaincu : le donjon est perdu"
		ProtocolDungeon.REASON_DISBANDED:
			return "Le groupe est dissous : vous quittez le donjon"
	return "Vous avez quitté le donjon"
