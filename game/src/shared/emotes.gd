## Emotes (P3.02c), pure: which emoticons a player may play. Table `emoticons` (animName,
## criterion, duration, persistancy). Nothing here draws; the client plays `animName` on the
## character (the sim only decides who may and tells the map).
class_name Emotes
extends RefCounted

static var _rewarded: Dictionary = {}


## emoticons.id of every emote some quest or achievement gives (those must be earned).
static func rewarded() -> Dictionary:
	if _rewarded.is_empty():
		for table: String in ["achievementrewards", "queststeprewards"]:
			for row: Dictionary in GameData.table(table).values():
				for id: Variant in row.get("emotesReward", []):
					_rewarded[int(id)] = true
		_rewarded[0] = true # never empty again (the table may be missing)
	return _rewarded


static func clear_cache() -> void:
	_rewarded.clear()


## True if `owned` (Character.emotes) lets the player play emoticons.id `id`.
## APPROX(P3.02c): the emote is free when no quest / achievement reward gives it; the others need
## the reward. `criterion` (class, level, ornaments...) is not evaluated: a row that has one is
## refused, which hides about ten emotes.
static func usable(id: int, owned: Array) -> bool:
	var row := GameData.row("emoticons", id)
	if row.is_empty() or str(row.get("criterion", "")) != "":
		return false
	return owned.has(id) or not rewarded().has(id)


## The animation base of an emote ("AnimEmoteSit"), "" if unknown.
static func anim(id: int) -> String:
	return str(GameData.row("emoticons", id).get("animName", ""))
