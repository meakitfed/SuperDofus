## Runs the game logic headless, with no rendering at all, and prints every
## event the player receives as JSON lines (one per event, with the game time).
##   godot --headless --path game -s res://tools/sim_cli.gd -- --world=test --seconds=30 \
##         --cmd=0:move:250 --cmd=8000:change_map:right [--out=trace.jsonl] [--seed=1]
## --cmd=<at_ms>:<type>[:<arg>[:<arg2>]]
##   move:<cell>[!]  change_map:<dir>  fight_attack[:<group id>] (default: first group of the map)
##   fight_place:<cell>  fight_ready  fight_move:<cell>  fight_cast:<spell>:<cell>  fight_end_turn  fight_option:<locked|party_only|secret|help>[:0|1]
##   fight_leave  boost_stat:<stat>[:<capital>]  reset_stats  use_item:<uid>  equip:<uid>:<slot>  unequip:<slot>  destroy_item:<uid>[:<qty>]  choose_variant:<spell id>  move_spell:<spell id>:<slot>
##   npc_talk:<actor id>  dialog_reply:<id>  quest_abandon:<quest>  dialog_close  shop_buy:<item>[:<qty>]  shop_sell:<uid>[:<qty>]  shop_close  tp:<map id>[:<cell>]  interactive_use:<element>:<skill>  craft_open:<skill>  craft_set:<item>:<qty>[:<item>:<qty>…]  craft_do:<count>  craft_close  fm_apply:<uid>:<rune>
##   list_characters  create_character:<name>[:<breed>[:<sex>[:<body id>[:<head id>[:<color hex>…]]]]]  delete_character:<name>  select_character:<name>
## --player=<name>   the character played (default Cli); --player= (empty) starts at the character selection
## --bot=fight|pass   a scripted player (ScenarioBot) plays the fights
## --character=<json> the saved character to start with (e.g. '{"level":30}')
## Reference scenarios (tests/scenarios, replayed by tests/test_scenarios.gd):
##   --record=res://tests/scenarios/<name>.jsonl --doc="what it pins"   record one
##   --scenario=res://tests/scenarios/<name>.jsonl                       replay + check one
##   --rerecord=res://tests/scenarios/<name>.jsonl   same header and commands, new expectations
##                                                   (a rule changed on purpose: note it in the Journal)
extends SceneTree


func _init() -> void:
	var opts := {"world": "test", "seconds": "20", "seed": "1", "out": "", "bot": "", "record": "",
			"scenario": "", "rerecord": "", "doc": "", "character": "", "player": "Cli"}
	var cmds: Array = []
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		if kv[0] == "cmd" and kv.size() == 2:
			cmds.append(kv[1].split(":"))
		elif kv.size() == 2:
			opts[kv[0]] = kv[1]
	cmds.sort_custom(func(a: PackedStringArray, b: PackedStringArray) -> bool: return int(a[0]) < int(b[0]))

	if opts["scenario"] != "":
		_replay(opts["scenario"])
		return
	if opts["rerecord"] != "":
		_rerecord(opts["rerecord"])
		return

	var scenario := Scenario.new()
	scenario.header = {"scenario": opts["record"].get_file().get_basename() if opts["record"] != "" else "cli",
			"doc": opts["doc"], "world": opts["world"], "seed": int(opts["seed"]),
			"seconds": float(opts["seconds"]), "step_ms": 50, "player": opts["player"], "look": "{1|120,2195||56}" if opts["player"] != "" else ""}
	if opts["character"] != "":
		scenario.header["character"] = JSON.parse_string(opts["character"])
	var bot: ScenarioBot = ScenarioBot.new(opts["bot"]) if opts["bot"] != "" else null
	var groups: Array = [] # monster group ids of the current map
	var seen := [0]
	var driver := func(backend: GameBackend, events: Array, out: Array) -> void:
		while seen[0] < events.size():
			var ev: Dictionary = events[seen[0]]["ev"]
			seen[0] += 1
			if ev["t"] == Protocol.MAP_ENTER:
				groups.clear()
				for a: Dictionary in ev["actors"]:
					if a["kind"] == "monster_group":
						groups.append(int(a["id"]))
		while not cmds.is_empty() and int(cmds[0][0]) <= backend.time_ms():
			var cmd := _command(cmds.pop_front(), groups)
			if not cmd.is_empty():
				out.append(cmd)
		if bot != null:
			bot.drive(backend, events, out)

	var backend := LocalBackend.new()
	var events := scenario.run(backend, driver)
	if opts["record"] != "":
		var path: String = opts["record"]
		FileAccess.open(path, FileAccess.WRITE).store_string(scenario.to_jsonl(events))
		print("%d commands, %d expectations -> %s" % [scenario.commands.size(),
				Scenario.load_file(path).expects.size(), ProjectSettings.globalize_path(path)])
		quit()
		return
	var lines := PackedStringArray()
	for e: Dictionary in events:
		lines.append(JSON.stringify({"time": e["at"], "ev": e["ev"]}))
	var text := "\n".join(lines)
	if opts["out"] != "":
		FileAccess.open(opts["out"], FileAccess.WRITE).store_string(text + "\n")
		print("%d events -> %s" % [lines.size(), opts["out"]])
	else:
		print(text)
	quit()


