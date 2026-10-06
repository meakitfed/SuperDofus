## A reference scenario (tests/scenarios/*.jsonl): the contract a game host
## must honour. Same seed + same timed commands => the expected events.
## LocalBackend replays them in tests/test_scenarios.gd; the network server
## will replay the very same files (roadmap S.07).
##
## File = JSON lines:
##   {"scenario": name, "doc": "...", "world": id, "seed": 1, "seconds": 40,
##    "step_ms": 50, "player": name, "look": look, "character": {Character dict}?}
##   ("player": "" = start at the character selection: hello without a name)
##   {"at": ms, "cmd": {protocol command}}          commands, sent before the poll at `at`
##   {"expect": {partial event}, "at"?: ms}          expected events, in order
## An expectation matches the next event (in order, others skipped) that has
## all its fields with equal values (recursively: dicts are partial, arrays
## must have the same length). With "at", the event must come at that time.
class_name Scenario
extends RefCounted

## Events kept as expectations when recording, and which of their fields.
## Wandering monsters and animation-only details are left out on purpose:
## a scenario pins game rules, not incidental behaviour.
const RECORDED := {
	Protocol.CHARACTERS: ["t", "list", "max", "breeds"],
	Protocol.CHARACTER_CREATED: ["t", "character"],
	Protocol.WELCOME: ["t", "v"],
	Protocol.MAP_ENTER: ["t", "map.id"],
	Protocol.ZAAP_LIST: ["t", "zaap", "destinations", "save_map"],
	Protocol.ZAAP_KNOWN: ["t", "map"],
	Protocol.GROUP_ALERT: ["t", "group", "target"],
	Protocol.INFO: ["t", "code", "args"],
	Protocol.DIALOG: ["t", "npc", "text_id", "text", "replies", "action"],
	Protocol.DIALOG_END: ["t", "action"],
	Protocol.SHOP_OPEN: ["t", "npc", "items", "sell_divisor"],
	Protocol.SHOP_END: ["t"],
	Protocol.BANK_OPEN: ["t", "npc", "cost", "kamas", "items"],
	Protocol.BANK_UPDATE: ["t", "kamas", "items"],
	Protocol.BANK_END: ["t"],
	Protocol.QUEST_START: ["t", "quest.id", "quest.step", "quest.objectives"],
	Protocol.QUEST_UPDATE: ["t", "quest.id", "quest.step", "quest.objectives", "rewards"],
	Protocol.QUEST_COMPLETE: ["t", "quest", "rewards"],
	Protocol.ACTOR_LOOK: ["t", "id", "looks"],
	Protocol.ERROR: ["t", "code", "cmd"],
	Protocol.PLAYER_STATS: ["t", "stats.level", "stats.xp", "stats.kamas", "stats.hp", "stats.spells", "stats.bar", "stats.capital", "stats.stats", "stats.max_hp", "stats.derived", "stats.additional", "stats.weight", "stats.bonus", "stats.energy", "stats.life"],
	Protocol.INVENTORY: ["t", "items"],
	Protocol.ITEM_ADDED: ["t", "item"],
	Protocol.ITEM_REMOVED: ["t", "uid"],
	Protocol.FIGHT_START: ["t", "phase"],
	Protocol.FIGHT_BEGIN: ["t", "order"],
	Protocol.FIGHT_TURN: ["t", "id", "effects"],
	Protocol.FIGHTER_MOVE: ["t", "id", "path", "mp", "triggered"],
	Protocol.SPELL_CAST: ["t", "caster", "spell", "cell", "crit", "effects"],
	Protocol.FIGHT_END: ["t", "result", "rewards"],
}

var header := {}
var commands: Array = [] # [{at, cmd}]
var expects: Array = []  # [{expect, at?}]


static func load_file(path: String) -> Scenario:
	var s := Scenario.new()
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.strip_edges() == "":
			continue
		var d: Variant = JSON.parse_string(line)
		if not d is Dictionary:
			continue
		if d.has("scenario"):
			s.header = d
		elif d.has("cmd"):
			s.commands.append(d)
		elif d.has("expect"):
			s.expects.append(d)
	return s


