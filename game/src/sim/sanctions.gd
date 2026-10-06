## Bans and mutes of accounts (A1.01), kept through Persistence in the account document
## (`accounts/<account>` key "sanction"), so they hold for every world and survive a restart:
##   sanction = {ban: {reason, by, at (unix ms)}, mute_until (unix ms)}
## The credentials ("auth") and the other account data (bank…) of the document are left alone.
## Real time comes from the caller (Clock), never from here. Nothing here knows which game a
## world runs.
class_name Sanctions
extends RefCounted


static func _doc(persistence: Persistence, account: String) -> Dictionary:
	var s: Variant = persistence.load_account(Bank.account_key(account)).get("sanction", {})
	return s if s is Dictionary else {}


static func _save(persistence: Persistence, account: String, sanction: Dictionary) -> void:
	var key := Bank.account_key(account)
	var doc := persistence.load_account(key)
	if sanction.is_empty():
		doc.erase("sanction")
	else:
		doc["sanction"] = sanction
	persistence.save_account(key, doc)


## The ban {reason, by, at} of the account, {} when it is not banned.
static func ban_of(persistence: Persistence, account: String) -> Dictionary:
	var b: Variant = _doc(persistence, account).get("ban", {})
	return b if b is Dictionary else {}


static func is_banned(persistence: Persistence, account: String) -> bool:
	return not ban_of(persistence, account).is_empty()


static func ban(persistence: Persistence, account: String, reason: String, by: String, now_unix_ms: int) -> void:
	var s := _doc(persistence, account)
	s["ban"] = {"reason": reason, "by": by, "at": now_unix_ms}
	_save(persistence, account, s)


## True if the account was banned.
static func unban(persistence: Persistence, account: String) -> bool:
	var s := _doc(persistence, account)
	if not s.has("ban"):
		return false
	s.erase("ban")
	_save(persistence, account, s)
	return true


## Mute until `until_unix_ms`; 0 lifts it.
static func mute(persistence: Persistence, account: String, until_unix_ms: int) -> void:
	var s := _doc(persistence, account)
	if until_unix_ms > 0:
		s["mute_until"] = until_unix_ms
	else:
		s.erase("mute_until")
	_save(persistence, account, s)


## Milliseconds of mute left (0 = may talk).
static func mute_left_ms(persistence: Persistence, account: String, now_unix_ms: int) -> int:
	return maxi(0, int(_doc(persistence, account).get("mute_until", 0)) - now_unix_ms)
