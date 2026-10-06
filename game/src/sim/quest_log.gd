## A character's quests (P2.03): the ones under way (current step and the progress
## of each objective) and the ones finished. Saved with the character (Character.to_dict).
##   active[quest id] = {step: index in quest.steps, progress: {objective id: count}}
## The rules live in QuestEngine; this is only the state.
class_name QuestLog
extends RefCounted

var active := {}
## finished quest ids, in completion order
var finished: Array = []
## quest id -> the day (days since 1970, Clock) of its last completion: a daily quest waits for the next one (P2.04)
var finished_day := {}


func is_active(quest: int) -> bool:
	return active.has(quest)


func is_finished(quest: int) -> bool:
	return finished.has(quest)


func step_of(quest: int) -> int:
	return int(active[quest]["step"]) if active.has(quest) else -1


func count(quest: int, objective: int) -> int:
	if not active.has(quest):
		return 0
	return int(active[quest]["progress"].get(objective, 0))


func set_count(quest: int, objective: int, value: int) -> void:
	active[quest]["progress"][objective] = value


func begin(quest: int) -> void:
	active[quest] = {"step": 0, "progress": {}}


func next_step(quest: int) -> void:
	active[quest]["step"] = int(active[quest]["step"]) + 1
	active[quest]["progress"] = {}


func finish(quest: int) -> void:
	active.erase(quest)
	if not finished.has(quest):
		finished.append(quest)


## Gives up a quest under way: its progress is lost (what the steps already gave is kept).
func abandon(quest: int) -> bool:
	return active.erase(quest)


func to_dict() -> Dictionary:
	var act := []
	for q: int in active:
		var prog := {}
		for o: int in active[q]["progress"]:
			prog[str(o)] = int(active[q]["progress"][o])
		act.append({"quest": q, "step": int(active[q]["step"]), "progress": prog})
	var days := {}
	for q: int in finished_day:
		days[str(q)] = int(finished_day[q])
	return {"active": act, "finished": finished.duplicate(), "finished_day": days}


static func from_dict(d: Dictionary) -> QuestLog:
	var log := QuestLog.new()
	for a: Dictionary in d.get("active", []):
		var prog := {}
		var saved: Dictionary = a.get("progress", {})
		for o: String in saved:
			prog[int(o)] = int(saved[o])
		log.active[int(a["quest"])] = {"step": int(a.get("step", 0)), "progress": prog}
	log.finished = (d.get("finished", []) as Array).map(func(v: Variant) -> int: return int(v))
	var days: Dictionary = d.get("finished_day", {})
	for q: String in days:
		log.finished_day[int(q)] = int(days[q])
	return log
