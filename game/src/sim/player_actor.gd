## A connected player. Events addressed to it are queued in `outbox` and drained
## by whatever transport serves this player (LocalBackend now, a socket later).
class_name PlayerActor
extends SimActor

var outbox: Array = []
## last event number sent to this session (Protocol envelope `seq`)
var seq := 0
## fight id while fighting (0 = roleplay) and the cell to come back to afterwards
var fight_id := 0
var return_cell := 0
## the fight being watched (P3.04, WorldFightWatch), 0 = none: a spectator is off the map and cannot act
var spectating := 0
## the connection dropped while in a fight (S.02b, WorldResume): the player stays in the world,
## absent, until it resumes, the fight ends, or the host gives up
var detached := false
## the persistent part (level, XP, inventory, HP...)
var character := Character.new()
## open NPC dialog (P2.01): the NPC actor id (0 = none) and the node shown
var dialog_npc := 0
var dialog_node := ""
## the tree of that dialog for this character: the NPC's own plus the quests it offers (P2.03)
var dialog_tree := {}
## open NPC shop (P2.02): the NPC actor id (0 = none)
var shop_npc := 0
## open bank chest (P2.08): the banker NPC actor id (0 = none)
var bank_npc := 0
## harvest under way (P2.05): {element, skill, end} (sim ms), {} = none
var harvest := {}
## open workshop (P2.06): {skill, ingredients: [{item, qty}]}, {} = none
var craft := {}
## game master: may send admin_cmd (the host grants it: the local player in standalone)
var gm := false
## chat anti-flood (P3.02): flood bucket -> send times (sim ms), see Chat.flood_wait
var chat_sent := {}


func kind() -> String:
	return "player"


## What the others on the map get to know of a player (P3.01): the actor fields plus the
## class, the level (Dofus shows both in the tooltip of a character) and `life` (Energy.GHOST)
## so that everyone sees a ghost. Nothing else of the character (account, stats, bag, quests)
## ever leaves through here: tests/test_players.gd checks this list.
const PUBLIC_KEYS := ["id", "kind", "name", "cell", "dir", "looks", "move", "breed", "level", "life"]


func to_dict(now: int) -> Dictionary:
	var d := super(now)
	d["breed"] = character.breed
	d["level"] = character.level
	if character.is_ghost():
		d["life"] = character.life
	return d
