## Friends, enemies, ignored (P3.05): the lists of an account, kept in its document of
## Persistence (`accounts/<account>` key "contacts", like the bank: every character and every
## world of the account share them), the connection notices sent to friends and the ignore
## filter used by WorldChat. Rules: shared/Contacts. Nothing here knows Dofus.
class_name WorldContacts
extends WorldHandler


static func _key(p: PlayerActor) -> String:
	return Bank.account_key(p.character.account)


func book_of(account: String) -> Dictionary:
	return Contacts.normalize(sim.persistence.load_account(Bank.account_key(account)).get("contacts", {}))


func _save(account: String, book: Dictionary) -> void:
	var key := Bank.account_key(account)
	var doc := sim.persistence.load_account(key)
	if Contacts.is_empty(book):
		doc.erase("contacts")
	else:
		doc["contacts"] = book
	sim.persistence.save_account(key, doc)


func on_command(p: PlayerActor, type: String, cmd: Dictionary) -> void:
	if type == ProtocolContacts.GET:
		send_lists(p)
		return
	var kind := str(cmd["kind"])
	var name := str(cmd["name"]).strip_edges()
	if not kind in Contacts.KINDS:
		_error(p, ProtocolContacts.E_BAD_CONTACT_KIND, type)
		return
	var book := book_of(p.character.account)
	if type == ProtocolContacts.REMOVE:
		if not Contacts.remove(book, kind, name):
			_error(p, ProtocolContacts.E_CONTACT_UNKNOWN, type)
			return
	else:
		var who := resolve(name)
		if who.is_empty():
			_error(p, ProtocolContacts.E_CONTACT_UNKNOWN, type)
			return
		var err := Contacts.add(book, kind, str(who["account"]), str(who["name"]), _key(p))
		if err != "":
			_error(p, err, type)
			return
	_save(p.character.account, book)
	send_lists(p)


func _error(p: PlayerActor, code: String, ref: String) -> void:
	p.outbox.append(Protocol.error(code, "", ref))


## {account (key), name} of the character called `name` (any case): connected, else saved in
## this world. {} if there is none.
func resolve(name: String) -> Dictionary:
	var lower := name.to_lower()
	if lower == "":
		return {}
	for q: PlayerActor in sim.players.values():
		if q.name.to_lower() == lower:
			return {"account": _key(q), "name": q.name}
	for n in sim.persistence.list_characters(sim.world_id()):
		if n.to_lower() == lower:
			var acc := str(sim.persistence.load_character(sim.world_id(), n).get("account", ""))
			return {"account": Bank.account_key(acc), "name": n}
	return {}


## The player (any character) of `account` who is connected, null if none.
func online_of(account: String) -> PlayerActor:
	for q: PlayerActor in sim.players.values():
		if _key(q) == account:
			return q
	return null


func _view(e: Dictionary, with_status: bool) -> Dictionary:
	if not with_status:
		return {"name": e["name"]}
	var q := online_of(str(e["account"]))
	if q == null:
		return {"name": e["name"], "online": false, "playing": "", "level": 0, "breed": -1}
	return {"name": e["name"], "online": true, "playing": q.name, "level": q.character.level, "breed": q.character.breed}


func send_lists(p: PlayerActor) -> void:
	var book := book_of(p.character.account)
	p.outbox.append(ProtocolContacts.contacts(
		Contacts.list_of(book, Contacts.FRIEND).map(func(e: Dictionary) -> Dictionary: return _view(e, true)),
		Contacts.list_of(book, Contacts.ENEMY).map(func(e: Dictionary) -> Dictionary: return _view(e, true)),
		Contacts.list_of(book, Contacts.IGNORED).map(func(e: Dictionary) -> Dictionary: return _view(e, false))))


## A player entered the world: its lists (only if it has any) and a notice to the friends online.
func on_connect(p: PlayerActor) -> void:
	if not Contacts.is_empty(book_of(p.character.account)):
		send_lists(p)
	_notify(p, true)


func on_disconnect(p: PlayerActor) -> void:
	_notify(p, false)


func _notify(p: PlayerActor, online: bool) -> void:
	var mine := _key(p)
	for q: PlayerActor in sim.players.values():
		if q != p and _key(q) == mine:
			return # another character of the account plays: the account stays as it was
	for q: PlayerActor in sim.players.values():
		if q == p:
			continue
		var book := book_of(q.character.account)
		for e: Dictionary in Contacts.list_of(book, Contacts.FRIEND):
			if e["account"] == mine:
				q.outbox.append(ProtocolContacts.status(Contacts.FRIEND, str(e["name"]), online, p.name if online else "", p.character.level if online else 0))


## True if `listener` ignores `speaker` (the account of the speaker is on its ignored list).
func ignores(listener: PlayerActor, speaker: PlayerActor) -> bool:
	if listener == speaker:
		return false
	return Contacts.has_account(book_of(listener.character.account), Contacts.IGNORED, _key(speaker))
