## A non-player character standing on a map: placed where the real server puts it
## (worlds/<id>/npcs.json), never moves. Its name, look and dialog texts are the
## client's own (npcs table); `dialog` is the tree it opens (Dialog).
class_name NpcActor
extends SimActor

## npcs.id (the template)
var npc_id := 0
## i18n id of its name (the client reads the text)
var name_id := 0
## npcactions the template offers (3 = talk)
var actions: Array = []
var dialog := {}


func kind() -> String:
	return "npc"


func to_dict(now: int) -> Dictionary:
	var d := super.to_dict(now)
	d["npc"] = npc_id
	d["name_id"] = name_id
	d["actions"] = actions
	d["talk"] = not dialog.is_empty()
	return d
