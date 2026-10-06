## Friends, enemies and ignored players (P3.05), pure rules on a book:
##   book = {friends: [entry], enemies: [entry], ignored: [entry]}, entry = {account, name}
## The lists belong to the account (every character of the account shares them) and are kept
## by WorldContacts through Persistence. An entry names the *account* of the other player
## (that is what an ignore must hold, whatever character it plays) and the character name
## it was added under (what the lists show). Nothing here is specific to Dofus.
##
## APPROX(P3.05): the data has no list limit or exclusivity rule (tables of the social
## window not extracted): 100 entries per list (Dofus 2: 100 friends, 100 ignored), and a
## player is on one list at a time (adding to one removes it from the others).
## APPROX(P3.05): adding a friend is one-way and immediate (no request / acceptance).
class_name Contacts
extends RefCounted

const FRIEND := "friend"
const ENEMY := "enemy"
const IGNORED := "ignored"
const KINDS := [FRIEND, ENEMY, IGNORED]
## kind -> key of the book
const KEYS := {FRIEND: "friends", ENEMY: "enemies", IGNORED: "ignored"}
const MAX_PER_LIST := 100


static func empty() -> Dictionary:
	return {"friends": [], "enemies": [], "ignored": []}


## The book of a stored document value (missing or damaged parts become empty lists).
static func normalize(raw: Variant) -> Dictionary:
	var book := empty()
	if raw is Dictionary:
		for kind: String in KINDS:
			var list: Variant = (raw as Dictionary).get(KEYS[kind], [])
			if list is Array:
				for e: Variant in list:
					if e is Dictionary and str(e.get("account", "")) != "" and str(e.get("name", "")) != "":
						book[KEYS[kind]].append({"account": str(e["account"]), "name": str(e["name"])})
	return book


static func is_empty(book: Dictionary) -> bool:
	for kind: String in KINDS:
		if not (book[KEYS[kind]] as Array).is_empty():
			return false
	return true


static func list_of(book: Dictionary, kind: String) -> Array:
	return book[KEYS[kind]]


## True if `account` is on the list `kind`.
static func has_account(book: Dictionary, kind: String, account: String) -> bool:
	for e: Dictionary in list_of(book, kind):
		if e["account"] == account:
			return true
	return false


## Adds `account` / `name` to `kind` (moving it off the other lists). Returns "" or an error code.
static func add(book: Dictionary, kind: String, account: String, name: String, own_account: String) -> String:
	if not kind in KINDS:
		return ProtocolContacts.E_BAD_CONTACT_KIND
	if account == own_account:
		return ProtocolContacts.E_CONTACT_SELF
	if has_account(book, kind, account):
		return ProtocolContacts.E_CONTACT_EXISTS
	if list_of(book, kind).size() >= MAX_PER_LIST:
		return ProtocolContacts.E_CONTACT_FULL
	for other: String in KINDS:
		var keep := (list_of(book, other) as Array).filter(func(e: Dictionary) -> bool: return e["account"] != account)
		book[KEYS[other]] = keep
	book[KEYS[kind]].append({"account": account, "name": name})
	return ""


## Removes the entry of that name (any case) from `kind`; false if it was not there.
static func remove(book: Dictionary, kind: String, name: String) -> bool:
	if not kind in KINDS:
		return false
	var lower := name.strip_edges().to_lower()
	var list: Array = list_of(book, kind)
	for i in list.size():
		if str(list[i]["name"]).to_lower() == lower:
			list.remove_at(i)
			return true
	return false
