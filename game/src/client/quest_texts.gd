## What the player reads of a quest: the Dofus 3 texts (i18n of the client). The sim sends ids and
## numbers (Protocol quest views); the sentence of an objective is the template of its type
## (questobjectivetypes.nameId, "Aller voir #1") with the arguments the view carries
## (`args`: {t: i18n id} or {n: number}).
class_name QuestTexts
extends RefCounted

## "Nouvelle quête : $quest{0}" / "Quête terminée : $quest{0}" (infomessages of the client)
const NEW_QUEST := 5347
const QUEST_DONE := 5308
## "Vous avez gagné {0} points d'expérience."
const XP_GAINED := 5056
## the journal's title ("Quêtes")
const JOURNAL := 272249
## objective types whose sentence shows a count (6, 14, 16 kills, 17 crafts)
const COUNTED := [6, 14, 16, 17]


static func quest_name(name_id: int, id := 0) -> String:
	return UiStyle.plain_text(DofusI18n.text(name_id, "Quête %d" % id))


## The sentence of one objective of a quest view.
static func objective(o: Dictionary) -> String:
	var type_row := GameData.row("questobjectivetypes", int(o["type"]))
	var s := DofusI18n.text(int(type_row.get("nameId", 0)), "Objectif")
	var args: Array = o.get("args", [])
	for i in range(args.size(), 0, -1): # #3 before #1: never a prefix of another
		var a: Dictionary = args[i - 1]
		var value := UiStyle.plain_text(DofusI18n.text(int(a["t"]), "")) if a.has("t") else str(int(a.get("n", 0)))
		s = s.replace("#%d" % i, value)
	s = UiStyle.plain_text(s)
	if int(o["type"]) in COUNTED and int(o.get("need", 1)) > 1:
		s += " (%d/%d)" % [int(o.get("count", 0)), int(o["need"])]
	return s


## "Nouvelle quête : Name" and "Quête terminée : Name".
static func headline(template_id: int, fallback: String, name: String) -> String:
	var s := DofusI18n.text(template_id, fallback)
	return UiStyle.plain_text(s.replace("$quest{0}", name))


## What a finished step gave, one line: "+ 42 XP · 60 K · 5 x Name".
static func rewards_line(r: Dictionary) -> String:
	var parts := PackedStringArray()
	if int(r.get("xp", 0)) > 0:
		parts.append("%s XP" % UiStyle.thousands(int(r["xp"])))
	if int(r.get("kamas", 0)) > 0:
		parts.append("%s K" % UiStyle.thousands(int(r["kamas"])))
	for it: Array in r.get("items", []):
		parts.append("%d x %s" % [int(it[1]), UiStyle.plain_text(DofusI18n.text(int(GameData.item(int(it[0])).get("name_id", 0)), "objet %d" % int(it[0])))])
	return " · ".join(parts)
