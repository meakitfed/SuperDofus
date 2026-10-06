## Quest rules (P2.03). Pure functions on a QuestLog and the world's quests
## (worlds/<id>/quests.json, made by `gamedata.py quests`: Dofus 3 tables quests /
## queststeps / questobjectives / queststeprewards):
##   quest = {id, name_id, criteria, start: {npc, map}, steps: [{id, name_id, desc_id, level,
##            objectives: [{id, type, map, params}], rewards: [row]}]}
## Objective types (questobjectivetypes, the names are the client's own texts):
##   0 text, at a map · 1 talk to an NPC [npc] · 2 show an item to an NPC [npc, item, qty] ·
##   3 bring items to an NPC [npc, item, qty] (taken) · 4 discover a map · 5 discover a subarea [subarea] ·
##   6 beat [monster, qty] in a single fight · 7 beat [monster] · 8 use an item [item] ·
##   9 go back to an NPC [npc] ·
##   14 beat [monster, qty] in any number of fights · 16 like 6, on the map of the objective ·
##   17 craft [item, qty]
## The objectives of a step come in runs of the same type (consecutive objectives of one type): the objectives of
## a run can be done in any order, a run begins when the previous one is done (so "talk to A, win, talk to A" or
## "visit five NPCs, go back to the first" keep their order). The step is done when all are, then the
## next step begins, after the last one the quest is finished and its rewards given step by step.
## APPROX(P2.03): the order is not stated in the data (questobjectives has none): runs of one type are the reading
## that fits every Incarnam quest (a step may repeat the same "talk to" around a fight).
##
## Events (what the sim reports): {kind: "talk", npc} · {kind: "map", map, subarea} ·
## {kind: "fight", win, monsters: [monsters.id], map} · {kind: "use", item} · {kind: "item"} (the bag changed).
##
## APPROX(P2.03): the dialogs of a quest step (queststeps.dialogId) are server data, absent from the client: the
## NPC says its usual line and offers the quest as a reply; the objectives complete by the action itself (talking, arriving…).
## APPROX(P2.03): crafting (17) is not implemented (jobs: P3.x): the objective is done once the bag holds the item,
## whatever way it came. A type 0 objective without a map (free text) is done as soon as the step begins.
## APPROX(P2.03): a quest is offered whatever its levelMin (a recommended level, the real condition is the criteria).
class_name QuestEngine
extends RefCounted

## id of the dialog reply that offers quest q: REPLY_BASE + q
const REPLY_BASE := 1000000
## APPROX(P2.03): the quest reward formulas are server code (queststeprewards only holds ratios): XP = ratio x this share
## of the XP between the step's optimal level and the next, kamas = ratio x KAMAS_PER_LEVEL x level.
const XP_SHARE := 0.05
const KAMAS_PER_LEVEL := 10


## Can the character begin quest `id` now (P2.04)? Not under way; never done, or repeatable (quests.repeatType):
## 1 = at once, 2 and 3 = once a day (the day is `day`, days since 1970); 0 and -1 = once. The criteria (CriteriaEval:
## Qf / Qa…) are the chain: a quest asks `Qf=<the previous one>`.
## APPROX(P2.04): the meaning of repeatType is not in the client data (quests.repeatLimit is always 1, no delay field):
## 1 = repeatable (the bakers, the alignment quests), 2 and 3 (the dungeon / event quests, category 31) = a daily delay,
## 0 and -1 = never twice. The real delays are server data.
static func can_start(quest: Dictionary, log: QuestLog, values: Dictionary, day := 0) -> bool:
	var id := int(quest["id"])
	if log.is_active(id) or not CriteriaEval.ok(str(quest.get("criteria", "")), values):
		return false
	if not log.is_finished(id):
		return true
	match int(quest.get("repeat", 0)):
		1:
			return true
		2, 3:
			return day > int(log.finished_day.get(id, -1))
	return false


## Quests the NPC `npc` offers this character (can_start).
static func offers(quests: Dictionary, log: QuestLog, npc: int, values: Dictionary, day := 0) -> Array:
	var out := []
	for id: int in quests:
		var q: Dictionary = quests[id]
		if int(q["start"]["npc"]) == npc and can_start(q, log, values, day):
			out.append(id)
	out.sort()
	return out


## The markers of a map (Protocol map_markers): [{kind: "offer" | "goal", quest, npc, map}] ("offer" = an NPC of the map
## offers a quest, "goal" = an objective of the step under way is here: `npc` is the NPC to talk to, 0 for a place).
static func markers(quests: Dictionary, log: QuestLog, map: int, npcs_here: Array, values: Dictionary, day := 0) -> Array:
	var out := []
	for npc: int in npcs_here:
		for id: int in offers(quests, log, npc, values, day):
			out.append({"kind": "offer", "quest": id, "npc": npc, "map": map})
	for id: int in log.active:
		if not quests.has(id):
			continue
		for o: Dictionary in active_run(_step(quests[id], log, id), log, id):
			var t := int(o["type"])
			if t in [1, 2, 3, 9]:
				if npcs_here.has(int(o["params"][0])) and (int(o["map"]) == 0 or int(o["map"]) == map):
					out.append({"kind": "goal", "quest": id, "npc": int(o["params"][0]), "map": map})
			elif int(o["map"]) == map:
				out.append({"kind": "goal", "quest": id, "npc": 0, "map": map})
	return out


