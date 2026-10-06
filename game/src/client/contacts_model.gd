## The client's copy of the friends / enemies / ignored lists (P3.05b), fed by `contacts` and
## `contact_status`. It decides nothing: the sim owns the lists. Also the text commands of the
## chat box (/friend, /enemy, /ignore and their un- forms), which only turn a line into a message.
class_name ContactsModel
extends RefCounted

## chat word -> [kind, remove?]
const COMMANDS := {
	"/friend": [Contacts.FRIEND, false], "/unfriend": [Contacts.FRIEND, true],
	"/enemy": [Contacts.ENEMY, false], "/unenemy": [Contacts.ENEMY, true],
	"/ignore": [Contacts.IGNORED, false], "/unignore": [Contacts.IGNORED, true],
}
const KIND_TITLES := {Contacts.FRIEND: "Amis", Contacts.ENEMY: "Ennemis", Contacts.IGNORED: "Ignorés"}

## kind -> [{name, online, playing, level, breed}]
var lists := {Contacts.FRIEND: [], Contacts.ENEMY: [], Contacts.IGNORED: []}


func apply(ev: Dictionary) -> void:
	lists[Contacts.FRIEND] = (ev["friends"] as Array).duplicate()
	lists[Contacts.ENEMY] = (ev["enemies"] as Array).duplicate()
	lists[Contacts.IGNORED] = (ev["ignored"] as Array).duplicate()


## contact_status: updates the friend; returns the line to show ("Bob est en ligne (niveau 12)").
func status(ev: Dictionary) -> String:
	var name := str(ev["name"])
	var online := bool(ev["online"])
	for e: Dictionary in lists[Contacts.FRIEND]:
		if str(e["name"]) == name:
			e["online"] = online
			e["playing"] = str(ev["playing"])
			e["level"] = int(ev["level"])
	if online:
		var as_name := str(ev["playing"])
		return "%s est en ligne%s" % [name, "" if as_name == "" or as_name == name else " (%s)" % as_name]
	return "%s s'est déconnecté" % name


func online_count() -> int:
	return (lists[Contacts.FRIEND] as Array).filter(func(e: Dictionary) -> bool: return bool(e.get("online", false))).size()


func has(kind: String, name: String) -> bool:
	return (lists[kind] as Array).any(func(e: Dictionary) -> bool: return str(e["name"]).to_lower() == name.to_lower())


## "/friend Bob" -> contact_add; "/unignore Bob" -> contact_remove; {} if the line is not one of
## these commands or has no name.
static func parse_command(line: String) -> Dictionary:
	var words := line.strip_edges().split(" ", false)
	if words.size() < 2 or not COMMANDS.has(words[0].to_lower()):
		return {}
	var c: Array = COMMANDS[words[0].to_lower()]
	return ProtocolContacts.remove(c[0], words[1]) if c[1] else ProtocolContacts.add(c[0], words[1])
