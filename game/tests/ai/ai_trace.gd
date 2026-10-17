## Trace of the first turn of an AI fighter (H.05): the actions FightAI makes it take, as short readable
## strings, so a change of behaviour (target, cell, spell, order) shows up as a line of diff in
## tests/golden/monsters/ai_*.json. Same ticking as the server (Fight.tick), seed fixed by the caller.
class_name AiTrace
extends RefCounted

const STEP_MS := 150
const TICK_GUARD := 5000
const GOLDEN_DIR := "res://tests/golden/monsters/"


static func updating() -> bool:
	return OS.get_environment("GOLDEN_UPDATE") == "1" or OS.get_cmdline_user_args().has("--update-golden")


## One event of the turn as a line, or "" for the events a trace leaves out.
static func line(ev: Dictionary) -> String:
	match str(ev.get("t", "")):
		Protocol.FIGHTER_MOVE:
			var path: Array = ev["path"]
			return "move %d>%d (%d steps) mp %d" % [int(ev["id"]), int(path.back()) if not path.is_empty() else -1, path.size(), int(ev["mp"])]
		Protocol.SPELL_CAST:
			var parts: PackedStringArray = []
			for e: Dictionary in ev["effects"]:
				parts.append("%s>%d" % [str(e.get("kind", "?")), int(e.get("target", 0))])
			return "cast %d spell %d at %d%s ap %d [%s]" % [int(ev["caster"]), int(ev["spell"]), int(ev["cell"]),
					" crit" if ev.get("crit", false) else "", int(ev["ap"]), ", ".join(parts)]
	return ""


## Plays the fight until the turn after `actor`'s first one begins; the fighters in `passive` just end
## their turn. Returns the lines of the actor's first turn, ending with "end" (or "result <x>").
static func first_turn(fight: Fight, events: Array, actor: Fighter, passive: Array) -> PackedStringArray:
	var now := 0
	var ticks := 0
	var started := false
	var seen := 0
	var out: PackedStringArray = []
	while ticks < TICK_GUARD:
		ticks += 1
		now += STEP_MS
		var cur := fight.current()
		if cur == null:
			out.append("no fighter has the turn")
			return out
		if cur != actor and passive.has(cur):
			fight.end_turn(now)
		else:
			fight.tick(now)
		while seen < events.size():
			var ev: Dictionary = events[seen]
			seen += 1
			if str(ev.get("t", "")) == Protocol.FIGHT_TURN:
				if started:
					out.append("end")
					return out
				started = int(ev["id"]) == actor.id
				if started:
					out.append("turn ap %d mp %d" % [int(ev["ap"]), int(ev["mp"])])
			elif started:
				var l := line(ev)
				if l != "":
					out.append(l)
		if fight.result != "":
			out.append("result " + fight.result)
			return out
	out.append("hang: no end of turn after %d ticks" % TICK_GUARD)
	return out


static func read(file: String) -> Dictionary:
	var f := FileAccess.open(GOLDEN_DIR + file, FileAccess.READ)
	if f == null:
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	return (data as Dictionary).get("traces", {}) if data is Dictionary else {}


static func write(file: String, traces: Dictionary, doc: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GOLDEN_DIR))
	var f := FileAccess.open(GOLDEN_DIR + file, FileAccess.WRITE)
	f.store_string(JSON.stringify({"_doc": doc, "traces": traces}, "\t", true) + "\n")


static func as_array(trace: PackedStringArray) -> Array:
	return Array(trace)


static func normalized(v: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(v, "", true))