## The dialog tree with a reply per offered quest on its first node (the NPC's own replies stay).
## A reply carries `quest` (the client prefixes the quest name) and the action quest_start.
static func with_offers(tree: Dictionary, quests: Dictionary, offered: Array) -> Dictionary:
	if offered.is_empty():
		return tree
	var out := tree.duplicate(true)
	if out.is_empty():
		out = {"start": "0", "nodes": {"0": {"text": "", "replies": []}}}
	var start: Dictionary = out["nodes"][out["start"]]
	var replies: Array = start.get("replies", [])
	for id: int in offered:
		replies.append({"id": REPLY_BASE + id, "text_id": int(quests[id]["name_id"]), "quest": id,
				"action": {"type": "quest_start", "quest": id}})
	start["replies"] = replies
	return out


## Begins a quest: its first step, with what is already done. Returns the changes (see on_event).
static func start(quests: Dictionary, log: QuestLog, id: int, owned: Callable) -> Array:
	log.begin(id)
	var out := [{"quest": id, "kind": "start", "consume": []}]
	_settle(quests, log, id, owned, out)
	return out


## Applies an event to every quest under way. Returns the changes, in order:
## {quest, kind: "update" | "step" | "finish" | "start", consume: [[item, qty]], reward: row (step / finish)}.
## "step" = a step was done and the next begins, "finish" = the last one was done.
static func on_event(quests: Dictionary, log: QuestLog, ev: Dictionary, owned: Callable) -> Array:
	var out := []
	for id: int in log.active.keys():
		if not quests.has(id):
			continue
		var step := _step(quests[id], log, id)
		var before := _snapshot(log, id)
		var consume := []
		for o: Dictionary in active_run(step, log, id):
			var cur := log.count(id, int(o["id"]))
			var gained := _gain(o, cur, ev, owned, consume)
			if gained != cur:
				log.set_count(id, int(o["id"]), gained)
		var rest := []
		_settle(quests, log, id, owned, rest)
		if rest.is_empty() and (not consume.is_empty() or _snapshot(log, id) != before):
			rest.append({"quest": id, "kind": "update", "consume": []})
		if not rest.is_empty():
			rest[0]["consume"] = consume
			out.append_array(rest)
	return out


## After a change: the free objectives (owned items, text without a map), then the finished steps.
static func _settle(quests: Dictionary, log: QuestLog, id: int, owned: Callable, out: Array) -> void:
	while log.is_active(id):
		var step := _step(quests[id], log, id)
		var moved := true
		while moved: # a run that is done opens the next, whose free objectives may be done too
			moved = false
			for o: Dictionary in active_run(step, log, id):
				var cur := log.count(id, int(o["id"]))
				var t := int(o["type"])
				if t == 17:
					var have := mini(need(o), int(owned.call(int(o["params"][0]))))
					if have > cur:
						log.set_count(id, int(o["id"]), have)
						moved = true
				elif t == 0 and int(o["map"]) == 0 and cur < 1:
					log.set_count(id, int(o["id"]), 1)
					moved = true
		var all := true
		for o: Dictionary in step["objectives"]:
			if not is_done(o, log.count(id, int(o["id"]))):
				all = false
		if not all:
			return
		var q: Dictionary = quests[id]
		var index := log.step_of(id)
		var reward := {"rows": step.get("rewards", []), "level": int(step.get("level", 1))}
		if index + 1 >= (q["steps"] as Array).size():
			log.finish(id)
			out.append({"quest": id, "kind": "finish", "consume": [], "reward": reward, "step": index})
		else:
			log.next_step(id)
			out.append({"quest": id, "kind": "step", "consume": [], "reward": reward, "step": index})


static func _step(quest: Dictionary, log: QuestLog, id: int) -> Dictionary:
	return quest["steps"][log.step_of(id)]


static func _snapshot(log: QuestLog, id: int) -> String:
	return JSON.stringify(log.active.get(id, {})) if log.active.has(id) else "done"


## Objective count that completes it.
static func need(o: Dictionary) -> int:
	match int(o["type"]):
		6, 14, 16, 17:
			return maxi(1, int(o["params"][1]))
	return 1


static func is_done(o: Dictionary, count: int) -> bool:
	return count >= need(o)


