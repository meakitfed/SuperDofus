## State of the challenges received (P3.10), without any Node so a test can drive it: who challenged
## us and since when. The sim decides everything (who may duel, the fight itself); this only keeps
## the cards shown under the group frame.
class_name DuelModel
extends RefCounted

const INVITE_MS := ProtocolDuel.INVITE_TTL_MS

## [{from, at (ms)}], oldest first
var invites: Array = []


func apply_requested(from: String, now: int) -> void:
	invites = invites.filter(func(i: Dictionary) -> bool: return i["from"] != from)
	invites.append({"from": from, "at": now})


## Drops the challenges unanswered for a minute; true if one went.
func expire(now: int) -> bool:
	var kept := invites.filter(func(i: Dictionary) -> bool: return now - int(i["at"]) < INVITE_MS)
	var changed := kept.size() != invites.size()
	invites = kept
	return changed


func forget(from: String) -> void:
	invites = invites.filter(func(i: Dictionary) -> bool: return i["from"] != from)


## The line the challenger reads when the challenge ends without a fight.
static func end_text(reason: String) -> String:
	return "Votre défi a été refusé" if reason == ProtocolDuel.REASON_DECLINED else "Votre défi est resté sans réponse"
