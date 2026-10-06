## Capture of the zone loading indicator (C.02d): godot --path game -s res://tools/zone_shot.gd -- --out=z.png [--fail=1]
extends SceneTree


func _init() -> void:
	var out := "zone.png"
	var fail := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a == "--fail=1":
			fail = true
	var layer := CanvasLayer.new()
	root.add_child(layer)
	layer.add_child(CharacterSelectScreen.backdrop())
	var gate := ZoneGate.new(ZoneStreamer.new(ContentClient.new("127.0.0.1", 1, ""), "dofus", "user://zone_shot"))
	layer.add_child(gate)
	gate.state = "failed" if fail else "loading"
	gate.error = "cannot connect to 127.0.0.1:7778" if fail else ""
	gate.done_bytes = 18_500_000
	gate.total_bytes = 31_000_000
	gate._holding = true
	await create_timer(0.8).timeout
	gate.indicator.update(gate)
	await create_timer(0.3).timeout
	root.get_texture().get_image().save_png(out)
	gate._holding = false
	quit()
