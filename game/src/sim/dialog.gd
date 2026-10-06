## NPC dialog trees (P2.01). A dialog is data:
##   {start: node id, nodes: {id: {text_id | text, replies: [reply]}}}
##   reply = {id, text_id | text, criteria?, next?, action?}
## `text_id` is an i18n id (npcmessages / npcreplies: the client reads the text),
## `text` a literal one (hand-made worlds, tests). A reply with `criteria` is only
## offered when CriteriaEval passes for the character (hidden otherwise, like
## Dofus); `next` = the node it leads to ("" or absent: the dialog ends);
## `action` = {type: "teleport", map, cell} | {type: "give_kamas", amount} |
## {type: "give_item", item, qty} | {type: "shop"} | {type: "quest_start", quest} (P2.03: added by
## QuestEngine.with_offers, never written by hand; anything else is only passed on to the client).
##
## APPROX(P2.01): the real server's tree (which message follows which reply, and the
## quest conditions of each line) is not in the client data: `npcs.dialogMessages` /
## `dialogReplies` are flat lists of every line the NPC may say, so a template
## without a hand-written tree gets one node (its first message) and no reply.
class_name Dialog
extends RefCounted


## The default tree of an `npcs` row: its first message, nothing to answer. {} = silent NPC (no message).
static func default_for(row: Dictionary) -> Dictionary:
	var messages: Array = row.get("dialogMessages", [])
	if messages.is_empty() or not (row.get("actions", []) as Array).any(func(a: Variant) -> bool: return int(a) == 3):
		return {}
	var first: Dictionary = messages[0]
	return {"start": "0", "nodes": {"0": {"text_id": int((first["values"] as Array)[1]), "replies": []}}}


## The default tree of a merchant: the NPC's first message with the shop button of
## the client's own menu (npcactions 1 "Acheter/Vendre", i18n nameId 8944), which
## opens the shop. {} stays {}: a merchant with nothing to say opens its shop directly.
const SHOP_TEXT_ID := 8944


static func with_shop(tree: Dictionary) -> Dictionary:
	if tree.is_empty():
		return tree
	var out := tree.duplicate(true)
	var start: Dictionary = out["nodes"][out["start"]]
	var next_id := 1
	for r: Dictionary in start.get("replies", []):
		next_id = maxi(next_id, int(r["id"]) + 1)
	start["replies"].append({"id": next_id, "text_id": SHOP_TEXT_ID, "action": {"type": "shop"}})
	return out


## A banker's tree: its message with "Consulter son coffre personnel." (BankRules.OPEN_TEXT_ID),
## which opens the account chest (action "bank"). {} stays {}: a silent banker opens it directly.
static func with_bank(tree: Dictionary) -> Dictionary:
	if tree.is_empty():
		return tree
	var out := tree.duplicate(true)
	var start: Dictionary = out["nodes"][out["start"]]
	var next_id := 1
	for r: Dictionary in start.get("replies", []):
		next_id = maxi(next_id, int(r["id"]) + 1)
	start["replies"].append({"id": next_id, "text_id": BankRules.OPEN_TEXT_ID, "action": {"type": "bank"}})
	return out


## What the player sees at `node`: {text_id | text, replies: [{id, text_id | text}]}, {} if the node does not exist.
static func view(tree: Dictionary, node: String, values: Dictionary) -> Dictionary:
	var n: Dictionary = tree.get("nodes", {}).get(node, {})
	if n.is_empty():
		return {}
	var out := _text(n)
	out["replies"] = []
	for r: Dictionary in n.get("replies", []):
		if CriteriaEval.ok(str(r.get("criteria", "")), values):
			var shown := _text(r)
			shown["id"] = int(r["id"])
			if r.has("quest"): # a quest the NPC offers (QuestEngine.with_offers): the client labels it
				shown["quest"] = int(r["quest"])
			out["replies"].append(shown)
	return out


## The reply `id` chosen at `node`: the reply dictionary, {} if it does not exist or its criteria fail.
static func find_reply(tree: Dictionary, node: String, id: int, values: Dictionary) -> Dictionary:
	for r: Dictionary in tree.get("nodes", {}).get(node, {}).get("replies", []):
		if int(r["id"]) == id and CriteriaEval.ok(str(r.get("criteria", "")), values):
			return r
	return {}


static func _text(d: Dictionary) -> Dictionary:
	var out := {}
	if d.has("text_id"):
		out["text_id"] = int(d["text_id"])
	if d.has("text"):
		out["text"] = str(d["text"])
	return out
