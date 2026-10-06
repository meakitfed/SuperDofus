## A character's jobs (P2.05): total XP per job (jobs.id). A job never practised is at
## level Jobs.START_LEVEL with 0 XP. Saved with the character (Character.to_dict).
class_name JobLog
extends RefCounted

var xp := {} # jobs.id -> total XP


func xp_of(job: int) -> int:
	return int(xp.get(job, 0))


func level(job: int) -> int:
	return Jobs.level_for_xp(xp_of(job))


## Adds XP; returns the levels gained.
func gain(job: int, amount: int) -> int:
	var before := level(job)
	xp[job] = xp_of(job) + maxi(0, amount)
	return level(job) - before


## jobs.id -> level of the jobs practised (the others are at Jobs.START_LEVEL: CriteriaEval PJ).
func levels() -> Dictionary:
	var out := {}
	for j: int in xp:
		out[j] = level(j)
	return out


## A job taught (queststeprewards.jobsReward): it is listed from now on, at its current level.
func learn(job: int) -> void:
	xp[job] = xp_of(job)


## What the client shows: [{job, level, xp, xp_floor, xp_next}] of the jobs practised.
func to_views() -> Array:
	var out := []
	var ids := xp.keys()
	ids.sort()
	for j: int in ids:
		out.append(view(j))
	return out


func view(job: int) -> Dictionary:
	var lv := level(job)
	return {"job": job, "level": lv, "xp": xp_of(job), "xp_floor": Jobs.xp_floor(lv), "xp_next": Jobs.xp_next(lv)}


func to_dict() -> Dictionary:
	var out := {}
	for j: int in xp:
		out[str(j)] = int(xp[j])
	return out


static func from_dict(d: Dictionary) -> JobLog:
	var log := JobLog.new()
	for k: String in d:
		log.xp[int(k)] = int(d[k])
	return log