## The objectives that can progress now: the first run (consecutive objectives of one type) with one left to do.
static func active_run(step: Dictionary, log: QuestLog, id: int) -> Array:
	var run := []
	var objectives: Array = step["objectives"]
	for o: Dictionary in objectives:
		if not run.is_empty() and int(run[0]["type"]) != int(o["type"]):
			if run.any(func(r: Dictionary) -> bool: return not is_done(r, log.count(id, int(r["id"])))):
				break
			run = []
		run.append(o)
	if run.all(func(r: Dictionary) -> bool: return is_done(r, log.count(id, int(r["id"])))):
		return []
	return run.filter(func(r: Dictionary) -> bool: return not is_done(r, log.count(id, int(r["id"]))))


## The new count of objective `o` after event `ev` (consumed items are added to `consume`).
static func _gain(o: Dictionary, cur: int, ev: Dictionary, owned: Callable, consume: Array) -> int:
	var p: Array = o["params"]
	match str(ev.get("kind", "")):
		"talk":
			if int(o["type"]) in [1, 2, 3, 9] and int(p[0]) == int(ev["npc"]):
				match int(o["type"]):
					1:
						return 1
					2:
						return 1 if int(owned.call(int(p[1]))) >= int(p[2]) else cur
					3:
						if int(owned.call(int(p[1]))) >= int(p[2]):
							consume.append([int(p[1]), int(p[2])])
							return 1
					9:
						return 1
		"map":
			match int(o["type"]):
				0, 4:
					return 1 if int(o["map"]) != 0 and int(o["map"]) == int(ev["map"]) else cur
				5:
					return 1 if int(p[0]) == int(ev.get("subarea", -1)) else cur
		"fight":
			if not bool(ev.get("win", false)):
				return cur
			var kills := (ev.get("monsters", []) as Array).filter(func(m: Variant) -> bool: return int(m) == int(p[0])).size() \
					if not p.is_empty() else 0
			match int(o["type"]):
				6:
					return need(o) if kills >= need(o) else cur
				16:
					return need(o) if kills >= need(o) and int(o["map"]) == int(ev.get("map", -1)) else cur
				7:
					return 1 if kills > 0 else cur
				14:
					return mini(need(o), cur + kills)
		"use":
			if int(o["type"]) == 8 and int(p[0]) == int(ev["item"]):
				return 1
	return cur


# ── rewards ────────────────────────────────────────────────────────────────────

## What a finished step gives a character of `level`: the row of queststeprewards for his level
## (level_min / level_max, -1 = any), {xp, kamas, items: [[id, qty]], emotes, spells, titles}.
static func rewards(reward: Dictionary, player_level: int) -> Dictionary:
	var out := {"xp": 0, "kamas": 0, "items": [], "emotes": [], "spells": [], "titles": [], "jobs": []}
	for r: Dictionary in reward.get("rows", []):
		var lo := int(r["level_min"])
		var hi := int(r["level_max"])
		if (lo > 0 and player_level < lo) or (hi > 0 and player_level > hi):
			continue
		var level := clampi(player_level if int(r.get("scale", 0)) != 0 else int(reward.get("level", 1)), 1, GameData.max_level())
		# APPROX(P2.03): see XP_SHARE
		out["xp"] = int(out["xp"]) + floori(float(r["xp"]) * XP_SHARE * (GameData.xp_next(level) - GameData.xp_floor(level)))
		out["kamas"] = int(out["kamas"]) + floori(float(r["kamas"]) * KAMAS_PER_LEVEL * level)
		for i: Array in r["items"]:
			out["items"].append([int(i[0]), int(i[1])])
		for k: String in ["emotes", "spells", "titles", "jobs"]:
			for v: Variant in r.get(k, []):
				out[k].append(int(v))
		break # one row applies
	return out


# ── views (protocol) ───────────────────────────────────────────────────────────

## What the client shows of a quest under way: {id, name_id, step, steps, step_name_id, desc_id, level, objectives}
## with objectives [{id, type, params, map, count, need, done, locked}].
static func view(quests: Dictionary, log: QuestLog, id: int) -> Dictionary:
	var q: Dictionary = quests[id]
	var index := log.step_of(id)
	var step: Dictionary = q["steps"][index]
	var objectives := []
	var run: Array = active_run(step, log, id).map(func(r: Dictionary) -> int: return int(r["id"]))
	for o: Dictionary in step["objectives"]:
		var c := log.count(id, int(o["id"]))
		var done := is_done(o, c)
		objectives.append({"id": int(o["id"]), "type": int(o["type"]), "params": o["params"], "map": int(o["map"]), "args": o.get("args", []),
				"count": c, "need": need(o), "done": done, "locked": not done and not run.has(int(o["id"]))})
	return {"id": id, "name_id": int(q["name_id"]), "category": int(q.get("category", 0)), "step": index, "steps": (q["steps"] as Array).size(),
			"step_name_id": int(step.get("name_id", 0)), "desc_id": int(step.get("desc_id", 0)), "level": int(step.get("level", 1)),
			"objectives": objectives}