func _command(c: PackedStringArray, groups: Array) -> Dictionary:
	match c[1]:
		"move":
			return Protocol.move(int(c[2]), c[2].ends_with("!"))
		"change_map":
			return Protocol.change_map(c[2])
		"use_trigger":
			return Protocol.use_trigger(int(c[2]))
		"interactive_use": # <element>:<skill>
			return Protocol.interactive_use(int(c[2]), int(c[3]))
		"craft_open":
			return Protocol.craft_open(int(c[2]))
		"craft_set": # <item>:<qty> pairs
			var given := []
			var i := 2
			while i + 1 < c.size():
				given.append({"item": int(c[i]), "qty": int(c[i + 1])})
				i += 2
			return Protocol.craft_set(given)
		"craft_do":
			return Protocol.craft_do(int(c[2]))
		"craft_close":
			return Protocol.craft_close()
		"fm_apply": # <item uid>:<rune item id>
			return Protocol.fm_apply(int(c[2]), int(c[3]))
		"use_zaap":
			return Protocol.use_zaap()
		"zaap_travel":
			return Protocol.zaap_travel(int(c[2]))
		"set_save_point":
			return Protocol.set_save_point()
		"fight_attack":
			return Protocol.fight_attack(int(c[2]) if c.size() > 2 else (groups[0] if not groups.is_empty() else -1))
		"fight_place":
			return Protocol.fight_place(int(c[2]))
		"fight_ready":
			return Protocol.fight_ready()
		"boost_stat":
			return Protocol.boost_stat(c[2], int(c[3]) if c.size() > 3 else 0)
		"reset_stats":
			return Protocol.reset_stats()
		"equip":
			return Protocol.equip(int(c[2]), int(c[3]))
		"unequip":
			return Protocol.unequip(int(c[2]))
		"use_item":
			return Protocol.use_item(int(c[2]))
		"destroy_item":
			return Protocol.destroy_item(int(c[2]), int(c[3]) if c.size() > 3 else 0)
		"npc_talk":
			return Protocol.npc_talk(int(c[2]))
		"dialog_reply":
			return Protocol.dialog_reply(int(c[2]))
		"quest_abandon":
			return Protocol.quest_abandon(int(c[2]))
		"dialog_close":
			return Protocol.dialog_close()
		"shop_buy":
			return Protocol.shop_buy(int(c[2]), int(c[3]) if c.size() > 3 else 1)
		"shop_sell":
			return Protocol.shop_sell(int(c[2]), int(c[3]) if c.size() > 3 else 1)
		"shop_close":
			return Protocol.shop_close()
		"tp": # the GM command /tp (the local player is a GM): tp:<map id>[:<cell>]
			return Protocol.admin_cmd("tp", [c[2], c[3] if c.size() > 3 else "300"])
		"admin": # a GM command (A1.01): admin:<cmd>[:<arg>...], e.g. admin:give:683:3 admin:level:50 admin:who
			return Protocol.admin_cmd(str(c[2]), Array(c.slice(3)))
		"choose_variant":
			return Protocol.choose_variant(int(c[2]))
		"move_spell":
			return Protocol.move_spell(int(c[2]), int(c[3]))
		"fight_move":
			return Protocol.fight_move(int(c[2]))
		"fight_cast":
			return Protocol.fight_cast(int(c[2]), int(c[3]))
		"fight_option":
			return Protocol.fight_option(str(c[2]), c.size() < 4 or c[3] != "0")
		"fight_end_turn":
			return Protocol.fight_end_turn()
		"fight_leave":
			return Protocol.fight_leave()
		"list_characters":
			return Protocol.list_characters()
		"create_character":
			var colors: Array = []
			for i in range(7, c.size()):
				colors.append(c[i].hex_to_int() if c[i] != "" else -1)
			return Protocol.create_character(c[2], int(c[3]) if c.size() > 3 else 12, int(c[4]) if c.size() > 4 else 0,
					int(c[5]) if c.size() > 5 else 0, int(c[6]) if c.size() > 6 else 0, colors)
		"delete_character":
			return Protocol.delete_character(c[2])
		"select_character":
			return Protocol.select_character(c[2])
	push_error("unknown --cmd " + c[1])
	return {}


func _rerecord(path: String) -> void:
	var s := Scenario.load_file(path)
	s.header = Scenario._intify(s.header)
	s.commands = s.commands.map(func(c: Dictionary) -> Variant: return Scenario._intify(c))
	var events := s.run(LocalBackend.new())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(s.to_jsonl(events))
	f.close()
	print("%s: rerecorded (%d commands)" % [path, s.commands.size()])
	quit(0)


func _replay(path: String) -> void:
	var s := Scenario.load_file(path)
	var failures := s.check(s.run(LocalBackend.new()))
	print("%s: %s" % [path, "OK" if failures.is_empty() else "\n  ".join(failures)])
	quit(0 if failures.is_empty() else 1)
