## A character's achievements (P2.12a): the ones obtained (with the day) and the event counters the
## objectives read (CriteriaEval.COUNTERS). Saved with the character (Character.to_dict).
##   counters["EM:55"] = how many times monster 55 was beaten · "ES:<subarea>" entered · "EI:<item>" used · "QF:<quest>" finished
## The rules live in Achievements; this is only the state.
class_name AchievementLog
extends RefCounted

## achievement id -> the day (days since 1970, Clock) it was obtained
var done := {}
var counters := {}


func has(id: int) -> bool:
	return done.has(id)


func bump(key: String, id: int, by := 1) -> void:
	var k := "%s:%d" % [key, id]
	counters[k] = int(counters.get(k, 0)) + by


func to_dict() -> Dictionary:
	var d := {}
	for id: int in done:
		d[str(id)] = int(done[id])
	return {"done": d, "counters": counters.duplicate()}


static func from_dict(d: Dictionary) -> AchievementLog:
	var log := AchievementLog.new()
	var saved: Dictionary = d.get("done", {})
	for id: String in saved:
		log.done[int(id)] = int(saved[id])
	var c: Dictionary = d.get("counters", {})
	for k: String in c:
		log.counters[k] = int(c[k])
	return log
