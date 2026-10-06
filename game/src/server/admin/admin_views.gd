## What the admin web reads (roadmap A1.02): overview, accounts, character sheets, audit trail.
## Everything is a JSON-safe Dictionary built from the live sims and from Persistence (the
## saved documents). A connected character is read live (WorldSim.character_write: the same
## document a save would write), an offline one from its save: both have the shape of
## Character.to_dict. No password hash, salt or session token ever leaves from here. Nothing
## here knows which game a world runs. Not used by sim/, shared/ or client/.
class_name AdminViews
extends RefCounted

const MAX_ACCOUNTS := 200
const MAX_AUDIT := 500

var host: ServerHost


func overview() -> Dictionary:
	var out := host.admin.metrics.snapshot(host)
	var players := []
	var fights := []
	var ids := host.server.worlds.keys()
	ids.sort()
	for id: String in ids:
		var sim: WorldSim = host.server.worlds[id]
		for p: PlayerActor in sim.players.values():
			players.append({"world": id, "name": p.name, "account": p.character.account,
					"level": p.character.level, "breed": p.character.breed, "map": p.map_id,
					"fight": p.fight_id, "detached": p.detached})
		for f: Fight in sim.fights.values():
			var names := []
			for fi: Fighter in f.fighters.values():
				names.append(fi.name)
			fights.append({"world": id, "id": f.id, "map": f.map.id, "phase": f.phase,
					"fighters": f.fighters.size(), "names": names, "spectators": f.spectators.size()})
	players.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["name"]) < str(b["name"]))
	out["player_list"] = players
	out["fight_list"] = fights
	out["accounts"] = host.auth.accounts.logins().size() if host.auth != null else 0
	return out


## Accounts whose login contains `q` (or one of whose characters' names does), at most
## MAX_ACCOUNTS: [{login, role, created, online, banned, characters: [{world, name, level}]}].
func accounts(q: String) -> Dictionary:
	q = q.strip_edges().to_lower()
	var chars := _characters_by_account()
	var list := []
	var total := 0
	for login in _logins(chars):
		var mine: Array = chars.get(login, [])
		var hit := q == "" or login.contains(q)
		for c: Dictionary in mine:
			hit = hit or str(c["name"]).to_lower().contains(q)
		if not hit:
			continue
		total += 1
		if list.size() < MAX_ACCOUNTS:
			list.append(_summary(login, mine))
	return {"accounts": list, "total": total}


## The sheet of an account: the summary plus sanction, last connection (time and address) and
## the characters. {} when unknown.
func account(login: String) -> Dictionary:
	login = AccountStore.normalize(login)
	var store := _store()
	if store != null and not store.exists(login):
		return {}
	var chars := _characters_by_account()
	var out := _summary(login, chars.get(login, []))
	var doc := host.server.persistence.load_account(Bank.account_key(login))
	out["seen"] = doc.get("seen", {})
	var s: Dictionary = doc.get("sanction", {})
	out["sanction"] = {"ban": s.get("ban", {}), "mute_until": int(s.get("mute_until", 0))}
	var bank: Dictionary = doc.get("bank", {})
	out["bank_kamas"] = int(bank.get("kamas", 0))
	out["bank_items"] = (bank.get("items", []) as Array).size()
	return out


## The sheet of a character: its document (live when connected) and where it is. {} when unknown.
func character(world: String, name: String) -> Dictionary:
	var sim: WorldSim = host.server.worlds.get(world)
	var p: PlayerActor = sim.chat.find_player(name) if sim != null else null
	var doc: Dictionary
	if p != null:
		doc = sim.character_write(p)["data"]
	else:
		doc = host.server.persistence.load_character(world, name)
	if doc.is_empty():
		return {}
	var out := doc.duplicate(true)
	out["world"] = world
	out["online"] = p != null
	out["fight"] = p.fight_id if p != null else 0
	out["quest_count"] = _count(doc.get("quests", {}))
	return out


## The newest `limit` audit entries (newest first): the file when there is one, else the
## sims' in-memory trails.
func audit(limit: int) -> Dictionary:
	limit = clampi(limit, 1, MAX_AUDIT)
	var entries: Array = []
	if host.audit != null:
		entries = host.audit.read_all()
	else:
		for sim: WorldSim in host.server.worlds.values():
			entries.append_array(sim.admin.audit_log)
		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["at"]) < int(b["at"]))
	entries = entries.slice(maxi(0, entries.size() - limit))
	entries.reverse()
	return {"entries": entries}


func _store() -> AccountStore:
	return host.auth.accounts if host.auth != null else null


## Logins to list: the accounts of the store, else (open server) those of the characters.
func _logins(chars: Dictionary) -> PackedStringArray:
	var store := _store()
	if store != null:
		return store.logins()
	var out := PackedStringArray(chars.keys())
	out.sort()
	return out


func _summary(login: String, mine: Array) -> Dictionary:
	var persistence := host.server.persistence
	var store := _store()
	var now := host.server.clock.now_unix_ms()
	var key := Bank.account_key(login)
	return {"login": login, "role": store.role(login) if store != null else "player",
			"gm": host.gm_accounts.has(login), "created": _created(login),
			"online": _online(login), "banned": Sanctions.is_banned(persistence, key),
			"mute_left_s": Sanctions.mute_left_ms(persistence, key, now) / 1000, "characters": mine}


func _created(login: String) -> int:
	return int(host.server.persistence.load_account(login).get("auth", {}).get("created", 0))


func _online(login: String) -> bool:
	for sim: WorldSim in host.server.worlds.values():
		for p: PlayerActor in sim.players.values():
			if p.character.account == login:
				return true
	return false


## account -> [{world, name, level, breed}] from the saved characters (the worlds that are loaded).
func _characters_by_account() -> Dictionary:
	var out := {}
	var persistence := host.server.persistence
	var ids := host.server.worlds.keys()
	ids.sort()
	for world: String in ids:
		var seen := {}
		for name in persistence.list_characters(world):
			var d := persistence.load_character(world, name)
			seen[name] = true
			_add(out, world, name, str(d.get("account", "")), int(d.get("level", 1)), int(d.get("breed", 0)))
		for p: PlayerActor in (host.server.worlds[world] as WorldSim).players.values():
			if not seen.has(p.name): # connected and not saved yet
				_add(out, world, p.name, p.character.account, p.character.level, p.character.breed)
	return out


func _add(out: Dictionary, world: String, name: String, account: String, level: int, breed: int) -> void:
	if not out.has(account):
		out[account] = []
	out[account].append({"world": world, "name": name, "level": level, "breed": breed})


static func _count(v: Variant) -> int:
	return (v as Dictionary).size() if v is Dictionary else ((v as Array).size() if v is Array else 0)
