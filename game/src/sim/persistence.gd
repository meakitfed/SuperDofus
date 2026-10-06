## Everything durable the game keeps: characters, accounts, and later banks,
## marketplace, guilds, houses. The sim only talks to this interface; the host
## injects the implementation (docs/ARCHITECTURE.md, "Standalone vs serveur"):
##   - this base class: in memory (tests, throwaway sessions);
##   - FilePersistence (api/): JSON files in user://saves (standalone game);
##   - DbPersistence (server/, roadmap S.03): a database, real transactions.
##
## Storage model: JSON-safe documents in named collections, addressed by a
## string key. Implementations only override the four _raw methods.
##   "characters"  key "<world>/<name>"  Character.to_dict() + saved_at
##   "accounts"    key "<account>"       account-wide data (bank, contacts…)
##   "counters"    key "<kind>"          {next}: unique ids (item uids…)
##   "worlds"      key "<world>/stars"   {subareas: {id: {bonus, at}}}: the stars (SubareaBonus)
##
## Calls are synchronous: SQLite is in-process, and a remote database would sit
## behind a write-behind cache in the server, keeping the sim simple and
## deterministic.
class_name Persistence
extends RefCounted

const CHARACTERS := "characters"
const ACCOUNTS := "accounts"
const COUNTERS := "counters"

var _mem := {} # collection -> {key -> data}


## {} when the document does not exist.
func load_doc(collection: String, key: String) -> Dictionary:
	return _raw_read(collection, key).duplicate(true)


func save_doc(collection: String, key: String, data: Dictionary) -> void:
	_raw_write(collection, key, data.duplicate(true))


func delete_doc(collection: String, key: String) -> void:
	_raw_erase(collection, key)


## Keys of a collection starting with prefix, sorted (deterministic order).
func list_keys(collection: String, prefix := "") -> PackedStringArray:
	var out := PackedStringArray()
	for k in _raw_keys(collection):
		if k.begins_with(prefix):
			out.append(k)
	out.sort()
	return out


## Applies several writes together: [{collection, key, data}] where a null
## data deletes. Needed by exchanges, marketplace, bank (both sides or none).
## The base and file versions write in order; DbPersistence wraps them in a
## database transaction.
func commit(writes: Array) -> void:
	for w: Dictionary in writes:
		if w.get("data") == null:
			delete_doc(str(w["collection"]), str(w["key"]))
		else:
			save_doc(str(w["collection"]), str(w["key"]), w["data"])


# --- typed helpers ---------------------------------------------------------

func load_character(world: String, name: String) -> Dictionary:
	return load_doc(CHARACTERS, world + "/" + name)


func save_character(world: String, name: String, data: Dictionary) -> void:
	save_doc(CHARACTERS, world + "/" + name, data)


func delete_character(world: String, name: String) -> void:
	delete_doc(CHARACTERS, world + "/" + name)


## Names of the characters of a world, optionally only those of one account.
func list_characters(world: String, account := "") -> PackedStringArray:
	var out := PackedStringArray()
	for k in list_keys(CHARACTERS, world + "/"):
		var name := k.substr(world.length() + 1)
		if account == "" or str(load_doc(CHARACTERS, k).get("account", "")) == account:
			out.append(name)
	return out


## A new unique id of `kind` ("item": item instance uids), never given twice by
## this store (a database sequence on the server).
func next_uid(kind: String) -> int:
	var doc := load_doc(COUNTERS, kind)
	var uid := int(doc.get("next", 1))
	save_doc(COUNTERS, kind, {"next": uid + 1})
	return uid


func load_account(account: String) -> Dictionary:
	return load_doc(ACCOUNTS, account)


func save_account(account: String, data: Dictionary) -> void:
	save_doc(ACCOUNTS, account, data)


# --- storage backend (override these) --------------------------------------

func _raw_read(collection: String, key: String) -> Dictionary:
	return (_mem.get(collection, {}) as Dictionary).get(key, {})


func _raw_write(collection: String, key: String, data: Dictionary) -> void:
	if not _mem.has(collection):
		_mem[collection] = {}
	_mem[collection][key] = data


func _raw_erase(collection: String, key: String) -> void:
	(_mem.get(collection, {}) as Dictionary).erase(key)


func _raw_keys(collection: String) -> PackedStringArray:
	return PackedStringArray((_mem.get(collection, {}) as Dictionary).keys())
