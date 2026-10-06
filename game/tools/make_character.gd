## Creates (or tops up) a test character in the local save (user://saves, the
## standalone game's FilePersistence), through the real rules: creation
## (CharacterRoster), XP (capital, HP), items rolled like drops (WorldSim.give_item).
##   godot --headless --path game -s res://tools/make_character.gd -- --name=Testeur \
##         [--world=incarnam] [--level=200] [--breed=12] [--sex=0] [--all-items] [--qty=10]
## --all-items: every item the game knows (game/data/items.json), 1 of each
## equipment, --qty of the others. The character belongs to the local account.
extends SceneTree


func _init() -> void:
	var opts := {"world": "dofus", "name": "Testeur", "level": "200", "breed": "12", "sex": "0", "qty": "10"}
	var all_items := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--all-items":
			all_items = true
			continue
		var kv := arg.trim_prefix("--").split("=", true, 1)
		if kv.size() == 2:
			opts[kv[0]] = kv[1]
	var server := LocalServer.new()
	server.persistence = FilePersistence.new("user://saves") # like ClientSession._make_backend
	server.clock = SystemClock.new()
	var sim := server.world(str(opts["world"]))
	if sim == null:
		printerr("unknown world ", opts["world"])
		quit(1)
		return
	var account := LocalBackend.new().account
	var name := str(opts["name"])
	if sim.persistence.load_character(sim.world_id(), name).is_empty():
		var err := CharacterRoster.create(sim, account, name, {"breed": int(opts["breed"]), "sex": int(opts["sex"])})
		if err != "":
			printerr("cannot create ", name, ": ", err)
			quit(1)
			return
	var id := sim.connect_player(name, "", account)
	var p: PlayerActor = sim.players[id]
	var level := clampi(int(opts["level"]), 1, GameData.max_level())
	if p.character.level < level:
		p.character.gain_xp(GameData.xp_floor(level) - p.character.xp, sim.now)
	if all_items:
		for item_id: int in GameData.item_ids():
			var equipment := not Equipment.positions(item_id).is_empty()
			sim.give_item(p, item_id, 1 if equipment else int(opts["qty"]))
	sim.disconnect_player(id)
	var saved := sim.persistence.load_character(sim.world_id(), name)
	print("%s (%s): level %d, capital %d, %d item stacks -> %s" % [name, sim.world_id(), int(saved["level"]),
			int(saved["capital"]), (saved["items"] as Array).size(), ProjectSettings.globalize_path("user://saves")])
	quit(0)
