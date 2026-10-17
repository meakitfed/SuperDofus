## What the jobs window shows (P2.05c), without any Node: the jobs practised, from player_stats.jobs
## and the job_xp events. The levels, the XP table and the skills are the sim's (Jobs, JobLog).
class_name JobsModel
extends RefCounted

var views := {} # jobs.id -> {job, level, xp, xp_floor, xp_next}


func apply_stats(stats: Dictionary) -> void:
	views = {}
	for v: Dictionary in stats.get("jobs", []):
		views[int(v["job"])] = v


func apply_xp(ev: Dictionary) -> void:
	var v: Dictionary = ev["view"]
	views[int(v["job"])] = v


## The jobs practised, best level first: [{job, name, level, xp, xp_floor, xp_next, skills: [{skill, item, level, locked, xp}]}].
func rows() -> Array:
	var out := []
	for j: int in views:
		var v: Dictionary = views[j]
		var lv := int(v["level"])
		var skills := []
		var seen := {} # two skills can give the same resource (Blé): listed once
		for sk in Jobs.gathering_skills(j):
			if seen.has(Jobs.item_of(sk)):
				continue
			seen[Jobs.item_of(sk)] = true
			skills.append({"skill": sk, "item": Jobs.item_of(sk), "level": Jobs.required_level(sk),
					"locked": Jobs.required_level(sk) > lv, "xp": Jobs.xp_gain(sk)})
		out.append({"job": j, "name": DofusI18n.text(int(Jobs.job(j).get("nameId", 0)), "Métier"), "level": lv,
				"xp": int(v["xp"]), "xp_floor": int(v["xp_floor"]), "xp_next": int(v["xp_next"]), "skills": skills})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["level"]) > int(b["level"]) or (int(a["level"]) == int(b["level"]) and int(a["job"]) < int(b["job"])))
	return out
