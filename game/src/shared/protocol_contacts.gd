## The friends / enemies / ignored messages (P3.05), an extension of Protocol (protocol.gd
## stays under its size limit). Same rules as Protocol: JSON-safe dictionaries, int() on read.
class_name ProtocolContacts
extends RefCounted

# same strings as Protocol.C2S / S2C (a test checks it): this file does not reference Protocol
const C2S := "client → jeu"
const S2C := "jeu → client"

# client -> game
const GET := "contacts_get"
const ADD := "contact_add"
const REMOVE := "contact_remove"
# game -> client
const CONTACTS := "contacts"
const STATUS := "contact_status"

const E_BAD_CONTACT_KIND := "bad_contact_kind"   # contact_add / contact_remove: kind is not friend | enemy | ignored
const E_CONTACT_SELF := "contact_self"           # contact_add: yourself (or another character of your account)
const E_CONTACT_EXISTS := "contact_exists"       # contact_add: already on that list
const E_CONTACT_FULL := "contact_full"           # contact_add: the list holds Contacts.MAX_PER_LIST
const E_CONTACT_UNKNOWN := "contact_unknown"     # contact_add: no character of that name / contact_remove: not on the list
const ERROR_CODES := [E_BAD_CONTACT_KIND, E_CONTACT_SELF, E_CONTACT_EXISTS, E_CONTACT_FULL, E_CONTACT_UNKNOWN]

## type -> [direction, meaning, {field: type}], same format as Protocol.SCHEMA.
## contacts = {friends, enemies, ignored}: lists of {name, online (bool), playing (the character
## the account plays now, "" offline), level (0 offline), breed (-1 offline)}; the ignored list
## only has {name}. Sent in answer to contacts_get / contact_add / contact_remove, and at
## connection when the account has at least one contact.
const SCHEMA := {
	GET: [C2S, "Amis (P3.05) : demander ses listes. Réponse : contacts", {}],
	ADD: [C2S, "Amis : ajouter le personnage `name` à la liste `kind` (friend, enemy, ignored ; il quitte les autres listes). Réponse : contacts, ou error (contact_unknown, contact_self, contact_exists, contact_full, bad_contact_kind)", {"kind": "str", "name": "str"}],
	REMOVE: [C2S, "Amis : retirer `name` de la liste `kind`. Réponse : contacts, ou error (contact_unknown, bad_contact_kind)", {"kind": "str", "name": "str"}],
	CONTACTS: [S2C, "Amis : les trois listes du compte (voir en tête de protocol_contacts.gd)", {"friends": "array", "enemies": "array", "ignored": "array"}],
	STATUS: [S2C, "Amis : un ami (`kind` friend) vient de se connecter ou de se déconnecter : `name`, `online`, `playing` (son personnage), `level`", {"kind": "str", "name": "str", "online": "bool", "playing": "str", "level": "int"}],
}


static func get_lists() -> Dictionary:
	return {"t": GET}

static func add(kind: String, name: String) -> Dictionary:
	return {"t": ADD, "kind": kind, "name": name}

static func remove(kind: String, name: String) -> Dictionary:
	return {"t": REMOVE, "kind": kind, "name": name}

static func contacts(friends: Array, enemies: Array, ignored: Array) -> Dictionary:
	return {"t": CONTACTS, "friends": friends, "enemies": enemies, "ignored": ignored}

static func status(kind: String, name: String, online: bool, playing: String, level: int) -> Dictionary:
	return {"t": STATUS, "kind": kind, "name": name, "online": online, "playing": playing, "level": level}