## Runs the scenario on a backend; returns [{at, ev}]. `driver` (optional)
## is called before each poll with (backend, events so far) and may send
## more commands: that is how a bot records a scenario.
func run(backend: GameBackend, driver := Callable()) -> Array:
	var events: Array = []
	var sent: Array = []
	if backend is LocalBackend:
		var local := backend as LocalBackend
		local.seed = int(header.get("seed", 1))
		if header.has("character") and str(header.get("player", "Tester")) != "":
			var ch: Dictionary = (header["character"] as Dictionary).duplicate(true)
			ch["name"] = str(header.get("player", "Tester"))
			local.persistence.save_character(str(header["world"]), ch["name"], ch)
	elif backend.has_method("prepare_scenario"):
		backend.call("prepare_scenario", header) # a backend hosted elsewhere (S.07: a server in the test process)
	backend.event.connect(func(ev: Dictionary) -> void: events.append({"at": backend.time_ms(), "ev": ev}))
	var step := int(header.get("step_ms", 50))
	var end := int(float(header.get("seconds", 30)) * 1000.0)
	var queue := commands.duplicate()
	var player := str(header.get("player", "Tester"))
	backend.send(Protocol.hello(str(header["world"]), player, str(header.get("look", "")) if player != "" else ""))
	backend.poll(0.0)
	while backend.time_ms() < end:
		while not queue.is_empty() and int(queue[0]["at"]) <= backend.time_ms():
			backend.send(queue.pop_front()["cmd"])
		if driver.is_valid():
			var before := sent.size()
			driver.call(backend, events, sent)
			for i in range(before, sent.size()):
				backend.send(sent[i])
				commands.append({"at": backend.time_ms(), "cmd": sent[i]})
		var t := backend.time_ms()
		backend.poll(step / 1000.0)
		if backend.time_ms() == t: # disconnected (no world): nothing will ever happen
			break
	backend.close()
	return events


## Failures of `events` against the expectations ([] = pass).
## `ignore_time`: the `at` of the expectations is not compared (the network clock differs, S.07).
func check(events: Array, ignore_time := false) -> PackedStringArray:
	var failures := PackedStringArray()
	var i := 0
	for e: Dictionary in expects:
		var found := false
		while i < events.size():
			var got: Dictionary = events[i]
			i += 1
			if _matches(e["expect"], got["ev"]) and (ignore_time or not e.has("at") or int(e["at"]) == int(got["at"])):
				found = true
				break
		if not found:
			failures.append("expected %s%s, not found after the previous match" % [
					JSON.stringify(e["expect"]), (" at %d ms" % int(e["at"])) if e.has("at") else ""])
			break # later expectations would all cascade
	return failures


## Writes this scenario with the RECORDED part of `events` as expectations.
func to_jsonl(events: Array) -> String:
	var lines := PackedStringArray([JSON.stringify(header)])
	var order := range(commands.size()) # stable sort by time (sort_custom is not stable)
	order.sort_custom(func(a: int, b: int) -> bool:
		var ta := int(commands[a]["at"])
		var tb := int(commands[b]["at"])
		return ta < tb or (ta == tb and a < b))
	for i: int in order:
		var c: Dictionary = commands[i]
		lines.append(JSON.stringify(c))
	for e: Dictionary in events:
		var ev: Dictionary = e["ev"]
		if RECORDED.has(ev["t"]):
			lines.append(JSON.stringify({"at": int(e["at"]), "expect": _intify(_pick(ev, RECORDED[ev["t"]]))}))
	return "\n".join(lines) + "\n"


## Integral floats (what JSON gave back) written as ints, for readable files.
static func _intify(v: Variant) -> Variant:
	if v is Dictionary:
		var d := {}
		for k: String in v:
			d[k] = _intify(v[k])
		return d
	if v is Array:
		return (v as Array).map(_intify)
	if v is float and v == floorf(v) and absf(v) < 1e15:
		return int(v)
	return v


static func _pick(ev: Dictionary, fields: Array) -> Dictionary:
	var out := {}
	for f: String in fields:
		var parts := f.split(".")
		var src: Variant = ev
		var ok := true
		for p in parts:
			if src is Dictionary and (src as Dictionary).has(p):
				src = src[p]
			else:
				ok = false
				break
		if not ok:
			continue
		var dst := out
		for j in parts.size() - 1:
			if not dst.has(parts[j]):
				dst[parts[j]] = {}
			dst = dst[parts[j]]
		dst[parts[-1]] = src
	return out


static func _matches(want: Variant, got: Variant) -> bool:
	if want is Dictionary:
		if not got is Dictionary:
			return false
		for k: String in want:
			if not (got as Dictionary).has(k) or not _matches(want[k], got[k]):
				return false
		return true
	if want is Array:
		if not got is Array or (want as Array).size() != (got as Array).size():
			return false
		for j in (want as Array).size():
			if not _matches(want[j], got[j]):
				return false
		return true
	if (want is int or want is float) and (got is int or got is float):
		return is_equal_approx(float(want), float(got))
	return want == got
