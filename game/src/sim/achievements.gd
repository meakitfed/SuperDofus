## Achievements (P2.12a): pure rules, reusing the quest machinery. data/achievements.json (made by
## `gamedata.py achievements` from the Dofus 3 tables achievements / achievementobjectives / achievementrewards):
##   achievement = {id, name_id, desc_id, category, icon, points, level, order,
##                  objectives: [{id, name_id, criterion}], rewards: [{criteria, xp, kamas, scale, items, emotes, spells, titles}]}
## An objective is a Dofus criterion read by CriteriaEval (PL level, Qf / QF quests, EM monsters beaten, ES subareas,
## EI items used, OA / Oa achievements and their points, PO an item owned). The sim reports its events (talk, map,
## fight, use, item, quest), the counters move, then every achievement not yet obtained is read again: all its
## objectives true = obtained, its rewards are given, and the points count (a "Oa>999" achievement chains on them).
## Rewards: each reward row whose criteria hold (the "Ob!<id>" rows, PL / PO conditions) goes through
## QuestEngine.rewards (the same XP / kamas ratios, same APPROX(P2.03) formulas) and the rows add up.
## APPROX(P2.12a): only the achievements whose every objective uses a key above are kept (725 of 2780); the others
## (mounts EB, challenges Ef / EH, captures HD...) come with the mechanics that raise their events.
## APPROX(P2.12a): "EM>id,0,d" (beat the monster in its dungeon) counts any win against the monster.
class_name Achievements
extends RefCounted

const FILE := "data/achievements.json"

static var _defs := {}
static var _order: Array = [] # ids by `order`, then id
static var _loaded := false


## {achievement id: def}, from data/achievements.json (or what set_defs gave).
static func defs() -> Dictionary:
	if not _loaded:
		_loaded = true
		var data: Variant = DataFiles.read_json(FILE)
		if data is Dictionary:
			set_defs((data as Dictionary).get("achievements", {}))
	return _defs


## Replaces the definitions (tests). Ids may be strings (JSON).
static func set_defs(defs_in: Dictionary) -> void:
	_loaded = true
	_defs = {}
	for k: Variant in defs_in:
		_defs[int(k)] = defs_in[k]
	_order = _defs.keys()
	_order.sort_custom(func(a: int, b: int) -> bool:
		var oa := int(_defs[a].get("order", 0))
		var ob := int(_defs[b].get("order", 0))
		return oa < ob or (oa == ob and a < b))


static func reset() -> void:
	_loaded = false
	_defs = {}
	_order = []


## Moves the counters for event `ev` (the same events as QuestEngine.on_event, plus {kind: "quest", quest}).
static func count_event(log: AchievementLog, ev: Dictionary) -> void:
	match str(ev.get("kind", "")):
		"fight":
			if bool(ev.get("win", false)):
				for m: Variant in ev.get("monsters", []):
					if int(m) > 0:
						log.bump("EM", int(m))
		"map":
			if int(ev.get("subarea", -1)) >= 0:
				log.bump("ES", int(ev["subarea"]))
		"use":
			log.bump("EI", int(ev["item"]))
		"quest":
			log.bump("QF", int(ev["quest"]))


static func points(log: AchievementLog) -> int:
	var total := 0
	var all := defs()
	for id: int in log.done:
		total += int((all[id] as Dictionary).get("points", 0)) if all.has(id) else 0
	return total


## The criteria values with what achievements read: `values` = Character.criteria_values().
static func with_state(values: Dictionary, log: AchievementLog) -> Dictionary:
	var v := values.duplicate()
	v["achievements"] = log.done.keys()
	v["achievement_points"] = points(log)
	v["counters"] = log.counters
	return v


static func objective_done(o: Dictionary, values: Dictionary) -> bool:
	return CriteriaEval.ok(str(o["criterion"]), values)


## Reads every achievement not yet obtained and marks the ones whose objectives all hold, `day` being today.
## Returns the ids obtained, in order. Loops, as an obtained achievement (OA / Oa) can open another.
static func check(log: AchievementLog, values: Dictionary, day: int) -> Array:
	var out := []
	var all := defs()
	var ids := all.keys()
	ids.sort_custom(func(a: int, b: int) -> bool: return int(all[a].get("order", 0)) < int(all[b].get("order", 0)) or \
			(int(all[a].get("order", 0)) == int(all[b].get("order", 0)) and a < b))
	var moved := true
	while moved:
		moved = false
		var v := with_state(values, log)
		for id: int in ids:
			if log.done.has(id):
				continue
			var a: Dictionary = all[id]
			var objectives: Array = a["objectives"]
			if objectives.is_empty() or not objectives.all(func(o: Dictionary) -> bool: return objective_done(o, v)):
				continue
			log.done[id] = day
			out.append(id)
			moved = true
			v = with_state(values, log)
	return out


## What achievement `id` gives a character of `level` (before it is marked obtained: its "Ob!<id>" rows count):
## {xp, kamas, items: [[id, qty]], emotes, spells, titles}. QuestEngine.rewards sums one row; the rows add up here.
static func rewards(id: int, values: Dictionary, level: int) -> Dictionary:
	var out := {"xp": 0, "kamas": 0, "items": [], "emotes": [], "spells": [], "titles": [], "jobs": []}
	var a: Dictionary = defs().get(id, {})
	for r: Dictionary in a.get("rewards", []):
		if not CriteriaEval.ok(str(r.get("criteria", "")), values):
			continue
		var row := {"level_min": -1, "level_max": -1, "xp": r["xp"], "kamas": r["kamas"], "scale": r["scale"], "items": r["items"],
				"emotes": r["emotes"], "spells": r["spells"], "titles": r["titles"]}
		var got := QuestEngine.rewards({"rows": [row], "level": int(a.get("level", 1))}, level)
		out["xp"] = int(out["xp"]) + int(got["xp"])
		out["kamas"] = int(out["kamas"]) + int(got["kamas"])
		for k: String in ["items", "emotes", "spells", "titles"]:
			(out[k] as Array).append_array(got[k])
	return out


## What the client lists (Protocol achievement_list): the points, the ids obtained with their day, and for the
## others the objectives already true: [{id, objectives: [objective ids]}] (only when some are).
static func view(log: AchievementLog, values: Dictionary) -> Dictionary:
	var v := with_state(values, log)
	var done := []
	var progress := []
	var ids := defs().keys()
	ids.sort()
	for id: int in ids:
		if log.done.has(id):
			done.append({"id": id, "day": int(log.done[id])})
			continue
		var some := []
		for o: Dictionary in defs()[id]["objectives"]:
			if objective_done(o, v):
				some.append(int(o["id"]))
		if not some.is_empty():
			progress.append({"id": id, "objectives": some})
	return {"points": points(log), "total": total_points(), "done": done, "progress": progress}


static func total_points() -> int:
	var total := 0
	for a: Dictionary in defs().values():
		total += int(a.get("points", 0))
	return total
